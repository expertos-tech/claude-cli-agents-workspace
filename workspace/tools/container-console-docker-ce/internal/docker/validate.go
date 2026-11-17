package docker

import (
	"regexp"

	"container-console-docker-ce/internal/fault"
)

const (
	maxRefLength      = 255
	maxImageRefLength = 512
)

var (
	refPattern      = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`)
	imageRefPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._:/@-]*$`)
)

// Ref is a validated id or name of a container, volume or network. Service methods
// only take this type, so an unvalidated value never reaches a command line.
type Ref string

// ImageRef is a validated image reference.
type ImageRef string

// ParseRef validates the format Docker accepts for ids and names.
func ParseRef(value string) (Ref, error) {
	if len(value) > maxRefLength || !refPattern.MatchString(value) {
		return "", fault.Invalid("invalid_docker_name", "invalid docker id or name")
	}
	return Ref(value), nil
}

// ParseImageRef validates the format of an image reference, an image id included.
func ParseImageRef(value string) (ImageRef, error) {
	if len(value) > maxImageRefLength || !imageRefPattern.MatchString(value) {
		return "", fault.Invalid("invalid_image_reference", "invalid image reference")
	}
	return ImageRef(value), nil
}
