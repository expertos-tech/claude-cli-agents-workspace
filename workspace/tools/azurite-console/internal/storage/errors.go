// Package storage is what the console does with the three services of the
// local Azurite: containers and blobs, queues and messages, tables and
// entities. It returns its own types, ready for JSON, and leaves the
// mapping of errors to HTTP to the api package through Classify.
package storage

import (
	"errors"
	"net/http"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
)

// Kind is the class of a failure, as the page needs it.
type Kind int

const (
	// KindInternal is a failure the console does not classify.
	KindInternal Kind = iota
	// KindBadRequest is a request Azurite refused as invalid.
	KindBadRequest
	// KindNotFound is a container, blob, queue, message, table or entity that does not exist.
	KindNotFound
	// KindConflict is a resource that already exists or is being deleted.
	KindConflict
	// KindPrecondition is an ETag or pop receipt that no longer matches.
	KindPrecondition
	// KindUnavailable is Azurite down or unreachable.
	KindUnavailable
)

// Failure is the classified form of an error of the SDK.
type Failure struct {
	Kind Kind
	// Status is the HTTP status Azurite answered, or zero without an answer.
	Status int
	// Code is the error code of Azurite (ContainerAlreadyExists, ...), or empty.
	Code string
}

// Classify returns the class of err. An error without an answer from
// Azurite (connection refused, timeout) is KindUnavailable.
func Classify(err error) Failure {
	re, ok := errors.AsType[*azcore.ResponseError](err)
	if !ok {
		return Failure{Kind: KindUnavailable}
	}
	f := Failure{Status: re.StatusCode, Code: re.ErrorCode}
	switch {
	case re.StatusCode == http.StatusNotFound:
		f.Kind = KindNotFound
	case re.StatusCode == http.StatusConflict:
		f.Kind = KindConflict
	case re.StatusCode == http.StatusPreconditionFailed:
		f.Kind = KindPrecondition
	case re.StatusCode == http.StatusBadRequest:
		// A pop receipt that no longer matches is a 400 in the Queue service.
		if re.ErrorCode == "PopReceiptMismatch" {
			f.Kind = KindPrecondition
		} else {
			f.Kind = KindBadRequest
		}
	case re.StatusCode >= http.StatusInternalServerError:
		f.Kind = KindUnavailable
	default:
		f.Kind = KindBadRequest
	}
	return f
}

// deref returns the value of p, or the zero value when p is nil.
func deref[T any](p *T) T {
	if p == nil {
		var zero T
		return zero
	}
	return *p
}
