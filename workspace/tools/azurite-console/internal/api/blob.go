package api

import (
	"io"
	"math"
	"mime"
	"net/http"
	"strconv"

	"azurite-console/internal/httpjson"
)

// maxPreview bounds the bytes read for the preview of a blob.
const maxPreview = 1 << 30

// inlineTypes are the content types served as they are for the preview;
// any other blob is served as text, so a stored HTML or SVG never runs as a
// page of the console.
var inlineTypes = map[string]bool{
	"application/pdf":  true,
	"application/json": true,
	"text/plain":       true,
	"text/csv":         true,
	"image/png":        true,
	"image/jpeg":       true,
	"image/gif":        true,
	"image/webp":       true,
}

// containers lists the containers.
func (h *Handler) containers(w http.ResponseWriter, r *http.Request) {
	out, err := h.cfg.Blobs.Containers(r.Context())
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

// createContainer creates the container named in the body.
func (h *Handler) createContainer(w http.ResponseWriter, r *http.Request) {
	var in named
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if err := in.validate(); err != nil {
		fail(w, r, err)
		return
	}
	if err := h.cfg.Blobs.CreateContainer(r.Context(), in.Name); err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusCreated, in)
}

// deleteContainer deletes the container.
func (h *Handler) deleteContainer(w http.ResponseWriter, r *http.Request) {
	if err := h.cfg.Blobs.DeleteContainer(r.Context(), r.PathValue("c")); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}

// emptyContainer deletes every blob of the container and answers what was removed.
func (h *Handler) emptyContainer(w http.ResponseWriter, r *http.Request) {
	u, err := h.cfg.Blobs.DeletePrefix(r.Context(), r.PathValue("c"), "")
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, u)
}

// list answers one level of the container under the prefix.
func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	out, err := h.cfg.Blobs.List(r.Context(), r.PathValue("c"), q.Get("prefix"), q.Get("marker"))
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

// usage counts what a delete of the prefix would remove, without a limit.
func (h *Handler) usage(w http.ResponseWriter, r *http.Request) {
	u, err := h.cfg.Blobs.Usage(r.Context(), r.PathValue("c"), r.URL.Query().Get("prefix"), math.MaxInt)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, u)
}

// deletePrefix deletes a folder. The prefix is required: emptying the whole
// container is its own action.
func (h *Handler) deletePrefix(w http.ResponseWriter, r *http.Request) {
	prefix := r.URL.Query().Get("prefix")
	if prefix == "" {
		fail(w, r, badRequest("prefix", httpjson.FieldRequired))
		return
	}
	u, err := h.cfg.Blobs.DeletePrefix(r.Context(), r.PathValue("c"), prefix)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, u)
}

// blob answers the properties (?props), the file to save (?download) or the
// content for the preview, the first max bytes when ?max is given.
func (h *Handler) blob(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	name, path := r.PathValue("c"), r.PathValue("path")
	q := r.URL.Query()
	if q.Has("props") {
		p, err := h.cfg.Blobs.Properties(ctx, name, path)
		if err != nil {
			fail(w, r, err)
			return
		}
		httpjson.WriteJSON(w, r, http.StatusOK, p)
		return
	}
	limit, err := intQuery(r, "max", 0, 1, maxPreview)
	if err != nil {
		fail(w, r, err)
		return
	}
	c, err := h.cfg.Blobs.Open(ctx, name, path, int64(limit))
	if err != nil {
		fail(w, r, err)
		return
	}
	defer c.Body.Close()
	hdr := w.Header()
	hdr.Set("X-Content-Type-Options", "nosniff")
	hdr.Set("Cache-Control", "no-store")
	hdr.Set("X-Blob-Size", strconv.FormatInt(c.Total, 10))
	hdr.Set("X-Blob-Content-Type", c.ContentType)
	hdr.Set("Content-Length", strconv.FormatInt(c.Size, 10))
	if q.Has("download") {
		hdr.Set("Content-Type", "application/octet-stream")
		hdr.Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": baseName(path)}))
	} else {
		hdr.Set("Content-Type", inlineType(c.ContentType))
	}
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, c.Body)
}

// inlineType is the content type of a preview: the type of the blob when it
// is safe to show, text otherwise.
func inlineType(contentType string) string {
	mt, _, err := mime.ParseMediaType(contentType)
	if err == nil && inlineTypes[mt] {
		return contentType
	}
	return "text/plain; charset=utf-8"
}

// baseName is the last segment of a blob path.
func baseName(path string) string {
	for i := len(path) - 1; i >= 0; i-- {
		if path[i] == '/' {
			return path[i+1:]
		}
	}
	return path
}

// upload writes the request body as the blob, with the content type of the request.
func (h *Handler) upload(w http.ResponseWriter, r *http.Request) {
	path := r.PathValue("path")
	if path == "" {
		fail(w, r, badRequest("path", httpjson.FieldRequired))
		return
	}
	if err := h.cfg.Blobs.Upload(r.Context(), r.PathValue("c"), path, r.Header.Get("Content-Type"), r.Body); err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusCreated, map[string]string{"name": path})
}

// deleteBlob deletes one blob.
func (h *Handler) deleteBlob(w http.ResponseWriter, r *http.Request) {
	if err := h.cfg.Blobs.DeleteBlob(r.Context(), r.PathValue("c"), r.PathValue("path")); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}
