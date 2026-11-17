package httpapi

import (
	"log/slog"
	"mime"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
)

// contentSecurityPolicy allows only what the front-end serves itself. style-src keeps
// 'unsafe-inline' because of the xterm styles. The two ws:// sources are the exact origins
// of the service, for the browsers that do not match WebSocket URLs with 'self'.
func contentSecurityPolicy(port int) string {
	text := strconv.Itoa(port)
	return strings.Join([]string{
		"default-src 'self'",
		"script-src 'self'",
		"style-src 'self' 'unsafe-inline'",
		"connect-src 'self' ws://127.0.0.1:" + text + " ws://localhost:" + text,
		"frame-ancestors 'none'",
		"base-uri 'none'",
		"form-action 'none'",
	}, "; ")
}

// guard wraps the routes with the browser defenses, in the order they must apply. A page
// on the attacker's site reaches this port through the user's browser: the service has no
// login, so these checks are what stop DNS rebinding and cross-site requests.
func (s *Server) guard(next http.Handler) http.Handler {
	protection := http.NewCrossOriginProtection()
	protection.SetDenyHandler(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		s.Logger.Warn("request denied", "reason", "cross_origin")
		writeForbidden(w)
	}))
	limited := s.limitBody(next)
	protected := protection.Handler(s.requireJSONContentType(limited))
	return s.logRequests(s.setSecurityHeaders(s.requireAllowedHost(protected)))
}

// requireAllowedHost refuses any Host outside the exact allowlist, which stops DNS rebinding.
func (s *Server) requireAllowedHost(next http.Handler) http.Handler {
	allowed := s.Config.AllowedHosts()
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !slices.Contains(allowed, r.Host) {
			s.Logger.Warn("request denied", "reason", "host")
			writeForbidden(w)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// setSecurityHeaders adds the response headers of every route.
func (s *Server) setSecurityHeaders(next http.Handler) http.Handler {
	policy := contentSecurityPolicy(s.Config.Port)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := w.Header()
		header.Set("Content-Security-Policy", policy)
		header.Set("X-Content-Type-Options", "nosniff")
		header.Set("Referrer-Policy", "no-referrer")
		header.Set("Cross-Origin-Resource-Policy", "same-origin")
		next.ServeHTTP(w, r)
	})
}

// requireJSONContentType accepts a state-changing method only as application/json,
// a type that a cross-site HTML form cannot send.
func (s *Server) requireJSONContentType(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isSafeMethod(r.Method) {
			next.ServeHTTP(w, r)
			return
		}
		mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if err != nil || mediaType != "application/json" {
			s.Logger.Warn("request denied", "reason", "content_type")
			writeForbidden(w)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// limitBody bounds the size of every request body.
func (s *Server) limitBody(next http.Handler) http.Handler {
	limit := s.Config.Limits.MaxBodyBytes
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, limit)
		next.ServeHTTP(w, r)
	})
}

// requireAllowedOrigin protects a WebSocket route. CrossOriginProtection lets GET through,
// so the Origin must be present and exactly one of the origins of the service, before the upgrade.
func (s *Server) requireAllowedOrigin(next http.HandlerFunc) http.HandlerFunc {
	allowed := s.Config.AllowedOrigins()
	return func(w http.ResponseWriter, r *http.Request) {
		if !slices.Contains(allowed, r.Header.Get("Origin")) {
			s.Logger.Warn("request denied", "reason", "origin")
			writeForbidden(w)
			return
		}
		next(w, r)
	}
}

// isSafeMethod tells the methods that never change state in this API.
func isSafeMethod(method string) bool {
	return method == http.MethodGet || method == http.MethodHead || method == http.MethodOptions
}

// logRequests records the route pattern, never the URL: paths may hold user data.
func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		started := time.Now()
		next.ServeHTTP(recorder, r)
		s.Logger.LogAttrs(r.Context(), slog.LevelInfo, "request",
			slog.String("method", r.Method),
			slog.String("route", r.Pattern),
			slog.Int("status", recorder.status),
			slog.Int64("durationMs", time.Since(started).Milliseconds()))
	})
}

// statusRecorder keeps the status for the log. Unwrap lets the WebSocket upgrade reach the Hijacker.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

// WriteHeader records the status and forwards it.
func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

// Unwrap returns the original writer, for http.ResponseController and the WebSocket library.
func (r *statusRecorder) Unwrap() http.ResponseWriter {
	return r.ResponseWriter
}
