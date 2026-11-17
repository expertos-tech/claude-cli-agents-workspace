package api_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"

	"azurite-console/internal/activity"
	"azurite-console/internal/api"
	"azurite-console/internal/storage"
)

// azuriteError is an error as the SDK returns it for an answer of Azurite.
func azuriteError(status int, code string) error {
	req := httptest.NewRequest(http.MethodPut, "http://127.0.0.1:10000/devstoreaccount1/demo", nil)
	resp := &http.Response{StatusCode: status, Header: http.Header{"X-Ms-Error-Code": {code}}, Body: io.NopCloser(strings.NewReader("")), Request: req}
	return runtime.NewResponseError(resp)
}

// errDown is a call that never reached Azurite.
var errDown = errors.New("dial tcp 127.0.0.1:10000: connect: connection refused")

// The fakes embed the interface: a method a test does not set panics.
type fakeBlobs struct {
	api.BlobStore
	containers   []storage.Container
	containerErr error
	createErr    error
	usage        storage.Usage
	deleted      string
	content      storage.Content
}

func (f *fakeBlobs) Containers(context.Context) ([]storage.Container, error) {
	return f.containers, f.containerErr
}
func (f *fakeBlobs) CreateContainer(context.Context, string) error { return f.createErr }
func (f *fakeBlobs) Usage(context.Context, string, string, int) (storage.Usage, error) {
	return f.usage, nil
}
func (f *fakeBlobs) DeletePrefix(_ context.Context, name, prefix string) (storage.Usage, error) {
	f.deleted = name + "/" + prefix
	return f.usage, nil
}
func (f *fakeBlobs) Open(context.Context, string, string, int64) (storage.Content, error) {
	return f.content, nil
}

type fakeQueues struct {
	api.QueueStore
	queues   []storage.Queue
	err      error
	received int32
}

func (f *fakeQueues) List(context.Context) ([]storage.Queue, error) { return f.queues, f.err }
func (f *fakeQueues) Receive(_ context.Context, _ string, n, _ int32) ([]storage.Message, error) {
	f.received = n
	return []storage.Message{{ID: "m1", Text: `{"id":"x"}`, PopReceipt: "r1"}}, nil
}

type fakeTables struct {
	api.TableStore
	tables    []storage.Table
	err       error
	count     storage.Count
	countArgs string
	deleted   bool
	updateErr error
	update    string
}

func (f *fakeTables) List(context.Context) ([]storage.Table, error) { return f.tables, f.err }
func (f *fakeTables) Count(_ context.Context, name, filter string, _ int) (storage.Count, error) {
	f.countArgs = name + "|" + filter
	return f.count, nil
}
func (f *fakeTables) DeleteByFilter(context.Context, string, string) (int, error) {
	f.deleted = true
	return 3, nil
}
func (f *fakeTables) Update(_ context.Context, name string, entity json.RawMessage, etag string, replace bool) (string, error) {
	mode := "merge"
	if replace {
		mode = "replace"
	}
	f.update = name + "|" + string(entity) + "|" + etag + "|" + mode
	return "W/\"2\"", f.updateErr
}

type fakeLog struct {
	log activity.Log
	err error
}

func (f *fakeLog) Tail(context.Context, int) (activity.Log, error) { return f.log, f.err }
func (f *fakeLog) Image(context.Context) (string, error)           { return f.log.Image, f.err }

type env struct {
	blobs  *fakeBlobs
	queues *fakeQueues
	tables *fakeTables
	log    *fakeLog
	ops    *activity.Operations
	web    string
}

func newEnv() *env {
	return &env{blobs: &fakeBlobs{}, queues: &fakeQueues{}, tables: &fakeTables{}, log: &fakeLog{}, ops: activity.NewOperations(10)}
}

func (e *env) server(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	api.New(api.Config{Blobs: e.blobs, Queues: e.queues, Tables: e.tables, Log: e.log, Ops: e.ops, WebDir: e.web, CountLimit: 100}).Register(mux)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts
}

func call(t *testing.T, ts *httptest.Server, method, path, body string) (int, http.Header, []byte) {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), method, ts.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Accept-Language", "en")
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := ts.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, resp.Header, b
}

type problem struct {
	Status int    `json:"status"`
	Code   string `json:"code"`
	Title  string `json:"title"`
	Detail string `json:"detail"`
	Errors []struct {
		Field string `json:"field"`
	} `json:"errors"`
}

func decodeProblem(t *testing.T, body []byte) problem {
	t.Helper()
	var p problem
	if err := json.Unmarshal(body, &p); err != nil {
		t.Fatalf("problem: %v: %s", err, body)
	}
	return p
}

func TestFailureOfAzuriteKeepsItsStatusAndCode(t *testing.T) {
	e := newEnv()
	e.blobs.createErr = azuriteError(http.StatusConflict, "ContainerAlreadyExists")
	ts := e.server(t)
	status, hdr, body := call(t, ts, http.MethodPost, "/api/containers", `{"name":"demo"}`)
	p := decodeProblem(t, body)
	if status != http.StatusConflict || p.Code != "console.conflict" || !strings.HasPrefix(hdr.Get("Content-Type"), "application/problem+json") {
		t.Fatalf("status %d, problem %+v", status, p)
	}
	if !strings.Contains(p.Detail, "409 ContainerAlreadyExists") {
		t.Errorf("detail = %q", p.Detail)
	}
	ops := e.ops.List()
	if len(ops) != 1 || ops[0].Name != "Create container" || ops[0].Status != http.StatusConflict || ops[0].Error != "console.conflict" {
		t.Errorf("operations = %+v", ops)
	}
}

func TestAzuriteDownIsUnavailable(t *testing.T) {
	e := newEnv()
	e.blobs.containerErr = errDown
	ts := e.server(t)
	status, _, body := call(t, ts, http.MethodGet, "/api/containers", "")
	if p := decodeProblem(t, body); status != http.StatusServiceUnavailable || p.Code != "console.unavailable" || p.Detail != "" {
		t.Fatalf("status %d, problem %+v", status, p)
	}
	if len(e.ops.List()) != 0 {
		t.Error("a read was recorded as an operation")
	}
}

func TestUpdateEntityPassesETagAndModeAndMapsPrecondition(t *testing.T) {
	e := newEnv()
	ts := e.server(t)
	entity := `{"PartitionKey":"a","RowKey":"b","N":1}`
	status, _, body := call(t, ts, http.MethodPut, "/api/tables/demo/entities", `{"entity":`+entity+`,"etag":"W/\"1\"","mode":"replace"}`)
	if status != http.StatusOK || !strings.Contains(string(body), `"etag"`) {
		t.Fatalf("status %d: %s", status, body)
	}
	if want := "demo|" + entity + `|W/"1"|replace`; e.tables.update != want {
		t.Errorf("update = %q, want %q", e.tables.update, want)
	}

	e.tables.updateErr = azuriteError(http.StatusPreconditionFailed, "UpdateConditionNotSatisfied")
	status, _, body = call(t, ts, http.MethodPut, "/api/tables/demo/entities", `{"entity":`+entity+`,"etag":"W/\"1\""}`)
	if p := decodeProblem(t, body); status != http.StatusPreconditionFailed || p.Code != "console.precondition" {
		t.Fatalf("status %d, problem %+v", status, p)
	}

	status, _, body = call(t, ts, http.MethodPut, "/api/tables/demo/entities", `{"entity":`+entity+`,"mode":"upsert"}`)
	if p := decodeProblem(t, body); status != http.StatusBadRequest || len(p.Errors) != 1 || p.Errors[0].Field != "mode" {
		t.Fatalf("status %d, problem %+v", status, p)
	}
}

func TestEntityInvalidIsABadRequest(t *testing.T) {
	e := newEnv()
	e.tables.updateErr = storage.ErrEntityInvalid
	ts := e.server(t)
	status, _, body := call(t, ts, http.MethodPut, "/api/tables/demo/entities", `{"entity":[1]}`)
	if p := decodeProblem(t, body); status != http.StatusBadRequest || p.Code != "console.entity_invalid" {
		t.Fatalf("status %d, problem %+v", status, p)
	}
}

func TestReceiveValidatesCountAndVisibility(t *testing.T) {
	e := newEnv()
	ts := e.server(t)
	for _, body := range []string{`{"count":0,"visibility_seconds":30}`, `{"count":33,"visibility_seconds":30}`, `{"count":1,"visibility_seconds":0}`} {
		if status, _, _ := call(t, ts, http.MethodPost, "/api/queues/demo/receive", body); status != http.StatusBadRequest {
			t.Errorf("%s: status %d, want 400", body, status)
		}
	}
	status, _, body := call(t, ts, http.MethodPost, "/api/queues/demo/receive", `{"count":5,"visibility_seconds":30}`)
	if status != http.StatusOK || e.queues.received != 5 || !strings.Contains(string(body), `"pop_receipt":"r1"`) {
		t.Fatalf("status %d, received %d: %s", status, e.queues.received, body)
	}
}

func TestDeleteByFilterDryRunOnlyCounts(t *testing.T) {
	e := newEnv()
	e.tables.count = storage.Count{Count: 7}
	ts := e.server(t)
	status, _, body := call(t, ts, http.MethodPost, "/api/tables/demo/delete-by-filter", `{"filter":"PartitionKey eq 'a'","dry_run":true}`)
	if status != http.StatusOK || string(body) != `{"count":7}` || e.tables.deleted || e.tables.countArgs != "demo|PartitionKey eq 'a'" {
		t.Fatalf("status %d, deleted %v, count args %q: %s", status, e.tables.deleted, e.tables.countArgs, body)
	}
	status, _, body = call(t, ts, http.MethodPost, "/api/tables/demo/delete-by-filter", `{"filter":"PartitionKey eq 'a'"}`)
	if status != http.StatusOK || string(body) != `{"count":3}` || !e.tables.deleted {
		t.Fatalf("status %d, deleted %v: %s", status, e.tables.deleted, body)
	}
}

func TestDeletePrefixRequiresAPrefix(t *testing.T) {
	e := newEnv()
	e.blobs.usage = storage.Usage{Count: 2, Bytes: 10}
	ts := e.server(t)
	if status, _, _ := call(t, ts, http.MethodDelete, "/api/containers/events/prefix", ""); status != http.StatusBadRequest {
		t.Fatalf("status %d, want 400", status)
	}
	status, _, body := call(t, ts, http.MethodDelete, "/api/containers/events/prefix?prefix=2026/10/28/", "")
	if status != http.StatusOK || e.blobs.deleted != "events/2026/10/28/" || !strings.Contains(string(body), `"count":2`) {
		t.Fatalf("status %d, deleted %q: %s", status, e.blobs.deleted, body)
	}
	if ops := e.ops.List(); len(ops) != 2 || ops[0].Target != "events/2026/10/28/*" {
		t.Errorf("operations = %+v", ops)
	}
}

func TestBlobPreviewNeverServesActiveContent(t *testing.T) {
	cases := []struct{ stored, query, want string }{
		{"text/html", "", "text/plain; charset=utf-8"},
		{"image/svg+xml", "", "text/plain; charset=utf-8"},
		{"application/pdf", "", "application/pdf"},
		{"application/json", "?max=10", "application/json"},
		{"text/html", "?download", "application/octet-stream"},
	}
	for _, tc := range cases {
		e := newEnv()
		e.blobs.content = storage.Content{Body: io.NopCloser(strings.NewReader("<p>x</p>")), ContentType: tc.stored, Size: 8, Total: 20}
		ts := e.server(t)
		status, hdr, body := call(t, ts, http.MethodGet, "/api/containers/events/blobs/2026/10/28/a%20b.html"+tc.query, "")
		if status != http.StatusOK || hdr.Get("Content-Type") != tc.want || string(body) != "<p>x</p>" {
			t.Errorf("%s%s: status %d, content-type %q", tc.stored, tc.query, status, hdr.Get("Content-Type"))
		}
		if hdr.Get("X-Content-Type-Options") != "nosniff" || hdr.Get("X-Blob-Size") != "20" || hdr.Get("X-Blob-Content-Type") != tc.stored {
			t.Errorf("%s%s: headers %v", tc.stored, tc.query, hdr)
		}
		if tc.query == "?download" && hdr.Get("Content-Disposition") != `attachment; filename="a b.html"` {
			t.Errorf("content-disposition = %q", hdr.Get("Content-Disposition"))
		}
	}
}

func TestOverviewShowsAServiceDownAndReadsTheOthers(t *testing.T) {
	e := newEnv()
	e.blobs.containers = []storage.Container{{Name: "events"}}
	e.blobs.usage = storage.Usage{Count: 3, Bytes: 300}
	e.queues.err = errDown
	e.tables.tables = []storage.Table{{Name: "Demo"}}
	e.tables.count = storage.Count{Count: 100, Truncated: true}
	e.log.log = activity.Log{Image: "mcr.microsoft.com/azure-storage/azurite:3.37.0"}
	ts := e.server(t)
	status, _, body := call(t, ts, http.MethodGet, "/api/overview", "")
	if status != http.StatusOK {
		t.Fatalf("status %d: %s", status, body)
	}
	var got struct {
		Services []struct {
			Name  string `json:"name"`
			Up    bool   `json:"up"`
			Error string `json:"error"`
		} `json:"services"`
		Containers []struct {
			Usage storage.Usage `json:"usage"`
		} `json:"containers"`
		Tables []struct {
			Entities storage.Count `json:"entities"`
		} `json:"tables"`
		Azurite struct {
			Version string `json:"version"`
		} `json:"azurite"`
	}
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if len(got.Services) != 3 || !got.Services[0].Up || got.Services[1].Up || !got.Services[2].Up {
		t.Fatalf("services = %+v", got.Services)
	}
	if got.Services[1].Error != "Azurite is down or unreachable" {
		t.Errorf("queue error = %q", got.Services[1].Error)
	}
	if got.Containers[0].Usage.Count != 3 || !got.Tables[0].Entities.Truncated || got.Azurite.Version != "3.37.0" {
		t.Errorf("overview = %s", body)
	}
}

func TestActivity(t *testing.T) {
	e := newEnv()
	e.log.err = errors.New("docker CLI not found on the PATH")
	ts := e.server(t)
	_, _, body := call(t, ts, http.MethodGet, "/api/activity", "")
	if !strings.Contains(string(body), `"available":false`) || !strings.Contains(string(body), "docker CLI not found") {
		t.Fatalf("activity without docker = %s", body)
	}

	e.log.err = nil
	e.log.log = activity.Log{Container: "azurite-console-azurite-1", Lines: []activity.Line{
		{Resource: "events/a.json", Method: "PUT", Status: 201, Bytes: -1},
		{Resource: "events-agent-sales/messages", Method: "POST", Status: 201, Bytes: -1},
	}}
	e.queues.queues = []storage.Queue{{Name: "events-agent-sales"}}
	_, _, body = call(t, ts, http.MethodGet, "/api/activity?tail=10", "")
	var got struct {
		Available bool `json:"available"`
		Lines     []struct {
			Resource string `json:"resource"`
			Service  string `json:"service"`
		} `json:"lines"`
	}
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if !got.Available || len(got.Lines) != 2 || got.Lines[0].Service != "queue" || got.Lines[1].Service != "blob" {
		t.Fatalf("activity = %s", body)
	}
	if status, _, _ := call(t, ts, http.MethodGet, "/api/activity?tail=0", ""); status != http.StatusBadRequest {
		t.Errorf("tail=0: status %d, want 400", status)
	}
}

func TestStatic(t *testing.T) {
	e := newEnv()
	e.web = t.TempDir()
	ts := e.server(t)
	status, _, body := call(t, ts, http.MethodGet, "/", "")
	if status != http.StatusOK || !strings.Contains(string(body), "npm --prefix tools/azurite-console/web run build") {
		t.Fatalf("without build: status %d: %s", status, body)
	}
	if err := os.WriteFile(filepath.Join(e.web, "index.html"), []byte("<!doctype html><div id=root></div>"), 0o600); err != nil {
		t.Fatal(err)
	}
	status, hdr, body := call(t, ts, http.MethodGet, "/", "")
	if status != http.StatusOK || !strings.Contains(string(body), "id=root") || hdr.Get("Cache-Control") != "no-store" {
		t.Fatalf("with build: status %d, cache %q: %s", status, hdr.Get("Cache-Control"), body)
	}
	status, hdr, _ = call(t, ts, http.MethodGet, "/api/nothing", "")
	if status != http.StatusNotFound || !strings.HasPrefix(hdr.Get("Content-Type"), "application/problem+json") {
		t.Fatalf("/api/nothing: status %d, content-type %q", status, hdr.Get("Content-Type"))
	}
}

// TestWrongMethodIsAProblemThatListsTheAllowedOnes covers the 405 of a known path.
func TestWrongMethodIsAProblemThatListsTheAllowedOnes(t *testing.T) {
	ts := newEnv().server(t)
	status, hdr, body := call(t, ts, http.MethodPatch, "/api/queues", "")
	p := decodeProblem(t, body)
	if status != http.StatusMethodNotAllowed || p.Code != "method_not_allowed" || p.Title != "method not allowed" {
		t.Fatalf("status %d, problem %+v", status, p)
	}
	if got := hdr.Get("Allow"); got != "GET, HEAD, POST" {
		t.Errorf("allow = %q", got)
	}
}

// TestProblemFollowsTheLanguageOfTheRequest covers the catalog in both languages.
func TestProblemFollowsTheLanguageOfTheRequest(t *testing.T) {
	e := newEnv()
	e.blobs.createErr = azuriteError(http.StatusConflict, "ContainerAlreadyExists")
	ts := e.server(t)
	for language, want := range map[string][2]string{
		"":             {"already exists or is being deleted", "Azurite answered 409 ContainerAlreadyExists"},
		"pt-BR":        {"já existe ou está sendo excluído", "o Azurite respondeu 409 ContainerAlreadyExists"},
		"en-US,en;q=1": {"already exists or is being deleted", "Azurite answered 409 ContainerAlreadyExists"},
		"fr":           {"already exists or is being deleted", "Azurite answered 409 ContainerAlreadyExists"},
	} {
		req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, ts.URL+"/api/containers", strings.NewReader(`{"name":"demo"}`))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Accept-Language", language)
		resp, err := ts.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		if err != nil {
			t.Fatal(err)
		}
		if p := decodeProblem(t, body); p.Title != want[0] || p.Detail != want[1] {
			t.Errorf("%q: problem %+v", language, p)
		}
	}
}
