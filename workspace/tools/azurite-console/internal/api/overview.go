package api

import (
	"net/http"
	"slices"
	"sync"
	"time"

	"azurite-console/internal/httpjson"

	"azurite-console/internal/activity"
	"azurite-console/internal/storage"
)

// serviceState is whether one service answered and how fast.
type serviceState struct {
	Name      string `json:"name"`
	Up        bool   `json:"up"`
	LatencyMs int64  `json:"latency_ms"`
	Error     string `json:"error,omitempty"`
}

type containerSummary struct {
	Name  string        `json:"name"`
	Usage storage.Usage `json:"usage"`
}

type tableSummary struct {
	Name     string        `json:"name"`
	Entities storage.Count `json:"entities"`
}

type azuriteInfo struct {
	Image   string `json:"image,omitempty"`
	Version string `json:"version,omitempty"`
	Error   string `json:"error,omitempty"`
}

// overviewResponse is the state of the account. The counts stop at Limit.
type overviewResponse struct {
	Services   []serviceState     `json:"services"`
	Containers []containerSummary `json:"containers"`
	Queues     []storage.Queue    `json:"queues"`
	Tables     []tableSummary     `json:"tables"`
	Azurite    azuriteInfo        `json:"azurite"`
	Limit      int                `json:"limit"`
}

// overview reads the three services at the same time. A service that fails
// is shown down, and the others are still read.
func (h *Handler) overview(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	out := overviewResponse{
		Services:   make([]serviceState, 3),
		Containers: []containerSummary{}, Queues: []storage.Queue{}, Tables: []tableSummary{},
		Limit: h.cfg.CountLimit,
	}
	var wg sync.WaitGroup
	wg.Go(func() {
		start := time.Now()
		containers, err := h.cfg.Blobs.Containers(ctx)
		out.Services[0] = h.state(r, "blob", start, err)
		for _, c := range containers {
			u, err := h.cfg.Blobs.Usage(ctx, c.Name, "", h.cfg.CountLimit)
			if err != nil {
				out.Services[0] = h.state(r, "blob", start, err)
				return
			}
			out.Containers = append(out.Containers, containerSummary{Name: c.Name, Usage: u})
		}
	})
	wg.Go(func() {
		start := time.Now()
		queues, err := h.cfg.Queues.List(ctx)
		out.Services[1] = h.state(r, "queue", start, err)
		if err == nil {
			out.Queues = queues
		}
	})
	wg.Go(func() {
		start := time.Now()
		tables, err := h.cfg.Tables.List(ctx)
		out.Services[2] = h.state(r, "table", start, err)
		for _, t := range tables {
			c, err := h.cfg.Tables.Count(ctx, t.Name, "", h.cfg.CountLimit)
			if err != nil {
				out.Services[2] = h.state(r, "table", start, err)
				return
			}
			out.Tables = append(out.Tables, tableSummary{Name: t.Name, Entities: c})
		}
	})
	wg.Go(func() {
		image, err := h.cfg.Log.Image(ctx)
		if err != nil {
			out.Azurite.Error = err.Error()
			return
		}
		out.Azurite = azuriteInfo{Image: image, Version: activity.Version(image)}
	})
	wg.Wait()
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

// state is the state of service after a call that started at start. The
// latency is that of the first list, before the counts.
func (h *Handler) state(r *http.Request, service string, start time.Time, err error) serviceState {
	s := serviceState{Name: service, Up: err == nil, LatencyMs: time.Since(start).Milliseconds()}
	if err != nil {
		p := problemOf(err)
		s.Error = httpjson.Message(r, p.Code)
	}
	return s
}

// activityResponse is the end of the access log, newest first. Without
// Docker or the container, Available is false and Reason says why.
type activityResponse struct {
	Available bool            `json:"available"`
	Reason    string          `json:"reason,omitempty"`
	Container string          `json:"container,omitempty"`
	Image     string          `json:"image,omitempty"`
	Lines     []activityEntry `json:"lines"`
}

type activityEntry struct {
	activity.Line
	Service string `json:"service,omitempty"`
}

// maxTail bounds the lines read from the log in one request.
const maxTail = 5000

// activity answers the end of the access log, newest first.
func (h *Handler) activity(w http.ResponseWriter, r *http.Request) {
	tail, err := intQuery(r, "tail", 500, 1, maxTail)
	if err != nil {
		fail(w, r, err)
		return
	}
	ctx := r.Context()
	log, err := h.cfg.Log.Tail(ctx, tail)
	if err != nil {
		httpjson.WriteJSON(w, r, http.StatusOK, activityResponse{Reason: err.Error(), Lines: []activityEntry{}})
		return
	}
	// The names tell queues and tables apart from containers; without them
	// every line on a named resource is shown as blob.
	queues, tables := map[string]bool{}, map[string]bool{}
	if qs, err := h.cfg.Queues.List(ctx); err == nil {
		for _, q := range qs {
			queues[q.Name] = true
		}
	}
	if ts, err := h.cfg.Tables.List(ctx); err == nil {
		for _, t := range ts {
			tables[t.Name] = true
		}
	}
	out := activityResponse{Available: true, Container: log.Container, Image: log.Image, Lines: make([]activityEntry, 0, len(log.Lines))}
	for _, l := range slices.Backward(log.Lines) {
		out.Lines = append(out.Lines, activityEntry{Line: l, Service: activity.Service(l, queues, tables)})
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}
