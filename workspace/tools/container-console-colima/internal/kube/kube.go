// Package kube owns every call to kubectl: reads, actions, YAML apply, logs and terminals.
package kube

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"container-console-colima/internal/cliexec"
	"container-console-colima/internal/fault"
)

const (
	logTailArg     = "--tail=500"
	terminalScript = "command -v bash >/dev/null 2>&1 && exec bash || exec sh"
)

// Timeouts are the deadlines of the kubectl calls.
type Timeouts struct {
	Read   time.Duration
	Action time.Duration
}

// Service is the owner of the kubectl integration.
type Service struct {
	runner      *cliexec.Runner
	binary      string
	context     string
	timeouts    Timeouts
	maxReplicas int
}

// NewService builds the Service for one kubectl context.
func NewService(runner *cliexec.Runner, binary, kubeContext string, timeouts Timeouts, maxReplicas int) *Service {
	return &Service{runner: runner, binary: binary, context: kubeContext, timeouts: timeouts, maxReplicas: maxReplicas}
}

// NamespaceRow is one row of the namespace list.
type NamespaceRow struct {
	Name      string `json:"name"`
	Status    string `json:"status"`
	CreatedAt string `json:"createdAt"`
}

// PodRow is one row of the pod list.
type PodRow struct {
	Namespace  string   `json:"namespace"`
	Name       string   `json:"name"`
	Status     string   `json:"status"`
	Ready      string   `json:"ready"`
	Restarts   int      `json:"restarts"`
	IP         string   `json:"ip"`
	Containers []string `json:"containers"`
	CreatedAt  string   `json:"createdAt"`
}

// DeploymentRow is one row of the deployment list.
type DeploymentRow struct {
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
	Replicas  int    `json:"replicas"`
	Ready     int    `json:"ready"`
	Updated   int    `json:"updated"`
	Available int    `json:"available"`
	CreatedAt string `json:"createdAt"`
}

// ServiceRow is one row of the service list.
type ServiceRow struct {
	Namespace string   `json:"namespace"`
	Name      string   `json:"name"`
	Type      string   `json:"type"`
	ClusterIP string   `json:"clusterIP"`
	Ports     []string `json:"ports"`
	CreatedAt string   `json:"createdAt"`
}

// Snapshot holds all the lists of the Kubernetes screens.
type Snapshot struct {
	Namespaces  []NamespaceRow  `json:"namespaces"`
	Pods        []PodRow        `json:"pods"`
	Deployments []DeploymentRow `json:"deployments"`
	Services    []ServiceRow    `json:"services"`
}

// EmptySnapshot returns lists that encode as [] rather than null.
func EmptySnapshot() Snapshot {
	return Snapshot{
		Namespaces:  []NamespaceRow{},
		Pods:        []PodRow{},
		Deployments: []DeploymentRow{},
		Services:    []ServiceRow{},
	}
}

// baseArgs starts every command with the context of the profile.
func (s *Service) baseArgs(args ...string) []string {
	return append([]string{"--context", s.context}, args...)
}

// readArgs adds the client-side deadline, which also covers a cluster that accepts and hangs.
func (s *Service) readArgs(args ...string) []string {
	return append(s.baseArgs("--request-timeout="+s.timeouts.Read.String()), args...)
}

// List reads the four kinds in one call and splits the result by kind.
func (s *Service) List(ctx context.Context) (Snapshot, error) {
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    s.readArgs("get", "namespaces,pods,deployments,services", "-A", "-o", "json"),
		Timeout: s.timeouts.Read,
	})
	if err != nil {
		return EmptySnapshot(), err
	}
	var list struct {
		Items []resource `json:"items"`
	}
	if err := json.Unmarshal(out, &list); err != nil {
		return EmptySnapshot(), errors.New("kubectl returned an unexpected format")
	}
	return buildSnapshot(list.Items), nil
}

// resource holds the fields read from kubectl JSON, tolerating everything else.
type resource struct {
	Kind     string `json:"kind"`
	Metadata struct {
		Name              string  `json:"name"`
		Namespace         string  `json:"namespace"`
		CreationTimestamp string  `json:"creationTimestamp"`
		DeletionTimestamp *string `json:"deletionTimestamp"`
	} `json:"metadata"`
	Spec struct {
		Replicas   *int   `json:"replicas"`
		Type       string `json:"type"`
		ClusterIP  string `json:"clusterIP"`
		Containers []struct {
			Name string `json:"name"`
		} `json:"containers"`
		Ports []struct {
			Port     int    `json:"port"`
			NodePort int    `json:"nodePort"`
			Protocol string `json:"protocol"`
		} `json:"ports"`
	} `json:"spec"`
	Status struct {
		Phase             string `json:"phase"`
		PodIP             string `json:"podIP"`
		ReadyReplicas     int    `json:"readyReplicas"`
		UpdatedReplicas   int    `json:"updatedReplicas"`
		AvailableReplicas int    `json:"availableReplicas"`
		ContainerStatuses []struct {
			Ready        bool `json:"ready"`
			RestartCount int  `json:"restartCount"`
			State        struct {
				Waiting *struct {
					Reason string `json:"reason"`
				} `json:"waiting"`
			} `json:"state"`
		} `json:"containerStatuses"`
	} `json:"status"`
}

// buildSnapshot sends each item to the list of its kind.
func buildSnapshot(items []resource) Snapshot {
	snapshot := EmptySnapshot()
	for _, item := range items {
		switch item.Kind {
		case "Namespace":
			snapshot.Namespaces = append(snapshot.Namespaces, NamespaceRow{
				Name:      item.Metadata.Name,
				Status:    item.Status.Phase,
				CreatedAt: item.Metadata.CreationTimestamp,
			})
		case "Pod":
			snapshot.Pods = append(snapshot.Pods, podRow(item))
		case "Deployment":
			snapshot.Deployments = append(snapshot.Deployments, deploymentRow(item))
		case "Service":
			snapshot.Services = append(snapshot.Services, serviceRow(item))
		}
	}
	return snapshot
}

// podRow summarizes a pod the way `kubectl get pods` does.
func podRow(item resource) PodRow {
	row := PodRow{
		Namespace:  item.Metadata.Namespace,
		Name:       item.Metadata.Name,
		Status:     item.Status.Phase,
		IP:         item.Status.PodIP,
		Containers: []string{},
		CreatedAt:  item.Metadata.CreationTimestamp,
	}
	for _, container := range item.Spec.Containers {
		row.Containers = append(row.Containers, container.Name)
	}
	ready := 0
	for _, status := range item.Status.ContainerStatuses {
		row.Restarts += status.RestartCount
		if status.Ready {
			ready++
		}
		if status.State.Waiting != nil && status.State.Waiting.Reason != "" {
			row.Status = status.State.Waiting.Reason
		}
	}
	if item.Metadata.DeletionTimestamp != nil {
		row.Status = "Terminating"
	}
	row.Ready = fmt.Sprintf("%d/%d", ready, len(item.Spec.Containers))
	return row
}

// deploymentRow summarizes a deployment.
func deploymentRow(item resource) DeploymentRow {
	row := DeploymentRow{
		Namespace: item.Metadata.Namespace,
		Name:      item.Metadata.Name,
		Ready:     item.Status.ReadyReplicas,
		Updated:   item.Status.UpdatedReplicas,
		Available: item.Status.AvailableReplicas,
		CreatedAt: item.Metadata.CreationTimestamp,
	}
	if item.Spec.Replicas != nil {
		row.Replicas = *item.Spec.Replicas
	}
	return row
}

// serviceRow summarizes a service, with ports such as 80:30080/TCP.
func serviceRow(item resource) ServiceRow {
	row := ServiceRow{
		Namespace: item.Metadata.Namespace,
		Name:      item.Metadata.Name,
		Type:      item.Spec.Type,
		ClusterIP: item.Spec.ClusterIP,
		Ports:     []string{},
		CreatedAt: item.Metadata.CreationTimestamp,
	}
	for _, port := range item.Spec.Ports {
		text := strconv.Itoa(port.Port)
		if port.NodePort != 0 {
			text += ":" + strconv.Itoa(port.NodePort)
		}
		row.Ports = append(row.Ports, text+"/"+port.Protocol)
	}
	return row
}

// Inspect returns the raw JSON of one resource.
func (s *Service) Inspect(ctx context.Context, target Target) (json.RawMessage, error) {
	args := append(append([]string{"get", string(target.Kind)}, target.scopeArgs()...), "-o", "json", "--", target.Name)
	out, err := s.runner.Run(ctx, cliexec.Command{Binary: s.binary, Args: s.readArgs(args...), Timeout: s.timeouts.Read})
	if err != nil {
		var cliErr *cliexec.Error
		if errors.As(err, &cliErr) && strings.Contains(cliErr.Stderr, "NotFound") {
			return nil, fault.NotFound("kubernetes_resource_not_found", cliErr.Stderr)
		}
		return nil, err
	}
	return json.RawMessage(out), nil
}

// act runs a mutation with the action deadline and streams its output to the job.
func (s *Service) act(ctx context.Context, out io.Writer, stdin []byte, args ...string) error {
	return s.runner.Stream(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    s.baseArgs(args...),
		Stdin:   stdin,
		Timeout: s.timeouts.Action,
	}, out)
}

// Delete removes one resource.
func (s *Service) Delete(ctx context.Context, target Target, out io.Writer) error {
	args := append(append([]string{"delete", string(target.Kind)}, target.scopeArgs()...), "--", target.Name)
	return s.act(ctx, out, nil, args...)
}

// Scale changes the replicas of a deployment.
func (s *Service) Scale(ctx context.Context, target Target, replicas int, out io.Writer) error {
	args := append(append([]string{"scale", string(KindDeployment)}, target.scopeArgs()...),
		"--replicas="+strconv.Itoa(replicas), "--", target.Name)
	return s.act(ctx, out, nil, args...)
}

// ValidateReplicas applies the range of a scale request.
func (s *Service) ValidateReplicas(replicas int) error {
	if replicas < 0 || replicas > s.maxReplicas {
		return fault.Invalid("replicas_out_of_range", "replicas is out of range").
			WithParams(map[string]any{"max": s.maxReplicas})
	}
	return nil
}

// Apply validates the YAML in the cluster and applies it only if the whole file passes.
// A refusal in the dry run counts as invalid and nothing changes.
func (s *Service) Apply(ctx context.Context, yaml []byte, out io.Writer) error {
	if err := s.act(ctx, out, yaml, "apply", "--dry-run=server", "--validate=strict", "-f", "-"); err != nil {
		return err
	}
	return s.act(ctx, out, yaml, "apply", "-f", "-")
}

// StreamLogs follows the logs of a pod until ctx ends or the pod stops.
func (s *Service) StreamLogs(ctx context.Context, pod Target, container string, w io.Writer) error {
	args := append([]string{"logs", "-f", logTailArg}, pod.scopeArgs()...)
	args = append(append(args, containerArgs(container)...), "--", pod.Name)
	return s.runner.Stream(ctx, cliexec.Command{Binary: s.binary, Args: s.baseArgs(args...)}, w)
}

// StartTerminal opens a shell inside a pod: bash when present, otherwise sh. The `--`
// is taken by the remote command here, so the pod name relies on its DNS-1123 validation.
func (s *Service) StartTerminal(ctx context.Context, pod Target, container string, cols, rows uint16) (*cliexec.PTYSession, error) {
	args := append([]string{"exec", "-it"}, pod.scopeArgs()...)
	args = append(append(args, containerArgs(container)...), pod.Name, "--", "sh", "-c", terminalScript)
	return s.runner.StartPTY(ctx, cliexec.Command{Binary: s.binary, Args: s.baseArgs(args...)}, cols, rows)
}

// containerArgs selects a container inside the pod when one was given.
func containerArgs(container string) []string {
	if container == "" {
		return nil
	}
	return []string{"-c", container}
}
