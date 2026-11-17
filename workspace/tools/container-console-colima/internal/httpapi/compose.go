package httpapi

import (
	"context"
	"io"
	"net/http"

	"container-console-colima/internal/compose"
	"container-console-colima/internal/jobs"
)

// composeAction is a Compose mutation on a known project.
type composeAction func(ctx context.Context, name string, out io.Writer) error

// composeRoutes declares the routes of Compose projects and of the file dialog.
func (s *Server) composeRoutes(mux *http.ServeMux) {
	handle(s, mux, "POST /api/compose/file-dialog", s.composeFileDialog)
	handle(s, mux, "POST /api/compose/projects", s.composeAdd)
	handle(s, mux, "POST /api/compose/projects/{name}/up", s.composeActionRoute("compose.up", s.Compose.Up))
	handle(s, mux, "POST /api/compose/projects/{name}/stop", s.composeActionRoute("compose.stop", s.Compose.Stop))
	handle(s, mux, "POST /api/compose/projects/{name}/remove", s.composeRemove)
}

// composeFileDialog opens the native dialog and returns the chosen path. It only reads,
// so it is not a job, and it ends with the request if the page goes away.
func (s *Server) composeFileDialog(w http.ResponseWriter, r *http.Request) error {
	if err := decodeBody(r, &struct{}{}); err != nil {
		return err
	}
	path, canceled, err := s.Picker.PickYAML(r.Context())
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": path, "canceled": canceled})
	return nil
}

// composeAdd remembers the project of a file chosen by the user. It needs no daemon and
// is short, so it answers directly instead of starting a job.
func (s *Server) composeAdd(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Path string `json:"path"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	project, err := s.Compose.Add(r.Context(), body.Path)
	if err != nil {
		return err
	}
	s.Hub.Refresh(TopicDocker)
	writeJSON(w, http.StatusCreated, map[string]any{"project": project})
	return nil
}

// composeActionRoute builds the route of a mutation on a known project.
func (s *Server) composeActionRoute(kind string, action composeAction) apiFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		name, err := s.prepareCompose(r)
		if err != nil {
			return err
		}
		if err := decodeBody(r, &struct{}{}); err != nil {
			return err
		}
		return s.submit(w, jobs.Spec{Kind: kind, Target: name}, func(ctx context.Context, out io.Writer) error {
			return action(ctx, name, out)
		})
	}
}

// composeRemove runs `down` after explicit confirmation. Volumes stay unless asked.
func (s *Server) composeRemove(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Confirm       bool `json:"confirm"`
		RemoveVolumes bool `json:"removeVolumes"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if err := requireConfirm(body.Confirm); err != nil {
		return err
	}
	name, err := s.prepareCompose(r)
	if err != nil {
		return err
	}
	return s.submit(w, jobs.Spec{Kind: "compose.remove", Target: name}, func(ctx context.Context, out io.Writer) error {
		return s.Compose.Remove(ctx, name, body.RemoveVolumes, out)
	})
}

// prepareCompose validates the name, the environment state and that the project has usable files.
func (s *Server) prepareCompose(r *http.Request) (string, error) {
	name, err := compose.ParseName(r.PathValue("name"))
	if err != nil {
		return "", err
	}
	if err := s.requireEnvironmentOn(r.Context()); err != nil {
		return "", err
	}
	if err := s.Compose.RequireKnown(r.Context(), name); err != nil {
		return "", err
	}
	return name, nil
}
