package httpapi

import (
	"context"
	"io"
	"net/http"

	"container-console-colima/internal/colima"
	"container-console-colima/internal/fault"
	"container-console-colima/internal/jobs"
)

const environmentExclusive = "environment"

// environmentRoutes declares the routes of the environment and of its mode.
func (s *Server) environmentRoutes(mux *http.ServeMux) {
	handle(s, mux, "POST /api/environment/start", s.environmentStart)
	handle(s, mux, "POST /api/environment/stop", s.environmentStop)
	handle(s, mux, "POST /api/environment/resources", s.environmentResources)
	handle(s, mux, "POST /api/environment/kubernetes/start", s.kubernetesStart)
	handle(s, mux, "POST /api/environment/kubernetes/stop", s.kubernetesStop)
}

// environmentSpec describes a job of the environment. There is one at a time; a second gets 409.
func (s *Server) environmentSpec(kind string) jobs.Spec {
	return jobs.Spec{Kind: kind, Target: s.Config.ColimaProfile, Exclusive: environmentExclusive}
}

// environmentStart turns the VM on in the chosen mode, with optional new resources.
func (s *Server) environmentStart(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Kubernetes bool `json:"kubernetes"`
		CPUs       *int `json:"cpus"`
		MemoryGiB  *int `json:"memoryGiB"`
		DiskGiB    *int `json:"diskGiB"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	state := s.Colima.CurrentState(r.Context())
	if state == colima.StateOn || state == colima.StateStarting || state == colima.StateStopping {
		return stateConflict("environment_not_off", "the environment is not off", state)
	}
	resources := colima.Resources{CPUs: body.CPUs, MemoryGiB: body.MemoryGiB, DiskGiB: body.DiskGiB}
	if err := s.Colima.ValidateResources(r.Context(), resources); err != nil {
		return err
	}
	return s.submit(w, s.environmentSpec("environment.start"), func(ctx context.Context, out io.Writer) error {
		return s.Colima.Start(ctx, body.Kubernetes, resources, out)
	})
}

// environmentStop turns the VM off, after the confirmation that lists what stops.
func (s *Server) environmentStop(w http.ResponseWriter, r *http.Request) error {
	var body confirmBody
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if err := requireConfirm(body.Confirm); err != nil {
		return err
	}
	state := s.Colima.CurrentState(r.Context())
	if state != colima.StateOn && state != colima.StateUnknown {
		return stateConflict("environment_not_on", "the environment is not on", state)
	}
	return s.submit(w, s.environmentSpec("environment.stop"), s.Colima.Stop)
}

// environmentResources applies new resources to a running VM, which restarts it. With the
// VM off the values go with the start request, since Colima only applies them when starting.
func (s *Server) environmentResources(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		CPUs      *int `json:"cpus"`
		MemoryGiB *int `json:"memoryGiB"`
		DiskGiB   *int `json:"diskGiB"`
		Confirm   bool `json:"confirm"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if err := requireConfirm(body.Confirm); err != nil {
		return err
	}
	if body.CPUs == nil && body.MemoryGiB == nil && body.DiskGiB == nil {
		return fault.Invalid("resources_empty", "at least one of cpus, memoryGiB and diskGiB is required")
	}
	snapshot := s.Colima.Snapshot(r.Context())
	if snapshot.State != colima.StateOn {
		return stateConflict("environment_not_on", "the environment is not on", snapshot.State)
	}
	resources := colima.Resources{CPUs: body.CPUs, MemoryGiB: body.MemoryGiB, DiskGiB: body.DiskGiB}
	if err := s.Colima.ValidateResources(r.Context(), resources); err != nil {
		return err
	}
	hooks := colima.RestartHooks{Capture: s.Docker.RunningContainerIDs, Restore: s.Docker.StartContainers}
	return s.submit(w, s.environmentSpec("environment.resources"), func(ctx context.Context, out io.Writer) error {
		return s.Colima.Restart(ctx, snapshot.Kubernetes.Enabled, resources, hooks, out)
	})
}

// kubernetesStart turns Kubernetes on without restarting the VM.
func (s *Server) kubernetesStart(w http.ResponseWriter, r *http.Request) error {
	if err := decodeBody(r, &struct{}{}); err != nil {
		return err
	}
	snapshot := s.Colima.Snapshot(r.Context())
	if snapshot.State != colima.StateOn {
		return stateConflict("environment_not_on", "the environment is not on", snapshot.State)
	}
	if snapshot.Kubernetes.Enabled {
		return fault.Conflict("kubernetes_already_on", "kubernetes is already on")
	}
	return s.submit(w, s.environmentSpec("kubernetes.start"), func(ctx context.Context, out io.Writer) error {
		return s.Colima.SetKubernetes(ctx, true, out)
	})
}

// kubernetesStop turns Kubernetes off, after the confirmation that says the pods stop.
// Colima fails when it is already off, so that state is refused first.
func (s *Server) kubernetesStop(w http.ResponseWriter, r *http.Request) error {
	var body confirmBody
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if err := requireConfirm(body.Confirm); err != nil {
		return err
	}
	snapshot := s.Colima.Snapshot(r.Context())
	if snapshot.State != colima.StateOn {
		return stateConflict("environment_not_on", "the environment is not on", snapshot.State)
	}
	if !snapshot.Kubernetes.Enabled {
		return fault.Conflict("kubernetes_already_off", "kubernetes is already off")
	}
	return s.submit(w, s.environmentSpec("kubernetes.stop"), func(ctx context.Context, out io.Writer) error {
		return s.Colima.SetKubernetes(ctx, false, out)
	})
}

// stateConflict builds the 409 of an action the environment state refuses.
func stateConflict(code, message string, state colima.State) error {
	return fault.Conflict(code, message).WithParams(map[string]any{"state": state})
}

// requireEnvironmentOn refuses Docker actions while the VM is not running.
func (s *Server) requireEnvironmentOn(ctx context.Context) error {
	state := s.Colima.CurrentState(ctx)
	if state != colima.StateOn {
		return stateConflict("environment_not_on", "the environment is not on", state)
	}
	return nil
}

// requireKubernetesOn refuses Kubernetes actions while Kubernetes is not running.
func (s *Server) requireKubernetesOn(ctx context.Context) error {
	snapshot := s.Colima.Snapshot(ctx)
	if snapshot.State != colima.StateOn {
		return stateConflict("environment_not_on", "the environment is not on", snapshot.State)
	}
	if !snapshot.Kubernetes.Enabled || snapshot.Kubernetes.Transition != "" {
		return fault.Conflict("kubernetes_not_on", "kubernetes is not on")
	}
	return nil
}
