// Package activity is what happened in the local Azurite: its access log,
// read from the container with the docker CLI, and the operations done by
// the console itself, kept in memory.
package activity

import (
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// account is the first segment of every path in the access log.
const account = "/devstoreaccount1"

// Line is one request of the access log of Azurite.
type Line struct {
	Time time.Time `json:"time"`
	// IP is the client address; Caller is its Compose service, "host" for
	// the gateway (a program on the machine) or empty when unknown.
	IP     string `json:"ip"`
	Caller string `json:"caller,omitempty"`
	Method string `json:"method,omitempty"`
	// Resource is the decoded path without the account, such as
	// "events/2026/10/28/a.json"; Query is the raw query string.
	Resource string `json:"resource,omitempty"`
	Query    string `json:"query,omitempty"`
	Status   int    `json:"status,omitempty"`
	// Bytes is the size of the answer, or -1 when the log has "-".
	Bytes int64 `json:"bytes"`
	// Raw is the line itself when it is not an access record (startup
	// messages, errors of Azurite).
	Raw string `json:"raw,omitempty"`
}

// accessRe matches the record Azurite writes per request:
// 172.18.0.10 - - [28/Oct/2026:13:26:10 +0000] "PUT /devstoreaccount1/events HTTP/1.1" 201 -
var accessRe = regexp.MustCompile(`^(\S+) \S+ \S+ \[([^\]]+)\] "(\S+) (\S+) [^"]*" (\d{3}) (\S+)\s*$`)

const accessTime = "02/Jan/2006:15:04:05 -0700"

// ParseLine parses one line of `docker logs --timestamps`: the timestamp of
// Docker, a space and the text Azurite wrote.
func ParseLine(s string) Line {
	s = strings.TrimRight(s, "\r\n")
	var ts time.Time
	if stamp, rest, ok := strings.Cut(s, " "); ok {
		if t, err := time.Parse(time.RFC3339Nano, stamp); err == nil {
			ts, s = t, rest
		}
	}
	m := accessRe.FindStringSubmatch(s)
	if m == nil {
		return Line{Time: ts, Bytes: -1, Raw: s}
	}
	l := Line{Time: ts, IP: m[1], Method: m[3], Bytes: -1}
	if ts.IsZero() {
		if t, err := time.Parse(accessTime, m[2]); err == nil {
			l.Time = t
		}
	}
	path, query, _ := strings.Cut(m[4], "?")
	l.Query = query
	path = strings.TrimPrefix(strings.TrimPrefix(path, account), "/")
	if decoded, err := url.PathUnescape(path); err == nil {
		path = decoded
	}
	l.Resource = path
	l.Status, _ = strconv.Atoi(m[5])
	if n, err := strconv.ParseInt(m[6], 10, 64); err == nil {
		l.Bytes = n
	}
	return l
}

// Service tells which service of Azurite answered a line, by the shape of
// the request and the names of the queues and tables of the account:
// "blob", "queue", "table", "account" for a request on the account itself
// (the lists of containers and of queues have the same shape) or "" for a
// line that is not a request. Blob is the rest, since containers and blobs
// have no mark of their own.
func Service(l Line, queues, tables map[string]bool) string {
	if l.Raw != "" {
		return ""
	}
	first, rest, _ := strings.Cut(l.Resource, "/")
	if base, _, ok := strings.Cut(first, "("); ok {
		first = base
	}
	container := strings.Contains(l.Query, "restype=container")
	switch {
	case first == "Tables" || first == "$batch" || strings.Contains(l.Resource, "("):
		return "table"
	case rest == "messages" || strings.HasPrefix(rest, "messages/"):
		return "queue"
	case first == "":
		return "account"
	case tables[first] && !container:
		return "table"
	case queues[first] && !container:
		return "queue"
	}
	return "blob"
}
