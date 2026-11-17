// Package compose owns the calls to `docker compose` and the list of known projects:
// the union of `compose ls --all` with what was chosen or seen before, without which
// a project would vanish from the list after `down`.
package compose

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"

	"container-console-docker-ce/internal/cliexec"
	"container-console-docker-ce/internal/fault"
)

const (
	stateRunning = "running"
	stateExited  = "exited"
	stateDown    = "down"
	stateUnknown = "unknown"

	storeFile     = "compose-projects.json"
	maxPathLength = 4096
)

var namePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)

// Project is one row of the project list.
type Project struct {
	Name        string   `json:"name"`
	State       string   `json:"state"`
	Status      string   `json:"status"`
	ConfigFiles []string `json:"configFiles"`
}

// Timeouts are the deadlines of the Compose calls.
type Timeouts struct {
	Read   time.Duration
	Action time.Duration
}

// Service is the owner of the Compose integration.
type Service struct {
	runner    *cliexec.Runner
	binary    string
	env       []string
	home      string
	storePath string
	timeouts  Timeouts
	logger    *slog.Logger
	mu        sync.Mutex
}

// NewService builds the Service. Known projects live in a JSON file under stateDir.
func NewService(runner *cliexec.Runner, binary, dockerHost, home, stateDir string, timeouts Timeouts, logger *slog.Logger) *Service {
	return &Service{
		runner:    runner,
		binary:    binary,
		env:       []string{"DOCKER_HOST=" + dockerHost},
		home:      home,
		storePath: filepath.Join(stateDir, storeFile),
		timeouts:  timeouts,
		logger:    logger,
	}
}

// storedProject is the only data kept on disk: name and paths.
type storedProject struct {
	Name        string   `json:"name"`
	ConfigFiles []string `json:"configFiles"`
}

// lsLine is one element of `docker compose ls --format json`.
type lsLine struct {
	Name        string
	Status      string
	ConfigFiles string
}

// List merges the projects Docker knows with the stored ones and remembers what is new.
// With the daemon down the stored projects are still listed, in the unknown state. The lock
// spans the read: an answer from before a `down` must not bring back a project Remove forgot.
func (s *Service) List(ctx context.Context) []Project {
	s.mu.Lock()
	defer s.mu.Unlock()
	lines, err := s.readProjects(ctx)
	stored := s.load()
	if err != nil {
		return projectsFromStore(stored, stateUnknown)
	}
	merged, changed := mergeProjects(stored, lines)
	if changed {
		s.save(storedFrom(merged))
	}
	return merged
}

// readProjects runs `docker compose ls`.
func (s *Service) readProjects(ctx context.Context) ([]lsLine, error) {
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    []string{"compose", "ls", "--all", "--format", "json"},
		Env:     s.env,
		Timeout: s.timeouts.Read,
	})
	if err != nil {
		return nil, err
	}
	var lines []lsLine
	if err := json.Unmarshal(out, &lines); err != nil {
		return nil, errors.New("docker compose ls returned an unexpected format")
	}
	return lines, nil
}

// mergeProjects returns the sorted union and whether the store must change.
func mergeProjects(stored []storedProject, lines []lsLine) ([]Project, bool) {
	byName := map[string]Project{}
	for _, item := range stored {
		byName[item.Name] = Project{Name: item.Name, State: stateDown, Status: stateDown, ConfigFiles: item.ConfigFiles}
	}
	changed := false
	for _, line := range lines {
		files := splitConfigFiles(line.ConfigFiles)
		previous, known := byName[line.Name]
		if len(files) == 0 {
			files = previous.ConfigFiles
		}
		if !known || !slices.Equal(files, previous.ConfigFiles) {
			changed = true
		}
		byName[line.Name] = Project{Name: line.Name, State: parseState(line.Status), Status: line.Status, ConfigFiles: files}
	}
	return sortedProjects(byName), changed
}

// splitConfigFiles splits the comma-separated list that `compose ls` prints.
func splitConfigFiles(value string) []string {
	files := []string{}
	for _, file := range strings.Split(value, ",") {
		if file != "" {
			files = append(files, file)
		}
	}
	return files
}

// parseState reads the summary such as running(2) or exited(1).
func parseState(status string) string {
	switch {
	case strings.Contains(status, stateRunning):
		return stateRunning
	case strings.Contains(status, stateExited):
		return stateExited
	}
	return stateUnknown
}

// sortedProjects returns the projects ordered by name.
func sortedProjects(byName map[string]Project) []Project {
	projects := make([]Project, 0, len(byName))
	for _, project := range byName {
		if project.ConfigFiles == nil {
			project.ConfigFiles = []string{}
		}
		projects = append(projects, project)
	}
	slices.SortFunc(projects, func(a, b Project) int { return strings.Compare(a.Name, b.Name) })
	return projects
}

// projectsFromStore lists the stored projects in the given state.
func projectsFromStore(stored []storedProject, state string) []Project {
	byName := map[string]Project{}
	for _, item := range stored {
		byName[item.Name] = Project{Name: item.Name, State: state, Status: state, ConfigFiles: item.ConfigFiles}
	}
	return sortedProjects(byName)
}

// storedFrom keeps only what the store may hold.
func storedFrom(projects []Project) []storedProject {
	stored := make([]storedProject, 0, len(projects))
	for _, project := range projects {
		stored = append(stored, storedProject{Name: project.Name, ConfigFiles: project.ConfigFiles})
	}
	return stored
}

// Add validates a file chosen by the user, asks Compose for its project name and
// remembers the project. A file Compose refuses comes back with its error.
func (s *Service) Add(ctx context.Context, path string) (Project, error) {
	if err := s.validateFile(path); err != nil {
		return Project{}, err
	}
	name, err := s.readProjectName(ctx, path)
	if err != nil {
		return Project{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	stored := slices.DeleteFunc(s.load(), func(item storedProject) bool { return item.Name == name })
	stored = append(stored, storedProject{Name: name, ConfigFiles: []string{path}})
	s.save(stored)
	return Project{Name: name, State: stateUnknown, Status: stateUnknown, ConfigFiles: []string{path}}, nil
}

// readProjectName runs `compose config`, which needs no daemon, and reads the name field.
func (s *Service) readProjectName(ctx context.Context, path string) (string, error) {
	out, err := s.runner.Run(ctx, cliexec.Command{
		Binary:  s.binary,
		Args:    []string{"compose", "-f", path, "config", "--no-interpolate", "--format", "json"},
		Env:     s.env,
		Timeout: s.timeouts.Read,
	})
	if err != nil {
		var cliErr *cliexec.Error
		if errors.As(err, &cliErr) && cliErr.ExitCode > 0 {
			return "", fault.Invalid("compose_file_invalid", cliErr.Error())
		}
		return "", err
	}
	var config struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(out, &config); err != nil || !namePattern.MatchString(config.Name) {
		return "", fault.Invalid("compose_file_invalid", "compose did not return a valid project name")
	}
	return config.Name, nil
}

// validateFile requires an absolute, clean path of a regular .yaml or .yml file inside the
// home folder. Links are resolved before the check, so one cannot point outside it.
func (s *Service) validateFile(path string) error {
	invalid := fault.Invalid("compose_path_invalid", "the path must be an absolute .yaml or .yml file inside the home folder")
	if len(path) > maxPathLength || !filepath.IsAbs(path) || filepath.Clean(path) != path {
		return invalid
	}
	if ext := filepath.Ext(path); ext != ".yaml" && ext != ".yml" {
		return invalid
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return invalid
	}
	home, err := filepath.EvalSymlinks(s.home)
	if err != nil || !strings.HasPrefix(resolved, home+string(filepath.Separator)) {
		return invalid
	}
	info, err := os.Stat(resolved)
	if err != nil || !info.Mode().IsRegular() {
		return invalid
	}
	return nil
}

// ParseName validates a project name received from outside.
func ParseName(name string) (string, error) {
	if !namePattern.MatchString(name) {
		return "", fault.Invalid("invalid_compose_project", "invalid compose project name")
	}
	return name, nil
}

// Up starts a known project in the background.
func (s *Service) Up(ctx context.Context, name string, out io.Writer) error {
	return s.act(ctx, name, out, "up", "-d")
}

// Stop stops a known project.
func (s *Service) Stop(ctx context.Context, name string, out io.Writer) error {
	return s.act(ctx, name, out, "stop")
}

// Remove runs `down`, with --volumes only when asked, and then forgets the project.
func (s *Service) Remove(ctx context.Context, name string, removeVolumes bool, out io.Writer) error {
	args := []string{"down"}
	if removeVolumes {
		args = append(args, "--volumes")
	}
	if err := s.act(ctx, name, out, args...); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.save(slices.DeleteFunc(s.load(), func(item storedProject) bool { return item.Name == name }))
	return nil
}

// RequireKnown fails when the project has no usable file, before a job is started.
func (s *Service) RequireKnown(ctx context.Context, name string) error {
	_, err := s.resolveFiles(ctx, name)
	return err
}

// resolveFiles finds the validated files of a project. Paths never come from the browser here.
func (s *Service) resolveFiles(ctx context.Context, name string) ([]string, error) {
	for _, project := range s.List(ctx) {
		if project.Name != name {
			continue
		}
		if len(project.ConfigFiles) == 0 {
			return nil, fault.Conflict("compose_files_unknown", "docker does not report the files of this project")
		}
		for _, file := range project.ConfigFiles {
			if err := s.validateFile(file); err != nil {
				return nil, err
			}
		}
		return project.ConfigFiles, nil
	}
	return nil, fault.NotFound("compose_project_not_found", "unknown compose project")
}

// act runs `docker compose -f FILE -p NAME ARGS` with the action deadline.
func (s *Service) act(ctx context.Context, name string, out io.Writer, action ...string) error {
	files, err := s.resolveFiles(ctx, name)
	if err != nil {
		return err
	}
	args := []string{"compose"}
	for _, file := range files {
		args = append(args, "-f", file)
	}
	args = append(append(args, "-p", name), action...)
	return s.runner.Stream(ctx, cliexec.Command{Binary: s.binary, Args: args, Env: s.env, Timeout: s.timeouts.Action}, out)
}

// load reads the store. A missing file is an empty list; an unreadable one is logged
// without its content and treated as empty, since `compose ls` rebuilds most of it.
func (s *Service) load() []storedProject {
	data, err := os.ReadFile(s.storePath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		s.logger.Warn("compose store unreadable", "errorType", "read")
		return nil
	}
	var file struct {
		Projects []storedProject `json:"projects"`
	}
	if err := json.Unmarshal(data, &file); err != nil {
		s.logger.Warn("compose store unreadable", "errorType", "decode")
		return nil
	}
	return file.Projects
}

// save replaces the store atomically, readable only by the user.
func (s *Service) save(projects []storedProject) {
	if err := s.writeStore(projects); err != nil {
		s.logger.Warn("compose store not saved", "errorType", "write")
	}
}

// writeStore writes a temporary file and renames it over the store.
func (s *Service) writeStore(projects []storedProject) error {
	data, err := json.MarshalIndent(struct {
		Projects []storedProject `json:"projects"`
	}{Projects: projects}, "", "  ")
	if err != nil {
		return err
	}
	dir := filepath.Dir(s.storePath)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	temp, err := os.CreateTemp(dir, storeFile+".*")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	return os.Rename(temp.Name(), s.storePath)
}
