package azurite

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const fakeKey = "ZmFrZS1rZXktZm9yLXRlc3Rz" // base64 of a fictitious value; gitleaks:allow

func TestNewAcceptsOnlyLocalHosts(t *testing.T) {
	for _, host := range []string{"127.0.0.1", "::1", "localhost", "azurite", "127.0.0.2"} {
		if _, err := New(host, fakeKey, ContainerPort); err != nil {
			t.Errorf("New(%q) = %v, want nil", host, err)
		}
	}
	for _, host := range []string{"", "10.0.0.5", "example.blob.core.windows.net", "0.0.0.0", "azurite.example.com"} {
		if _, err := New(host, fakeKey, ContainerPort); err == nil {
			t.Errorf("New(%q) accepted a host that is not local", host)
		}
	}
}

func TestNewRejectsEmptyKey(t *testing.T) {
	if _, err := New("127.0.0.1", "  ", ContainerPort); err == nil {
		t.Fatal("New accepted an empty key")
	}
}

func TestConnectionStringPointsAtTheLocalAccount(t *testing.T) {
	a, err := New("127.0.0.1", fakeKey, ContainerPort)
	if err != nil {
		t.Fatal(err)
	}
	cs := a.ConnectionString()
	for _, want := range []string{
		"AccountName=devstoreaccount1;",
		"AccountKey=" + fakeKey + ";",
		"BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;",
		"QueueEndpoint=http://127.0.0.1:10001/devstoreaccount1;",
		"TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;",
	} {
		if !strings.Contains(cs, want) {
			t.Errorf("connection string lacks %q", want)
		}
	}
	v6, err := New("::1", fakeKey, ContainerPort)
	if err != nil {
		t.Fatal(err)
	}
	if got := v6.endpoint(blobOffset); got != "http://[::1]:10000/devstoreaccount1" {
		t.Errorf("IPv6 endpoint = %q", got)
	}
}

// TestHostPortReachesThePortsComposePublishes covers the console run outside Compose.
func TestHostPortReachesThePortsComposePublishes(t *testing.T) {
	a, err := New("127.0.0.1", fakeKey, HostPort)
	if err != nil {
		t.Fatal(err)
	}
	cs := a.ConnectionString()
	for _, want := range []string{
		"BlobEndpoint=http://127.0.0.1:30000/devstoreaccount1;",
		"QueueEndpoint=http://127.0.0.1:30001/devstoreaccount1;",
		"TableEndpoint=http://127.0.0.1:30002/devstoreaccount1;",
	} {
		if !strings.Contains(cs, want) {
			t.Errorf("connection string lacks %q", want)
		}
	}
}

// TestNewRejectsPortsOutOfRange covers a first port without room for the three services.
func TestNewRejectsPortsOutOfRange(t *testing.T) {
	for _, port := range []int{0, -1, 65534} {
		if _, err := New("127.0.0.1", fakeKey, port); err == nil {
			t.Errorf("New accepted port %d", port)
		}
	}
}

func TestClientsBuildFromTheConnectionString(t *testing.T) {
	a, err := New("127.0.0.1", fakeKey, ContainerPort)
	if err != nil {
		t.Fatal(err)
	}
	c, err := a.Clients(nil)
	if err != nil {
		t.Fatal(err)
	}
	if c.Blob == nil || c.Queue == nil || c.Table == nil {
		t.Fatal("a client is nil")
	}
	if got := c.Blob.URL(); !strings.HasPrefix(got, "http://127.0.0.1:10000/devstoreaccount1") {
		t.Errorf("blob URL = %q", got)
	}
}

func TestLookupKeyPrefersTheEnvironment(t *testing.T) {
	t.Setenv(KeyEnv, fakeKey)
	got, err := LookupKey("")
	if err != nil || got != fakeKey {
		t.Fatalf("LookupKey() = %q, %v", got, err)
	}
}

func TestLookupKeyReadsTheEnvFile(t *testing.T) {
	t.Setenv(KeyEnv, "")
	file := filepath.Join(t.TempDir(), "azurite-console.env")
	if err := os.WriteFile(file, []byte("# local\nOTHER=1\n"+KeyEnv+"=\""+fakeKey+"\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := LookupKey(file)
	if err != nil || got != fakeKey {
		t.Fatalf("LookupKey() = %q, %v", got, err)
	}
}

func TestLookupKeyNeverSearchesTheFolders(t *testing.T) {
	t.Setenv(KeyEnv, "")
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, ".env"), []byte(KeyEnv+"="+fakeKey+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	child := filepath.Join(root, "tools", "azurite-console")
	if err := os.MkdirAll(child, 0o750); err != nil {
		t.Fatal(err)
	}
	t.Chdir(child)
	if got, err := LookupKey(""); err == nil || got != "" {
		t.Fatalf("LookupKey(\"\") = %q, %v; want an error and no key", got, err)
	}
}

func TestLookupKeyRefusesAMissingOrEmptyFile(t *testing.T) {
	t.Setenv(KeyEnv, "")
	dir := t.TempDir()
	if _, err := LookupKey(filepath.Join(dir, "missing.env")); err == nil || !strings.Contains(err.Error(), "/local-env") {
		t.Fatalf("missing file: err = %v", err)
	}
	empty := filepath.Join(dir, "empty.env")
	if err := os.WriteFile(empty, []byte(KeyEnv+"=\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LookupKey(empty); err == nil {
		t.Fatal("empty key: want an error")
	}
}
