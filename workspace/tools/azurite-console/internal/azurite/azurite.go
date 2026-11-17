// Package azurite is the only account the console talks to: the development
// account of the local Azurite. The connection string is built here from a
// host that must be local and the account key, so no flag or variable can
// point the console at a real storage account.
package azurite

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/data/aztables"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azqueue"
)

const (
	// AccountName is the development account of Azurite.
	AccountName = "devstoreaccount1"
	// KeyEnv is the variable that holds the account key, also read from .env.
	KeyEnv = "AZURITE_ACCOUNT_KEY"

	// ContainerPort is the first port of Azurite inside its container, the
	// one the console uses inside the Compose network.
	ContainerPort = 10000
	// HostPort is the first port compose.yaml publishes on the host, the one
	// the console uses when it runs outside Compose.
	HostPort = 30000
)

// The services listen on consecutive ports: blob, queue and table.
const (
	blobOffset = iota
	queueOffset
	tableOffset
)

// maxPort is the largest port that leaves room for the three services.
const maxPort = 65535 - tableOffset

// composeHost is the name of the Azurite service inside the Compose network.
const composeHost = "azurite"

// Account is the local Azurite account. Its key is never printed.
type Account struct {
	host string
	key  string
	port int
}

// New returns the account on host with key, whose blob service listens on
// port and the queue and table services on the next two. Only a loopback
// address, localhost or the Compose service name are accepted.
func New(host, key string, port int) (Account, error) {
	if !IsLocal(host) {
		return Account{}, fmt.Errorf("azurite: host %q is not local; only loopback, localhost or %s are accepted", host, composeHost)
	}
	if strings.TrimSpace(key) == "" {
		return Account{}, errors.New("azurite: empty account key")
	}
	if port < 1 || port > maxPort {
		return Account{}, fmt.Errorf("azurite: port %d out of the range 1 to %d", port, maxPort)
	}
	return Account{host: host, key: key, port: port}, nil
}

// IsLocal reports whether host is a loopback address, localhost or the
// Compose service name of Azurite.
func IsLocal(host string) bool {
	switch host {
	case "localhost", composeHost:
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// Host is the host of the endpoints.
func (a Account) Host() string { return a.host }

// endpoint is the base URL of the service at offset from the first port.
func (a Account) endpoint(offset int) string {
	return fmt.Sprintf("http://%s/%s", net.JoinHostPort(a.host, fmt.Sprint(a.port+offset)), AccountName)
}

// ConnectionString is the connection string of the three services.
func (a Account) ConnectionString() string {
	return fmt.Sprintf("DefaultEndpointsProtocol=http;AccountName=%s;AccountKey=%s;BlobEndpoint=%s;QueueEndpoint=%s;TableEndpoint=%s;",
		AccountName, a.key, a.endpoint(blobOffset), a.endpoint(queueOffset), a.endpoint(tableOffset))
}

// Clients are the SDK clients of the three services.
type Clients struct {
	Blob  *azblob.Client
	Queue *azqueue.ServiceClient
	Table *aztables.ServiceClient
}

// Clients returns the three clients over transport. The SDK retries are
// off: the console answers at once when Azurite is down. A nil transport
// means the SDK default.
func (a Account) Clients(transport *http.Client) (Clients, error) {
	opts := azcore.ClientOptions{Retry: policy.RetryOptions{MaxRetries: -1}}
	if transport != nil {
		opts.Transport = transport
	}
	conn := a.ConnectionString()
	b, err := azblob.NewClientFromConnectionString(conn, &azblob.ClientOptions{ClientOptions: opts})
	if err != nil {
		return Clients{}, fmt.Errorf("azurite: blob client: %w", err)
	}
	q, err := azqueue.NewServiceClientFromConnectionString(conn, &azqueue.ClientOptions{ClientOptions: opts})
	if err != nil {
		return Clients{}, fmt.Errorf("azurite: queue client: %w", err)
	}
	t, err := aztables.NewServiceClientFromConnectionString(conn, &aztables.ClientOptions{ClientOptions: opts})
	if err != nil {
		return Clients{}, fmt.Errorf("azurite: table client: %w", err)
	}
	return Clients{Blob: b, Queue: q, Table: t}, nil
}
