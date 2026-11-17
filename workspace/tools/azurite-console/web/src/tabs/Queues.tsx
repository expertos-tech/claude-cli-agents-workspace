import { useCallback, useEffect, useState } from 'react'
import { api, errorText, type Message, type Queue } from '../api.ts'
import { decodeBase64, formatCount, formatTime, parseJSON, plural, secondsUntil } from '../format.ts'
import { go, href, type Route } from '../route.ts'
import { useFeedback } from '../ui/feedback.tsx'
import { JsonView } from '../ui/JsonView.tsx'
import { Sidebar } from '../ui/Sidebar.tsx'

// From this many deliveries a message is probably failing every time.
const poisonCount = 5

export function Queues({ route, tick, onChange }: { route: Route; tick: number; onChange: () => void }) {
  const fb = useFeedback()
  const [queues, setQueues] = useState<Queue[]>([])
  const name = route.resource

  const loadQueues = useCallback(
    async (signal?: AbortSignal) => {
      try {
        setQueues(await api.queues(signal))
      } catch (err) {
        if (!signal?.aborted) fb.error(err, 'List queues')
      }
    },
    [fb],
  )

  // biome-ignore lint/correctness/useExhaustiveDependencies: tick is the trigger of the refresh that lists the queues again
  useEffect(() => {
    const ctrl = new AbortController()
    void loadQueues(ctrl.signal)
    return () => ctrl.abort()
  }, [loadQueues, tick])

  const current = queues.find(q => q.name === name)
  const changed = () => {
    void loadQueues()
    onChange()
  }

  return (
    <div className="split">
      <Sidebar
        title="Queues"
        noun="queue"
        items={queues.map(q => ({ name: q.name, info: formatCount(q.messages) }))}
        selected={name}
        hrefOf={n => href('queues', n)}
        rule="3 to 63 characters: lowercase letters, digits and hyphens."
        onCreate={async n => {
          await api.createQueue(n)
          changed()
          go('queues', n)
        }}
        onDelete={async n => {
          await api.deleteQueue(n)
          changed()
          if (n === name) go('queues')
        }}
      />
      {name ? (
        <QueuePanel
          key={name}
          name={name}
          count={current?.messages}
          others={queues.map(q => q.name).filter(q => q !== name)}
          tick={tick}
          onChange={changed}
        />
      ) : (
        <p className="empty grow">Choose a queue.</p>
      )}
    </div>
  )
}

function QueuePanel(props: { name: string; count?: number; others: string[]; tick: number; onChange: () => void }) {
  const { name, count, others, tick, onChange } = props
  const fb = useFeedback()
  const [peeked, setPeeked] = useState<Message[] | null>(null)
  const [peekError, setPeekError] = useState<string | null>(null)
  const [received, setReceived] = useState<Message[]>([])
  const [receiveCount, setReceiveCount] = useState(1)
  const [visibility, setVisibility] = useState(30)

  const peek = useCallback(
    async (signal?: AbortSignal) => {
      try {
        setPeeked(await api.peek(name, 32, signal))
        setPeekError(null)
      } catch (err) {
        if (!signal?.aborted) setPeekError(errorText(err))
      }
    },
    [name],
  )

  // biome-ignore lint/correctness/useExhaustiveDependencies: tick is the trigger of the refresh that peeks the messages again
  useEffect(() => {
    const ctrl = new AbortController()
    void peek(ctrl.signal)
    return () => ctrl.abort()
  }, [peek, tick])

  const changed = () => {
    void peek()
    onChange()
  }

  async function receive() {
    try {
      const got = await api.receive(name, receiveCount, visibility)
      if (got.length === 0) fb.ok('No visible messages to receive.')
      setReceived(r => [...got, ...r.filter(m => !got.some(g => g.id === m.id))])
      changed()
    } catch (err) {
      fb.error(err, 'Receive')
    }
  }

  async function clear() {
    const ok = await fb.confirm({
      title: `Clear queue ${name}?`,
      message: <p>Deletes every message, including received ones still invisible. The queue stays.</p>,
      typeToConfirm: name,
      confirmLabel: 'Clear',
    })
    if (!ok) return
    try {
      await api.clearQueue(name)
      setReceived([])
      fb.ok(`Cleared queue ${name}.`)
      changed()
    } catch (err) {
      fb.error(err, `Clear ${name}`)
    }
  }

  const drop = (id: string) => setReceived(r => r.filter(m => m.id !== id))
  const replace = (m: Message) => setReceived(r => r.map(x => (x.id === m.id ? m : x)))

  return (
    <section className="grow stack">
      <div className="panel">
        <header className="panel-header wrap-row">
          <h2 className="mono">{name}</h2>
          <span className="muted">
            {count === undefined ? '' : `${formatCount(count)} ${plural(count, 'message')}, approximate`}
          </span>
          <div className="actions">
            <button type="button" className="secondary" onClick={() => void peek()}>
              Peek again
            </button>
            <button type="button" className="danger" onClick={() => void clear()}>
              Clear queue
            </button>
          </div>
        </header>
        <div className="columns2">
          <SendForm name={name} onSent={changed} />
          <form
            className="form"
            onSubmit={e => {
              e.preventDefault()
              void receive()
            }}
          >
            <h3>Receive</h3>
            <p className="muted small">
              Hides the messages from other consumers for the chosen time and gives the receipt to delete, return, edit
              or move them.
            </p>
            <div className="row">
              <label className="field">
                <span>How many (1 to 32)</span>
                <input
                  type="number"
                  min={1}
                  max={32}
                  value={receiveCount}
                  onChange={e => setReceiveCount(Number(e.target.value))}
                />
              </label>
              <label className="field">
                <span>Invisible for (s)</span>
                <input
                  type="number"
                  min={1}
                  max={604800}
                  value={visibility}
                  onChange={e => setVisibility(Number(e.target.value))}
                />
              </label>
            </div>
            <button type="submit">Receive</button>
          </form>
        </div>
      </div>

      {received.length > 0 && (
        <div className="panel">
          <header className="panel-header">
            <h2>Received</h2>
            <span className="muted small">
              With a receipt. When the time is up they return to the queue and the receipt stops being valid.
            </span>
          </header>
          <div className="messages">
            {received.map(m => (
              <ReceivedMessage
                key={m.id}
                queue={name}
                message={m}
                others={others}
                onGone={() => drop(m.id)}
                onUpdated={replace}
                onChange={changed}
              />
            ))}
          </div>
        </div>
      )}

      <div className="panel">
        <header className="panel-header">
          <h2>Visible</h2>
          <span className="muted small">Peek shows up to 32 messages without taking them off the queue.</span>
        </header>
        {peekError && <p className="error">{peekError}</p>}
        {peeked && peeked.length === 0 ? (
          <p className="empty">No visible messages.</p>
        ) : (
          <div className="messages">
            {(peeked ?? []).map(m => (
              <div key={m.id} className="message">
                <MessageHeader m={m} />
                <MessageText text={m.text} />
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  )
}

function SendForm({ name, onSent }: { name: string; onSent: () => void }) {
  const fb = useFeedback()
  const [text, setText] = useState('')
  const [checkJSON, setCheckJSON] = useState(true)
  const [delay, setDelay] = useState(0)
  const [ttl, setTTL] = useState('')
  const invalid = checkJSON && text.trim() !== '' && !parseJSON(text).ok

  async function send() {
    try {
      await api.send(name, text, delay, ttl === '' ? 0 : Number(ttl))
      fb.ok(`Message sent to ${name}.`)
      setText('')
      onSent()
    } catch (err) {
      fb.error(err, 'Send')
    }
  }

  return (
    <form
      className="form"
      onSubmit={e => {
        e.preventDefault()
        void send()
      }}
    >
      <h3>Send message</h3>
      <textarea
        rows={5}
        value={text}
        onChange={e => setText(e.target.value)}
        placeholder='{"id": "example"}'
        spellCheck={false}
      />
      {invalid && <p className="error small">Not valid JSON.</p>}
      <div className="row">
        <label className="check">
          <input type="checkbox" checked={checkJSON} onChange={e => setCheckJSON(e.target.checked)} />
          check JSON
        </label>
        <label className="field">
          <span>Delay (s)</span>
          <input type="number" min={0} max={604800} value={delay} onChange={e => setDelay(Number(e.target.value))} />
        </label>
        <label className="field">
          <span>TTL (s)</span>
          <input
            type="number"
            min={-1}
            placeholder="7 days; -1 never"
            value={ttl}
            onChange={e => setTTL(e.target.value)}
          />
        </label>
      </div>
      <button type="submit" disabled={invalid}>
        Send
      </button>
    </form>
  )
}

function MessageHeader({ m, now }: { m: Message; now?: number }) {
  return (
    <div className="message-head">
      <span className="mono small">{m.id}</span>
      <span
        className={m.dequeue_count >= poisonCount ? 'badge badge-error' : 'badge'}
        title="Times the message was received"
      >
        received {m.dequeue_count}x
      </span>
      <span className="muted small">inserted {formatTime(m.inserted)}</span>
      <span className="muted small">expires {formatTime(m.expires)}</span>
      {now !== undefined && m.next_visible && (
        <span className="badge badge-warn">
          {secondsUntil(m.next_visible, now) > 0
            ? `returns in ${secondsUntil(m.next_visible, now)} s`
            : 'back in the queue'}
        </span>
      )}
    </div>
  )
}

function MessageText({ text }: { text: string }) {
  const [decode, setDecode] = useState(false)
  const decoded = decodeBase64(text)
  const shown = decode && decoded !== null ? decoded : text
  const parsed = parseJSON(shown)
  return (
    <div>
      {decoded !== null && (
        <label className="check small">
          <input type="checkbox" checked={decode} onChange={e => setDecode(e.target.checked)} />
          decode base64
        </label>
      )}
      {parsed.ok && typeof parsed.value === 'object' && parsed.value !== null ? (
        <JsonView value={parsed.value} />
      ) : (
        <pre className="json">{shown}</pre>
      )}
    </div>
  )
}

function ReceivedMessage(props: {
  queue: string
  message: Message
  others: string[]
  onGone: () => void
  onUpdated: (m: Message) => void
  onChange: () => void
}) {
  const { queue, message: m, others, onGone, onUpdated, onChange } = props
  const fb = useFeedback()
  const [now, setNow] = useState(() => Date.now())
  const [editing, setEditing] = useState(false)
  const [text, setText] = useState(m.text)
  const [editVisibility, setEditVisibility] = useState(0)
  const [to, setTo] = useState('')
  // The list of queues may arrive after the message; the first one is the default.
  const target = others.includes(to) ? to : (others[0] ?? '')

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])

  const receipt = m.pop_receipt ?? ''

  async function act(label: string, fn: () => Promise<void>) {
    try {
      await fn()
      onChange()
    } catch (err) {
      fb.error(err, label)
    }
  }

  return (
    <div className="message">
      <MessageHeader m={m} now={now} />
      {editing ? (
        <div className="form">
          <textarea rows={5} value={text} onChange={e => setText(e.target.value)} spellCheck={false} />
          <div className="row">
            <label className="field">
              <span>Returns to the queue in (s)</span>
              <input
                type="number"
                min={0}
                max={604800}
                value={editVisibility}
                onChange={e => setEditVisibility(Number(e.target.value))}
              />
            </label>
            <button
              type="button"
              onClick={() =>
                void act('Save', async () => {
                  const r = await api.updateMessage(queue, m.id, receipt, text, editVisibility)
                  fb.ok('Message updated.')
                  setEditing(false)
                  if (editVisibility === 0) onGone()
                  else onUpdated({ ...m, text, pop_receipt: r.pop_receipt, next_visible: r.next_visible })
                })
              }
            >
              Save
            </button>
            <button type="button" className="secondary" onClick={() => setEditing(false)}>
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <MessageText text={m.text} />
      )}
      {!editing && (
        <div className="actions">
          <button
            type="button"
            className="danger"
            onClick={() =>
              void act('Delete', async () => {
                await api.deleteMessage(queue, m.id, receipt)
                fb.ok('Message deleted.')
                onGone()
              })
            }
          >
            Delete
          </button>
          <button
            type="button"
            className="secondary"
            onClick={() =>
              void act('Return', async () => {
                await api.updateMessage(queue, m.id, receipt, m.text, 0)
                fb.ok('Message returned to the queue.')
                onGone()
              })
            }
          >
            Return
          </button>
          <button type="button" className="secondary" onClick={() => setEditing(true)}>
            Edit
          </button>
          {others.length > 0 && (
            <span className="row">
              <select value={target} onChange={e => setTo(e.target.value)} aria-label="Target queue">
                {others.map(q => (
                  <option key={q} value={q}>
                    {q}
                  </option>
                ))}
              </select>
              <button
                type="button"
                className="secondary"
                disabled={!target}
                onClick={() =>
                  void act('Move', async () => {
                    await api.moveMessage(queue, m.id, receipt, m.text, target)
                    fb.ok(`Message moved to ${target}.`)
                    onGone()
                  })
                }
              >
                Move
              </button>
            </span>
          )}
        </div>
      )}
    </div>
  )
}
