// Package cliexec runs external CLIs: never through a shell, always with a list of
// arguments, a deadline, a bounded capture and a process that cannot outlive its caller.
package cliexec

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	stderrTailBytes = 8 << 10
	maxStdoutBytes  = 64 << 20
)

// Command describes one execution of an external CLI.
type Command struct {
	Binary  string
	Args    []string
	Env     []string
	Stdin   []byte
	Timeout time.Duration
}

// Runner starts processes. WaitDelay bounds how long a canceled or finished
// process may hold its pipes: `colima start` leaves daemons that inherit them.
type Runner struct {
	WaitDelay time.Duration
}

// Run executes the command and returns its stdout. Failures come back as *Error.
func (r *Runner) Run(ctx context.Context, c Command) ([]byte, error) {
	stdout := &boundedBuffer{limit: maxStdoutBytes}
	tail := &tailBuffer{limit: stderrTailBytes}
	err := r.execute(ctx, c, stdout, tail, tail)
	return stdout.data, err
}

// Stream executes the command and sends stdout and stderr to w, in arrival order.
// A zero Timeout leaves the lifetime to ctx, which is what follow-mode commands need.
func (r *Runner) Stream(ctx context.Context, c Command, w io.Writer) error {
	shared := &lockedWriter{w: w}
	tail := &tailBuffer{limit: stderrTailBytes}
	return r.execute(ctx, c, shared, io.MultiWriter(shared, tail), tail)
}

// execute runs the process to completion and classifies the outcome.
func (r *Runner) execute(ctx context.Context, c Command, stdout, stderr io.Writer, tail *tailBuffer) error {
	ctx, cancel := withTimeout(ctx, c.Timeout)
	defer cancel()
	cmd := r.build(ctx, c)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	return classify(ctx, c, cmd.Run(), tail.String())
}

// build creates the process with its cancellation policy: SIGTERM first, then
// SIGKILL and closed pipes once WaitDelay expires.
func (r *Runner) build(ctx context.Context, c Command) *exec.Cmd {
	cmd := exec.CommandContext(ctx, c.Binary, c.Args...)
	cmd.Env = append(os.Environ(), c.Env...)
	if c.Stdin != nil {
		cmd.Stdin = bytes.NewReader(c.Stdin)
	}
	cmd.Cancel = func() error {
		return cmd.Process.Signal(syscall.SIGTERM)
	}
	cmd.WaitDelay = r.WaitDelay
	return cmd
}

// withTimeout applies the deadline when the command has one.
func withTimeout(ctx context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
	if timeout <= 0 {
		return context.WithCancel(ctx)
	}
	return context.WithTimeout(ctx, timeout)
}

// classify turns the result of Wait into nil or *Error. ErrWaitDelay alone means the
// process exited with 0 and only a daemon that inherited the pipes was left, so it succeeded.
func classify(ctx context.Context, c Command, err error, stderr string) error {
	if err == nil || errors.Is(err, exec.ErrWaitDelay) {
		return nil
	}
	failure := &Error{
		Binary:   c.Binary,
		ExitCode: -1,
		Stderr:   strings.TrimSpace(stderr),
		Timeout:  c.Timeout,
		cause:    err,
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		failure.ExitCode = exitErr.ExitCode()
	}
	failure.NotFound = errors.Is(err, exec.ErrNotFound) || errors.Is(err, fs.ErrNotExist)
	failure.TimedOut = errors.Is(ctx.Err(), context.DeadlineExceeded)
	failure.Canceled = errors.Is(ctx.Err(), context.Canceled)
	return failure
}

// Error is a failed CLI execution, with what the screen must show.
type Error struct {
	Binary   string
	ExitCode int
	Stderr   string
	Timeout  time.Duration
	TimedOut bool
	NotFound bool
	Canceled bool
	cause    error
}

// Error returns the error the CLI reported or, without one, what happened to the process.
func (e *Error) Error() string {
	switch {
	case e.NotFound:
		return fmt.Sprintf("%s: executable not found", e.Binary)
	case e.TimedOut:
		return fmt.Sprintf("%s: timed out after %s", e.Binary, e.Timeout)
	case e.Stderr != "":
		return e.Stderr
	case e.ExitCode >= 0:
		return fmt.Sprintf("%s: exited with code %d", e.Binary, e.ExitCode)
	}
	return fmt.Sprintf("%s: %v", e.Binary, e.cause)
}

// Unwrap exposes the underlying execution error.
func (e *Error) Unwrap() error {
	return e.cause
}

// lockedWriter serializes the writes of the stdout and stderr copy goroutines.
type lockedWriter struct {
	mu sync.Mutex
	w  io.Writer
}

// Write forwards one chunk while holding the lock.
func (l *lockedWriter) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.w.Write(p)
}

// tailBuffer keeps only the last bytes written, which is where a CLI puts its error.
type tailBuffer struct {
	limit int
	data  []byte
}

// Write appends and discards what no longer fits.
func (t *tailBuffer) Write(p []byte) (int, error) {
	t.data = append(t.data, p...)
	if extra := len(t.data) - t.limit; extra > 0 {
		t.data = t.data[extra:]
	}
	return len(p), nil
}

// String returns the kept bytes.
func (t *tailBuffer) String() string {
	return string(t.data)
}

// boundedBuffer keeps the first bytes written and fails once the limit is passed,
// so a runaway CLI ends with an error instead of filling the memory.
type boundedBuffer struct {
	limit int
	data  []byte
}

// Write appends while the limit allows.
func (b *boundedBuffer) Write(p []byte) (int, error) {
	if len(b.data)+len(p) > b.limit {
		return 0, errors.New("command output exceeds the capture limit")
	}
	b.data = append(b.data, p...)
	return len(p), nil
}

// LineWriter calls Emit for each complete line written. A line longer than the
// limit is emitted in pieces. The caller serializes the calls to Write.
type LineWriter struct {
	Emit    func(line string)
	pending []byte
}

const maxLineBytes = 64 << 10

// Write splits the chunk into lines and keeps the unfinished one.
func (l *LineWriter) Write(p []byte) (int, error) {
	l.pending = append(l.pending, p...)
	for {
		index := bytes.IndexByte(l.pending, '\n')
		if index < 0 {
			break
		}
		l.Emit(strings.TrimRight(string(l.pending[:index]), "\r"))
		l.pending = l.pending[index+1:]
	}
	if len(l.pending) > maxLineBytes {
		l.Emit(string(l.pending))
		l.pending = nil
	}
	return len(p), nil
}

// Flush emits a final line that had no line break.
func (l *LineWriter) Flush() {
	if len(l.pending) > 0 {
		l.Emit(string(l.pending))
		l.pending = nil
	}
}
