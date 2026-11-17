package httpapi

import (
	"context"

	"container-console-docker-ce/internal/engine"
	"container-console-docker-ce/internal/fault"
)

// requireEnvironmentOn refuses Docker actions while the daemon does not answer.
func (s *Server) requireEnvironmentOn(ctx context.Context) error {
	state := s.Engine.CurrentState(ctx)
	if state != engine.StateOn {
		return fault.Conflict("environment_not_on", "the docker daemon is not on").
			WithParams(map[string]any{"state": state})
	}
	return nil
}

// requireKubernetesReachable refuses Kubernetes actions while no cluster answers.
// The message is the error kubectl gave, which the screen shows as received.
func (s *Server) requireKubernetesReachable(ctx context.Context) error {
	if err := s.Kube.Ping(ctx); err != nil {
		return fault.Conflict("kubernetes_unavailable", err.Error())
	}
	return nil
}
