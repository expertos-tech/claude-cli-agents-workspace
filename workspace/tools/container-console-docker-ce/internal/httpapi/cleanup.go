package httpapi

import (
	"context"
	"io"
	"net/http"

	"container-console-docker-ce/internal/jobs"
)

// cleanupRoutes declares the summary and the run of the cleanup of what is not in use.
func (s *Server) cleanupRoutes(mux *http.ServeMux) {
	handle(s, mux, "GET /api/cleanup", s.cleanupSummary)
	handle(s, mux, "POST /api/cleanup", s.cleanupRun)
}

// cleanupSummary lists what the cleanup would remove now.
func (s *Server) cleanupSummary(w http.ResponseWriter, r *http.Request) error {
	if err := s.requireEnvironmentOn(r.Context()); err != nil {
		return err
	}
	summary, err := s.Docker.CleanupSummary(r.Context())
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, summary)
	return nil
}

// cleanupRun removes what is not in use, after explicit confirmation. Volumes only on request.
func (s *Server) cleanupRun(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Confirm bool `json:"confirm"`
		Volumes bool `json:"volumes"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if err := requireConfirm(body.Confirm); err != nil {
		return err
	}
	if err := s.requireEnvironmentOn(r.Context()); err != nil {
		return err
	}
	target := ""
	if body.Volumes {
		target = "volumes"
	}
	return s.submit(w, jobs.Spec{Kind: "docker.cleanup", Target: target}, func(ctx context.Context, out io.Writer) error {
		return s.Docker.Cleanup(ctx, body.Volumes, out)
	})
}
