package activity

import (
	"sync"
	"time"
)

// Operation is one action of the console, as the page shows it.
type Operation struct {
	Time   time.Time `json:"time"`
	Name   string    `json:"name"`
	Target string    `json:"target"`
	Status int       `json:"status"`
	// DurationMs is how long the action took, in milliseconds.
	DurationMs int64 `json:"duration_ms"`
	// Error is the problem code of a failed action.
	Error string `json:"error,omitempty"`
}

// Operations keeps the last operations in memory, newest first.
type Operations struct {
	mu    sync.Mutex
	max   int
	items []Operation
}

// NewOperations keeps up to max operations.
func NewOperations(max int) *Operations { return &Operations{max: max} }

// Add records op.
func (o *Operations) Add(op Operation) {
	o.mu.Lock()
	defer o.mu.Unlock()
	o.items = append([]Operation{op}, o.items...)
	if len(o.items) > o.max {
		o.items = o.items[:o.max]
	}
}

// List returns a copy of the operations, newest first.
func (o *Operations) List() []Operation {
	o.mu.Lock()
	defer o.mu.Unlock()
	return append([]Operation{}, o.items...)
}
