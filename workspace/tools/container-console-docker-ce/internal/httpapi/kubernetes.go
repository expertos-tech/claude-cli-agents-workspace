package httpapi

import (
	"context"
	"io"
	"net/http"

	"container-console-docker-ce/internal/fault"
	"container-console-docker-ce/internal/jobs"
	"container-console-docker-ce/internal/kube"
)

// kubernetesRoutes declares the routes of Kubernetes resources.
func (s *Server) kubernetesRoutes(mux *http.ServeMux) {
	handle(s, mux, "GET /api/kubernetes/namespaces/{name}", s.kubeInspectRoute(parseNamespaceTarget))
	handle(s, mux, "GET /api/kubernetes/{kind}/{namespace}/{name}", s.kubeInspectRoute(parseNamespacedTarget))
	handle(s, mux, "POST /api/kubernetes/namespaces/{name}/remove", s.kubeRemoveRoute(parseNamespaceTarget))
	handle(s, mux, "POST /api/kubernetes/{kind}/{namespace}/{name}/remove", s.kubeRemoveRoute(parseNamespacedTarget))
	handle(s, mux, "POST /api/kubernetes/deployments/{namespace}/{name}/scale", s.kubeScale)
	handle(s, mux, "POST /api/kubernetes/apply", s.kubeApply)
}

// targetParser reads a validated resource from the path of a request.
type targetParser func(r *http.Request) (kube.Target, error)

// parseNamespaceTarget reads a namespace from the path.
func parseNamespaceTarget(r *http.Request) (kube.Target, error) {
	return kube.ParseNamespace(r.PathValue("name"))
}

// parseNamespacedTarget reads a namespaced resource from the path.
func parseNamespacedTarget(r *http.Request) (kube.Target, error) {
	return kube.ParseNamespaced(r.PathValue("kind"), r.PathValue("namespace"), r.PathValue("name"))
}

// targetLabel names a resource in the job record.
func targetLabel(target kube.Target) string {
	if target.Namespace == "" {
		return string(target.Kind) + "/" + target.Name
	}
	return string(target.Kind) + "/" + target.Namespace + "/" + target.Name
}

// kubeInspectRoute builds the route that returns the raw JSON of a resource.
func (s *Server) kubeInspectRoute(parse targetParser) apiFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		target, err := parse(r)
		if err != nil {
			return err
		}
		if err := s.requireKubernetesReachable(r.Context()); err != nil {
			return err
		}
		details, err := s.Kube.Inspect(r.Context(), target)
		if err != nil {
			return err
		}
		writeJSON(w, http.StatusOK, details)
		return nil
	}
}

// kubeRemoveRoute builds the route that removes a resource, after explicit confirmation.
func (s *Server) kubeRemoveRoute(parse targetParser) apiFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		target, err := parse(r)
		if err != nil {
			return err
		}
		if err := decodeConfirmation(r, true); err != nil {
			return err
		}
		if err := s.requireKubernetesReachable(r.Context()); err != nil {
			return err
		}
		spec := jobs.Spec{Kind: "kubernetes.remove", Target: targetLabel(target)}
		return s.submit(w, spec, func(ctx context.Context, out io.Writer) error {
			return s.Kube.Delete(ctx, target, out)
		})
	}
}

// kubeScale changes the replicas of a deployment.
func (s *Server) kubeScale(w http.ResponseWriter, r *http.Request) error {
	target, err := kube.ParseNamespaced(string(kube.KindDeployment), r.PathValue("namespace"), r.PathValue("name"))
	if err != nil {
		return err
	}
	var body struct {
		Replicas *int `json:"replicas"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if body.Replicas == nil {
		return fault.Invalid("replicas_required", "replicas is required")
	}
	if err := s.Kube.ValidateReplicas(*body.Replicas); err != nil {
		return err
	}
	if err := s.requireKubernetesReachable(r.Context()); err != nil {
		return err
	}
	spec := jobs.Spec{Kind: "kubernetes.scale", Target: targetLabel(target)}
	return s.submit(w, spec, func(ctx context.Context, out io.Writer) error {
		return s.Kube.Scale(ctx, target, *body.Replicas, out)
	})
}

// kubeApply validates the YAML in the cluster and applies it only if the whole file passes.
func (s *Server) kubeApply(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		YAML string `json:"yaml"`
	}
	if err := decodeBody(r, &body); err != nil {
		return err
	}
	if body.YAML == "" {
		return fault.Invalid("yaml_empty", "the YAML is empty")
	}
	if err := s.requireKubernetesReachable(r.Context()); err != nil {
		return err
	}
	return s.submit(w, jobs.Spec{Kind: "kubernetes.apply", PrivateFailure: true}, func(ctx context.Context, out io.Writer) error {
		return s.Kube.Apply(ctx, []byte(body.YAML), out)
	})
}
