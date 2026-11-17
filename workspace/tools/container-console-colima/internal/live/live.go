// Package live keeps named topics. Each topic has a source that only runs while the
// topic has subscribers and that publishes full snapshots, never diffs.
package live

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"time"
)

// Source produces snapshots until ctx ends. A value on refresh asks for a new snapshot now.
type Source func(ctx context.Context, publish func(snapshot any), refresh <-chan struct{})

// LoopOptions describes the usual source: fetch, publish, wait for the next reason to fetch.
type LoopOptions struct {
	// Fetch builds the current snapshot.
	Fetch func(ctx context.Context) any
	// Interval is the wait between fetches; zero means no periodic fetch.
	Interval time.Duration
	// Watch optionally follows an external stream and calls notify on relevant changes.
	Watch func(ctx context.Context, notify func())
	// Debounce is how long to wait after a notify, so a burst costs one fetch.
	Debounce time.Duration
}

// Loop builds a Source that runs one fetch at a time.
func Loop(opts LoopOptions) Source {
	return func(ctx context.Context, publish func(any), refresh <-chan struct{}) {
		changed := make(chan struct{}, 1)
		if opts.Watch != nil {
			go opts.Watch(ctx, func() { signal(changed) })
		}
		for ctx.Err() == nil {
			publish(opts.Fetch(ctx))
			waitForNext(ctx, opts, refresh, changed)
		}
	}
}

// waitForNext blocks until the interval passes, a refresh arrives or the debounce of a change ends.
func waitForNext(ctx context.Context, opts LoopOptions, refresh <-chan struct{}, changed <-chan struct{}) {
	var interval <-chan time.Time
	if opts.Interval > 0 {
		timer := time.NewTimer(opts.Interval)
		defer timer.Stop()
		interval = timer.C
	}
	select {
	case <-ctx.Done():
	case <-interval:
	case <-refresh:
	case <-changed:
		sleep(ctx, opts.Debounce)
	}
}

// sleep waits for the duration or for ctx to end.
func sleep(ctx context.Context, duration time.Duration) {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
	case <-timer.C:
	}
}

// signal records a pending notification without ever blocking.
func signal(ch chan struct{}) {
	select {
	case ch <- struct{}{}:
	default:
	}
}

// Subscription delivers the latest snapshot of a topic. A slow reader skips
// intermediate snapshots, which is safe because each one is complete.
type Subscription struct {
	C     <-chan []byte
	topic *topic
	ch    chan []byte
}

// Close ends the subscription. The last one to leave stops the topic source.
func (s *Subscription) Close() {
	s.topic.unsubscribe(s)
}

// Hub holds the registered topics.
type Hub struct {
	topics map[string]*topic
	logger *slog.Logger
}

// NewHub builds an empty Hub.
func NewHub(logger *slog.Logger) *Hub {
	return &Hub{topics: map[string]*topic{}, logger: logger}
}

// Register adds a topic. Call it before serving subscribers.
func (h *Hub) Register(name string, source Source) {
	h.topics[name] = &topic{
		name:        name,
		source:      source,
		logger:      h.logger,
		subscribers: map[*Subscription]bool{},
		refresh:     make(chan struct{}, 1),
	}
}

// Subscribe joins a topic and reports false when the topic does not exist.
func (h *Hub) Subscribe(name string) (*Subscription, bool) {
	t, known := h.topics[name]
	if !known {
		return nil, false
	}
	return t.subscribe(), true
}

// Refresh asks the running sources of the given topics for a new snapshot.
func (h *Hub) Refresh(names ...string) {
	for _, name := range names {
		if t, known := h.topics[name]; known {
			signal(t.refresh)
		}
	}
}

// topic tracks the subscribers and the source of one topic.
type topic struct {
	name        string
	source      Source
	logger      *slog.Logger
	refresh     chan struct{}
	mu          sync.Mutex
	subscribers map[*Subscription]bool
	latest      []byte
	generation  int
	stop        context.CancelFunc
}

// subscribe adds a subscriber, starts the source for the first one and delivers the latest snapshot.
func (t *topic) subscribe() *Subscription {
	ch := make(chan []byte, 1)
	sub := &Subscription{C: ch, ch: ch, topic: t}
	t.mu.Lock()
	defer t.mu.Unlock()
	t.subscribers[sub] = true
	if t.latest != nil {
		ch <- t.latest
	}
	if len(t.subscribers) == 1 {
		t.startLocked()
	}
	return sub
}

// startLocked runs the source under a new generation, so a stopped one cannot publish anymore.
func (t *topic) startLocked() {
	t.generation++
	generation := t.generation
	ctx, cancel := context.WithCancel(context.Background())
	t.stop = cancel
	publish := func(snapshot any) { t.publish(generation, snapshot) }
	go t.source(ctx, publish, t.refresh)
}

// unsubscribe removes a subscriber and, for the last one, stops the source and forgets the snapshot.
func (t *topic) unsubscribe(sub *Subscription) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.subscribers, sub)
	if len(t.subscribers) == 0 && t.stop != nil {
		t.stop()
		t.stop = nil
		t.latest = nil
	}
}

// publish frames the snapshot and delivers it only when its content changed.
func (t *topic) publish(generation int, snapshot any) {
	frame, err := json.Marshal(struct {
		Type  string `json:"type"`
		Topic string `json:"topic"`
		Data  any    `json:"data"`
	}{Type: "snapshot", Topic: t.name, Data: snapshot})
	if err != nil {
		t.logger.Error("snapshot encoding failed", "topic", t.name, "error", fmt.Sprintf("%T", err))
		return
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if generation != t.generation || t.stop == nil || bytes.Equal(frame, t.latest) {
		return
	}
	t.latest = frame
	for sub := range t.subscribers {
		deliver(sub.ch, frame)
	}
}

// deliver replaces a pending snapshot with the new one. Only publish writes to the
// channel, under the topic lock, so the send below always has room.
func deliver(ch chan []byte, frame []byte) {
	select {
	case <-ch:
	default:
	}
	ch <- frame
}
