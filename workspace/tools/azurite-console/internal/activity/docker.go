package activity

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

const (
	serviceLabel = "com.docker.compose.service"
	projectLabel = "com.docker.compose.project"
	azuriteName  = "azurite"
)

// Runner runs the docker CLI with args and returns its standard output.
type Runner func(ctx context.Context, args ...string) ([]byte, error)

// ExecDocker runs the docker binary on the PATH.
func ExecDocker(ctx context.Context, args ...string) ([]byte, error) {
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "docker", args...) //nolint:gosec // fixed binary, arguments built here
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		if errors.Is(err, exec.ErrNotFound) {
			return nil, errors.New("docker CLI not found on the PATH")
		}
		return nil, fmt.Errorf("docker %s: %w: %s", args[0], err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

// Log is the end of the access log of the Azurite container.
type Log struct {
	// Container is the name of the container; Image is its image, whose tag
	// is the version of Azurite.
	Container string `json:"container"`
	Image     string `json:"image"`
	Lines     []Line `json:"lines"`
}

// Docker reads the Azurite container of Compose, found by its
// service label, and maps client addresses to Compose services.
type Docker struct {
	run Runner
}

// NewDocker returns a reader that calls run.
func NewDocker(run Runner) *Docker { return &Docker{run: run} }

// container is the Azurite container as docker inspect shows it.
type container struct {
	id, name, image, project string
}

// Tail returns the last n lines of the log of the Azurite container, oldest
// first, with the Compose service of each client address.
func (d *Docker) Tail(ctx context.Context, n int) (Log, error) {
	c, err := d.azurite(ctx)
	if err != nil {
		return Log{}, err
	}
	// Azurite writes the access log to stdout; docker logs replays stdout
	// and stderr, and both are read here.
	out, err := d.run(ctx, "logs", "--tail", strconv.Itoa(n), "--timestamps", c.id)
	if err != nil {
		return Log{}, err
	}
	callers := d.callers(ctx, c.project)
	log := Log{Container: c.name, Image: c.image, Lines: []Line{}}
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) == "" {
			continue
		}
		l := ParseLine(sc.Text())
		if l.IP != "" {
			l.Caller = callers[l.IP]
		}
		log.Lines = append(log.Lines, l)
	}
	return log, sc.Err()
}

// Image returns the image of the Azurite container.
func (d *Docker) Image(ctx context.Context) (string, error) {
	c, err := d.azurite(ctx)
	if err != nil {
		return "", err
	}
	return c.image, nil
}

// azurite finds the running Azurite container by its Compose service label.
func (d *Docker) azurite(ctx context.Context) (container, error) {
	out, err := d.run(ctx, "ps", "-q", "--filter", "label="+serviceLabel+"="+azuriteName)
	if err != nil {
		return container{}, err
	}
	ids := strings.Fields(string(out))
	if len(ids) == 0 {
		return container{}, errors.New("no running container with the Compose service azurite")
	}
	format := `{{.Id}}|{{.Name}}|{{.Config.Image}}|{{index .Config.Labels "` + projectLabel + `"}}`
	out, err = d.run(ctx, "inspect", "--format", format, ids[0])
	if err != nil {
		return container{}, err
	}
	parts := strings.Split(strings.TrimSpace(string(out)), "|")
	if len(parts) != 4 {
		return container{}, fmt.Errorf("unexpected docker inspect output %q", strings.TrimSpace(string(out)))
	}
	return container{id: parts[0], name: strings.TrimPrefix(parts[1], "/"), image: parts[2], project: parts[3]}, nil
}

// callers maps the addresses of the containers of project to their Compose
// service, and each network gateway to "host". A failure leaves the map
// empty: the log is still shown, without callers.
func (d *Docker) callers(ctx context.Context, project string) map[string]string {
	m := map[string]string{}
	if project == "" {
		return m
	}
	out, err := d.run(ctx, "ps", "-q", "--filter", "label="+projectLabel+"="+project)
	if err != nil {
		return m
	}
	ids := strings.Fields(string(out))
	if len(ids) == 0 {
		return m
	}
	format := `{{index .Config.Labels "` + serviceLabel + `"}}{{range .NetworkSettings.Networks}} {{.IPAddress}}/{{.Gateway}}{{end}}`
	out, err = d.run(ctx, append([]string{"inspect", "--format", format}, ids...)...)
	if err != nil {
		return m
	}
	for line := range strings.Lines(string(out)) {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		for _, pair := range fields[1:] {
			ip, gateway, _ := strings.Cut(pair, "/")
			if ip != "" {
				m[ip] = fields[0]
			}
			if gateway != "" {
				m[gateway] = "host"
			}
		}
	}
	return m
}

// Version is the tag of image, such as 3.37.0, or "" without one. A digest
// after the tag, as in a pinned image, is not part of it.
func Version(image string) string {
	image, _, _ = strings.Cut(image, "@")
	i := strings.LastIndex(image, ":")
	if i < 0 || strings.Contains(image[i:], "/") {
		return ""
	}
	return image[i+1:]
}
