package httpapi

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strconv"

	"github.com/coder/websocket"

	"container-console-docker-ce/internal/cliexec"
	"container-console-docker-ce/internal/docker"
	"container-console-docker-ce/internal/fault"
	"container-console-docker-ce/internal/kube"
)

const (
	defaultCols      = 80
	defaultRows      = 24
	maxTerminalSide  = 1000
	terminalBufBytes = 32 << 10
)

// websocketRoute registers a WebSocket handler behind the Origin check and tracks it for shutdown.
func (s *Server) websocketRoute(mux *http.ServeMux, pattern string, handler http.HandlerFunc) {
	mux.HandleFunc(pattern, s.requireAllowedOrigin(func(w http.ResponseWriter, r *http.Request) {
		s.streams.Add(1)
		defer s.streams.Done()
		handler(w, r)
	}))
}

// accept upgrades the connection. Without OriginPatterns or InsecureSkipVerify the library
// keeps its own check on top of the guard. Refusals that are not about security happen after
// this point, as a frame, because a browser cannot read the body of a failed upgrade.
func (s *Server) accept(w http.ResponseWriter, r *http.Request) (*websocket.Conn, bool) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		s.Logger.Warn("websocket upgrade failed", "route", r.Pattern)
		return nil, false
	}
	conn.SetReadLimit(s.Config.Limits.WSReadBytes)
	return conn, true
}

// controlFrame is the JSON of every text frame that is not a snapshot.
type controlFrame struct {
	Type     string         `json:"type"`
	Code     string         `json:"code,omitempty"`
	Message  string         `json:"message,omitempty"`
	ExitCode *int           `json:"exitCode,omitempty"`
	Params   map[string]any `json:"params,omitempty"`
}

// writeControl sends one control frame with the write deadline.
func (s *Server) writeControl(ctx context.Context, conn *websocket.Conn, frame controlFrame) error {
	data, err := json.Marshal(frame)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, s.Config.Timeouts.WSWrite)
	defer cancel()
	return conn.Write(ctx, websocket.MessageText, data)
}

// closeWithError reports the error in a frame and closes with the given status.
func (s *Server) closeWithError(ctx context.Context, conn *websocket.Conn, err error, status websocket.StatusCode) {
	_, payload := describeError(err)
	_ = s.writeControl(ctx, conn, controlFrame{
		Type:     "error",
		Code:     payload.Code,
		Message:  payload.Message,
		ExitCode: payload.ExitCode,
		Params:   payload.Params,
	})
	_ = conn.Close(status, "")
}

// serveLive sends the snapshot of the topic on subscribing and on each change of content.
func (s *Server) serveLive(w http.ResponseWriter, r *http.Request) {
	conn, ok := s.accept(w, r)
	if !ok {
		return
	}
	defer conn.CloseNow()
	sub, known := s.Hub.Subscribe(r.PathValue("topic"))
	if !known {
		s.closeWithError(r.Context(), conn, fault.NotFound("topic_not_found", "unknown topic"), websocket.StatusNormalClosure)
		return
	}
	defer sub.Close()
	ctx := conn.CloseRead(r.Context())
	for {
		select {
		case <-ctx.Done():
			_ = conn.Close(websocket.StatusGoingAway, "")
			return
		case frame := <-sub.C:
			if err := s.writeFrame(ctx, conn, websocket.MessageText, frame); err != nil {
				return
			}
		}
	}
}

// writeFrame sends one frame with the write deadline. A client too slow for it loses the connection.
func (s *Server) writeFrame(ctx context.Context, conn *websocket.Conn, kind websocket.MessageType, data []byte) error {
	ctx, cancel := context.WithTimeout(ctx, s.Config.Timeouts.WSWrite)
	defer cancel()
	return conn.Write(ctx, kind, data)
}

// binaryWriter sends each chunk written as one binary frame.
type binaryWriter struct {
	server *Server
	ctx    context.Context
	conn   *websocket.Conn
}

// Write sends one chunk.
func (b binaryWriter) Write(p []byte) (int, error) {
	if err := b.server.writeFrame(b.ctx, b.conn, websocket.MessageBinary, p); err != nil {
		return 0, err
	}
	return len(p), nil
}

// logFollower follows the logs of a resource until ctx ends.
type logFollower func(ctx context.Context, w io.Writer) error

// serveContainerLogs streams the logs of a container.
func (s *Server) serveContainerLogs(w http.ResponseWriter, r *http.Request) {
	s.serveLogs(w, r, func(ctx context.Context) (logFollower, error) {
		ref, err := docker.ParseRef(r.PathValue("id"))
		if err != nil {
			return nil, err
		}
		if err := s.requireEnvironmentOn(ctx); err != nil {
			return nil, err
		}
		return func(ctx context.Context, w io.Writer) error { return s.Docker.StreamLogs(ctx, ref, w) }, nil
	})
}

// servePodLogs streams the logs of a pod.
func (s *Server) servePodLogs(w http.ResponseWriter, r *http.Request) {
	s.serveLogs(w, r, func(ctx context.Context) (logFollower, error) {
		pod, container, err := parsePodRequest(r)
		if err != nil {
			return nil, err
		}
		if err := s.requireKubernetesReachable(ctx); err != nil {
			return nil, err
		}
		return func(ctx context.Context, w io.Writer) error { return s.Kube.StreamLogs(ctx, pod, container, w) }, nil
	})
}

// parsePodRequest reads the pod in the path and the optional container in the query.
func parsePodRequest(r *http.Request) (kube.Target, string, error) {
	pod, err := kube.ParseNamespaced(string(kube.KindPod), r.PathValue("namespace"), r.PathValue("name"))
	if err != nil {
		return kube.Target{}, "", err
	}
	container, err := kube.ParseContainerName(r.URL.Query().Get("container"))
	if err != nil {
		return kube.Target{}, "", err
	}
	return pod, container, nil
}

// serveLogs bridges a log process to the WebSocket. The process dies with the connection,
// because ctx ends when the client closes it. Log content never reaches the service log.
func (s *Server) serveLogs(w http.ResponseWriter, r *http.Request, prepare func(ctx context.Context) (logFollower, error)) {
	conn, ok := s.accept(w, r)
	if !ok {
		return
	}
	defer conn.CloseNow()
	ctx := conn.CloseRead(r.Context())
	follow, err := prepare(ctx)
	if err != nil {
		s.closeWithError(ctx, conn, err, websocket.StatusNormalClosure)
		return
	}
	err = follow(ctx, binaryWriter{server: s, ctx: ctx, conn: conn})
	if ctx.Err() != nil {
		return
	}
	if err != nil {
		s.closeWithError(ctx, conn, err, websocket.StatusNormalClosure)
		return
	}
	_ = s.writeControl(ctx, conn, controlFrame{Type: "end"})
	_ = conn.Close(websocket.StatusNormalClosure, "")
}

// terminalStarter starts the terminal process with the initial size.
type terminalStarter func(ctx context.Context, cols, rows uint16) (*cliexec.PTYSession, error)

// serveContainerTerminal opens a terminal inside a container.
func (s *Server) serveContainerTerminal(w http.ResponseWriter, r *http.Request) {
	s.serveTerminal(w, r, func(ctx context.Context) (terminalStarter, error) {
		ref, err := docker.ParseRef(r.PathValue("id"))
		if err != nil {
			return nil, err
		}
		if err := s.requireEnvironmentOn(ctx); err != nil {
			return nil, err
		}
		return func(ctx context.Context, cols, rows uint16) (*cliexec.PTYSession, error) {
			return s.Docker.StartTerminal(ctx, ref, cols, rows)
		}, nil
	})
}

// servePodTerminal opens a terminal inside a pod.
func (s *Server) servePodTerminal(w http.ResponseWriter, r *http.Request) {
	s.serveTerminal(w, r, func(ctx context.Context) (terminalStarter, error) {
		pod, container, err := parsePodRequest(r)
		if err != nil {
			return nil, err
		}
		if err := s.requireKubernetesReachable(ctx); err != nil {
			return nil, err
		}
		return func(ctx context.Context, cols, rows uint16) (*cliexec.PTYSession, error) {
			return s.Kube.StartTerminal(ctx, pod, container, cols, rows)
		}, nil
	})
}

// serveTerminal holds one of the limited terminal slots while the process runs.
func (s *Server) serveTerminal(w http.ResponseWriter, r *http.Request, prepare func(ctx context.Context) (terminalStarter, error)) {
	conn, ok := s.accept(w, r)
	if !ok {
		return
	}
	defer conn.CloseNow()
	select {
	case s.terminals <- struct{}{}:
		defer func() { <-s.terminals }()
	default:
		tooMany := fault.Conflict("too_many_terminals", "the limit of simultaneous terminals was reached").
			WithParams(map[string]any{"max": s.Config.Limits.MaxTerminals})
		s.closeWithError(r.Context(), conn, tooMany, websocket.StatusTryAgainLater)
		return
	}
	session, err := s.startTerminal(r, prepare)
	if err != nil {
		s.closeWithError(r.Context(), conn, err, websocket.StatusNormalClosure)
		return
	}
	s.bridgeTerminal(r.Context(), conn, session)
}

// startTerminal validates the request and starts the process.
func (s *Server) startTerminal(r *http.Request, prepare func(ctx context.Context) (terminalStarter, error)) (*cliexec.PTYSession, error) {
	cols, rows, err := parseTerminalSize(r)
	if err != nil {
		return nil, err
	}
	start, err := prepare(r.Context())
	if err != nil {
		return nil, err
	}
	return start(r.Context(), cols, rows)
}

// parseTerminalSize reads the optional initial size from the query.
func parseTerminalSize(r *http.Request) (uint16, uint16, error) {
	cols, err := parseTerminalSide(r.URL.Query().Get("cols"), defaultCols)
	if err != nil {
		return 0, 0, err
	}
	rows, err := parseTerminalSide(r.URL.Query().Get("rows"), defaultRows)
	if err != nil {
		return 0, 0, err
	}
	return cols, rows, nil
}

// parseTerminalSide validates one side of the terminal.
func parseTerminalSide(value string, fallback uint16) (uint16, error) {
	if value == "" {
		return fallback, nil
	}
	side, err := strconv.Atoi(value)
	if err != nil || !validTerminalSide(side) {
		return 0, invalidTerminalSize()
	}
	return uint16(side), nil
}

// validTerminalSide checks the range of a terminal side.
func validTerminalSide(side int) bool {
	return side >= 1 && side <= maxTerminalSide
}

// invalidTerminalSize builds the error of a size out of range.
func invalidTerminalSize() error {
	return fault.Invalid("invalid_terminal_size", "the terminal size is out of range")
}

// bridgeTerminal connects the process and the WebSocket in both directions. Closing the
// WebSocket ends the process, and the end of the process closes the WebSocket.
func (s *Server) bridgeTerminal(parent context.Context, conn *websocket.Conn, session *cliexec.PTYSession) {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	outputDone := make(chan struct{})
	go func() {
		defer close(outputDone)
		s.copyTerminalOutput(ctx, conn, session)
	}()
	s.copyTerminalInput(ctx, conn, session)
	session.Close()
	<-outputDone
}

// copyTerminalOutput sends the output as binary frames, then the exit code when the process ends.
// Terminal content never reaches the service log.
func (s *Server) copyTerminalOutput(ctx context.Context, conn *websocket.Conn, session *cliexec.PTYSession) {
	buffer := make([]byte, terminalBufBytes)
	for {
		n, err := session.Read(buffer)
		if n > 0 {
			if writeErr := s.writeFrame(ctx, conn, websocket.MessageBinary, buffer[:n]); writeErr != nil {
				session.Close()
				return
			}
		}
		if err != nil {
			break
		}
	}
	code := session.ExitCode()
	_ = s.writeControl(ctx, conn, controlFrame{Type: "exit", ExitCode: &code})
	_ = conn.Close(websocket.StatusNormalClosure, "")
}

// resizeFrame is the only text frame a client may send to a terminal.
type resizeFrame struct {
	Type string `json:"type"`
	Cols int    `json:"cols"`
	Rows int    `json:"rows"`
}

// copyTerminalInput forwards binary frames as keys and text frames as resize requests.
// It returns when the client leaves or sends something invalid.
func (s *Server) copyTerminalInput(ctx context.Context, conn *websocket.Conn, session *cliexec.PTYSession) {
	for {
		kind, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		if kind == websocket.MessageBinary {
			if _, err := session.Write(data); err != nil {
				return
			}
			continue
		}
		if err := applyResize(session, data); err != nil {
			s.closeWithError(ctx, conn, err, websocket.StatusPolicyViolation)
			return
		}
	}
}

// applyResize validates a resize frame and applies it.
func applyResize(session *cliexec.PTYSession, data []byte) error {
	var frame resizeFrame
	if err := json.Unmarshal(data, &frame); err != nil || frame.Type != "resize" {
		return fault.Invalid("invalid_terminal_frame", "unknown terminal frame")
	}
	if !validTerminalSide(frame.Cols) || !validTerminalSide(frame.Rows) {
		return invalidTerminalSize()
	}
	return session.Resize(uint16(frame.Cols), uint16(frame.Rows))
}
