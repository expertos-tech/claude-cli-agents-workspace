// Package config reads and validates the service settings from CONSOLE_* variables.
package config

import (
	"errors"
	"fmt"
	"net"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	loopbackHost      = "127.0.0.1"
	defaultListen     = loopbackHost + ":27850"
	defaultDockerHost = "unix:///var/run/docker.sock"
	fallbackPath      = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	mebibyte          = 1 << 20
	kibibyte          = 1 << 10
)

var contextPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._@:/-]*$`)

// Binaries holds the executable of each external CLI, as a bare name or an absolute path.
type Binaries struct {
	Docker  string
	Kubectl string
	Zenity  string
}

// Timeouts holds the explicit deadline of each kind of external call and of the HTTP server.
type Timeouts struct {
	Read          time.Duration
	DockerAction  time.Duration
	DockerPull    time.Duration
	ComposeAction time.Duration
	KubeAction    time.Duration
	FilePicker    time.Duration
	ProcessWait   time.Duration
	HTTPHeader    time.Duration
	HTTPRead      time.Duration
	HTTPIdle      time.Duration
	WSWrite       time.Duration
	Shutdown      time.Duration
}

// Intervals holds the refresh cadence of the live topics.
type Intervals struct {
	Environment    time.Duration
	Kubernetes     time.Duration
	DockerSync     time.Duration
	DockerDebounce time.Duration
	EventsRetry    time.Duration
}

// Limits holds the resource limits of the HTTP and WebSocket surface.
type Limits struct {
	MaxBodyBytes    int64
	MaxHeaderBytes  int
	WSReadBytes     int64
	MaxTerminals    int
	JobsKept        int
	JobOutputLines  int
	ReplicasMaximum int
}

// Config is the validated service configuration.
type Config struct {
	ListenAddr string
	Port       int
	DockerHost string
	// KubeContext is empty to use the current context of the kubeconfig.
	KubeContext string
	HomeDir     string
	StateDir    string
	LogFile     string
	SearchPath  string
	Binaries    Binaries
	Timeouts    Timeouts
	Intervals   Intervals
	Limits      Limits
}

// AllowedHosts returns the only Host header values the service accepts.
func (c Config) AllowedHosts() []string {
	port := strconv.Itoa(c.Port)
	return []string{net.JoinHostPort(loopbackHost, port), net.JoinHostPort("localhost", port)}
}

// AllowedOrigins returns the only Origin header values accepted on WebSocket routes.
func (c Config) AllowedOrigins() []string {
	hosts := c.AllowedHosts()
	origins := make([]string, 0, len(hosts))
	for _, host := range hosts {
		origins = append(origins, "http://"+host)
	}
	return origins
}

// Load builds the configuration from the given environment lookup and home folder.
// It reports every invalid value at once, and a bad setting stops the service at startup.
func Load(getenv func(string) string, home string) (Config, error) {
	if !filepath.IsAbs(home) {
		return Config{}, errors.New("home folder must be an absolute path")
	}
	r := &envReader{getenv: getenv}
	cfg := Config{HomeDir: home}
	cfg.DockerHost = r.text("CONSOLE_DOCKER_HOST", defaultDockerHost)
	cfg.KubeContext = r.text("CONSOLE_KUBE_CONTEXT", "")
	cfg.StateDir = r.text("CONSOLE_STATE_DIR", defaultStateDir(getenv, home))
	cfg.LogFile = r.text("CONSOLE_LOG_FILE", filepath.Join(cfg.StateDir, "console.log"))
	cfg.SearchPath = searchPath(getenv("CONSOLE_PATH_PREPEND"), getenv("PATH"))
	cfg.Binaries = r.binaries()
	cfg.Timeouts = r.timeouts()
	cfg.Intervals = r.intervals()
	cfg.Limits = r.limits()

	cfg.ListenAddr = r.text("CONSOLE_LISTEN", defaultListen)
	port, err := parseLoopback(cfg.ListenAddr)
	r.check(err)
	cfg.Port = port
	r.check(validateSettings(cfg))
	if len(r.errs) > 0 {
		return Config{}, errors.Join(r.errs...)
	}
	return cfg, nil
}

// parseLoopback accepts only the IPv4 loopback literal with an explicit port.
// A name such as localhost is refused because resolving it could yield another address.
func parseLoopback(listen string) (int, error) {
	host, portText, err := net.SplitHostPort(listen)
	if err != nil {
		return 0, fmt.Errorf("CONSOLE_LISTEN: %w", err)
	}
	if host != loopbackHost {
		return 0, fmt.Errorf("CONSOLE_LISTEN: host must be %s", loopbackHost)
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 1 || port > 65535 {
		return 0, errors.New("CONSOLE_LISTEN: port must be between 1 and 65535")
	}
	return port, nil
}

// validateSettings checks the formats that the CLIs and the file system depend on.
func validateSettings(cfg Config) error {
	var errs []error
	if !strings.HasPrefix(cfg.DockerHost, "unix://") {
		errs = append(errs, errors.New("CONSOLE_DOCKER_HOST: must be a unix:// socket"))
	}
	if cfg.KubeContext != "" && !contextPattern.MatchString(cfg.KubeContext) {
		errs = append(errs, errors.New("CONSOLE_KUBE_CONTEXT: invalid context name"))
	}
	if !filepath.IsAbs(cfg.StateDir) {
		errs = append(errs, errors.New("CONSOLE_STATE_DIR: must be an absolute path"))
	}
	if !filepath.IsAbs(cfg.LogFile) {
		errs = append(errs, errors.New("CONSOLE_LOG_FILE: must be an absolute path"))
	}
	for name, value := range map[string]string{
		"CONSOLE_DOCKER_BIN":  cfg.Binaries.Docker,
		"CONSOLE_KUBECTL_BIN": cfg.Binaries.Kubectl,
		"CONSOLE_ZENITY_BIN":  cfg.Binaries.Zenity,
	} {
		if !validBinary(value) {
			errs = append(errs, fmt.Errorf("%s: must be a bare name or an absolute path", name))
		}
	}
	return errors.Join(errs...)
}

// validBinary accepts a name resolved through PATH or an absolute path, and no relative path.
func validBinary(value string) bool {
	if value == "" || strings.HasPrefix(value, "-") {
		return false
	}
	return filepath.IsAbs(value) || !strings.Contains(value, "/")
}

// defaultStateDir follows the XDG base directory rule: a relative XDG_STATE_HOME counts as unset.
func defaultStateDir(getenv func(string) string, home string) string {
	stateHome := getenv("XDG_STATE_HOME")
	if !filepath.IsAbs(stateHome) {
		stateHome = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(stateHome, "container-console-docker-ce")
}

// searchPath puts the optional folders first and keeps the inherited PATH, without repeats.
// An empty PATH gets the usual system folders, so the CLIs can still be found.
func searchPath(prepend, inherited string) string {
	if inherited == "" {
		inherited = fallbackPath
	}
	seen := map[string]bool{}
	var dirs []string
	for _, dir := range strings.Split(prepend+":"+inherited, ":") {
		if dir != "" && !seen[dir] {
			seen[dir] = true
			dirs = append(dirs, dir)
		}
	}
	return strings.Join(dirs, ":")
}

// envReader reads typed values with defaults and collects every parsing error.
type envReader struct {
	getenv func(string) string
	errs   []error
}

// check records an error when there is one.
func (r *envReader) check(err error) {
	if err != nil {
		r.errs = append(r.errs, err)
	}
}

// text returns the variable or its default.
func (r *envReader) text(key, fallback string) string {
	if value := r.getenv(key); value != "" {
		return value
	}
	return fallback
}

// duration returns a positive duration from the variable or its default.
func (r *envReader) duration(key string, fallback time.Duration) time.Duration {
	raw := r.getenv(key)
	if raw == "" {
		return fallback
	}
	value, err := time.ParseDuration(raw)
	if err != nil || value <= 0 {
		r.check(fmt.Errorf("%s: must be a positive duration", key))
		return fallback
	}
	return value
}

// positiveInt returns a positive integer from the variable or its default.
func (r *envReader) positiveInt(key string, fallback int) int {
	raw := r.getenv(key)
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		r.check(fmt.Errorf("%s: must be a positive integer", key))
		return fallback
	}
	return value
}

// binaries reads the executable of each CLI.
func (r *envReader) binaries() Binaries {
	return Binaries{
		Docker:  r.text("CONSOLE_DOCKER_BIN", "docker"),
		Kubectl: r.text("CONSOLE_KUBECTL_BIN", "kubectl"),
		Zenity:  r.text("CONSOLE_ZENITY_BIN", "zenity"),
	}
}

// timeouts reads the deadlines, with their defaults.
func (r *envReader) timeouts() Timeouts {
	return Timeouts{
		Read:          r.duration("CONSOLE_TIMEOUT_READ", 5*time.Second),
		DockerAction:  r.duration("CONSOLE_TIMEOUT_DOCKER_ACTION", 90*time.Second),
		DockerPull:    r.duration("CONSOLE_TIMEOUT_DOCKER_PULL", 30*time.Minute),
		ComposeAction: r.duration("CONSOLE_TIMEOUT_COMPOSE_ACTION", 15*time.Minute),
		KubeAction:    r.duration("CONSOLE_TIMEOUT_KUBE_ACTION", 2*time.Minute),
		FilePicker:    r.duration("CONSOLE_TIMEOUT_FILE_PICKER", 5*time.Minute),
		ProcessWait:   r.duration("CONSOLE_TIMEOUT_PROCESS_WAIT", 5*time.Second),
		HTTPHeader:    r.duration("CONSOLE_TIMEOUT_HTTP_HEADER", 5*time.Second),
		HTTPRead:      r.duration("CONSOLE_TIMEOUT_HTTP_READ", 30*time.Second),
		HTTPIdle:      r.duration("CONSOLE_TIMEOUT_HTTP_IDLE", 60*time.Second),
		WSWrite:       r.duration("CONSOLE_TIMEOUT_WS_WRITE", 5*time.Second),
		Shutdown:      r.duration("CONSOLE_TIMEOUT_SHUTDOWN", 10*time.Second),
	}
}

// intervals reads the cadence of the live topics.
func (r *envReader) intervals() Intervals {
	return Intervals{
		Environment:    r.duration("CONSOLE_INTERVAL_ENVIRONMENT", time.Second),
		Kubernetes:     r.duration("CONSOLE_INTERVAL_KUBERNETES", time.Second),
		DockerSync:     r.duration("CONSOLE_INTERVAL_DOCKER_SYNC", 5*time.Second),
		DockerDebounce: r.duration("CONSOLE_INTERVAL_DOCKER_DEBOUNCE", 150*time.Millisecond),
		EventsRetry:    r.duration("CONSOLE_INTERVAL_EVENTS_RETRY", 2*time.Second),
	}
}

// limits reads the resource limits.
func (r *envReader) limits() Limits {
	return Limits{
		MaxBodyBytes:    int64(r.positiveInt("CONSOLE_MAX_BODY_BYTES", mebibyte)),
		MaxHeaderBytes:  r.positiveInt("CONSOLE_MAX_HEADER_BYTES", 64*kibibyte),
		WSReadBytes:     int64(r.positiveInt("CONSOLE_WS_READ_BYTES", 64*kibibyte)),
		MaxTerminals:    r.positiveInt("CONSOLE_MAX_TERMINALS", 8),
		JobsKept:        r.positiveInt("CONSOLE_JOBS_KEPT", 50),
		JobOutputLines:  r.positiveInt("CONSOLE_JOB_OUTPUT_LINES", 200),
		ReplicasMaximum: r.positiveInt("CONSOLE_REPLICAS_MAXIMUM", 1000),
	}
}
