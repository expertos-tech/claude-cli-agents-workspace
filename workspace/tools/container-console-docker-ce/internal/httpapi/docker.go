package httpapi

import (
	"context"
	"encoding/json"
	"io"
	"net/http"

	"container-console-docker-ce/internal/docker"
	"container-console-docker-ce/internal/jobs"
)

// refAction is a Docker mutation on a validated id or name.
type refAction func(ctx context.Context, ref docker.Ref, out io.Writer) error

// refInspect is a Docker read of the details of a validated id or name.
type refInspect func(ctx context.Context, ref docker.Ref) (json.RawMessage, error)

// dockerRoutes declares the routes of containers, images, volumes and networks.
func (s *Server) dockerRoutes(mux *http.ServeMux) {
	handle(s, mux, "GET /api/containers/{id}", s.inspectRoute(s.Docker.InspectContainer))
	handle(s, mux, "GET /api/containers/{id}/stats", s.containerStats)
	handle(s, mux, "POST /api/containers/{id}/start", s.refActionRoute("container.start", false, s.Docker.StartContainer))
	handle(s, mux, "POST /api/containers/{id}/stop", s.refActionRoute("container.stop", false, s.Docker.StopContainer))
	handle(s, mux, "POST /api/containers/{id}/restart", s.refActionRoute("container.restart", false, s.Docker.RestartContainer))
	handle(s, mux, "POST /api/containers/{id}/remove", s.refActionRoute("container.remove", true, s.Docker.RemoveContainer))

	handle(s, mux, "POST /api/images/pull", s.imagePull)
	handle(s, mux, "POST /api/images/remove", s.imageRemove)

	handle(s, mux, "POST /api/volumes", s.createRoute("volume.create", s.Docker.CreateVolume))
	handle(s, mux, "GET /api/volumes/{id}", s.inspectRoute(s.Docker.InspectVolume))
	handle(s, mux, "POST /api/volumes/{id}/remove", s.refActionRoute("volume.remove", true, s.Docker.RemoveVolume))

	handle(s, mux, "POST /api/networks", s.createRoute("network.create", s.Docker.CreateNetwork))
	handle(s, mux, "GET /api/networks/{id}", s.inspectRoute(s.Docker.InspectNetwork))
	handle(s, mux, "POST /api/networks/{id}/remove", s.refActionRoute("network.remove", true, s.Docker.RemoveNetwork))
}

// inspectRoute builds the route that returns the raw details of a resource.
func (s *Server) inspectRoute(inspect refInspect) apiFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		ref, err := docker.ParseRef(r.PathValue("id"))
		if err != nil {
			return err
		}
		if err := s.requireEnvironmentOn(r.Context()); err != nil {
			return err
		}
		details, err := inspect(r.Context(), ref)
		if err != nil {
			return err
		}
		writeJSON(w, http.StatusOK, details)
		return nil
	}
}

// containerStats returns one reading of the resource usage.
func (s *Server) containerStats(w http.ResponseWriter, r *http.Request) error {
	ref, err := docker.ParseRef(r.PathValue("id"))
	if err != nil {
		return err
	}
	if err := s.requireEnvironmentOn(r.Context()); err != nil {
		return err
	}
	stats, err := s.Docker.ReadStats(r.Context(), ref)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, stats)
	return nil
}

// refActionRoute builds the route of a mutation on the id in the path. A route
// with needsConfirm refuses without `"confirm": true` before anything else runs.
func (s *Server) refActionRoute(kind string, needsConfirm bool, action refAction) apiFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		ref, err := docker.ParseRef(r.PathValue("id"))
		if err != nil {
			return err
		}
		if err := decodeConfirmation(r, needsConfirm); err != nil {
			return err
		}
		if err := s.requireEnvironmentOn(r.Context()); err != nil {
			return err
		}
		return s.submit(w, jobs.Spec{Kind: kind, Target: string(ref)}, func(ctx context.Context, out io.Writer) error {
			return action(ctx, ref, out)
		})
	}
}

// decodeConfirmation reads the body of an action, which only a removal may carry.
func decodeConfirmation(r *http.Request, needsConfirm bool) error {
	if !needsConfirm {
		return decodeBody(r, &struct{}{})
	}
	var body confirmBody
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	return requireConfirm(body.Confirm)
}

// createRoute builds the route that creates a named volume or network.
func (s *Server) createRoute(kind string, action refAction) apiFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		var body struct {
			Name string `json:"name"`
		}
		if err := decodeBody(r, &body); err != nil {
			return err
		}
		ref, err := docker.ParseRef(body.Name)
		if err != nil {
			return err
		}
		if err := s.requireEnvironmentOn(r.Context()); err != nil {
			return err
		}
		return s.submit(w, jobs.Spec{Kind: kind, Target: string(ref)}, func(ctx context.Context, out io.Writer) error {
			return action(ctx, ref, out)
		})
	}
}

// imagePull downloads an image. An image reference holds slashes, so it travels in the body.
func (s *Server) imagePull(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Reference string `json:"reference"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	ref, err := docker.ParseImageRef(body.Reference)
	if err != nil {
		return err
	}
	if err := s.requireEnvironmentOn(r.Context()); err != nil {
		return err
	}
	return s.submit(w, jobs.Spec{Kind: "image.pull", Target: string(ref)}, func(ctx context.Context, out io.Writer) error {
		return s.Docker.PullImage(ctx, ref, out)
	})
}

// imageRemove removes an image, after explicit confirmation.
func (s *Server) imageRemove(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Reference string `json:"reference"`
		Confirm   bool   `json:"confirm"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	ref, err := docker.ParseImageRef(body.Reference)
	if err != nil {
		return err
	}
	if err := requireConfirm(body.Confirm); err != nil {
		return err
	}
	if err := s.requireEnvironmentOn(r.Context()); err != nil {
		return err
	}
	return s.submit(w, jobs.Spec{Kind: "image.remove", Target: string(ref)}, func(ctx context.Context, out io.Writer) error {
		return s.Docker.RemoveImage(ctx, ref, out)
	})
}
