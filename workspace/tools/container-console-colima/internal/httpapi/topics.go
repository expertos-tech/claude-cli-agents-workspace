package httpapi

import (
	"context"

	"container-console-colima/internal/colima"
	"container-console-colima/internal/compose"
	"container-console-colima/internal/docker"
	"container-console-colima/internal/jobs"
	"container-console-colima/internal/kube"
	"container-console-colima/internal/live"
)

// Names of the live topics.
const (
	TopicEnvironment = "environment"
	TopicDocker      = "docker"
	TopicKubernetes  = "kubernetes"
	TopicJobs        = "jobs"
)

// dockerTopic is the snapshot of the docker topic.
type dockerTopic struct {
	Available       bool              `json:"available"`
	ReasonCode      string            `json:"reasonCode,omitempty"`
	Reason          string            `json:"reason,omitempty"`
	ComposeProjects []compose.Project `json:"composeProjects"`
	docker.Snapshot
}

// kubernetesTopic is the snapshot of the kubernetes topic.
type kubernetesTopic struct {
	Available  bool   `json:"available"`
	ReasonCode string `json:"reasonCode,omitempty"`
	Reason     string `json:"reason,omitempty"`
	kube.Snapshot
}

// jobsTopic is the snapshot of the jobs topic.
type jobsTopic struct {
	Jobs []jobs.Job `json:"jobs"`
}

// registerTopics connects each topic to its source and cadence.
func (s *Server) registerTopics() {
	intervals := s.Config.Intervals
	s.Hub.Register(TopicEnvironment, live.Loop(live.LoopOptions{
		Fetch:    func(ctx context.Context) any { return s.Colima.Snapshot(ctx) },
		Interval: intervals.Environment,
	}))
	s.Hub.Register(TopicDocker, live.Loop(live.LoopOptions{
		Fetch:    func(ctx context.Context) any { return s.dockerSnapshot(ctx) },
		Interval: intervals.DockerSync,
		Debounce: intervals.DockerDebounce,
		Watch: func(ctx context.Context, notify func()) {
			s.Docker.WatchEvents(ctx, intervals.EventsRetry, notify)
		},
	}))
	s.Hub.Register(TopicKubernetes, live.Loop(live.LoopOptions{
		Fetch:    func(ctx context.Context) any { return s.kubernetesSnapshot(ctx) },
		Interval: intervals.Kubernetes,
	}))
	s.Hub.Register(TopicJobs, live.Loop(live.LoopOptions{
		Fetch: func(context.Context) any { return jobsTopic{Jobs: s.Jobs.Snapshot()} },
	}))
}

// dockerSnapshot reads the lists. On failure it says why: the environment state when
// the VM is not running, and otherwise the error received. Known projects always appear.
func (s *Server) dockerSnapshot(ctx context.Context) dockerTopic {
	list, err := s.Docker.List(ctx)
	topic := dockerTopic{Available: err == nil, Snapshot: list, ComposeProjects: s.Compose.List(ctx)}
	if err == nil {
		return topic
	}
	topic.Reason = err.Error()
	topic.ReasonCode = "docker_error"
	if state := s.Colima.CurrentState(ctx); state != colima.StateOn {
		topic.ReasonCode = "environment_not_on"
	}
	return topic
}

// kubernetesSnapshot reads the lists. kubectl goes first because the usual case then
// costs one process; Colima is only asked to explain a failure.
func (s *Server) kubernetesSnapshot(ctx context.Context) kubernetesTopic {
	list, err := s.Kube.List(ctx)
	if err == nil {
		return kubernetesTopic{Available: true, Snapshot: list}
	}
	topic := kubernetesTopic{Snapshot: list, Reason: err.Error(), ReasonCode: "kubernetes_error"}
	snapshot := s.Colima.Snapshot(ctx)
	switch {
	case snapshot.State != colima.StateOn:
		topic.ReasonCode = "environment_not_on"
	case !snapshot.Kubernetes.Enabled:
		topic.ReasonCode = "kubernetes_not_on"
	}
	return topic
}
