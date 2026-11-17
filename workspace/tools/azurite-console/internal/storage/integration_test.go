package storage_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"azurite-console/internal/azurite"
	"azurite-console/internal/storage"
)

// clients returns the clients of the local Azurite, or skips the test
// unless AZURITE_CONSOLE_IT=1. Every resource a test creates is named
// it-console-<suffix> (itconsole<suffix> for tables) and deleted in
// t.Cleanup with a context of its own: t.Context() is already canceled
// when the cleanup functions run.
func clients(t *testing.T) azurite.Clients {
	t.Helper()
	if os.Getenv("AZURITE_CONSOLE_IT") != "1" {
		t.Skip("set AZURITE_CONSOLE_IT=1 with the Azurite of compose.yaml up to run against Azurite")
	}
	// The key: AZURITE_ACCOUNT_KEY, else the file named by AZURITE_CONSOLE_ENV_FILE.
	key, err := azurite.LookupKey(os.Getenv("AZURITE_CONSOLE_ENV_FILE"))
	if err != nil {
		t.Fatal(err)
	}
	account, err := azurite.New("127.0.0.1", key, azurite.HostPort)
	if err != nil {
		t.Fatal(err)
	}
	c, err := account.Clients(nil)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func suffix() string { return fmt.Sprint(time.Now().UnixNano()) }

func cleanup(t *testing.T, what string, fn func(context.Context) error) {
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := fn(ctx); err != nil {
			t.Errorf("cleanup of %s: %v", what, err)
		}
	})
}

func TestBlobsAgainstAzurite(t *testing.T) {
	b := storage.NewBlobs(clients(t).Blob)
	ctx := t.Context()
	name := "it-console-" + suffix()
	if err := b.CreateContainer(ctx, name); err != nil {
		t.Fatal(err)
	}
	cleanup(t, name, func(ctx context.Context) error { return b.DeleteContainer(ctx, name) })

	if f := storage.Classify(b.CreateContainer(ctx, name)); f.Kind != storage.KindConflict {
		t.Errorf("second create = %+v, want conflict", f)
	}
	for path, body := range map[string]string{
		"2026/11/16/ev1/fictitious contract.pdf": "%PDF-1.4 fictitious",
		"2026/11/16/agent-x_ev1.json":            `{"id":"agent-x_ev1"}`,
		"leia-me.txt":                            "texto",
	} {
		if err := b.Upload(ctx, name, path, "application/octet-stream", strings.NewReader(body)); err != nil {
			t.Fatal(err)
		}
	}

	root, err := b.List(ctx, name, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(root.Prefixes) != 1 || root.Prefixes[0] != "2026/" || len(root.Blobs) != 1 || root.Blobs[0].Name != "leia-me.txt" {
		t.Fatalf("root listing = %+v", root)
	}
	day, err := b.List(ctx, name, "2026/11/16/", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(day.Prefixes) != 1 || day.Prefixes[0] != "2026/11/16/ev1/" || len(day.Blobs) != 1 {
		t.Fatalf("day listing = %+v", day)
	}

	props, err := b.Properties(ctx, name, "2026/11/16/agent-x_ev1.json")
	if err != nil {
		t.Fatal(err)
	}
	if props.Size != 20 || props.ETag == "" {
		t.Errorf("properties = %+v", props)
	}
	c, err := b.Open(ctx, name, "leia-me.txt", 3)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := io.ReadAll(c.Body)
	_ = c.Body.Close()
	if string(got) != "tex" || c.Total != 5 {
		t.Errorf("range read = %q of %d", got, c.Total)
	}

	u, err := b.Usage(ctx, name, "2026/", 1)
	if err != nil || u.Count != 1 || !u.Truncated {
		t.Errorf("limited usage = %+v, %v", u, err)
	}
	u, err = b.DeletePrefix(ctx, name, "2026/11/16/ev1/")
	if err != nil || u.Count != 1 {
		t.Fatalf("delete prefix = %+v, %v", u, err)
	}
	if err := b.DeleteBlob(ctx, name, "leia-me.txt"); err != nil {
		t.Fatal(err)
	}
	if f := storage.Classify(b.DeleteBlob(ctx, name, "leia-me.txt")); f.Kind != storage.KindNotFound {
		t.Errorf("second delete = %+v, want not found", f)
	}
	u, err = b.DeletePrefix(ctx, name, "")
	if err != nil || u.Count != 1 {
		t.Errorf("empty container = %+v, %v", u, err)
	}
}

func TestQueuesAgainstAzurite(t *testing.T) {
	q := storage.NewQueues(clients(t).Queue)
	ctx := t.Context()
	name, other := "it-console-"+suffix(), "it-console-"+suffix()+"-b"
	for _, n := range []string{name, other} {
		if err := q.Create(ctx, n); err != nil {
			t.Fatal(err)
		}
		cleanup(t, n, func(ctx context.Context) error { return q.Delete(ctx, n) })
	}
	for _, text := range []string{`{"id":"m1"}`, `{"id":"m2"}`} {
		if err := q.Send(ctx, name, text, 0, 0); err != nil {
			t.Fatal(err)
		}
	}
	peeked, err := q.Peek(ctx, name, 32)
	if err != nil || len(peeked) != 2 || peeked[0].PopReceipt != "" {
		t.Fatalf("peek = %+v, %v", peeked, err)
	}
	got, err := q.Receive(ctx, name, 2, 60)
	if err != nil || len(got) != 2 || got[0].PopReceipt == "" || got[0].DequeueCount != 1 {
		t.Fatalf("receive = %+v, %v", got, err)
	}
	if again, _ := q.Peek(ctx, name, 32); len(again) != 0 {
		t.Errorf("received messages still visible: %+v", again)
	}

	receipt, err := q.Update(ctx, name, got[0].ID, got[0].PopReceipt, `{"id":"m1","edited":true}`, 0)
	if err != nil || receipt.PopReceipt == "" {
		t.Fatalf("update = %+v, %v", receipt, err)
	}
	if f := storage.Classify(q.DeleteMessage(ctx, name, got[0].ID, got[0].PopReceipt)); f.Kind != storage.KindPrecondition && f.Kind != storage.KindNotFound {
		t.Errorf("delete with the old receipt = %+v", f)
	}
	visible, err := q.Peek(ctx, name, 32)
	if err != nil || len(visible) != 1 || visible[0].Text != `{"id":"m1","edited":true}` {
		t.Fatalf("after update = %+v, %v", visible, err)
	}

	if err := q.Move(ctx, name, got[1].ID, got[1].PopReceipt, got[1].Text, other); err != nil {
		t.Fatal(err)
	}
	moved, err := q.Peek(ctx, other, 32)
	if err != nil || len(moved) != 1 || moved[0].Text != `{"id":"m2"}` {
		t.Fatalf("moved = %+v, %v", moved, err)
	}

	list, err := q.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int32{}
	for _, item := range list {
		counts[item.Name] = item.Messages
	}
	if counts[name] != 1 || counts[other] != 1 {
		t.Errorf("counts = %v", counts)
	}
	if err := q.Clear(ctx, name); err != nil {
		t.Fatal(err)
	}
	if left, _ := q.Peek(ctx, name, 32); len(left) != 0 {
		t.Errorf("after clear = %+v", left)
	}
}

func TestTablesAgainstAzurite(t *testing.T) {
	tb := storage.NewTables(clients(t).Table)
	ctx := t.Context()
	name := "itconsole" + suffix()
	if err := tb.Create(ctx, name); err != nil {
		t.Fatal(err)
	}
	cleanup(t, name, func(ctx context.Context) error { return tb.Delete(ctx, name) })

	for i := range 3 {
		e := fmt.Sprintf(`{"PartitionKey":"p%d","RowKey":"r%d","Count":"%d","Count@odata.type":"Edm.Int64","Name":"fictitious"}`, i%2, i, i)
		if _, err := tb.Insert(ctx, name, json.RawMessage(e)); err != nil {
			t.Fatal(err)
		}
	}
	page, err := tb.Query(ctx, name, storage.Query{Filter: "PartitionKey eq 'p0'"})
	if err != nil || len(page.Entities) != 2 {
		t.Fatalf("query = %+v, %v", page, err)
	}
	var row map[string]any
	if err := json.Unmarshal(page.Entities[0], &row); err != nil {
		t.Fatal(err)
	}
	etag, _ := row["odata.etag"].(string)
	if etag == "" || row["Count@odata.type"] != "Edm.Int64" {
		t.Fatalf("entity = %v", row)
	}
	first, err := tb.Query(ctx, name, storage.Query{Top: 1})
	if err != nil || len(first.Entities) != 1 || first.NextPartitionKey == "" {
		t.Fatalf("first page = %+v, %v", first, err)
	}
	next, err := tb.Query(ctx, name, storage.Query{Top: 5, NextPartitionKey: first.NextPartitionKey, NextRowKey: first.NextRowKey})
	if err != nil || len(next.Entities) != 2 {
		t.Fatalf("next page = %+v, %v", next, err)
	}

	edited := json.RawMessage(strings.Replace(string(page.Entities[0]), `"fictitious"`, `"edited"`, 1))
	newETag, err := tb.Update(ctx, name, edited, etag, false)
	if err != nil || newETag == "" {
		t.Fatalf("update = %q, %v", newETag, err)
	}
	if f := storage.Classify(func() error { _, err := tb.Update(ctx, name, edited, etag, true); return err }()); f.Kind != storage.KindPrecondition {
		t.Errorf("update with the old ETag = %+v, want precondition", f)
	}
	got, err := tb.Get(ctx, name, "p0", "r0")
	if err != nil || !strings.Contains(string(got.Value), `"edited"`) {
		t.Fatalf("get = %s, %v", got.Value, err)
	}

	c, err := tb.Count(ctx, name, "PartitionKey eq 'p1'", 100)
	if err != nil || c.Count != 1 {
		t.Errorf("count = %+v, %v", c, err)
	}
	n, err := tb.DeleteByFilter(ctx, name, "PartitionKey eq 'p0'")
	if err != nil || n != 2 {
		t.Fatalf("delete by filter = %d, %v", n, err)
	}
	if err := tb.DeleteEntity(ctx, name, "p1", "r1", ""); err != nil {
		t.Fatal(err)
	}
	if c, _ := tb.Count(ctx, name, "", 100); c.Count != 0 {
		t.Errorf("left = %+v", c)
	}
}
