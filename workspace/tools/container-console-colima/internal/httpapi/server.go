// Package httpapi is the only entry point of the service: the guard, the REST routes
// and the WebSocket bridges of topics, logs and terminals.
package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"sync"

	"container-console-colima/internal/colima"
	"container-console-colima/internal/compose"
	"container-console-colima/internal/config"
	"container-console-colima/internal/docker"
	"container-console-colima/internal/filepicker"
	"container-console-colima/internal/jobs"
	"container-console-colima/internal/kube"
	"container-console-colima/internal/live"
)

// Deps are the collaborators of the API.
type Deps struct {
	Config  config.Config
	Colima  *colima.Service
	Docker  *docker.Service
	Compose *compose.Service
	Kube    *kube.Service
	Picker  *filepicker.Service
	Jobs    *jobs.Manager
	Hub     *live.Hub
	Static  http.Handler
	Logger  *slog.Logger
}

// Server serves the whole HTTP surface.
type Server struct {
	Deps
	handler   http.Handler
	terminals chan struct{}
	streams   sync.WaitGroup
}

// New registers the live topics and builds the guarded handler.
func New(deps Deps) *Server {
	s := &Server{Deps: deps, terminals: make(chan struct{}, deps.Config.Limits.MaxTerminals)}
	s.registerTopics()
	s.handler = s.guard(s.routes())
	return s
}

// ServeHTTP implements http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.handler.ServeHTTP(w, r)
}

// WaitForStreams waits for the WebSocket handlers, whose request context the caller already
// canceled, so log and terminal processes end before the service exits.
func (s *Server) WaitForStreams(ctx context.Context) {
	done := make(chan struct{})
	go func() {
		s.streams.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-ctx.Done():
	}
}

// apiFunc is a REST handler that returns its error instead of writing it.
type apiFunc func(w http.ResponseWriter, r *http.Request) error

// routes declares every route of the service. docs/api.md is the contract of this list.
func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.Handle("GET /", s.Static)

	s.environmentRoutes(mux)
	s.dockerRoutes(mux)
	s.composeRoutes(mux)
	s.kubernetesRoutes(mux)
	handle(s, mux, "GET /api/jobs/{id}", s.getJob)
	handle(s, mux, "GET /api/", notFoundRoute)
	handle(s, mux, "POST /api/", notFoundRoute)

	s.websocketRoute(mux, "GET /ws/live/{topic}", s.serveLive)
	s.websocketRoute(mux, "GET /ws/logs/containers/{id}", s.serveContainerLogs)
	s.websocketRoute(mux, "GET /ws/logs/pods/{namespace}/{name}", s.servePodLogs)
	s.websocketRoute(mux, "GET /ws/terminal/containers/{id}", s.serveContainerTerminal)
	s.websocketRoute(mux, "GET /ws/terminal/pods/{namespace}/{name}", s.servePodTerminal)
	return mux
}

// handle registers a REST handler and writes the error it returns.
func handle(s *Server, mux *http.ServeMux, pattern string, fn apiFunc) {
	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		if err := fn(w, r); err != nil {
			s.writeError(w, r, err)
		}
	})
}

// healthz answers the Dock icon script.
func (s *Server) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// getJob returns one job, for a client that lost the jobs topic.
func (s *Server) getJob(w http.ResponseWriter, r *http.Request) error {
	job, found := s.Jobs.Get(r.PathValue("id"))
	if !found {
		return errJobNotFound
	}
	writeJSON(w, http.StatusOK, map[string]any{"job": job})
	return nil
}
