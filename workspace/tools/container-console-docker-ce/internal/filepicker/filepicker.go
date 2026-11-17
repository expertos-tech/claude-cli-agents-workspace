// Package filepicker owns the calls to zenity: the desktop file dialog is the only way
// to get an absolute path, which an <input type=file> does not give.
package filepicker

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"container-console-docker-ce/internal/cliexec"
	"container-console-docker-ce/internal/fault"
)

const (
	canceledExitCode = 1
	// noDisplayMark is how zenity reports a session without a display, also with exit code 1.
	noDisplayMark = "open display"
)

// dialogArgs are fixed: they carry no external value.
var dialogArgs = []string{
	"--file-selection",
	"--title=Choose a Compose file",
	"--file-filter=YAML | *.yaml *.yml",
}

// Service is the owner of the zenity integration.
type Service struct {
	runner  *cliexec.Runner
	binary  string
	timeout time.Duration
	busy    sync.Mutex
}

// NewService builds the Service.
func NewService(runner *cliexec.Runner, binary string, timeout time.Duration) *Service {
	return &Service{runner: runner, binary: binary, timeout: timeout}
}

// PickYAML opens the dialog and returns the chosen path, or canceled when the user
// closes it. Only one dialog opens at a time.
func (s *Service) PickYAML(ctx context.Context) (path string, canceled bool, err error) {
	if !s.busy.TryLock() {
		return "", false, fault.Conflict("file_picker_busy", "a file dialog is already open")
	}
	defer s.busy.Unlock()
	out, err := s.runner.Run(ctx, cliexec.Command{Binary: s.binary, Args: dialogArgs, Timeout: s.timeout})
	if err != nil {
		var cliErr *cliexec.Error
		if errors.As(err, &cliErr) && isCancel(cliErr) {
			return "", true, nil
		}
		return "", false, err
	}
	return strings.TrimSpace(string(out)), false, nil
}

// isCancel tells a user cancel from the failures that share its exit code.
func isCancel(err *cliexec.Error) bool {
	return err.ExitCode == canceledExitCode && !strings.Contains(strings.ToLower(err.Stderr), noDisplayMark)
}
