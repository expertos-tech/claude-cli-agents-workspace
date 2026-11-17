// Package docker owns every call to the Docker CLI: containers, images, volumes,
// networks, events, logs and terminals. DOCKER_HOST is pinned to the profile socket.
package docker

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
	"time"

	"container-console-colima/internal/cliexec"
	"container-console-colima/internal/fault"
)

const (
	podNamespaceLabel = "io.kubernetes.pod.namespace"
	composeLabel      = "com.docker.compose.project"
	noneValue         = "<none>"
	logTailLines      = "500"
	terminalScript    = "command -v bash >/dev/null 2>&1 && exec bash || exec sh"
)

// Timeouts are the deadlines of the Docker calls.
type Timeouts struct {
	Read   time.Duration
	Action time.Duration
	Pull   time.Duration
}

// Service is the owner of the Docker integration.
type Service struct {
	runner   *cliexec.Runner
	binary   string
	env      []string
	timeouts Timeouts
}

// NewService builds the Service for one Docker socket.
func NewService(runner *cliexec.Runner, binary, dockerHost string, timeouts Timeouts) *Service {
	return &Service{runner: runner, binary: binary, env: []string{"DOCKER_HOST=" + dockerHost}, timeouts: timeouts}
}

// Container is one row of the container list.
type Container struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Image          string `json:"image"`
	Command        string `json:"command"`
	State          string `json:"state"`
	Status         string `json:"status"`
	Health         string `json:"health,omitempty"`
	Ports          string `json:"ports"`
	CreatedAt      string `json:"createdAt"`
	ComposeProject string `json:"composeProject,omitempty"`
}

// Image is one row of the image list. Reference is what remove accepts.
type Image struct {
	ID         string `json:"id"`
	Repository string `json:"repository"`
	Tag        string `json:"tag"`
	Reference  string `json:"reference"`
	Size       string `json:"size"`
	CreatedAt  string `json:"createdAt"`
}

// Volume is one row of the volume list.
type Volume struct {
	Name           string `json:"name"`
	Driver         string `json:"driver"`
	Scope          string `json:"scope"`
	Mountpoint     string `json:"mountpoint"`
	ComposeProject string `json:"composeProject,omitempty"`
}

// Network is one row of the network list.
type Network struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Driver         string `json:"driver"`
	Scope          string `json:"scope"`
	Internal       bool   `json:"internal"`
	CreatedAt      string `json:"createdAt"`
	ComposeProject string `json:"composeProject,omitempty"`
}

// Stats is the resource usage of a container, in the form the CLI prints it.
type Stats struct {
	CPUPercent    string `json:"cpuPercent"`
	MemoryUsage   string `json:"memoryUsage"`
	MemoryPercent string `json:"memoryPercent"`
	NetworkIO     string `json:"networkIO"`
	BlockIO       string `json:"blockIO"`
	PIDs          string `json:"pids"`
}

// Snapshot holds all the lists of the Docker screens.
type Snapshot struct {
	Containers []Container `json:"containers"`
	Images     []Image     `json:"images"`
	Volumes    []Volume    `json:"volumes"`
	Networks   []Network   `json:"networks"`
}

// EmptySnapshot returns lists that encode as [] rather than null.
func EmptySnapshot() Snapshot {
	return Snapshot{Containers: []Container{}, Images: []Image{}, Volumes: []Volume{}, Networks: []Network{}}
}

// List reads all the lists at once, so the snapshot is ready within a single read.
func (s *Service) List(ctx context.Context) (Snapshot, error) {
	snapshot := EmptySnapshot()
	var (
		wg   sync.WaitGroup
		errs [4]error
	)
	wg.Go(func() { snapshot.Containers, errs[0] = s.listContainers(ctx) })
	wg.Go(func() { snapshot.Images, errs[1] = s.listImages(ctx) })
	wg.Go(func() { snapshot.Volumes, errs[2] = s.listVolumes(ctx) })
	wg.Go(func() { snapshot.Networks, errs[3] = s.listNetworks(ctx) })
	wg.Wait()
	if err := firstError(errs[:]); err != nil {
		return EmptySnapshot(), err
	}
	return snapshot, nil
}

// firstError returns the first failure, which is the one the CLI reported, without repeats.
func firstError(errs []error) error {
	for _, err := range errs {
		if err != nil {
			return err
		}
	}
	return nil
}

// read runs a read-only command with the read deadline.
func (s *Service) read(ctx context.Context, args ...string) ([]byte, error) {
	return s.runner.Run(ctx, cliexec.Command{Binary: s.binary, Args: args, Env: s.env, Timeout: s.timeouts.Read})
}

// decodeLines reads the JSON Lines that `--format json` prints, tolerating new fields.
func decodeLines[T any](data []byte) ([]T, error) {
	items := []T{}
	decoder := json.NewDecoder(bytes.NewReader(data))
	for decoder.More() {
		var item T
		if err := decoder.Decode(&item); err != nil {
			return nil, errors.New("docker returned an unexpected format")
		}
		items = append(items, item)
	}
	return items, nil
}

// containerLine is one line of `docker ps --format json`.
type containerLine struct {
	ID           string
	Names        string
	Image        string
	Command      string
	State        string
	Status       string
	HealthStatus string
	Ports        string
	CreatedAt    string
	Labels       string
}

// listContainers returns the containers without those of pods: they have their own
// screen, and removing them from outside only makes the kubelet recreate them.
func (s *Service) listContainers(ctx context.Context) ([]Container, error) {
	lines, err := s.readContainerLines(ctx)
	if err != nil {
		return nil, err
	}
	containers := make([]Container, 0, len(lines))
	for _, line := range lines {
		if hasLabel(line.Labels, podNamespaceLabel) {
			continue
		}
		containers = append(containers, Container{
			ID:             line.ID,
			Name:           line.Names,
			Image:          line.Image,
			Command:        line.Command,
			State:          line.State,
			Status:         line.Status,
			Health:         line.HealthStatus,
			Ports:          line.Ports,
			CreatedAt:      line.CreatedAt,
			ComposeProject: labelValue(line.Labels, composeLabel),
		})
	}
	return containers, nil
}

// readContainerLines runs `docker ps` over all containers.
func (s *Service) readContainerLines(ctx context.Context) ([]containerLine, error) {
	out, err := s.read(ctx, "ps", "-a", "--no-trunc", "--format", "json")
	if err != nil {
		return nil, err
	}
	return decodeLines[containerLine](out)
}

// hasLabel tells whether the comma-separated label list has the key.
func hasLabel(labels, key string) bool {
	return strings.HasPrefix(labels, key+"=") || strings.Contains(labels, ","+key+"=")
}

// labelValue returns the value of a key in the comma-separated label list.
func labelValue(labels, key string) string {
	for _, pair := range strings.Split(labels, ",") {
		if value, found := strings.CutPrefix(pair, key+"="); found {
			return value
		}
	}
	return ""
}

// listImages returns the images with the reference that identifies each one.
func (s *Service) listImages(ctx context.Context) ([]Image, error) {
	out, err := s.read(ctx, "image", "ls", "--no-trunc", "--format", "json")
	if err != nil {
		return nil, err
	}
	lines, err := decodeLines[struct {
		ID, Repository, Tag, Digest, Size, CreatedAt string
	}](out)
	if err != nil {
		return nil, err
	}
	images := make([]Image, 0, len(lines))
	for _, line := range lines {
		images = append(images, Image{
			ID:         line.ID,
			Repository: line.Repository,
			Tag:        line.Tag,
			Reference:  imageReference(line.ID, line.Repository, line.Tag, line.Digest),
			Size:       line.Size,
			CreatedAt:  line.CreatedAt,
		})
	}
	return images, nil
}

// imageReference prefers repository and tag, then digest, then the id for dangling images.
func imageReference(id, repository, tag, digest string) string {
	switch {
	case repository == noneValue || repository == "":
		return id
	case tag != noneValue && tag != "":
		return repository + ":" + tag
	case digest != noneValue && digest != "":
		return repository + "@" + digest
	}
	return id
}

// listVolumes returns the volumes.
func (s *Service) listVolumes(ctx context.Context) ([]Volume, error) {
	out, err := s.read(ctx, "volume", "ls", "--format", "json")
	if err != nil {
		return nil, err
	}
	lines, err := decodeLines[struct {
		Name, Driver, Scope, Mountpoint, Labels string
	}](out)
	if err != nil {
		return nil, err
	}
	volumes := make([]Volume, 0, len(lines))
	for _, line := range lines {
		volumes = append(volumes, Volume{
			Name:           line.Name,
			Driver:         line.Driver,
			Scope:          line.Scope,
			Mountpoint:     line.Mountpoint,
			ComposeProject: labelValue(line.Labels, composeLabel),
		})
	}
	return volumes, nil
}

// listNetworks returns the networks.
func (s *Service) listNetworks(ctx context.Context) ([]Network, error) {
	out, err := s.read(ctx, "network", "ls", "--no-trunc", "--format", "json")
	if err != nil {
		return nil, err
	}
	lines, err := decodeLines[struct {
		ID, Name, Driver, Scope, Internal, CreatedAt, Labels string
	}](out)
	if err != nil {
		return nil, err
	}
	networks := make([]Network, 0, len(lines))
	for _, line := range lines {
		networks = append(networks, Network{
			ID:             line.ID,
			Name:           line.Name,
			Driver:         line.Driver,
			Scope:          line.Scope,
			Internal:       line.Internal == "true",
			CreatedAt:      line.CreatedAt,
			ComposeProject: labelValue(line.Labels, composeLabel),
		})
	}
	return networks, nil
}

// InspectContainer returns the raw details of a container.
func (s *Service) InspectContainer(ctx context.Context, ref Ref) (json.RawMessage, error) {
	return s.inspect(ctx, "container", "inspect", "--type", "container", "--", string(ref))
}

// InspectVolume returns the raw details of a volume.
func (s *Service) InspectVolume(ctx context.Context, ref Ref) (json.RawMessage, error) {
	return s.inspect(ctx, "volume", "volume", "inspect", "--", string(ref))
}

// InspectNetwork returns the raw details of a network.
func (s *Service) InspectNetwork(ctx context.Context, ref Ref) (json.RawMessage, error) {
	return s.inspect(ctx, "network", "network", "inspect", "--", string(ref))
}

// inspect unwraps the single-element array that the inspect commands print.
func (s *Service) inspect(ctx context.Context, kind string, args ...string) (json.RawMessage, error) {
	out, err := s.read(ctx, args...)
	if err != nil {
		return nil, asNotFound(err, kind)
	}
	var items []json.RawMessage
	if err := json.Unmarshal(out, &items); err != nil || len(items) == 0 {
		return nil, fault.NotFound(kind+"_not_found", kind+" not found")
	}
	return items[0], nil
}

// asNotFound turns the "no such" error of the CLI into a domain error.
func asNotFound(err error, kind string) error {
	var cliErr *cliexec.Error
	if errors.As(err, &cliErr) && strings.Contains(strings.ToLower(cliErr.Stderr), "no such") {
		return fault.NotFound(kind+"_not_found", cliErr.Stderr)
	}
	return err
}

// ReadStats returns one reading of the resource usage of a container.
func (s *Service) ReadStats(ctx context.Context, ref Ref) (Stats, error) {
	out, err := s.read(ctx, "stats", "--no-stream", "--format", "json", "--", string(ref))
	if err != nil {
		return Stats{}, asNotFound(err, "container")
	}
	var line struct {
		CPUPerc, MemUsage, MemPerc, NetIO, BlockIO, PIDs string
	}
	if err := json.Unmarshal(out, &line); err != nil {
		return Stats{}, errors.New("docker stats returned an unexpected format")
	}
	return Stats{
		CPUPercent:    line.CPUPerc,
		MemoryUsage:   line.MemUsage,
		MemoryPercent: line.MemPerc,
		NetworkIO:     line.NetIO,
		BlockIO:       line.BlockIO,
		PIDs:          line.PIDs,
	}, nil
}

// act runs a mutation with the action deadline and streams its output to the job.
func (s *Service) act(ctx context.Context, out io.Writer, timeout time.Duration, args ...string) error {
	return s.runner.Stream(ctx, cliexec.Command{Binary: s.binary, Args: args, Env: s.env, Timeout: timeout}, out)
}

// StartContainer starts a container.
func (s *Service) StartContainer(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "start", "--", string(ref))
}

// StopContainer stops a container.
func (s *Service) StopContainer(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "stop", "--", string(ref))
}

// RestartContainer restarts a container.
func (s *Service) RestartContainer(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "restart", "--", string(ref))
}

// RemoveContainer removes a container even when running; the confirmation dialog says so.
func (s *Service) RemoveContainer(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "rm", "--force", "--", string(ref))
}

// PullImage downloads an image; each output line appears in the job.
func (s *Service) PullImage(ctx context.Context, ref ImageRef, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Pull, "pull", "--", string(ref))
}

// RemoveImage removes an image without --force, so the in-use error reaches the user.
func (s *Service) RemoveImage(ctx context.Context, ref ImageRef, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "image", "rm", "--", string(ref))
}

// CreateVolume creates a volume.
func (s *Service) CreateVolume(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "volume", "create", "--", string(ref))
}

// RemoveVolume removes a volume without --force, so the in-use error reaches the user.
func (s *Service) RemoveVolume(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "volume", "rm", "--", string(ref))
}

// CreateNetwork creates a network.
func (s *Service) CreateNetwork(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "network", "create", "--", string(ref))
}

// RemoveNetwork removes a network without --force, so the in-use error reaches the user.
func (s *Service) RemoveNetwork(ctx context.Context, ref Ref, out io.Writer) error {
	return s.act(ctx, out, s.timeouts.Action, "network", "rm", "--", string(ref))
}

// RunningContainerIDs returns the running containers that do not belong to pods.
func (s *Service) RunningContainerIDs(ctx context.Context) ([]string, error) {
	containers, err := s.listContainers(ctx)
	if err != nil {
		return nil, err
	}
	ids := []string{}
	for _, container := range containers {
		if container.State == "running" {
			ids = append(ids, container.ID)
		}
	}
	return ids, nil
}

// StartContainers starts the ids captured before a restart. The ids come from the CLI itself.
func (s *Service) StartContainers(ctx context.Context, ids []string, out io.Writer) error {
	if len(ids) == 0 {
		return nil
	}
	fmt.Fprintf(out, "starting %d containers that were running\n", len(ids))
	args := append([]string{"start", "--"}, ids...)
	return s.act(ctx, out, s.timeouts.Action, args...)
}

// StreamLogs follows the logs of a container until ctx ends or the container stops.
func (s *Service) StreamLogs(ctx context.Context, ref Ref, w io.Writer) error {
	return s.runner.Stream(ctx, cliexec.Command{
		Binary: s.binary,
		Args:   []string{"logs", "-f", "--tail", logTailLines, "--", string(ref)},
		Env:    s.env,
	}, w)
}

// StartTerminal opens a shell inside a container: bash when present, otherwise sh.
// An image without a shell shows the error it receives.
func (s *Service) StartTerminal(ctx context.Context, ref Ref, cols, rows uint16) (*cliexec.PTYSession, error) {
	return s.runner.StartPTY(ctx, cliexec.Command{
		Binary: s.binary,
		Args:   []string{"exec", "-it", "--", string(ref), "sh", "-c", terminalScript},
		Env:    s.env,
	}, cols, rows)
}

// WatchEvents follows `docker events` and calls notify on each change that can alter
// a list. The stream ends when the daemon goes away, so it reconnects until ctx ends.
func (s *Service) WatchEvents(ctx context.Context, retry time.Duration, notify func()) {
	for ctx.Err() == nil {
		lines := &cliexec.LineWriter{Emit: func(line string) {
			if isRelevantEvent(line) {
				notify()
			}
		}}
		_ = s.runner.Stream(ctx, cliexec.Command{
			Binary: s.binary,
			Args:   []string{"events", "--format", "json"},
			Env:    s.env,
		}, lines)
		waitBeforeRetry(ctx, retry)
	}
}

// waitBeforeRetry waits for the duration or for ctx to end.
func waitBeforeRetry(ctx context.Context, retry time.Duration) {
	timer := time.NewTimer(retry)
	defer timer.Stop()
	select {
	case <-ctx.Done():
	case <-timer.C:
	}
}

// isRelevantEvent ignores exec_* and top, which do not change any list. Health probes
// emit exec_* continuously, and without this filter each one would cost a full read.
func isRelevantEvent(line string) bool {
	var event struct {
		Action string
	}
	if err := json.Unmarshal([]byte(line), &event); err != nil {
		return false
	}
	return !strings.HasPrefix(event.Action, "exec_") && event.Action != "top"
}
