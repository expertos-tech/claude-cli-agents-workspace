package storage

import (
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blockblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
)

// listPage is the number of blobs asked per page when browsing a folder.
const listPage = 500

// Blobs operates the Blob service.
type Blobs struct {
	client *azblob.Client
}

// NewBlobs returns the operations over client.
func NewBlobs(client *azblob.Client) *Blobs { return &Blobs{client: client} }

// Container is one container of the account.
type Container struct {
	Name         string     `json:"name"`
	LastModified *time.Time `json:"last_modified,omitempty"`
}

// Blob is one blob in a listing.
type Blob struct {
	Name         string     `json:"name"`
	Size         int64      `json:"size"`
	ContentType  string     `json:"content_type,omitempty"`
	LastModified *time.Time `json:"last_modified,omitempty"`
	ETag         string     `json:"etag,omitempty"`
}

// Listing is one page of a folder: the subfolders (prefixes ending in "/")
// and the blobs directly in it.
type Listing struct {
	Prefixes   []string `json:"prefixes"`
	Blobs      []Blob   `json:"blobs"`
	NextMarker string   `json:"next_marker,omitempty"`
}

// Properties are the properties of one blob.
type Properties struct {
	Blob
	MD5      string            `json:"md5,omitempty"`
	Created  *time.Time        `json:"created,omitempty"`
	BlobType string            `json:"blob_type,omitempty"`
	Metadata map[string]string `json:"metadata,omitempty"`
}

// Usage counts the blobs under a prefix. Truncated means the count stopped
// at the limit.
type Usage struct {
	Count     int   `json:"count"`
	Bytes     int64 `json:"bytes"`
	Truncated bool  `json:"truncated"`
}

// Content is an open blob.
type Content struct {
	Body        io.ReadCloser
	ContentType string
	Size        int64
	// Total is the size of the whole blob, larger than Size when a range was read.
	Total int64
}

// Ping lists one container, to know whether the service answers.
func (b *Blobs) Ping(ctx context.Context) error {
	_, err := b.client.NewListContainersPager(&azblob.ListContainersOptions{MaxResults: to.Ptr(int32(1))}).NextPage(ctx)
	return err
}

// Containers lists every container.
func (b *Blobs) Containers(ctx context.Context) ([]Container, error) {
	out := []Container{}
	pager := b.client.NewListContainersPager(nil)
	for pager.More() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		for _, c := range page.ContainerItems {
			item := Container{Name: deref(c.Name)}
			if c.Properties != nil {
				item.LastModified = c.Properties.LastModified
			}
			out = append(out, item)
		}
	}
	return out, nil
}

// CreateContainer creates container name.
func (b *Blobs) CreateContainer(ctx context.Context, name string) error {
	_, err := b.client.CreateContainer(ctx, name, nil)
	return err
}

// DeleteContainer deletes container name and everything in it.
func (b *Blobs) DeleteContainer(ctx context.Context, name string) error {
	_, err := b.client.DeleteContainer(ctx, name, nil)
	return err
}

// List returns one page of the folder prefix of container name, from marker.
func (b *Blobs) List(ctx context.Context, name, prefix, marker string) (Listing, error) {
	opts := &container.ListBlobsHierarchyOptions{MaxResults: to.Ptr(int32(listPage))}
	if prefix != "" {
		opts.Prefix = &prefix
	}
	if marker != "" {
		opts.Marker = &marker
	}
	page, err := b.container(name).NewListBlobsHierarchyPager("/", opts).NextPage(ctx)
	if err != nil {
		return Listing{}, err
	}
	out := Listing{Prefixes: []string{}, Blobs: []Blob{}, NextMarker: deref(page.NextMarker)}
	if page.Segment == nil {
		return out, nil
	}
	for _, p := range page.Segment.BlobPrefixes {
		out.Prefixes = append(out.Prefixes, deref(p.Name))
	}
	for _, item := range page.Segment.BlobItems {
		out.Blobs = append(out.Blobs, blobOf(item))
	}
	return out, nil
}

// Usage counts the blobs of container name under prefix, stopping at limit.
func (b *Blobs) Usage(ctx context.Context, name, prefix string, limit int) (Usage, error) {
	var u Usage
	err := b.walk(ctx, name, prefix, func(item Blob) bool {
		if u.Count >= limit {
			u.Truncated = true
			return false
		}
		u.Count++
		u.Bytes += item.Size
		return true
	})
	return u, err
}

// Properties returns the properties of blob path in container name.
func (b *Blobs) Properties(ctx context.Context, name, path string) (Properties, error) {
	p, err := b.container(name).NewBlobClient(path).GetProperties(ctx, nil)
	if err != nil {
		return Properties{}, err
	}
	out := Properties{
		Blob: Blob{
			Name:         path,
			Size:         deref(p.ContentLength),
			ContentType:  deref(p.ContentType),
			LastModified: p.LastModified,
		},
		Created:  p.CreationTime,
		Metadata: map[string]string{},
	}
	if p.ETag != nil {
		out.ETag = string(*p.ETag)
	}
	if len(p.ContentMD5) > 0 {
		out.MD5 = base64.StdEncoding.EncodeToString(p.ContentMD5)
	}
	if p.BlobType != nil {
		out.BlobType = string(*p.BlobType)
	}
	for k, v := range p.Metadata {
		out.Metadata[k] = deref(v)
	}
	return out, nil
}

// Open opens blob path of container name. A positive limit reads only its
// first limit bytes.
func (b *Blobs) Open(ctx context.Context, name, path string, limit int64) (Content, error) {
	opts := &blob.DownloadStreamOptions{}
	if limit > 0 {
		opts.Range = blob.HTTPRange{Offset: 0, Count: limit}
	}
	resp, err := b.container(name).NewBlobClient(path).DownloadStream(ctx, opts)
	if err != nil {
		return Content{}, err
	}
	size := deref(resp.ContentLength)
	total := size
	if resp.ContentRange != nil {
		var start, end int64
		if _, err := fmt.Sscanf(*resp.ContentRange, "bytes %d-%d/%d", &start, &end, &total); err != nil {
			total = size
		}
	}
	return Content{Body: resp.Body, ContentType: deref(resp.ContentType), Size: size, Total: total}, nil
}

// Upload writes body as blob path of container name, replacing it.
func (b *Blobs) Upload(ctx context.Context, name, path, contentType string, body io.Reader) error {
	opts := &blockblob.UploadStreamOptions{}
	if contentType != "" {
		opts.HTTPHeaders = &blob.HTTPHeaders{BlobContentType: &contentType}
	}
	_, err := b.container(name).NewBlockBlobClient(path).UploadStream(ctx, body, opts)
	return err
}

// DeleteBlob deletes blob path of container name with its snapshots.
func (b *Blobs) DeleteBlob(ctx context.Context, name, path string) error {
	_, err := b.container(name).NewBlobClient(path).Delete(ctx, &blob.DeleteOptions{DeleteSnapshots: to.Ptr(blob.DeleteSnapshotsOptionTypeInclude)})
	return err
}

// DeletePrefix deletes every blob of container name under prefix (the whole
// container when prefix is empty) and returns what was deleted. It stops at
// the first failure, reporting what was deleted before it.
func (b *Blobs) DeletePrefix(ctx context.Context, name, prefix string) (Usage, error) {
	var items []Blob
	if err := b.walk(ctx, name, prefix, func(item Blob) bool {
		items = append(items, item)
		return true
	}); err != nil {
		return Usage{}, err
	}
	var u Usage
	for _, item := range items {
		if err := b.DeleteBlob(ctx, name, item.Name); err != nil {
			return u, err
		}
		u.Count++
		u.Bytes += item.Size
	}
	return u, nil
}

// walk calls fn for every blob of container name under prefix until fn
// returns false.
func (b *Blobs) walk(ctx context.Context, name, prefix string, fn func(Blob) bool) error {
	opts := &container.ListBlobsFlatOptions{}
	if prefix != "" {
		opts.Prefix = &prefix
	}
	pager := b.container(name).NewListBlobsFlatPager(opts)
	for pager.More() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return err
		}
		if page.Segment == nil {
			continue
		}
		for _, item := range page.Segment.BlobItems {
			if !fn(blobOf(item)) {
				return nil
			}
		}
	}
	return nil
}

// container returns the client of the container name.
func (b *Blobs) container(name string) *container.Client {
	return b.client.ServiceClient().NewContainerClient(name)
}

// blobOf converts a listed item to the type of this package.
func blobOf(item *container.BlobItem) Blob {
	out := Blob{Name: deref(item.Name)}
	if p := item.Properties; p != nil {
		out.Size = deref(p.ContentLength)
		out.ContentType = deref(p.ContentType)
		out.LastModified = p.LastModified
		if p.ETag != nil {
			out.ETag = string(*p.ETag)
		}
	}
	return out
}
