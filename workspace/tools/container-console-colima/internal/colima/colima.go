// Package colima owns every call to the Colima CLI and the rules of environment
// state, mode and resources.
package colima

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"container-console-colima/internal/cliexec"
	"container-console-colima/internal/fault"
)

const (
	gibibyte   = int64(1) << 30
	maxDiskGiB = 4096

	statusRunning = "Running"
	statusStopped = "Stopped"
)

// State is the lifecycle stage of the environment.
type State string

const (
	// StateOff means the VM is stopped or was never created.
	StateOff State = "off"
	// StateStarting means a start requested through the console is running.
	StateStarting State = "starting"
	// StateOn means the VM is running.
	StateOn State = "on"
	// StateStopping means a stop requested through the console is running.
	StateStopping State = "stopping"
	// StateUnknown means the state could not be read; Snapshot.Reason says why.
	StateUnknown State = "unknown"
)

// Kubernetes is the mode of the running environment.
type Kubernetes struct {
	Enabled    bool  `json:"enabled"`
	Transition State `json:"transition,omitempty"`
}

// Usage is the size of the VM. Colima reports memory and disk in bytes.
type Usage struct {
	CPUs        int   `json:"cpus"`
	MemoryBytes int64 `json:"memoryBytes"`
	DiskBytes   int64 `json:"diskBytes"`
}

// Host is the capacity of this Mac, the upper limit of CPU and memory.
type Host struct {
	CPUs        int   `json:"cpus"`
	MemoryBytes int64 `json:"memoryBytes"`
}

// Snapshot is the state of the environment as the screen shows it.
type Snapshot struct {
	State      State      `json:"state"`
	Reason     string     `json:"reason,omitempty"`
	Profile    string     `json:"profile"`
	Kubernetes Kubernetes `json:"kubernetes"`
	Usage      Usage      `json:"usage"`
	Host       Host       `json:"host"`
	Arch       string     `json:"arch,omitempty"`
	Runtime    string     `json:"runtime,omitempty"`
	Driver     string     `json:"driver,omitempty"`
	MountType  string     `json:"mountType,omitempty"`
}

// Resources are the values requested by the user, in the unit of the Colima flags.
// A nil field keeps the saved value.
type Resources struct {
	CPUs      *int
	MemoryGiB *int
	DiskGiB   *int
}

// Timeouts are the deadlines of the Colima calls.
type Timeouts struct {
	Read            time.Duration
	Start           time.Duration
	Stop            time.Duration
	KubernetesStart time.Duration
}

// RestartHooks are the steps around a restart that belong to other systems.
type RestartHooks struct {
	// Capture returns what must come back after the restart. It runs before stopping.
	Capture func(ctx context.Context) ([]string, error)
	// Restore brings back what Capture returned. It runs after starting.
	Restore func(ctx context.Context, ids []string, out io.Writer) error
}

// Service is the owner of the Colima integration.
type Service struct {
	runner    *cliexec.Runner
	binary    string
	sysctl    string
	profile   string
	timeouts  Timeouts
	mu        sync.Mutex
	phase     State
	kubePhase State
	host      Host
}

// NewService builds the Service for one Colima profile.
func NewService(runner *cliexec.Runner, binary, sysctl, profile string, timeouts Timeouts) *Service {
	return &Service{runner: runner, binary: binary, sysctl: sysctl, profile: profile, timeouts: timeouts}
}

// listEntry is one line of `colima list --json`.
type listEntry struct {
	Name    string `json:"name"`
	Status  string `json:"status"`
	Arch    string `json:"arch"`
	CPUs    int    `json:"cpus"`
	Memory  int64  `json:"memory"`
	Disk    int64  `json:"disk"`
	Runtime string `json:"runtime"`
}

// statusOutput is the object of `colima status --json`, available only with the VM running.
type statusOutput struct {
	Driver     string `json:"driver"`
	MountType  string `json:"mount_type"`
	Kubernetes bool   `json:"kubernetes"`
}

// Snapshot reads the current state. A missing binary or a failed read yields
// StateUnknown with the reason, never an error, so the screen always opens.
func (s *Service) Snapshot(ctx context.Context) Snapshot {
	var (
		wg        sync.WaitGroup
		entry     *listEntry
		listErr   error
		status    statusOutput
		statusErr error
	)
	snapshot := Snapshot{Profile: s.profile, Host: s.Host(ctx)}
	wg.Go(func() { entry, listErr = s.readList(ctx) })
	wg.Go(func() { status, statusErr = s.readStatus(ctx) })
	wg.Wait()

	applyList(&snapshot, entry, listErr)
	if snapshot.State == StateOn {
		applyStatus(&snapshot, status, statusErr)
	}
	phase, kubePhase := s.phases()
	if phase != "" {
		snapshot.State = phase
	}
	snapshot.Kubernetes.Transition = kubePhase
	return snapshot
}

// CurrentState reads only the state, which is cheaper than a full Snapshot.
func (s *Service) CurrentState(ctx context.Context) State {
	if phase, _ := s.phases(); phase != "" {
		return phase
	}
	var snapshot Snapshot
	entry, err := s.readList(ctx)
	applyList(&snapshot, entry, err)
	return snapshot.State
}

// applyList fills what comes from `colima list`.
func applyList(snapshot *Snapshot, entry *listEntry, err error) {
	if err != nil {
		snapshot.State = StateUnknown
		snapshot.Reason = err.Error()
		return
	}
	if entry == nil {
		snapshot.State = StateOff
		return
	}
	snapshot.Usage = Usage{CPUs: entry.CPUs, MemoryBytes: entry.Memory, DiskBytes: entry.Disk}
	snapshot.Arch = entry.Arch
	snapshot.Runtime = entry.Runtime
	switch entry.Status {
	case statusRunning:
		snapshot.State = StateOn
	case statusStopped:
		snapshot.State = StateOff
	default:
		snapshot.State = StateUnknown
		snapshot.Reason = "colima reported status " + strconv.Quote(entry.Status)
	}
}

// applyStatus fills what comes from `colima status`. A failure leaves the VM on, with the reason.
func applyStatus(snapshot *Snapshot, status statusOutput, err error) {
	if err != nil {
		snapshot.Reason = err.Error()
		return
	}
	snapshot.Kubernetes.Enabled = status.Kubernetes
	snapshot.Driver = status.Driver
	snapshot.MountType = status.MountType
}

// readList returns the line of this profile in `colima list --json`, which is
// JSON Lines. The profile not existing yet returns nil and no error.
func (s *Service) readList(ctx context.Context) (*listEntry, error) {
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    []string{"list", "--json"},
		Timeout: s.timeouts.Read,
	})
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(out))
	for decoder.More() {
		var entry listEntry
		if err := decoder.Decode(&entry); err != nil {
			return nil, errors.New("colima list returned an unexpected format")
		}
		if entry.Name == s.profile {
			return &entry, nil
		}
	}
	return nil, nil
}

// readStatus returns `colima status --json`, which exits with 1 and no JSON when stopped.
func (s *Service) readStatus(ctx context.Context) (statusOutput, error) {
	var status statusOutput
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    []string{"status", "--profile", s.profile, "--json"},
		Timeout: s.timeouts.Read,
	})
	if err != nil {
		return status, err
	}
	if err := json.Unmarshal(out, &status); err != nil {
		return status, errors.New("colima status returned an unexpected format")
	}
	return status, nil
}

// Host returns the capacity of this Mac. The memory is read once; a failed read
// stays at zero, is retried on the next call, and skips the upper limit meanwhile.
func (s *Service) Host(ctx context.Context) Host {
	s.mu.Lock()
	known := s.host
	s.mu.Unlock()
	if known.MemoryBytes > 0 {
		return known
	}
	host := Host{CPUs: runtime.NumCPU()}
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.sysctl,
		Args:    []string{"-n", "hw.memsize"},
		Timeout: s.timeouts.Read,
	})
	if err == nil {
		host.MemoryBytes, _ = strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
	}
	s.mu.Lock()
	s.host = host
	s.mu.Unlock()
	return host
}

// ValidateResources applies the rules of CPU, memory and disk. A smaller disk is refused
// here, before Colima is called, because shrinking loses data (Colima issue #1661).
func (s *Service) ValidateResources(ctx context.Context, res Resources) error {
	host := s.Host(ctx)
	if res.CPUs != nil && (*res.CPUs < 1 || *res.CPUs > host.CPUs) {
		return fault.Invalid("cpus_out_of_range", "cpus must be between 1 and the CPUs of this Mac").
			WithParams(map[string]any{"max": host.CPUs})
	}
	if res.MemoryGiB != nil {
		maxMemory := host.MemoryBytes / gibibyte
		if *res.MemoryGiB < 1 || (maxMemory > 0 && int64(*res.MemoryGiB) > maxMemory) {
			return fault.Invalid("memory_out_of_range", "memoryGiB must be between 1 and the memory of this Mac").
				WithParams(map[string]any{"max": maxMemory})
		}
	}
	if res.DiskGiB != nil {
		return s.validateDisk(ctx, *res.DiskGiB)
	}
	return nil
}

// validateDisk refuses a value out of range or smaller than the current disk.
func (s *Service) validateDisk(ctx context.Context, diskGiB int) error {
	if diskGiB < 1 || diskGiB > maxDiskGiB {
		return fault.Invalid("disk_out_of_range", "diskGiB is out of range").
			WithParams(map[string]any{"max": maxDiskGiB})
	}
	entry, err := s.readList(ctx)
	if err != nil {
		return err
	}
	if entry == nil {
		return nil
	}
	if current := entry.Disk / gibibyte; int64(diskGiB) < current {
		return fault.Invalid("disk_shrink_refused", "reducing the disk loses data, so it is refused").
			WithParams(map[string]any{"currentGiB": current})
	}
	return nil
}

// Start turns the VM on in the chosen mode, with optional new resources.
func (s *Service) Start(ctx context.Context, kubernetes bool, res Resources, out io.Writer) error {
	return s.withPhase(StateStarting, func() error {
		return s.runner.Stream(ctx, cliexec.Command{
			Binary:  s.binary,
			Args:    startArgs(s.profile, kubernetes, res),
			Timeout: s.timeouts.Start,
		}, out)
	})
}

// startArgs builds `colima start`. --activate stays out: the value saved in colima.yaml decides.
func startArgs(profile string, kubernetes bool, res Resources) []string {
	args := []string{"start", "--profile", profile, "--kubernetes=" + strconv.FormatBool(kubernetes)}
	if res.CPUs != nil {
		args = append(args, "--cpus", strconv.Itoa(*res.CPUs))
	}
	if res.MemoryGiB != nil {
		args = append(args, "--memory", strconv.Itoa(*res.MemoryGiB))
	}
	if res.DiskGiB != nil {
		args = append(args, "--disk", strconv.Itoa(*res.DiskGiB))
	}
	return args
}

// Stop turns the VM off.
func (s *Service) Stop(ctx context.Context, out io.Writer) error {
	return s.withPhase(StateStopping, func() error {
		return s.runner.Stream(ctx, cliexec.Command{
			Binary:  s.binary,
			Args:    []string{"stop", "--profile", s.profile},
			Timeout: s.timeouts.Stop,
		}, out)
	})
}

// Restart applies new resources to a running VM. If Capture fails nothing has stopped yet.
// Containers without a restart policy only come back through Restore.
func (s *Service) Restart(ctx context.Context, kubernetes bool, res Resources, hooks RestartHooks, out io.Writer) error {
	ids, err := hooks.Capture(ctx)
	if err != nil {
		return err
	}
	if err := s.Stop(ctx, out); err != nil {
		return err
	}
	if err := s.Start(ctx, kubernetes, res, out); err != nil {
		return err
	}
	return hooks.Restore(ctx, ids, out)
}

// SetKubernetes turns Kubernetes on or off without restarting the VM.
func (s *Service) SetKubernetes(ctx context.Context, enabled bool, out io.Writer) error {
	action, timeout, phase := "stop", s.timeouts.Stop, StateStopping
	if enabled {
		action, timeout, phase = "start", s.timeouts.KubernetesStart, StateStarting
	}
	s.setKubePhase(phase)
	defer s.setKubePhase("")
	return s.runner.Stream(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    []string{"kubernetes", action, "--profile", s.profile},
		Timeout: timeout,
	}, out)
}

// withPhase publishes the transition state while the action runs.
func (s *Service) withPhase(phase State, action func() error) error {
	s.mu.Lock()
	s.phase = phase
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		s.phase = ""
		s.mu.Unlock()
	}()
	return action()
}

// setKubePhase publishes the transition state of Kubernetes.
func (s *Service) setKubePhase(phase State) {
	s.mu.Lock()
	s.kubePhase = phase
	s.mu.Unlock()
}

// phases returns the running transitions.
func (s *Service) phases() (State, State) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.phase, s.kubePhase
}
