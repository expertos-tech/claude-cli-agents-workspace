// Command container-console-docker-ce serves the local console of the container environment.
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

	"container-console-docker-ce/internal/cliexec"
	"container-console-docker-ce/internal/compose"
	"container-console-docker-ce/internal/config"
	"container-console-docker-ce/internal/docker"
	"container-console-docker-ce/internal/engine"
	"container-console-docker-ce/internal/filepicker"
	"container-console-docker-ce/internal/httpapi"
	"container-console-docker-ce/internal/jobs"
	"container-console-docker-ce/internal/kube"
	"container-console-docker-ce/internal/live"
	"container-console-docker-ce/internal/webui"
)

// main reports a startup or serving failure and exits with an error status.
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "container-console-docker-ce:", err)
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
	logger.Info("service started", "port", cfg.Port)
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

// openLog creates the structured log file, truncated at each start and readable only by the user.
func openLog(path string) (*slog.Logger, func(), error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, nil, err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return nil, nil, err
	}
	logger := slog.New(slog.NewJSONHandler(file, nil))
	return logger, func() { _ = file.Close() }, nil
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
		Engine: engine.NewService(runner, cfg.Binaries.Docker, cfg.DockerHost, cfg.Timeouts.Read),
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
		Picker: filepicker.NewService(runner, cfg.Binaries.Zenity, cfg.Timeouts.FilePicker),
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
// Running jobs are left alone: with KillMode=process in the systemd unit, a restart does not signal their CLIs.
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
