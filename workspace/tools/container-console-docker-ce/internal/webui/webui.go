// Package webui serves the front-end embedded in the binary. Vite writes the build
// to dist/; the tracked placeholder.html keeps the embed valid before the first build.
package webui

import (
	"embed"
	"io/fs"
	"net/http"
	"strings"
)

//go:embed all:dist
var distFiles embed.FS

const (
	indexFile       = "index.html"
	placeholderFile = "placeholder.html"
)

// Handler returns the handler of the static files, or of the placeholder page
// while the binary was built without a front-end.
func Handler() (http.Handler, error) {
	dist, err := fs.Sub(distFiles, "dist")
	if err != nil {
		return nil, err
	}
	if _, err := fs.Stat(dist, indexFile); err != nil {
		return placeholderHandler(dist), nil
	}
	return withCachePolicy(http.FileServerFS(dist)), nil
}

// placeholderHandler serves the placeholder page at the root and 404 elsewhere.
func placeholderHandler(dist fs.FS) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeFileFS(w, r, dist, placeholderFile)
	})
}

// withCachePolicy keeps hashed assets for long and always revalidates the rest,
// so a new binary shows the new front-end at once.
func withCachePolicy(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/assets/") {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			w.Header().Set("Cache-Control", "no-cache")
		}
		next.ServeHTTP(w, r)
	})
}
