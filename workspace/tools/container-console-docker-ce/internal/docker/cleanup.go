package docker

import (
	"context"
	"io"
	"strings"
)

// Containers in these states are in use: the cleanup keeps them and what they use.
var activeStates = map[string]bool{"running": true, "paused": true, "restarting": true, "removing": true}

// Networks Docker creates itself; prune never removes them, so the summary leaves them out.
var builtinNetworks = map[string]bool{"bridge": true, "host": true, "none": true}

// CleanupItem is one resource the cleanup would remove.
type CleanupItem struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Detail string `json:"detail,omitempty"`
}

// CleanupSummary lists what the cleanup removes now: what no active container uses.
type CleanupSummary struct {
	Containers []CleanupItem `json:"containers"`
	Images     []CleanupItem `json:"images"`
	Networks   []CleanupItem `json:"networks"`
	Volumes    []CleanupItem `json:"volumes"`
	// BuildCache is the reclaimable size of the build cache, as `docker system df` prints it.
	BuildCache string `json:"buildCache"`
}

// inUse is what the active containers hold: image ids, volume names and network names.
type inUse struct {
	images, volumes, networks map[string]bool
}

// CleanupSummary computes what Cleanup would remove, from one reading of the daemon.
func (s *Service) CleanupSummary(ctx context.Context) (CleanupSummary, error) {
	lines, err := s.readContainerLines(ctx)
	if err != nil {
		return CleanupSummary{}, err
	}
	stopped, keptIDs := splitContainers(lines)
	used, err := s.readInUse(ctx, keptIDs)
	if err != nil {
		return CleanupSummary{}, err
	}
	summary := CleanupSummary{Containers: stopped}
	if summary.Images, err = s.unusedImages(ctx, used); err != nil {
		return CleanupSummary{}, err
	}
	if summary.Networks, err = s.unusedNetworks(ctx, used); err != nil {
		return CleanupSummary{}, err
	}
	if summary.Volumes, err = s.unusedVolumes(ctx, used); err != nil {
		return CleanupSummary{}, err
	}
	if summary.BuildCache, err = s.reclaimableBuildCache(ctx); err != nil {
		return CleanupSummary{}, err
	}
	return summary, nil
}

// splitContainers returns the stopped containers the cleanup removes and the ids it keeps.
// Pod containers are always kept: Kubernetes owns them and the prune filter skips them.
func splitContainers(lines []containerLine) ([]CleanupItem, []string) {
	stopped := []CleanupItem{}
	kept := []string{}
	for _, line := range lines {
		if activeStates[line.State] || hasLabel(line.Labels, podNamespaceLabel) {
			kept = append(kept, line.ID)
			continue
		}
		stopped = append(stopped, CleanupItem{ID: line.ID, Name: line.Names, Detail: line.Image})
	}
	return stopped, kept
}

// readInUse reads, in one call, the image, volumes and networks of each kept container.
func (s *Service) readInUse(ctx context.Context, ids []string) (inUse, error) {
	used := inUse{images: map[string]bool{}, volumes: map[string]bool{}, networks: map[string]bool{}}
	if len(ids) == 0 {
		return used, nil
	}
	const format = `{{.Image}}|{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}},{{end}}{{end}}` +
		`|{{range $name, $_ := .NetworkSettings.Networks}}{{$name}},{{end}}`
	args := append([]string{"container", "inspect", "--format", format, "--"}, ids...)
	out, err := s.read(ctx, args...)
	if err != nil {
		return inUse{}, err
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		parts := strings.Split(line, "|")
		if len(parts) != 3 {
			continue
		}
		used.images[parts[0]] = true
		addNames(used.volumes, parts[1])
		addNames(used.networks, parts[2])
	}
	return used, nil
}

// addNames adds each name of a comma-terminated list to the set.
func addNames(set map[string]bool, list string) {
	for _, name := range strings.Split(list, ",") {
		if name != "" {
			set[name] = true
		}
	}
}

// unusedImages returns the images no kept container runs.
func (s *Service) unusedImages(ctx context.Context, used inUse) ([]CleanupItem, error) {
	images, err := s.listImages(ctx)
	if err != nil {
		return nil, err
	}
	items := []CleanupItem{}
	for _, image := range images {
		if !used.images[image.ID] {
			items = append(items, CleanupItem{ID: image.ID, Name: image.Reference, Detail: image.Size})
		}
	}
	return items, nil
}

// unusedNetworks returns the networks no kept container is attached to, built-in ones left out.
func (s *Service) unusedNetworks(ctx context.Context, used inUse) ([]CleanupItem, error) {
	networks, err := s.listNetworks(ctx)
	if err != nil {
		return nil, err
	}
	items := []CleanupItem{}
	for _, network := range networks {
		if !builtinNetworks[network.Name] && !used.networks[network.Name] {
			items = append(items, CleanupItem{ID: network.ID, Name: network.Name, Detail: network.ComposeProject})
		}
	}
	return items, nil
}

// unusedVolumes returns the volumes no kept container mounts.
func (s *Service) unusedVolumes(ctx context.Context, used inUse) ([]CleanupItem, error) {
	volumes, err := s.listVolumes(ctx)
	if err != nil {
		return nil, err
	}
	items := []CleanupItem{}
	for _, volume := range volumes {
		if !used.volumes[volume.Name] {
			items = append(items, CleanupItem{ID: volume.Name, Name: volume.Name, Detail: volume.ComposeProject})
		}
	}
	return items, nil
}

// reclaimableBuildCache reads what `docker builder prune --all` would free.
func (s *Service) reclaimableBuildCache(ctx context.Context) (string, error) {
	out, err := s.read(ctx, "system", "df", "--format", "json")
	if err != nil {
		return "", err
	}
	lines, err := decodeLines[struct{ Type, Reclaimable string }](out)
	if err != nil {
		return "", err
	}
	for _, line := range lines {
		if line.Type == "Build Cache" {
			return line.Reclaimable, nil
		}
	}
	return "0B", nil
}

// Cleanup removes what no active container uses: stopped containers (pods excluded), then
// the images, networks and build cache left without one, and the volumes only when asked,
// because they hold data. Each step works on the state of the daemon when it runs.
func (s *Service) Cleanup(ctx context.Context, withVolumes bool, out io.Writer) error {
	steps := [][]string{
		{"container", "prune", "--force", "--filter", "label!=" + podNamespaceLabel},
		{"image", "prune", "--all", "--force"},
		{"network", "prune", "--force"},
	}
	if withVolumes {
		steps = append(steps, []string{"volume", "prune", "--all", "--force"})
	}
	steps = append(steps, []string{"builder", "prune", "--all", "--force"})
	for _, args := range steps {
		if _, err := io.WriteString(out, "$ docker "+strings.Join(args, " ")+"\n"); err != nil {
			return err
		}
		if err := s.act(ctx, out, s.timeouts.Pull, args...); err != nil {
			return err
		}
	}
	return nil
}
