// Package filepicker owns the calls to osascript: the native macOS file dialog is the
// only way to get an absolute path, which an <input type=file> does not give.
package filepicker

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"container-console-colima/internal/cliexec"
	"container-console-colima/internal/fault"
)

const (
	userCanceledMark = "-128"
	dialogScript     = `POSIX path of (choose file of type {"yaml","yml"} with prompt "Select a Compose file")`
)

// Service is the owner of the osascript integration.
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
// closes it. Only one dialog opens at a time. The arguments carry no external value.
func (s *Service) PickYAML(ctx context.Context) (path string, canceled bool, err error) {
	if !s.busy.TryLock() {
		return "", false, fault.Conflict("file_picker_busy", "a file dialog is already open")
	}
	defer s.busy.Unlock()
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    []string{"-e", "activate", "-e", dialogScript},
		Timeout: s.timeout,
	})
	if err != nil {
		var cliErr *cliexec.Error
		if errors.As(err, &cliErr) && strings.Contains(cliErr.Stderr, userCanceledMark) {
			return "", true, nil
		}
		return "", false, err
	}
	return strings.TrimSpace(string(out)), false, nil
}
