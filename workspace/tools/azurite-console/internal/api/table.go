package api

import (
	"encoding/json"
	"math"
	"net/http"

	"azurite-console/internal/httpjson"

	"azurite-console/internal/storage"
)

// maxTop is the largest page the Table service returns.
const maxTop = 1000

// tables lists the tables.
func (h *Handler) tables(w http.ResponseWriter, r *http.Request) {
	out, err := h.cfg.Tables.List(r.Context())
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

// createTable creates the table named in the body.
func (h *Handler) createTable(w http.ResponseWriter, r *http.Request) {
	var in named
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if err := in.validate(); err != nil {
		fail(w, r, err)
		return
	}
	if err := h.cfg.Tables.Create(r.Context(), in.Name); err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusCreated, in)
}

// deleteTable deletes the table.
func (h *Handler) deleteTable(w http.ResponseWriter, r *http.Request) {
	if err := h.cfg.Tables.Delete(r.Context(), r.PathValue("t")); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}

// entities answers one page of the query on the table.
func (h *Handler) entities(w http.ResponseWriter, r *http.Request) {
	top, err := intQuery(r, "top", 100, 1, maxTop)
	if err != nil {
		fail(w, r, err)
		return
	}
	q := r.URL.Query()
	out, err := h.cfg.Tables.Query(r.Context(), r.PathValue("t"), storage.Query{
		Filter: q.Get("filter"), Top: int32(top), //nolint:gosec // bounded by maxTop
		NextPartitionKey: q.Get("next_pk"), NextRowKey: q.Get("next_rk"),
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

// entity answers one entity with its ETag.
func (h *Handler) entity(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	out, err := h.cfg.Tables.Get(r.Context(), r.PathValue("t"), q.Get("pk"), q.Get("rk"))
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

type entityRequest struct {
	Entity json.RawMessage `json:"entity"`
	// ETag is the version read; empty writes over any version.
	ETag string `json:"etag"`
	// Mode is merge (default) or replace.
	Mode string `json:"mode"`
}

type etagResponse struct {
	ETag string `json:"etag"`
}

// insertEntity adds the entity of the body and answers its ETag.
func (h *Handler) insertEntity(w http.ResponseWriter, r *http.Request) {
	var in entityRequest
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	etag, err := h.cfg.Tables.Insert(r.Context(), r.PathValue("t"), in.Entity)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusCreated, etagResponse{ETag: etag})
}

// updateEntity saves the entity of the body in merge or replace mode, against the ETag read.
func (h *Handler) updateEntity(w http.ResponseWriter, r *http.Request) {
	var in entityRequest
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if in.Mode != "" && in.Mode != "merge" && in.Mode != "replace" {
		fail(w, r, badRequest("mode", httpjson.FieldInvalid))
		return
	}
	etag, err := h.cfg.Tables.Update(r.Context(), r.PathValue("t"), in.Entity, in.ETag, in.Mode == "replace")
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, etagResponse{ETag: etag})
}

// deleteEntity deletes the entity named by pk and rk, against the ETag when given.
func (h *Handler) deleteEntity(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	if !q.Has("pk") || !q.Has("rk") {
		fail(w, r, badRequest("pk", httpjson.FieldRequired))
		return
	}
	if err := h.cfg.Tables.DeleteEntity(r.Context(), r.PathValue("t"), q.Get("pk"), q.Get("rk"), q.Get("etag")); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}

type deleteByFilterRequest struct {
	// Filter is an OData $filter; empty means every entity of the table.
	Filter string `json:"filter"`
	// DryRun only counts what would be deleted.
	DryRun bool `json:"dry_run"`
}

type countResponse struct {
	Count int `json:"count"`
}

// deleteByFilter deletes what the filter selects, or only counts it with dry_run.
func (h *Handler) deleteByFilter(w http.ResponseWriter, r *http.Request) {
	var in deleteByFilterRequest
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	ctx, name := r.Context(), r.PathValue("t")
	if in.DryRun {
		c, err := h.cfg.Tables.Count(ctx, name, in.Filter, math.MaxInt)
		if err != nil {
			fail(w, r, err)
			return
		}
		httpjson.WriteJSON(w, r, http.StatusOK, countResponse{Count: c.Count})
		return
	}
	n, err := h.cfg.Tables.DeleteByFilter(ctx, name, in.Filter)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, countResponse{Count: n})
}
