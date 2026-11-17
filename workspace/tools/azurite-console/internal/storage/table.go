package storage

import (
	"context"
	"encoding/json"
	"errors"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/data/aztables"
)

// countPage is the page size used to count entities.
const countPage = 1000

// ErrEntityInvalid is an entity that is not a JSON object with string
// PartitionKey and RowKey.
var ErrEntityInvalid = errors.New("entity must be a JSON object with string PartitionKey and RowKey")

// Tables operates the Table service.
type Tables struct {
	client *aztables.ServiceClient
}

// NewTables returns the operations over client.
func NewTables(client *aztables.ServiceClient) *Tables { return &Tables{client: client} }

// Table is one table.
type Table struct {
	Name string `json:"name"`
}

// Count counts entities. Truncated means the count stopped at the limit.
type Count struct {
	Count     int  `json:"count"`
	Truncated bool `json:"truncated"`
}

// EntityPage is one page of a query. Each entity is the JSON of the service,
// with odata.etag and the @odata.type annotations of typed properties.
type EntityPage struct {
	Entities         []json.RawMessage `json:"entities"`
	NextPartitionKey string            `json:"next_partition_key,omitempty"`
	NextRowKey       string            `json:"next_row_key,omitempty"`
}

// Entity is one entity with its ETag.
type Entity struct {
	Value json.RawMessage `json:"value"`
	ETag  string          `json:"etag"`
}

// Query is a filter and a page of a table.
type Query struct {
	// Filter is an OData $filter; empty means every entity.
	Filter string
	// Top is the page size; zero means the default of the service.
	Top int32
	// NextPartitionKey and NextRowKey continue a previous page.
	NextPartitionKey, NextRowKey string
}

// Ping lists one table, to know whether the service answers.
func (t *Tables) Ping(ctx context.Context) error {
	_, err := t.client.NewListTablesPager(&aztables.ListTablesOptions{Top: to.Ptr(int32(1))}).NextPage(ctx)
	return err
}

// List lists every table.
func (t *Tables) List(ctx context.Context) ([]Table, error) {
	out := []Table{}
	pager := t.client.NewListTablesPager(nil)
	for pager.More() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		for _, item := range page.Tables {
			out = append(out, Table{Name: deref(item.Name)})
		}
	}
	return out, nil
}

// Create creates table name.
func (t *Tables) Create(ctx context.Context, name string) error {
	_, err := t.client.CreateTable(ctx, name, nil)
	return err
}

// Delete deletes table name and its entities.
func (t *Tables) Delete(ctx context.Context, name string) error {
	_, err := t.client.DeleteTable(ctx, name, nil)
	return err
}

// Count counts the entities of table name that match filter, stopping at limit.
func (t *Tables) Count(ctx context.Context, name, filter string, limit int) (Count, error) {
	var c Count
	err := t.walk(ctx, name, filter, func(json.RawMessage) bool {
		if c.Count >= limit {
			c.Truncated = true
			return false
		}
		c.Count++
		return true
	})
	return c, err
}

// Query returns one page of table name.
func (t *Tables) Query(ctx context.Context, name string, q Query) (EntityPage, error) {
	opts := &aztables.ListEntitiesOptions{}
	if q.Filter != "" {
		opts.Filter = &q.Filter
	}
	if q.Top > 0 {
		opts.Top = &q.Top
	}
	if q.NextPartitionKey != "" {
		opts.NextPartitionKey = &q.NextPartitionKey
		opts.NextRowKey = &q.NextRowKey
	}
	page, err := t.client.NewClient(name).NewListEntitiesPager(opts).NextPage(ctx)
	if err != nil {
		return EntityPage{}, err
	}
	out := EntityPage{Entities: make([]json.RawMessage, 0, len(page.Entities)),
		NextPartitionKey: deref(page.NextPartitionKey), NextRowKey: deref(page.NextRowKey)}
	for _, e := range page.Entities {
		out.Entities = append(out.Entities, e)
	}
	return out, nil
}

// Get returns the entity of table name with the keys pk and rk.
func (t *Tables) Get(ctx context.Context, name, pk, rk string) (Entity, error) {
	resp, err := t.client.NewClient(name).GetEntity(ctx, pk, rk, nil)
	if err != nil {
		return Entity{}, err
	}
	return Entity{Value: resp.Value, ETag: string(resp.ETag)}, nil
}

// Insert adds entity to table name and returns its ETag. The entity must
// not exist.
func (t *Tables) Insert(ctx context.Context, name string, entity json.RawMessage) (string, error) {
	body, err := writable(entity)
	if err != nil {
		return "", err
	}
	resp, err := t.client.NewClient(name).AddEntity(ctx, body, nil)
	if err != nil {
		return "", err
	}
	return string(resp.ETag), nil
}

// Update writes entity over the one in table name with the same keys, merging
// its properties or replacing them all, and returns the new ETag. An empty
// etag writes whatever the current version is.
func (t *Tables) Update(ctx context.Context, name string, entity json.RawMessage, etag string, replace bool) (string, error) {
	body, err := writable(entity)
	if err != nil {
		return "", err
	}
	opts := &aztables.UpdateEntityOptions{UpdateMode: aztables.UpdateModeMerge, IfMatch: ifMatch(etag)}
	if replace {
		opts.UpdateMode = aztables.UpdateModeReplace
	}
	resp, err := t.client.NewClient(name).UpdateEntity(ctx, body, opts)
	if err != nil {
		return "", err
	}
	return string(resp.ETag), nil
}

// DeleteEntity deletes the entity of table name with the keys pk and rk. An
// empty etag deletes whatever the current version is.
func (t *Tables) DeleteEntity(ctx context.Context, name, pk, rk, etag string) error {
	_, err := t.client.NewClient(name).DeleteEntity(ctx, pk, rk, &aztables.DeleteEntityOptions{IfMatch: ifMatch(etag)})
	return err
}

// DeleteByFilter deletes every entity of table name that matches filter
// and returns how many were deleted. It stops at the first failure,
// reporting what was deleted before it.
func (t *Tables) DeleteByFilter(ctx context.Context, name, filter string) (int, error) {
	type keys struct{ pk, rk string }
	var all []keys
	if err := t.walk(ctx, name, filter, func(e json.RawMessage) bool {
		var k struct {
			PartitionKey string `json:"PartitionKey"`
			RowKey       string `json:"RowKey"`
		}
		if json.Unmarshal(e, &k) == nil {
			all = append(all, keys{k.PartitionKey, k.RowKey})
		}
		return true
	}); err != nil {
		return 0, err
	}
	deleted := 0
	for _, k := range all {
		if err := t.DeleteEntity(ctx, name, k.pk, k.rk, ""); err != nil {
			return deleted, err
		}
		deleted++
	}
	return deleted, nil
}

// walk calls fn for the keys of every entity of table name that matches
// filter until fn returns false.
func (t *Tables) walk(ctx context.Context, name, filter string, fn func(json.RawMessage) bool) error {
	opts := &aztables.ListEntitiesOptions{Select: to.Ptr("PartitionKey,RowKey"), Top: to.Ptr(int32(countPage))}
	if filter != "" {
		opts.Filter = &filter
	}
	pager := t.client.NewClient(name).NewListEntitiesPager(opts)
	for pager.More() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return err
		}
		for _, e := range page.Entities {
			if !fn(e) {
				return nil
			}
		}
	}
	return nil
}

// writable checks entity and drops what the service manages and refuses on
// a write: the odata.* metadata and Timestamp. The @odata.type annotations
// of the properties stay.
func writable(entity json.RawMessage) ([]byte, error) {
	var m map[string]any
	if err := json.Unmarshal(entity, &m); err != nil {
		return nil, ErrEntityInvalid
	}
	for _, key := range []string{"PartitionKey", "RowKey"} {
		if _, ok := m[key].(string); !ok {
			return nil, ErrEntityInvalid
		}
	}
	for k := range m {
		if strings.HasPrefix(k, "odata.") || k == "Timestamp" || k == "Timestamp@odata.type" {
			delete(m, k)
		}
	}
	return json.Marshal(m)
}

// ifMatch is the ETag condition of a write; empty matches any version.
func ifMatch(etag string) *azcore.ETag {
	if etag == "" {
		return to.Ptr(azcore.ETagAny)
	}
	return to.Ptr(azcore.ETag(etag))
}
