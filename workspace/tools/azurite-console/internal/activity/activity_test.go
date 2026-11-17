package activity

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestParseLine(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want Line
	}{
		{
			name: "blob with encoded path",
			in:   `2026-10-28T13:26:10.377556717Z 172.18.0.10 - - [28/Oct/2026:13:26:10 +0000] "PUT /devstoreaccount1/events/2026%2F10%2F28%2Fa1%2F02-contrato.pdf HTTP/1.1" 201 -`,
			want: Line{Time: time.Date(2026, 10, 28, 13, 26, 10, 377556717, time.UTC), IP: "172.18.0.10", Method: "PUT",
				Resource: "events/2026/10/28/a1/02-contrato.pdf", Status: 201, Bytes: -1},
		},
		{
			name: "queue message",
			in:   `2026-10-28T13:26:10.414081342Z 172.18.0.10 - - [28/Oct/2026:13:26:10 +0000] "POST /devstoreaccount1/events-agent-sales/messages HTTP/1.1" 201 -`,
			want: Line{Time: time.Date(2026, 10, 28, 13, 26, 10, 414081342, time.UTC), IP: "172.18.0.10", Method: "POST",
				Resource: "events-agent-sales/messages", Status: 201, Bytes: -1},
		},
		{
			name: "query and size",
			in:   `2026-10-28T13:26:11.244456134Z 172.18.0.1 - - [28/Oct/2026:13:26:11 +0000] "GET /devstoreaccount1/events?restype=container&comp=list HTTP/1.1" 200 639`,
			want: Line{Time: time.Date(2026, 10, 28, 13, 26, 11, 244456134, time.UTC), IP: "172.18.0.1", Method: "GET",
				Resource: "events", Query: "restype=container&comp=list", Status: 200, Bytes: 639},
		},
		{
			name: "without docker timestamp",
			in:   `172.18.0.1 - - [28/Oct/2026:13:26:11 +0000] "DELETE /devstoreaccount1/demo HTTP/1.1" 404 -`,
			want: Line{Time: time.Date(2026, 10, 28, 13, 26, 11, 0, time.FixedZone("", 0)), IP: "172.18.0.1", Method: "DELETE",
				Resource: "demo", Status: 404, Bytes: -1},
		},
		{
			name: "startup message",
			in:   `2026-10-27T09:00:00.000000000Z Azurite Blob service is successfully listening at http://0.0.0.0:10000`,
			want: Line{Time: time.Date(2026, 10, 27, 9, 0, 0, 0, time.UTC), Bytes: -1, Raw: "Azurite Blob service is successfully listening at http://0.0.0.0:10000"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ParseLine(tc.in)
			if !got.Time.Equal(tc.want.Time) {
				t.Errorf("time = %v, want %v", got.Time, tc.want.Time)
			}
			got.Time, tc.want.Time = time.Time{}, time.Time{}
			if got != tc.want {
				t.Errorf("ParseLine() = %+v\nwant %+v", got, tc.want)
			}
		})
	}
}

func TestService(t *testing.T) {
	queues := map[string]bool{"events-agent-sales": true}
	tables := map[string]bool{"RelayDays": true}
	cases := []struct {
		resource, query, want string
	}{
		{"events/2026/10/28/a.json", "", "blob"},
		{"events", "restype=container", "blob"},
		{"events-agent-sales", "", "queue"},
		{"events-agent-sales", "restype=container", "blob"},
		{"other-queue/messages", "numofmessages=32", "queue"},
		{"other-queue/messages/abc", "popreceipt=x", "queue"},
		{"Tables", "", "table"},
		{"RelayDays()", "$filter=x", "table"},
		{"RelayDays(PartitionKey='a',RowKey='b')", "", "table"},
		{"RelayDays", "", "table"},
		{"$batch", "", "table"},
		{"", "comp=list", "account"},
	}
	for _, tc := range cases {
		if got := Service(Line{Resource: tc.resource, Query: tc.query}, queues, tables); got != tc.want {
			t.Errorf("Service(%q, %q) = %q, want %q", tc.resource, tc.query, got, tc.want)
		}
	}
	if got := Service(Line{Raw: "Azurite started"}, queues, tables); got != "" {
		t.Errorf("Service(raw) = %q, want empty", got)
	}
}

func TestDockerTail(t *testing.T) {
	log := strings.Join([]string{
		`2026-10-28T13:26:10.401467550Z 172.18.0.10 - - [28/Oct/2026:13:26:10 +0000] "PUT /devstoreaccount1/events-agent-sales HTTP/1.1" 204 -`,
		``,
		`2026-10-28T13:26:11.244456134Z 172.18.0.1 - - [28/Oct/2026:13:26:11 +0000] "GET /devstoreaccount1/events HTTP/1.1" 200 10`,
	}, "\n")
	var calls []string
	run := func(_ context.Context, args ...string) ([]byte, error) {
		calls = append(calls, strings.Join(args, " "))
		switch {
		case args[0] == "ps" && strings.HasSuffix(args[3], "service=azurite"):
			return []byte("abc123\n"), nil
		case args[0] == "inspect" && len(args) == 4 && args[3] == "abc123":
			return []byte("abc123full|/azurite-console-azurite-1|mcr.microsoft.com/azure-storage/azurite:3.37.0|azurite-console\n"), nil
		case args[0] == "logs":
			return []byte(log), nil
		case args[0] == "ps":
			return []byte("abc123\ndef456\n"), nil
		case args[0] == "inspect":
			return []byte("azurite 172.18.0.2/172.18.0.1\nsample-worker 172.18.0.10/172.18.0.1\n"), nil
		}
		return nil, fmt.Errorf("unexpected call %v", args)
	}
	got, err := NewDocker(run).Tail(context.Background(), 50)
	if err != nil {
		t.Fatal(err)
	}
	if got.Container != "azurite-console-azurite-1" || Version(got.Image) != "3.37.0" {
		t.Errorf("container = %q, image = %q", got.Container, got.Image)
	}
	if len(got.Lines) != 2 {
		t.Fatalf("lines = %d, want 2", len(got.Lines))
	}
	if got.Lines[0].Caller != "sample-worker" || got.Lines[1].Caller != "host" {
		t.Errorf("callers = %q, %q", got.Lines[0].Caller, got.Lines[1].Caller)
	}
	if !strings.Contains(strings.Join(calls, ";"), "logs --tail 50 --timestamps abc123full") {
		t.Errorf("logs not read from the inspected id: %v", calls)
	}
}

func TestDockerWithoutContainer(t *testing.T) {
	run := func(_ context.Context, args ...string) ([]byte, error) {
		if args[0] == "ps" {
			return nil, nil
		}
		return nil, errors.New("not expected")
	}
	if _, err := NewDocker(run).Tail(context.Background(), 10); err == nil {
		t.Fatal("Tail without an Azurite container returned no error")
	}
}

// TestVersionIgnoresTheDigestOfAPinnedImage covers the image pinned in compose.yaml.
func TestVersionIgnoresTheDigestOfAPinnedImage(t *testing.T) {
	if got := Version("mcr.microsoft.com/azure-storage/azurite:3.37.0@sha256:abc"); got != "3.37.0" {
		t.Errorf("Version = %q", got)
	}
}

func TestVersion(t *testing.T) {
	for image, want := range map[string]string{
		"mcr.microsoft.com/azure-storage/azurite:3.37.0": "3.37.0",
		"mcr.microsoft.com/azure-storage/azurite":        "",
		"localhost:5000/azurite":                         "",
	} {
		if got := Version(image); got != want {
			t.Errorf("Version(%q) = %q, want %q", image, got, want)
		}
	}
}

func TestOperationsKeepTheNewestFirst(t *testing.T) {
	ops := NewOperations(2)
	for _, name := range []string{"a", "b", "c"} {
		ops.Add(Operation{Name: name})
	}
	got := ops.List()
	if len(got) != 2 || got[0].Name != "c" || got[1].Name != "b" {
		t.Fatalf("List() = %+v", got)
	}
}
