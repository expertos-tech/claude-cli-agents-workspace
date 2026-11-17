package api

import (
	"net/http"

	"azurite-console/internal/httpjson"

	"azurite-console/internal/storage"
)

// maxSeconds is the longest visibility or delay the Queue service accepts: 7 days.
const maxSeconds = 7 * 24 * 3600

// queues lists the queues with their approximate message counts.
func (h *Handler) queues(w http.ResponseWriter, r *http.Request) {
	out, err := h.cfg.Queues.List(r.Context())
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

// createQueue creates the queue named in the body.
func (h *Handler) createQueue(w http.ResponseWriter, r *http.Request) {
	var in named
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if err := in.validate(); err != nil {
		fail(w, r, err)
		return
	}
	if err := h.cfg.Queues.Create(r.Context(), in.Name); err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusCreated, in)
}

// deleteQueue deletes the queue.
func (h *Handler) deleteQueue(w http.ResponseWriter, r *http.Request) {
	if err := h.cfg.Queues.Delete(r.Context(), r.PathValue("q")); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}

// clearQueue removes every message of the queue.
func (h *Handler) clearQueue(w http.ResponseWriter, r *http.Request) {
	if err := h.cfg.Queues.Clear(r.Context(), r.PathValue("q")); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}

// peek answers messages without taking them from the queue.
func (h *Handler) peek(w http.ResponseWriter, r *http.Request) {
	n, err := intQuery(r, "n", storage.MaxMessages, 1, storage.MaxMessages)
	if err != nil {
		fail(w, r, err)
		return
	}
	out, err := h.cfg.Queues.Peek(r.Context(), r.PathValue("q"), int32(n)) //nolint:gosec // bounded by MaxMessages
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

type receiveRequest struct {
	Count             int32 `json:"count"`
	VisibilitySeconds int32 `json:"visibility_seconds"`
}

// receive takes messages, which stay invisible to others for the given time.
func (h *Handler) receive(w http.ResponseWriter, r *http.Request) {
	var in receiveRequest
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if err := inRange("count", in.Count, 1, storage.MaxMessages); err != nil {
		fail(w, r, err)
		return
	}
	if err := inRange("visibility_seconds", in.VisibilitySeconds, 1, maxSeconds); err != nil {
		fail(w, r, err)
		return
	}
	out, err := h.cfg.Queues.Receive(r.Context(), r.PathValue("q"), in.Count, in.VisibilitySeconds)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

type sendRequest struct {
	Text         string `json:"text"`
	DelaySeconds int32  `json:"delay_seconds"`
	// TTLSeconds zero keeps the default of the service (7 days); -1 never expires.
	TTLSeconds int32 `json:"ttl_seconds"`
}

// send adds a message with the given delay and time to live.
func (h *Handler) send(w http.ResponseWriter, r *http.Request) {
	var in sendRequest
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if err := inRange("delay_seconds", in.DelaySeconds, 0, maxSeconds); err != nil {
		fail(w, r, err)
		return
	}
	if in.TTLSeconds < -1 {
		fail(w, r, badRequest("ttl_seconds", httpjson.FieldInvalid))
		return
	}
	if err := h.cfg.Queues.Send(r.Context(), r.PathValue("q"), in.Text, in.DelaySeconds, in.TTLSeconds); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}

type updateMessageRequest struct {
	PopReceipt        string `json:"pop_receipt"`
	Text              string `json:"text"`
	VisibilitySeconds int32  `json:"visibility_seconds"`
}

// updateMessage changes the text of a received message; visibility zero
// returns it to the queue at once.
func (h *Handler) updateMessage(w http.ResponseWriter, r *http.Request) {
	var in updateMessageRequest
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if in.PopReceipt == "" {
		fail(w, r, badRequest("pop_receipt", httpjson.FieldRequired))
		return
	}
	if err := inRange("visibility_seconds", in.VisibilitySeconds, 0, maxSeconds); err != nil {
		fail(w, r, err)
		return
	}
	out, err := h.cfg.Queues.Update(r.Context(), r.PathValue("q"), r.PathValue("id"), in.PopReceipt, in.Text, in.VisibilitySeconds)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpjson.WriteJSON(w, r, http.StatusOK, out)
}

// deleteMessage deletes a received message, by its pop receipt.
func (h *Handler) deleteMessage(w http.ResponseWriter, r *http.Request) {
	receipt := r.URL.Query().Get("pop_receipt")
	if receipt == "" {
		fail(w, r, badRequest("pop_receipt", httpjson.FieldRequired))
		return
	}
	if err := h.cfg.Queues.DeleteMessage(r.Context(), r.PathValue("q"), r.PathValue("id"), receipt); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}

type moveRequest struct {
	PopReceipt string `json:"pop_receipt"`
	Text       string `json:"text"`
	To         string `json:"to"`
}

// moveMessage sends a received message to another queue and removes it from this one.
func (h *Handler) moveMessage(w http.ResponseWriter, r *http.Request) {
	var in moveRequest
	if err := decode(r, &in); err != nil {
		fail(w, r, err)
		return
	}
	switch {
	case in.PopReceipt == "":
		fail(w, r, badRequest("pop_receipt", httpjson.FieldRequired))
		return
	case in.To == "":
		fail(w, r, badRequest("to", httpjson.FieldRequired))
		return
	case in.To == r.PathValue("q"):
		fail(w, r, badRequest("to", httpjson.FieldInvalid))
		return
	}
	if err := h.cfg.Queues.Move(r.Context(), r.PathValue("q"), r.PathValue("id"), in.PopReceipt, in.Text, in.To); err != nil {
		fail(w, r, err)
		return
	}
	noContent(w, r)
}
