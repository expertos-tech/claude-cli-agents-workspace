// Command azurite-console is a proof of concept: a page to see and operate a
// local Azurite (containers and blobs, queues and messages, tables and
// entities) and to read its access log. The browser talks only to this
// program, which signs the calls to Azurite with the development account.
//
// Run from this folder, with the Azurite of compose.yaml up and the page built:
//
//	npm --prefix web ci
//	npm --prefix web run build
//	go run . -env-file ../../custom/env/azurite-console.env [-addr 127.0.0.1:28091] [-host 127.0.0.1] [-azurite-port 30000]
//
// The account key is AZURITE_ACCOUNT_KEY, from the environment or from the file
// of -env-file (the workspace's custom/env/azurite-console.env).
// Only a local Azurite is accepted, and the server listens only on loopback,
// except with -container: in Compose it listens on every interface of the
// container, whose port Compose publishes only on 127.0.0.1. The -healthcheck
// flag probes the running instance and exits, for a container without a
// shell. Logs are JSON on stdout.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"azurite-console/internal/activity"
	"azurite-console/internal/api"
	"azurite-console/internal/azurite"
	"azurite-console/internal/httpjson"
	"azurite-console/internal/storage"
)

const (
	// clientTimeout bounds one call to Azurite, a whole download included.
	clientTimeout = 5 * time.Minute
	// dialTimeout bounds the connection: Azurite is local, so a connection
	// that takes longer means it is down.
	dialTimeout = 3 * time.Second
	// countLimit stops the counts of the overview in each container and table.
	countLimit = 10_000
	// keptOperations is how many actions of the console the page lists.
	keptOperations = 200
	// readHeaderTimeout bounds the wait for the headers of a request.
	readHeaderTimeout = 10 * time.Second
	// idleTimeout closes a keep-alive connection without requests.
	idleTimeout = 2 * time.Minute
	// shutdownTimeout bounds the wait for requests in flight on SIGINT or
	// SIGTERM; it stays under the 10 s Compose gives before killing the container.
	shutdownTimeout = 8 * time.Second
	// probeTimeout bounds the call of -healthcheck.
	probeTimeout = 3 * time.Second
)

// options are the command line flags.
type options struct {
	addr, host, web string
	envFile         string
	azuritePort     int
	maxUpload       int64
	container       bool
}

// main parses the flags and runs the probe or the server until a signal.
func main() {
	var o options
	flag.StringVar(&o.addr, "addr", "127.0.0.1:28091", "listen address; only loopback is accepted, unless -container")
	flag.StringVar(&o.host, "host", "127.0.0.1", "host of Azurite: loopback, localhost or azurite")
	flag.IntVar(&o.azuritePort, "azurite-port", azurite.HostPort, "first of the three consecutive ports of Azurite (blob, queue, table)")
	flag.StringVar(&o.web, "web", "web/dist", "folder of the built page")
	flag.StringVar(&o.envFile, "env-file", "", "KEY=VALUE file read for AZURITE_ACCOUNT_KEY when the environment lacks it (custom/env/azurite-console.env)")
	flag.Int64Var(&o.maxUpload, "max-upload", 64<<20, "largest request body, uploads included, in bytes")
	flag.BoolVar(&o.container, "container", false, "run in Compose: accept any listen address, since Compose publishes the port only on 127.0.0.1")
	healthcheck := flag.Bool("healthcheck", false, "probe the local /healthz at -addr and exit with 0 when healthy")
	flag.Parse()
	if *healthcheck {
		os.Exit(probe(o.addr))
	}

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	err := run(ctx, o)
	stop()
	if err != nil {
		slog.Error("azurite-console failed", slog.Any("error", err))
		os.Exit(1)
	}
}

// run builds the clients and the routes and serves until ctx ends.
func run(ctx context.Context, o options) error {
	if !o.container {
		if err := loopback(o.addr); err != nil {
			return err
		}
	}
	key, err := azurite.LookupKey(o.envFile)
	if err != nil {
		return err
	}
	account, err := azurite.New(o.host, key, o.azuritePort)
	if err != nil {
		return err
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.DialContext = (&net.Dialer{Timeout: dialTimeout}).DialContext
	clients, err := account.Clients(&http.Client{Timeout: clientTimeout, Transport: transport})
	if err != nil {
		return err
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", healthz)
	api.New(api.Config{
		Blobs:      storage.NewBlobs(clients.Blob),
		Queues:     storage.NewQueues(clients.Queue),
		Tables:     storage.NewTables(clients.Table),
		Log:        activity.NewDocker(activity.ExecDocker),
		Ops:        activity.NewOperations(keptOperations),
		WebDir:     o.web,
		CountLimit: countLimit,
	}).Register(mux)

	listener, err := (&net.ListenConfig{}).Listen(ctx, "tcp", o.addr)
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	slog.InfoContext(ctx, "azurite-console ready", slog.String("addr", "http://"+o.addr), slog.String("azurite", account.Host()),
		slog.Int("azurite_port", o.azuritePort), slog.String("web", o.web), slog.Int64("max_upload", o.maxUpload), slog.Bool("container", o.container))
	return serve(ctx, &http.Server{
		Handler:           limitBody(mux, o.maxUpload),
		ReadHeaderTimeout: readHeaderTimeout,
		WriteTimeout:      clientTimeout,
		IdleTimeout:       idleTimeout,
	}, listener)
}

// serve answers on listener until ctx ends, then waits for the requests in
// flight, up to shutdownTimeout.
func serve(ctx context.Context, srv *http.Server, listener net.Listener) error {
	failed := make(chan error, 1)
	go func() { failed <- srv.Serve(listener) }()
	select {
	case err := <-failed:
		return err
	case <-ctx.Done():
	}
	slog.Info("azurite-console stopping")
	shutdown, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdown); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	return nil
}

// limitBody refuses a request body over limit; the handlers see it as an
// *http.MaxBytesError when they read the body.
func limitBody(next http.Handler, limit int64) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, limit)
		next.ServeHTTP(w, r)
	})
}

// healthz says the program is up. It does not call Azurite: with Azurite
// down the console is still healthy, and its page shows the failure.
func healthz(w http.ResponseWriter, r *http.Request) {
	httpjson.WriteJSON(w, r, http.StatusOK, map[string]string{"status": "ok"})
}

// probe calls the /healthz of the instance at addr and returns the exit code:
// 0 when it answers 200, 1 otherwise. An address without a host, as in
// ":28091", is reached through loopback.
func probe(addr string) int {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return 1
	}
	if ip := net.ParseIP(host); host == "" || (ip != nil && ip.IsUnspecified()) {
		host = "127.0.0.1"
	}
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://"+net.JoinHostPort(host, port)+"/healthz", http.NoBody)
	if err != nil {
		return 1
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 1
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

// loopback refuses a listen address outside loopback: the console deletes
// data and has no login.
func loopback(addr string) error {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return fmt.Errorf("addr %q: %w", addr, err)
	}
	if host == "localhost" {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return errors.New("addr must listen on loopback (127.0.0.1, ::1 or localhost)")
	}
	return nil
}
