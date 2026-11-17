// Package fault defines the domain errors the service reports to its callers.
// It carries no transport types: the HTTP layer maps each Kind to a status.
package fault

// Kind classifies a domain error by what the caller can do about it.
type Kind int

const (
	// KindInvalid means the input breaks a validation or business rule.
	KindInvalid Kind = iota
	// KindConflict means the current state of the system refuses the action.
	KindConflict
	// KindNotFound means the target of the action does not exist.
	KindNotFound
)

// Error is a domain error with a stable code the front-end can translate.
type Error struct {
	Kind    Kind
	Code    string
	Message string
	Params  map[string]any
}

// Error returns the technical message.
func (e *Error) Error() string {
	return e.Message
}

// WithParams returns a copy of the error with named values for the translated message.
func (e *Error) WithParams(params map[string]any) *Error {
	copied := *e
	copied.Params = params
	return &copied
}

// Invalid builds an error for input that breaks a rule.
func Invalid(code, message string) *Error {
	return &Error{Kind: KindInvalid, Code: code, Message: message}
}

// Conflict builds an error for an action the current state refuses.
func Conflict(code, message string) *Error {
	return &Error{Kind: KindConflict, Code: code, Message: message}
}

// NotFound builds an error for a target that does not exist.
func NotFound(code, message string) *Error {
	return &Error{Kind: KindNotFound, Code: code, Message: message}
}
