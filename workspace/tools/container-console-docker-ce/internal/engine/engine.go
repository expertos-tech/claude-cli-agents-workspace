// Package engine owns the read of the Docker daemon state: `docker info` is the only source,
// and the service never starts or stops the daemon, because that needs root.
package engine

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"container-console-docker-ce/internal/cliexec"
)

// infoFormat asks only for server fields, so the CLI does not scan its plugins on each read.
const infoFormat = `{"serverVersion":{{json .ServerVersion}},"cpus":{{json .NCPU}},"memoryBytes":{{json .MemTotal}},` +
	`"storageDriver":{{json .Driver}},"operatingSystem":{{json .OperatingSystem}},"osType":{{json .OSType}},` +
	`"architecture":{{json .Architecture}},"serverErrors":{{json .ServerErrors}}}`

// daemonDownMark is what the CLI says when nothing answers on the socket. A socket that
// exists but refuses this user reports "permission denied" instead, which stays unknown.
const daemonDownMark = "cannot connect to the docker daemon"

// State is the state of the Docker daemon.
type State string

const (
	// StateOn means the daemon answered.
	StateOn State = "on"
	// StateOff means nothing answers on the socket.
	StateOff State = "off"
	// StateUnknown means the read failed for another reason, given in Snapshot.Reason.
	StateUnknown State = "unknown"
)

// Snapshot is the content of the environment topic. Only State and Reason exist when the daemon is not on.
type Snapshot struct {
	State           State  `json:"state"`
	Reason          string `json:"reason,omitempty"`
	ServerVersion   string `json:"serverVersion,omitempty"`
	CPUs            int    `json:"cpus,omitempty"`
	MemoryBytes     int64  `json:"memoryBytes,omitempty"`
	StorageDriver   string `json:"storageDriver,omitempty"`
	OperatingSystem string `json:"operatingSystem,omitempty"`
	OSType          string `json:"osType,omitempty"`
	Architecture    string `json:"architecture,omitempty"`
}

// Service is the owner of the daemon state read.
type Service struct {
	runner  *cliexec.Runner
	binary  string
	env     []string
	timeout time.Duration
}

// NewService builds the Service for one Docker socket.
func NewService(runner *cliexec.Runner, binary, dockerHost string, timeout time.Duration) *Service {
	return &Service{runner: runner, binary: binary, env: []string{"DOCKER_HOST=" + dockerHost}, timeout: timeout}
}

// Snapshot reads the daemon state and data. A failure becomes a state, never an error,
// so the screen always has something to show.
func (s *Service) Snapshot(ctx context.Context) Snapshot {
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    []string{"info", "--format", infoFormat},
		Env:     s.env,
		Timeout: s.timeout,
	})
	if err != nil {
		return failedSnapshot(err)
	}
	return parseInfo(out)
}

// CurrentState reads only what an action needs to decide whether it may run.
func (s *Service) CurrentState(ctx context.Context) State {
	return s.Snapshot(ctx).State
}

// failedSnapshot turns a failed CLI run into the state it means.
func failedSnapshot(err error) Snapshot {
	var cliErr *cliexec.Error
	if errors.As(err, &cliErr) && !cliErr.NotFound && !cliErr.TimedOut {
		return stateFromMessage(cliErr.Stderr)
	}
	return Snapshot{State: StateUnknown, Reason: err.Error()}
}

// parseInfo reads the formatted output. A successful exit may still carry server errors,
// as older CLIs report an unreachable daemon that way.
func parseInfo(out []byte) Snapshot {
	var info struct {
		Snapshot
		ServerErrors []string `json:"serverErrors"`
	}
	if err := json.Unmarshal(out, &info); err != nil {
		return Snapshot{State: StateUnknown, Reason: "docker info returned an unexpected format"}
	}
	if len(info.ServerErrors) > 0 {
		return stateFromMessage(strings.Join(info.ServerErrors, "\n"))
	}
	if info.ServerVersion == "" {
		return Snapshot{State: StateUnknown, Reason: "docker info returned no server version"}
	}
	info.State = StateOn
	return info.Snapshot
}

// stateFromMessage decides between off and unknown from what the CLI reported.
func stateFromMessage(message string) Snapshot {
	if strings.Contains(strings.ToLower(message), daemonDownMark) {
		return Snapshot{State: StateOff, Reason: message}
	}
	return Snapshot{State: StateUnknown, Reason: message}
}
