// Package httpjson writes the JSON answers of the console: plain values and
// failures as problem documents (RFC 9457) with a stable code, a title in the
// language of the request and, for validation failures, the invalid fields.
package httpjson

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
)

// Codes of the failures this package knows; each is the catalog key of its title.
const (
	CodeBadRequest       = "bad_request"
	CodeValidation       = "validation_failed"
	CodeNotFound         = "not_found"
	CodeMethodNotAllowed = "method_not_allowed"
	CodePayloadTooLarge  = "payload_too_large"
	CodeInternal         = "internal"
)

// Codes of an invalid field.
const (
	FieldRequired = "required"
	FieldInvalid  = "invalid"
)

const (
	contentTypeJSON    = "application/json"
	contentTypeProblem = "application/problem+json"
	// statusClientClosed marks a request whose client left before the answer.
	statusClientClosed = 499
)

// FieldError is one invalid field of a validation failure.
type FieldError struct {
	Field string `json:"field"`
	Code  string `json:"code"`
}

// Field returns the error of the field name, with a code such as FieldRequired.
func Field(name, code string) FieldError {
	return FieldError{Field: name, Code: code}
}

// Problem is a failure to answer as a problem document. It is an error, so
// it travels through the call stack up to WriteError.
type Problem struct {
	Status int
	Code   string
	Errors []FieldError

	detailKey  string
	detailArgs []any
	cause      error
}

// New returns the problem with status and code.
func New(status int, code string) *Problem {
	return &Problem{Status: status, Code: code}
}

// Validation returns the 400 problem of the invalid fields.
func Validation(fields ...FieldError) *Problem {
	return &Problem{Status: http.StatusBadRequest, Code: CodeValidation, Errors: fields}
}

// Wrap keeps err as the cause of p, for errors.Is and errors.As. The cause
// never reaches the client.
func (p *Problem) Wrap(err error) *Problem {
	p.cause = err
	return p
}

// WithDetail sets the detail of p: the catalog key and the arguments of its text.
func (p *Problem) WithDetail(key string, args ...any) *Problem {
	p.detailKey, p.detailArgs = key, args
	return p
}

// Error describes p with its code and cause.
func (p *Problem) Error() string {
	if p.cause == nil {
		return p.Code
	}
	return p.Code + ": " + p.cause.Error()
}

// Unwrap returns the cause of p.
func (p *Problem) Unwrap() error { return p.cause }

// document is the JSON form of a problem, which the page reads.
type document struct {
	Status int          `json:"status"`
	Code   string       `json:"code"`
	Title  string       `json:"title"`
	Detail string       `json:"detail,omitempty"`
	Errors []FieldError `json:"errors,omitempty"`
}

// WriteJSON answers v with status. A 204 has no body.
func WriteJSON(w http.ResponseWriter, r *http.Request, status int, v any) {
	if status == http.StatusNoContent {
		w.WriteHeader(status)
		return
	}
	write(w, r, status, contentTypeJSON, v)
}

// WriteError answers err as a problem document. An error that is not a
// Problem is a 500 that reveals nothing; a canceled request gets no body,
// since its client already left. Failures of the server are logged with the
// route and the type of the cause, never with names of the stored data.
func WriteError(w http.ResponseWriter, r *http.Request, err error) {
	p, ok := errors.AsType[*Problem](err)
	switch {
	case ok:
	case errors.Is(err, context.Canceled):
		w.WriteHeader(statusClientClosed)
		return
	default:
		p = New(http.StatusInternalServerError, CodeInternal).Wrap(err)
	}
	if p.Status >= http.StatusInternalServerError {
		slog.ErrorContext(r.Context(), "request failed", slog.String("route", r.Pattern), slog.Int("status", p.Status),
			slog.String("code", p.Code), slog.String("error_type", fmt.Sprintf("%T", p.cause)))
	}
	doc := document{Status: p.Status, Code: p.Code, Title: Message(r, p.Code), Errors: p.Errors}
	if p.detailKey != "" {
		doc.Detail = Message(r, p.detailKey, p.detailArgs...)
	}
	write(w, r, p.Status, contentTypeProblem, doc)
}

// MethodNotAllowed returns the handler of a path that does not accept the
// method of the request: a 405 problem that lists the allowed methods.
func MethodNotAllowed(allowed ...string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", strings.Join(allowed, ", "))
		WriteError(w, r, New(http.StatusMethodNotAllowed, CodeMethodNotAllowed))
	})
}

// write answers v as JSON. v is encoded first, so a value that cannot be
// encoded still becomes a clean 500 instead of a truncated answer.
func write(w http.ResponseWriter, r *http.Request, status int, contentType string, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		WriteError(w, r, New(http.StatusInternalServerError, CodeInternal).Wrap(err))
		return
	}
	w.Header().Set("Content-Type", contentType)
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		slog.DebugContext(r.Context(), "answer not delivered", slog.String("route", r.Pattern))
	}
}
