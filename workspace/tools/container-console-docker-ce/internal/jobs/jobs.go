// Package jobs runs every mutation in the background and keeps its result in memory,
// so the screen never waits on a long HTTP call and errors always arrive the same way.
package jobs

import (
	"context"
	"crypto/rand"
	"errors"
	"io"
	"log/slog"
	"os"
	"strings"
	"sync"
	"time"

	"container-console-docker-ce/internal/cliexec"
	"container-console-docker-ce/internal/fault"
)

// Status is the lifecycle stage of a job.
type Status string

const (
	// StatusRunning means the action is still executing.
	StatusRunning Status = "running"
	// StatusSucceeded means the action finished without error.
	StatusSucceeded Status = "succeeded"
	// StatusFailed means the action finished with the error in Job.Failure.
	StatusFailed Status = "failed"
)

// maxLoggedMessageRunes limits the error text that reaches the log file.
const maxLoggedMessageRunes = 200

// Failure is the error received from the action, shown to the user as it came.
type Failure struct {
	Code     string `json:"code"`
	Message  string `json:"message"`
	ExitCode *int   `json:"exitCode,omitempty"`
}

// Job is the public record of an action.
type Job struct {
	ID         string     `json:"id"`
	Kind       string     `json:"kind"`
	Target     string     `json:"target"`
	Status     Status     `json:"status"`
	Output     []string   `json:"output"`
	Failure    *Failure   `json:"error,omitempty"`
	StartedAt  time.Time  `json:"startedAt"`
	FinishedAt *time.Time `json:"finishedAt,omitempty"`
}

// Spec describes a job to start. Jobs with the same non-empty Exclusive key never run together.
type Spec struct {
	// PrivateFailure keeps the error text out of the log file, for actions whose input can hold secrets.
	PrivateFailure bool
	Kind           string
	Target         string
	Exclusive      string
}

// Func is the action. Lines written to out appear in Job.Output.
type Func func(ctx context.Context, out io.Writer) error

// Options configures a Manager.
type Options struct {
	Kept        int
	OutputLines int
	Now         func() time.Time
	Logger      *slog.Logger
	// OnChange runs after any change of a job, outside the manager lock.
	OnChange func()
	// OnFinish runs after a job ends, outside the manager lock.
	OnFinish func()
}

// Manager holds running jobs and the most recent finished ones.
type Manager struct {
	opts      Options
	mu        sync.Mutex
	jobs      []*Job
	exclusive map[string]string
}

// NewManager builds a Manager.
func NewManager(opts Options) *Manager {
	return &Manager{opts: opts, exclusive: map[string]string{}}
}

// Submit starts the action and returns its record. An Exclusive key already held by
// a running job makes it return a conflict naming that job, and nothing starts.
// The action outlives the request on purpose: its deadline comes from each CLI call.
func (m *Manager) Submit(spec Spec, fn Func) (Job, error) {
	m.mu.Lock()
	if running, held := m.exclusive[spec.Exclusive]; held && spec.Exclusive != "" {
		m.mu.Unlock()
		return Job{}, fault.Conflict("job_conflict", "another action of this kind is running").
			WithParams(map[string]any{"jobId": running})
	}
	job := &Job{
		ID:        rand.Text(),
		Kind:      spec.Kind,
		Target:    spec.Target,
		Status:    StatusRunning,
		Output:    []string{},
		StartedAt: m.opts.Now().UTC(),
	}
	m.jobs = append(m.jobs, job)
	if spec.Exclusive != "" {
		m.exclusive[spec.Exclusive] = job.ID
	}
	view := copyJob(job)
	m.mu.Unlock()

	m.notify()
	go m.run(job, spec, fn)
	return view, nil
}

// run executes the action and records the outcome.
func (m *Manager) run(job *Job, spec Spec, fn Func) {
	sink := &outputSink{manager: m, job: job}
	sink.lines.Emit = sink.appendLine
	err := fn(context.Background(), sink)
	sink.flush()
	m.finish(job, spec, err)
}

// finish stores the final state, releases the exclusive key and drops old records.
func (m *Manager) finish(job *Job, spec Spec, err error) {
	finished := m.opts.Now().UTC()
	m.mu.Lock()
	job.FinishedAt = &finished
	job.Status = StatusSucceeded
	if err != nil {
		job.Status = StatusFailed
		job.Failure = DescribeFailure(err)
	}
	if spec.Exclusive != "" {
		delete(m.exclusive, spec.Exclusive)
	}
	m.prune()
	duration := finished.Sub(job.StartedAt)
	status := job.Status
	failure := job.Failure
	m.mu.Unlock()

	if failure != nil {
		m.opts.Logger.Error("job failed", "kind", spec.Kind, "target", spec.Target, "code", failure.Code,
			"exitCode", failure.ExitCode,
			"durationMs", duration.Milliseconds())
	} else {
		m.opts.Logger.Info("job finished",
			"kind", spec.Kind, "target", spec.Target, "status", status, "durationMs", duration.Milliseconds())
	}
	m.notify()
	if m.opts.OnFinish != nil {
		m.opts.OnFinish()
	}
}

// loggableMessage returns what the log file may keep of an error, which stays whole only in memory:
// one line, shortened and without the login. A spec with PrivateFailure keeps nothing.
func loggableMessage(spec Spec, message string) string {
	if spec.PrivateFailure {
		return ""
	}
	line, _, _ := strings.Cut(message, "\n")
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		line = strings.ReplaceAll(line, home, "~")
	}
	if runes := []rune(line); len(runes) > maxLoggedMessageRunes {
		return string(runes[:maxLoggedMessageRunes])
	}
	return line
}

// prune removes the oldest finished jobs beyond the kept amount. Running jobs always stay.
func (m *Manager) prune() {
	finished := 0
	for _, job := range m.jobs {
		if job.Status != StatusRunning {
			finished++
		}
	}
	kept := m.jobs[:0]
	for _, job := range m.jobs {
		if job.Status != StatusRunning && finished > m.opts.Kept {
			finished--
			continue
		}
		kept = append(kept, job)
	}
	m.jobs = kept
}

// Snapshot returns all known jobs, newest first.
func (m *Manager) Snapshot() []Job {
	m.mu.Lock()
	defer m.mu.Unlock()
	views := make([]Job, 0, len(m.jobs))
	for i := len(m.jobs) - 1; i >= 0; i-- {
		views = append(views, copyJob(m.jobs[i]))
	}
	return views
}

// Get returns one job by id.
func (m *Manager) Get(id string) (Job, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, job := range m.jobs {
		if job.ID == id {
			return copyJob(job), true
		}
	}
	return Job{}, false
}

// notify runs the change callback when one is set.
func (m *Manager) notify() {
	if m.opts.OnChange != nil {
		m.opts.OnChange()
	}
}

// copyJob returns a record that shares nothing mutable with the manager.
func copyJob(job *Job) Job {
	view := *job
	view.Output = append([]string{}, job.Output...)
	return view
}

// DescribeFailure turns any action error into its public form.
func DescribeFailure(err error) *Failure {
	var cliErr *cliexec.Error
	if errors.As(err, &cliErr) {
		return describeCLIFailure(cliErr)
	}
	var domainErr *fault.Error
	if errors.As(err, &domainErr) {
		return &Failure{Code: domainErr.Code, Message: domainErr.Message}
	}
	return &Failure{Code: "action_failed", Message: err.Error()}
}

// describeCLIFailure keeps the CLI error and its exit code.
func describeCLIFailure(err *cliexec.Error) *Failure {
	failure := &Failure{Code: "command_failed", Message: err.Error()}
	switch {
	case err.NotFound:
		failure.Code = "binary_not_found"
	case err.TimedOut:
		failure.Code = "command_timeout"
	}
	if err.ExitCode >= 0 {
		code := err.ExitCode
		failure.ExitCode = &code
	}
	return failure
}

// outputSink receives the action output and stores the most recent lines in the job.
type outputSink struct {
	manager *Manager
	job     *Job
	lines   cliexec.LineWriter
	mu      sync.Mutex
}

// Write stores the complete lines of the chunk.
func (s *outputSink) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lines.Write(p)
}

// flush stores a final line that had no line break.
func (s *outputSink) flush() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lines.Flush()
}

// appendLine adds one line and notifies the subscribers.
func (s *outputSink) appendLine(line string) {
	limit := s.manager.opts.OutputLines
	s.manager.mu.Lock()
	s.job.Output = append(s.job.Output, line)
	if extra := len(s.job.Output) - limit; extra > 0 {
		s.job.Output = s.job.Output[extra:]
	}
	s.manager.mu.Unlock()
	s.manager.notify()
}
