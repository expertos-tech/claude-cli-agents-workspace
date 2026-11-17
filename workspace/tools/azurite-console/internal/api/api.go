// Package api serves the JSON API of the console under /api/ and the built
// page of web/dist. Every failure is a problem document; the failures of
// Azurite carry its status and error code in the detail. The actions that
// change something are recorded in the operations shown by the page.
package api

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"strconv"
	"strings"
	"time"

	"azurite-console/internal/httpjson"

	"azurite-console/internal/activity"
	"azurite-console/internal/storage"
)

//go:embed locales
var localeFiles embed.FS

// init adds the messages of the console to the catalog. The files are embedded
// at build time, so a failure here is a build defect.
func init() {
	sub, err := fs.Sub(localeFiles, "locales")
	if err != nil {
		panic(err)
	}
	if err := httpjson.Register(sub); err != nil {
		panic(err)
	}
}

// Problem codes of the console; each is the catalog key of its title.
const (
	codeNotFound     = "console.not_found"
	codeConflict     = "console.conflict"
	codePrecondition = "console.precondition"
	codeBadRequest   = "console.bad_request"
	codeUnavailable  = "console.unavailable"
	codeEntity       = "console.entity_invalid"
	detailAnswer     = "console.azurite_answer"
)

// BlobStore is what the handler needs from the Blob service.
type BlobStore interface {
	Ping(ctx context.Context) error
	Containers(ctx context.Context) ([]storage.Container, error)
	CreateContainer(ctx context.Context, name string) error
	DeleteContainer(ctx context.Context, name string) error
	List(ctx context.Context, name, prefix, marker string) (storage.Listing, error)
	Usage(ctx context.Context, name, prefix string, limit int) (storage.Usage, error)
	Properties(ctx context.Context, name, path string) (storage.Properties, error)
	Open(ctx context.Context, name, path string, limit int64) (storage.Content, error)
	Upload(ctx context.Context, name, path, contentType string, body io.Reader) error
	DeleteBlob(ctx context.Context, name, path string) error
	DeletePrefix(ctx context.Context, name, prefix string) (storage.Usage, error)
}

// QueueStore is what the handler needs from the Queue service.
type QueueStore interface {
	Ping(ctx context.Context) error
	List(ctx context.Context) ([]storage.Queue, error)
	Create(ctx context.Context, name string) error
	Delete(ctx context.Context, name string) error
	Clear(ctx context.Context, name string) error
	Peek(ctx context.Context, name string, n int32) ([]storage.Message, error)
	Receive(ctx context.Context, name string, n, visibility int32) ([]storage.Message, error)
	Send(ctx context.Context, name, text string, delay, ttl int32) error
	Update(ctx context.Context, name, id, popReceipt, text string, visibility int32) (storage.Receipt, error)
	DeleteMessage(ctx context.Context, name, id, popReceipt string) error
	Move(ctx context.Context, from, id, popReceipt, text, to string) error
}

// TableStore is what the handler needs from the Table service.
type TableStore interface {
	Ping(ctx context.Context) error
	List(ctx context.Context) ([]storage.Table, error)
	Create(ctx context.Context, name string) error
	Delete(ctx context.Context, name string) error
	Count(ctx context.Context, name, filter string, limit int) (storage.Count, error)
	Query(ctx context.Context, name string, q storage.Query) (storage.EntityPage, error)
	Get(ctx context.Context, name, pk, rk string) (storage.Entity, error)
	Insert(ctx context.Context, name string, entity json.RawMessage) (string, error)
	Update(ctx context.Context, name string, entity json.RawMessage, etag string, replace bool) (string, error)
	DeleteEntity(ctx context.Context, name, pk, rk, etag string) error
	DeleteByFilter(ctx context.Context, name, filter string) (int, error)
}

// LogSource reads the access log and the image of the Azurite container.
type LogSource interface {
	Tail(ctx context.Context, n int) (activity.Log, error)
	Image(ctx context.Context) (string, error)
}

// Router registers handlers by ServeMux pattern; *http.ServeMux is one.
type Router interface {
	Handle(pattern string, h http.Handler)
}

// Config is what the handler serves.
type Config struct {
	Blobs  BlobStore
	Queues QueueStore
	Tables TableStore
	Log    LogSource
	Ops    *activity.Operations
	// WebDir is the folder of the built page (web/dist).
	WebDir string
	// CountLimit stops the counts of the overview.
	CountLimit int
}

// Handler serves the routes of the console.
type Handler struct {
	cfg Config
}

// New returns the handler of cfg.
func New(cfg Config) *Handler { return &Handler{cfg: cfg} }

// Register adds the routes to r.
func (h *Handler) Register(r Router) {
	routes := []struct {
		pattern, name string
		fn            http.HandlerFunc
	}{
		{"GET /api/overview", "", h.overview},
		{"GET /api/activity", "", h.activity},
		{"GET /api/operations", "", h.operations},

		{"GET /api/containers", "", h.containers},
		{"POST /api/containers", "Create container", h.createContainer},
		{"DELETE /api/containers/{c}", "Delete container", h.deleteContainer},
		{"POST /api/containers/{c}/empty", "Empty container", h.emptyContainer},
		{"GET /api/containers/{c}/list", "", h.list},
		{"GET /api/containers/{c}/usage", "", h.usage},
		{"DELETE /api/containers/{c}/prefix", "Delete folder", h.deletePrefix},
		{"GET /api/containers/{c}/blobs/{path...}", "", h.blob},
		{"PUT /api/containers/{c}/blobs/{path...}", "Upload blob", h.upload},
		{"DELETE /api/containers/{c}/blobs/{path...}", "Delete blob", h.deleteBlob},

		{"GET /api/queues", "", h.queues},
		{"POST /api/queues", "Create queue", h.createQueue},
		{"DELETE /api/queues/{q}", "Delete queue", h.deleteQueue},
		{"POST /api/queues/{q}/clear", "Clear queue", h.clearQueue},
		{"GET /api/queues/{q}/peek", "", h.peek},
		{"POST /api/queues/{q}/receive", "Receive messages", h.receive},
		{"POST /api/queues/{q}/messages", "Send message", h.send},
		{"PUT /api/queues/{q}/messages/{id}", "Update message", h.updateMessage},
		{"DELETE /api/queues/{q}/messages/{id}", "Delete message", h.deleteMessage},
		{"POST /api/queues/{q}/messages/{id}/move", "Move message", h.moveMessage},

		{"GET /api/tables", "", h.tables},
		{"POST /api/tables", "Create table", h.createTable},
		{"DELETE /api/tables/{t}", "Delete table", h.deleteTable},
		{"GET /api/tables/{t}/entities", "", h.entities},
		{"GET /api/tables/{t}/entity", "", h.entity},
		{"POST /api/tables/{t}/entities", "Insert entity", h.insertEntity},
		{"PUT /api/tables/{t}/entities", "Save entity", h.updateEntity},
		{"DELETE /api/tables/{t}/entities", "Delete entity", h.deleteEntity},
		{"POST /api/tables/{t}/delete-by-filter", "Delete by filter", h.deleteByFilter},

		// Without a method: the 405 fallbacks added below are method-less too,
		// and a "GET /" would conflict with them.
		{"/", "", h.static},
	}
	allowed := map[string][]string{}
	for _, rt := range routes {
		var handler http.Handler = rt.fn
		if rt.name != "" {
			handler = h.record(rt.name, rt.fn)
		}
		r.Handle(rt.pattern, handler)
		if method, path, ok := strings.Cut(rt.pattern, " "); ok {
			allowed[path] = append(allowed[path], method)
			if method == http.MethodGet {
				allowed[path] = append(allowed[path], http.MethodHead)
			}
		}
	}
	// A wrong method on a known path would otherwise fall to "/", as a 404.
	for path, methods := range allowed {
		r.Handle(path, httpjson.MethodNotAllowed(methods...))
	}
}

// operations answers the actions recorded by the console.
func (h *Handler) operations(w http.ResponseWriter, r *http.Request) {
	httpjson.WriteJSON(w, r, http.StatusOK, h.cfg.Ops.List())
}

// record wraps an action that changes something, so the page lists it with
// its target, status and duration.
func (h *Handler) record(name string, next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &recorder{ResponseWriter: w, status: http.StatusOK}
		next(rec, r)
		h.cfg.Ops.Add(activity.Operation{
			Time: start, Name: name, Target: target(r), Status: rec.status,
			DurationMs: time.Since(start).Milliseconds(), Error: rec.code,
		})
	})
}

// recorder keeps the status written and the problem code set by fail.
type recorder struct {
	http.ResponseWriter
	status int
	code   string
}

// WriteHeader keeps the status before writing it.
func (r *recorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

// target names what an action acted on, from the path and the query.
func target(r *http.Request) string {
	var parts []string
	for _, key := range []string{"c", "q", "t", "path", "id"} {
		if v := r.PathValue(key); v != "" {
			parts = append(parts, v)
		}
	}
	q := r.URL.Query()
	if v := q.Get("prefix"); v != "" {
		parts = append(parts, v+"*")
	}
	if pk := q.Get("pk"); pk != "" {
		parts = append(parts, "("+pk+", "+q.Get("rk")+")")
	}
	return strings.Join(parts, "/")
}

// fail writes err as a problem document. Failures of Azurite keep its
// status and code in the detail, so the page shows what Azurite said.
func fail(w http.ResponseWriter, r *http.Request, err error) {
	if rec, ok := w.(*recorder); ok {
		defer func() { rec.code = problemCode(err) }()
	}
	if _, ok := errors.AsType[*httpjson.Problem](err); ok {
		httpjson.WriteError(w, r, err)
		return
	}
	if errors.Is(err, context.Canceled) && r.Context().Err() != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if errors.Is(err, storage.ErrEntityInvalid) {
		httpjson.WriteError(w, r, httpjson.New(http.StatusBadRequest, codeEntity).Wrap(err))
		return
	}
	if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
		httpjson.WriteError(w, r, httpjson.New(http.StatusRequestEntityTooLarge, httpjson.CodePayloadTooLarge).Wrap(err))
		return
	}
	httpjson.WriteError(w, r, problemOf(err))
}

// problemOf maps a failure of Azurite to a problem.
func problemOf(err error) *httpjson.Problem {
	f := storage.Classify(err)
	var p *httpjson.Problem
	switch f.Kind {
	case storage.KindNotFound:
		p = httpjson.New(http.StatusNotFound, codeNotFound)
	case storage.KindConflict:
		p = httpjson.New(http.StatusConflict, codeConflict)
	case storage.KindPrecondition:
		p = httpjson.New(http.StatusPreconditionFailed, codePrecondition)
	case storage.KindBadRequest:
		p = httpjson.New(http.StatusBadRequest, codeBadRequest)
	case storage.KindUnavailable:
		p = httpjson.New(http.StatusServiceUnavailable, codeUnavailable)
	default:
		p = httpjson.New(http.StatusInternalServerError, httpjson.CodeInternal)
	}
	if f.Status != 0 {
		p = p.WithDetail(detailAnswer, f.Status, f.Code)
	}
	return p.Wrap(err)
}

// problemCode is the code that fail answers for err.
func problemCode(err error) string {
	if p, ok := errors.AsType[*httpjson.Problem](err); ok {
		return p.Code
	}
	if errors.Is(err, storage.ErrEntityInvalid) {
		return codeEntity
	}
	if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
		return httpjson.CodePayloadTooLarge
	}
	return problemOf(err).Code
}

// badRequest is a request of the page the console refuses before calling Azurite.
func badRequest(field, code string) error {
	return httpjson.Validation(httpjson.Field(field, code))
}

// decode reads the JSON body into v.
func decode(r *http.Request, v any) error {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(body, v); err != nil {
		return httpjson.New(http.StatusBadRequest, httpjson.CodeBadRequest).Wrap(err)
	}
	return nil
}

// intQuery reads the integer query parameter key, with def when absent, and
// refuses a value outside [lo, hi].
func intQuery(r *http.Request, key string, def, lo, hi int) (int, error) {
	s := r.URL.Query().Get(key)
	if s == "" {
		return def, nil
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < lo || n > hi {
		return 0, badRequest(key, httpjson.FieldInvalid)
	}
	return n, nil
}

// inRange refuses n outside [lo, hi] as the field name.
func inRange(field string, n, lo, hi int32) error {
	if n < lo || n > hi {
		return badRequest(field, httpjson.FieldInvalid)
	}
	return nil
}

// named is the body that creates a container, a queue or a table.
type named struct {
	Name string `json:"name"`
}

// validate refuses an empty name.
func (n named) validate() error {
	if strings.TrimSpace(n.Name) == "" {
		return badRequest("name", httpjson.FieldRequired)
	}
	return nil
}

// noContent answers 204.
func noContent(w http.ResponseWriter, r *http.Request) {
	httpjson.WriteJSON(w, r, http.StatusNoContent, nil)
}
