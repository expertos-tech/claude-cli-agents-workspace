package cliexec

import (
	"context"
	"os"
	"os/exec"
	"sync"

	"github.com/creack/pty"
)

// PTYSession is a process attached to a pseudo-terminal.
type PTYSession struct {
	cmd      *exec.Cmd
	terminal *os.File
	cancel   context.CancelFunc
	done     chan struct{}
	exitCode int
	once     sync.Once
}

// StartPTY starts the command on a new pseudo-terminal with the given size.
// The process ends when ctx ends or when Close is called.
func (r *Runner) StartPTY(ctx context.Context, c Command, cols, rows uint16) (*PTYSession, error) {
	ctx, cancel := context.WithCancel(ctx)
	c.Env = append(c.Env, "TERM=xterm-256color")
	cmd := r.build(ctx, c)
	terminal, err := pty.StartWithSize(cmd, &pty.Winsize{Cols: cols, Rows: rows})
	if err != nil {
		cancel()
		return nil, classify(ctx, c, err, "")
	}
	session := &PTYSession{cmd: cmd, terminal: terminal, cancel: cancel, done: make(chan struct{})}
	go session.wait()
	return session, nil
}

// wait reaps the process and records its exit code.
func (s *PTYSession) wait() {
	err := s.cmd.Wait()
	s.exitCode = 0
	if err != nil {
		s.exitCode = s.cmd.ProcessState.ExitCode()
	}
	close(s.done)
}

// Read returns the next output of the terminal.
func (s *PTYSession) Read(p []byte) (int, error) {
	return s.terminal.Read(p)
}

// Write sends input to the terminal.
func (s *PTYSession) Write(p []byte) (int, error) {
	return s.terminal.Write(p)
}

// Resize changes the terminal size, and the process receives SIGWINCH.
func (s *PTYSession) Resize(cols, rows uint16) error {
	return pty.Setsize(s.terminal, &pty.Winsize{Cols: cols, Rows: rows})
}

// ExitCode waits for the process to end and returns its exit code.
func (s *PTYSession) ExitCode() int {
	<-s.done
	return s.exitCode
}

// Close ends the process and releases the terminal. On macOS a blocked read on the
// terminal only returns after the process is gone, so the process goes first.
func (s *PTYSession) Close() {
	s.once.Do(func() {
		s.cancel()
		<-s.done
		_ = s.terminal.Close()
	})
}
