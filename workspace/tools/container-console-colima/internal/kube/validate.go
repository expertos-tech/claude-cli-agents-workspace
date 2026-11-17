package kube

import (
	"regexp"

	"container-console-colima/internal/fault"
)

const (
	maxLabelLength     = 63
	maxSubdomainLength = 253
)

var (
	labelPattern     = regexp.MustCompile(`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`)
	subdomainPattern = regexp.MustCompile(`^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$`)
)

// Kind is a resource kind the console manages, in the form kubectl accepts.
type Kind string

const (
	// KindNamespace is the namespaces resource, the only one without a namespace.
	KindNamespace Kind = "namespaces"
	// KindPod is the pods resource.
	KindPod Kind = "pods"
	// KindDeployment is the deployments resource.
	KindDeployment Kind = "deployments"
	// KindService is the services resource.
	KindService Kind = "services"
)

// Target is a validated resource. Service methods only take this type, so an
// unvalidated value never reaches a command line.
type Target struct {
	Kind      Kind
	Namespace string
	Name      string
}

// ParseNamespace validates a namespace as a target of its own.
func ParseNamespace(name string) (Target, error) {
	if !validLabel(name) {
		return Target{}, invalidName()
	}
	return Target{Kind: KindNamespace, Name: name}, nil
}

// ParseNamespaced validates a namespaced target: a DNS-1123 label as the namespace, and
// as the name a label for services and a subdomain for pods and deployments.
func ParseNamespaced(kind, namespace, name string) (Target, error) {
	if !validLabel(namespace) {
		return Target{}, invalidName()
	}
	parsed := Kind(kind)
	switch parsed {
	case KindService:
		if !validLabel(name) {
			return Target{}, invalidName()
		}
	case KindPod, KindDeployment:
		if !validSubdomain(name) {
			return Target{}, invalidName()
		}
	default:
		return Target{}, fault.NotFound("kubernetes_kind_unknown", "unknown resource kind")
	}
	return Target{Kind: parsed, Namespace: namespace, Name: name}, nil
}

// ParseContainerName validates the optional container of a pod.
func ParseContainerName(name string) (string, error) {
	if name != "" && !validLabel(name) {
		return "", invalidName()
	}
	return name, nil
}

// scopeArgs returns the namespace flag, absent for a namespace itself.
func (t Target) scopeArgs() []string {
	if t.Kind == KindNamespace {
		return nil
	}
	return []string{"-n", t.Namespace}
}

// validLabel checks a DNS-1123 label.
func validLabel(value string) bool {
	return len(value) <= maxLabelLength && labelPattern.MatchString(value)
}

// validSubdomain checks a DNS-1123 subdomain.
func validSubdomain(value string) bool {
	return len(value) <= maxSubdomainLength && subdomainPattern.MatchString(value)
}

// invalidName builds the error of a name out of format.
func invalidName() error {
	return fault.Invalid("invalid_kubernetes_name", "invalid kubernetes name")
}
