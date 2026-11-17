package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"container-console-docker-ce/internal/fault"
	"container-console-docker-ce/internal/jobs"
)

var errJobNotFound = fault.NotFound("job_not_found", "unknown job")

// errorPayload is the single error shape of the REST API.
type errorPayload struct {
	Code     string         `json:"code"`
	Message  string         `json:"message"`
	ExitCode *int           `json:"exitCode,omitempty"`
	Params   map[string]any `json:"params,omitempty"`
}

// writeJSON writes a JSON response that is never cached.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// writeForbidden answers any refused security check the same way: the reason only goes to the log.
func writeForbidden(w http.ResponseWriter) {
	writeJSON(w, http.StatusForbidden, map[string]errorPayload{
		"error": {Code: "forbidden", Message: "forbidden"},
	})
}

// writeError maps an error to its status and writes the error shape.
func (s *Server) writeError(w http.ResponseWriter, r *http.Request, err error) {
	status, payload := describeError(err)
	if status >= http.StatusInternalServerError {
		s.Logger.Warn("request failed", "route", r.Pattern, "code", payload.Code)
	}
	writeJSON(w, status, map[string]errorPayload{"error": payload})
}

// describeError decides the status and payload of an error.
func describeError(err error) (int, errorPayload) {
	var domainErr *fault.Error
	if errors.As(err, &domainErr) {
		return statusOf(domainErr.Kind), errorPayload{Code: domainErr.Code, Message: domainErr.Message, Params: domainErr.Params}
	}
	var tooLarge *http.MaxBytesError
	if errors.As(err, &tooLarge) {
		return http.StatusRequestEntityTooLarge, errorPayload{Code: "body_too_large", Message: "the request body is too large"}
	}
	failure := jobs.DescribeFailure(err)
	return http.StatusBadGateway, errorPayload{Code: failure.Code, Message: failure.Message, ExitCode: failure.ExitCode}
}

// statusOf maps a domain error kind to its HTTP status.
func statusOf(kind fault.Kind) int {
	switch kind {
	case fault.KindConflict:
		return http.StatusConflict
	case fault.KindNotFound:
		return http.StatusNotFound
	}
	return http.StatusUnprocessableEntity
}

// notFoundRoute answers unknown API paths in the error shape.
func notFoundRoute(_ http.ResponseWriter, _ *http.Request) error {
	return fault.NotFound("route_not_found", "unknown route")
}

// decodeBody reads a JSON body and rejects unknown fields and trailing data.
// An empty body decodes as the zero value, so a missing `confirm` is simply false.
func decodeBody(r *http.Request, target any) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		if errors.Is(err, io.EOF) {
			return nil
		}
		return asBodyError(err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return invalidBody()
	}
	return nil
}

// asBodyError keeps the size error and turns anything else into an invalid body.
func asBodyError(err error) error {
	var tooLarge *http.MaxBytesError
	if errors.As(err, &tooLarge) {
		return err
	}
	return invalidBody()
}

// invalidBody builds the error of a malformed or unexpected body.
func invalidBody() error {
	return fault.Invalid("invalid_body", "the request body is not valid for this route")
}

// confirmBody is the body of the routes that require explicit confirmation.
type confirmBody struct {
	Confirm bool `json:"confirm"`
}

// requireConfirm enforces explicit confirmation on the server: without `"confirm": true` nothing happens,
// so a defect in the screen cannot remove anything.
func requireConfirm(confirm bool) error {
	if !confirm {
		return fault.Invalid("confirmation_required", "this action requires explicit confirmation")
	}
	return nil
}

// submit starts a job and answers 202 with its record.
func (s *Server) submit(w http.ResponseWriter, spec jobs.Spec, fn jobs.Func) error {
	job, err := s.Jobs.Submit(spec, fn)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusAccepted, map[string]any{"job": job})
	return nil
}
