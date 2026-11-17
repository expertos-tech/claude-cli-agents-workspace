package storage

import (
	"context"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azqueue"
)

// MaxMessages is the most messages the Queue service returns in one peek or receive.
const MaxMessages = 32

// Queues operates the Queue service.
type Queues struct {
	client *azqueue.ServiceClient
}

// NewQueues returns the operations over client.
func NewQueues(client *azqueue.ServiceClient) *Queues { return &Queues{client: client} }

// Queue is one queue with its approximate message count.
type Queue struct {
	Name     string `json:"name"`
	Messages int32  `json:"messages"`
}

// Message is one message. PopReceipt and NextVisible come only with a
// received message.
type Message struct {
	ID           string     `json:"id"`
	Text         string     `json:"text"`
	Inserted     *time.Time `json:"inserted,omitempty"`
	Expires      *time.Time `json:"expires,omitempty"`
	DequeueCount int64      `json:"dequeue_count"`
	PopReceipt   string     `json:"pop_receipt,omitempty"`
	NextVisible  *time.Time `json:"next_visible,omitempty"`
}

// Receipt is the new pop receipt of an updated message.
type Receipt struct {
	PopReceipt  string     `json:"pop_receipt"`
	NextVisible *time.Time `json:"next_visible,omitempty"`
}

// Ping lists one queue, to know whether the service answers.
func (q *Queues) Ping(ctx context.Context) error {
	_, err := q.client.NewListQueuesPager(&azqueue.ListQueuesOptions{MaxResults: to.Ptr(int32(1))}).NextPage(ctx)
	return err
}

// List lists every queue with its approximate message count.
func (q *Queues) List(ctx context.Context) ([]Queue, error) {
	out := []Queue{}
	pager := q.client.NewListQueuesPager(nil)
	for pager.More() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		for _, item := range page.Queues {
			name := deref(item.Name)
			props, err := q.client.NewQueueClient(name).GetProperties(ctx, nil)
			if err != nil {
				return nil, err
			}
			out = append(out, Queue{Name: name, Messages: deref(props.ApproximateMessagesCount)})
		}
	}
	return out, nil
}

// Create creates queue name.
func (q *Queues) Create(ctx context.Context, name string) error {
	_, err := q.client.CreateQueue(ctx, name, nil)
	return err
}

// Delete deletes queue name and its messages.
func (q *Queues) Delete(ctx context.Context, name string) error {
	_, err := q.client.DeleteQueue(ctx, name, nil)
	return err
}

// Clear deletes every message of queue name.
func (q *Queues) Clear(ctx context.Context, name string) error {
	_, err := q.client.NewQueueClient(name).ClearMessages(ctx, nil)
	return err
}

// Peek returns up to n visible messages of queue name without taking them.
func (q *Queues) Peek(ctx context.Context, name string, n int32) ([]Message, error) {
	resp, err := q.client.NewQueueClient(name).PeekMessages(ctx, &azqueue.PeekMessagesOptions{NumberOfMessages: &n})
	if err != nil {
		return nil, err
	}
	out := make([]Message, 0, len(resp.Messages))
	for _, m := range resp.Messages {
		out = append(out, Message{
			ID: deref(m.MessageID), Text: deref(m.MessageText),
			Inserted: m.InsertionTime, Expires: m.ExpirationTime, DequeueCount: deref(m.DequeueCount),
		})
	}
	return out, nil
}

// Receive takes up to n messages of queue name, invisible to others for
// visibility seconds.
func (q *Queues) Receive(ctx context.Context, name string, n, visibility int32) ([]Message, error) {
	resp, err := q.client.NewQueueClient(name).DequeueMessages(ctx, &azqueue.DequeueMessagesOptions{NumberOfMessages: &n, VisibilityTimeout: &visibility})
	if err != nil {
		return nil, err
	}
	out := make([]Message, 0, len(resp.Messages))
	for _, m := range resp.Messages {
		out = append(out, Message{
			ID: deref(m.MessageID), Text: deref(m.MessageText),
			Inserted: m.InsertionTime, Expires: m.ExpirationTime, DequeueCount: deref(m.DequeueCount),
			PopReceipt: deref(m.PopReceipt), NextVisible: m.TimeNextVisible,
		})
	}
	return out, nil
}

// Send enqueues text in queue name, visible after delay seconds and kept
// for ttl seconds; zero keeps the default of the service and -1 is a ttl
// that never expires.
func (q *Queues) Send(ctx context.Context, name, text string, delay, ttl int32) error {
	opts := &azqueue.EnqueueMessageOptions{}
	if delay > 0 {
		opts.VisibilityTimeout = &delay
	}
	if ttl != 0 {
		opts.TimeToLive = &ttl
	}
	_, err := q.client.NewQueueClient(name).EnqueueMessage(ctx, text, opts)
	return err
}

// Update changes the text of a received message and makes it visible again
// after visibility seconds (zero returns it to the queue at once).
func (q *Queues) Update(ctx context.Context, name, id, popReceipt, text string, visibility int32) (Receipt, error) {
	resp, err := q.client.NewQueueClient(name).UpdateMessage(ctx, id, popReceipt, text, &azqueue.UpdateMessageOptions{VisibilityTimeout: &visibility})
	if err != nil {
		return Receipt{}, err
	}
	return Receipt{PopReceipt: deref(resp.PopReceipt), NextVisible: resp.TimeNextVisible}, nil
}

// DeleteMessage deletes a received message.
func (q *Queues) DeleteMessage(ctx context.Context, name, id, popReceipt string) error {
	_, err := q.client.NewQueueClient(name).DeleteMessage(ctx, id, popReceipt, nil)
	return err
}

// Move enqueues text in queue to and then deletes the received message of
// queue from. A failure on the delete leaves the message in both queues.
func (q *Queues) Move(ctx context.Context, from, id, popReceipt, text, to string) error {
	if err := q.Send(ctx, to, text, 0, 0); err != nil {
		return err
	}
	return q.DeleteMessage(ctx, from, id, popReceipt)
}
