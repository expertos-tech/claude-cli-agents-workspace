// Command container-console-colima serves the local console of the container environment.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"container-console-colima/internal/cliexec"
	"container-console-colima/internal/colima"
	"container-console-colima/internal/compose"
	"container-console-colima/internal/config"
	"container-console-colima/internal/docker"
	"container-console-colima/internal/filepicker"
	"container-console-colima/internal/httpapi"
	"container-console-colima/internal/jobs"
	"container-console-colima/internal/kube"
	"container-console-colima/internal/live"
	"container-console-colima/internal/webui"
)

// main reports a startup or serving failure and exits with an error status.
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "container-console-colima:", err)
		os.Exit(1)
	}
}

// run wires the service and blocks until a termination signal arrives.
func run() error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}
	if err := os.Setenv("PATH", cfg.SearchPath); err != nil {
		return err
	}
	logger, closeLog, err := openLog(cfg.LogFile)
	if err != nil {
		return err
	}
	defer closeLog()

	server, err := buildServer(cfg, logger)
	if err != nil {
		return err
	}
	listener, err := net.Listen("tcp4", cfg.ListenAddr)
	if err != nil {
		return err
	}
	logger.Info("service started", "port", cfg.Port, "profile", cfg.ColimaProfile)
	return serve(cfg, server, listener)
}

// loadConfig reads the configuration from the process environment.
func loadConfig() (config.Config, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return config.Config{}, err
	}
	return config.Load(os.Getenv, home)
}

// maxLogBytes is the size above which the log moves to path.1, so the two files hold at most twice this.
const maxLogBytes = 5 << 20

// rotatingLog appends to a file and moves it to path.1 when it passes maxLogBytes. The slog handler
// serializes the writes.
type rotatingLog struct {
	path string
	file *os.File
	size int64
}

// Write rotates when needed and appends p. A failed rotation keeps the current file, because logging
// must not take the service down.
func (l *rotatingLog) Write(p []byte) (int, error) {
	if l.size+int64(len(p)) > maxLogBytes {
		l.rotate()
	}
	n, err := l.file.Write(p)
	l.size += int64(n)
	return n, err
}

// rotate moves the file to path.1, replacing the previous one, and opens a new file.
func (l *rotatingLog) rotate() {
	if err := os.Rename(l.path, l.path+".1"); err != nil {
		return
	}
	file, err := openLogFile(l.path)
	if err != nil {
		return
	}
	_ = l.file.Close()
	l.file = file
	l.size = 0
}

// openLogFile opens the log for appending, readable only by the user.
func openLogFile(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
}

// openLog opens the structured log file, which keeps errors across restarts and rotates by size.
func openLog(path string) (*slog.Logger, func(), error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, nil, err
	}
	file, err := openLogFile(path)
	if err != nil {
		return nil, nil, err
	}
	info, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return nil, nil, err
	}
	log := &rotatingLog{path: path, file: file, size: info.Size()}
	logger := slog.New(slog.NewJSONHandler(log, nil))
	return logger, func() { _ = log.file.Close() }, nil
}

// buildServer creates the owner module of each external system and the API on top of them.
func buildServer(cfg config.Config, logger *slog.Logger) (*httpapi.Server, error) {
	static, err := webui.Handler()
	if err != nil {
		return nil, err
	}
	runner := &cliexec.Runner{WaitDelay: cfg.Timeouts.ProcessWait}
	hub := live.NewHub(logger)
	return httpapi.New(httpapi.Deps{
		Config: cfg,
		Colima: colima.NewService(runner, cfg.Binaries.Colima, cfg.Binaries.Sysctl, cfg.ColimaProfile, colima.Timeouts{
			Read:            cfg.Timeouts.Read,
			Start:           cfg.Timeouts.ColimaStart,
			Stop:            cfg.Timeouts.ColimaStop,
			KubernetesStart: cfg.Timeouts.KubernetesStart,
		}),
		Docker: docker.NewService(runner, cfg.Binaries.Docker, cfg.DockerHost, docker.Timeouts{
			Read:   cfg.Timeouts.Read,
			Action: cfg.Timeouts.DockerAction,
			Pull:   cfg.Timeouts.DockerPull,
		}),
		Compose: compose.NewService(runner, cfg.Binaries.Docker, cfg.DockerHost, cfg.HomeDir, cfg.StateDir, compose.Timeouts{
			Read:   cfg.Timeouts.Read,
			Action: cfg.Timeouts.ComposeAction,
		}, logger),
		Kube: kube.NewService(runner, cfg.Binaries.Kubectl, cfg.KubeContext, kube.Timeouts{
			Read:   cfg.Timeouts.Read,
			Action: cfg.Timeouts.KubeAction,
		}, cfg.Limits.ReplicasMaximum),
		Picker: filepicker.NewService(runner, cfg.Binaries.Osascript, cfg.Timeouts.FilePicker),
		Jobs: jobs.NewManager(jobs.Options{
			Kept:        cfg.Limits.JobsKept,
			OutputLines: cfg.Limits.JobOutputLines,
			Now:         time.Now,
			Logger:      logger,
			OnChange:    func() { hub.Refresh(httpapi.TopicJobs) },
			OnFinish: func() {
				hub.Refresh(httpapi.TopicEnvironment, httpapi.TopicDocker, httpapi.TopicKubernetes)
			},
		}),
		Hub:    hub,
		Static: static,
		Logger: logger,
	}), nil
}

// serve runs the HTTP server until a signal, then stops the streams and their processes.
// Running jobs are left alone: the launchd agent keeps them alive across a service restart.
func serve(cfg config.Config, server *httpapi.Server, listener net.Listener) error {
	signals, stopSignals := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stopSignals()
	base, cancelBase := context.WithCancel(context.Background())
	defer cancelBase()

	httpServer := &http.Server{
		Handler:           server,
		BaseContext:       func(net.Listener) context.Context { return base },
		ReadHeaderTimeout: cfg.Timeouts.HTTPHeader,
		ReadTimeout:       cfg.Timeouts.HTTPRead,
		WriteTimeout:      cfg.Timeouts.FilePicker + cfg.Timeouts.HTTPRead,
		IdleTimeout:       cfg.Timeouts.HTTPIdle,
		MaxHeaderBytes:    cfg.Limits.MaxHeaderBytes,
	}
	failed := make(chan error, 1)
	go func() { failed <- httpServer.Serve(listener) }()

	select {
	case err := <-failed:
		return err
	case <-signals.Done():
	}
	ctx, cancel := context.WithTimeout(context.Background(), cfg.Timeouts.Shutdown)
	defer cancel()
	cancelBase()
	err := httpServer.Shutdown(ctx)
	server.WaitForStreams(ctx)
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
