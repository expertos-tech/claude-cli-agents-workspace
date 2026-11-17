package api

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"azurite-console/internal/httpjson"
)

// noBuild is the page served when web/dist has not been built.
const noBuild = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>azurite-console</title></head>
<body style="font-family: system-ui, sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem">
<h1>azurite-console</h1>
<p>The API is up, but the page has not been built yet. From the workspace root:</p>
<pre>npm --prefix tools/azurite-console/web install
npm --prefix tools/azurite-console/web run build</pre>
<p>Then reload this page.</p>
</body></html>
`

// static serves the built page from WebDir, for GET and HEAD. An unknown
// /api/ path is a 404 problem, never the page.
func (h *Handler) static(w http.ResponseWriter, r *http.Request) {
	if strings.HasPrefix(r.URL.Path, "/api/") {
		httpjson.WriteError(w, r, httpjson.New(http.StatusNotFound, httpjson.CodeNotFound))
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		httpjson.MethodNotAllowed(http.MethodGet, http.MethodHead).ServeHTTP(w, r)
		return
	}
	if r.URL.Path == "/" || r.URL.Path == "/index.html" {
		if _, err := os.Stat(filepath.Join(h.cfg.WebDir, "index.html")); err != nil {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Cache-Control", "no-store")
			_, _ = w.Write([]byte(noBuild))
			return
		}
		// The file names of the assets change with each build; the page does not.
		w.Header().Set("Cache-Control", "no-store")
	}
	http.FileServer(http.Dir(h.cfg.WebDir)).ServeHTTP(w, r)
}
