import { useState } from 'react'
import { useFeedback } from './feedback.tsx'

// The list of containers, queues or tables of a tab, with create and delete.

type Item = { name: string; info?: string }

type Props = {
  title: string
  noun: string
  items: Item[]
  selected: string
  hrefOf: (name: string) => string
  /** Naming rule shown under the create field. */
  rule: string
  onCreate: (name: string) => Promise<void>
  onDelete: (name: string) => Promise<void>
}

export function Sidebar({ title, noun, items, selected, hrefOf, rule, onCreate, onDelete }: Props) {
  const fb = useFeedback()
  const [name, setName] = useState('')
  const [filter, setFilter] = useState('')
  const [busy, setBusy] = useState(false)
  const shown = items.filter(it => it.name.toLowerCase().includes(filter.toLowerCase()))

  async function create() {
    const n = name.trim()
    if (!n) return
    setBusy(true)
    try {
      await onCreate(n)
      fb.ok(`Created ${noun} ${n}.`)
      setName('')
    } catch (err) {
      fb.error(err, `Create ${n}`)
    } finally {
      setBusy(false)
    }
  }

  async function remove(n: string) {
    const ok = await fb.confirm({
      title: `Delete ${noun} ${n}?`,
      message: <p>Everything inside is deleted with it, for good.</p>,
      typeToConfirm: n,
      confirmLabel: 'Delete',
    })
    if (!ok) return
    try {
      await onDelete(n)
      fb.ok(`Deleted ${noun} ${n}.`)
    } catch (err) {
      fb.error(err, `Delete ${n}`)
    }
  }

  return (
    <aside className="sidebar panel">
      <header className="panel-header">
        <h2>{title}</h2>
        <span className="muted small">{items.length}</span>
      </header>
      <form
        className="create"
        onSubmit={e => {
          e.preventDefault()
          void create()
        }}
      >
        <input
          placeholder={`${noun[0].toUpperCase()}${noun.slice(1)} name`}
          value={name}
          onChange={e => setName(e.target.value)}
          spellCheck={false}
        />
        <button type="submit" disabled={busy || !name.trim()}>
          Create
        </button>
      </form>
      <p className="muted small rule">{rule}</p>
      {items.length > 8 && (
        <input type="search" placeholder="Filter" value={filter} onChange={e => setFilter(e.target.value)} />
      )}
      {shown.length === 0 ? (
        <p className="empty">Nothing here.</p>
      ) : (
        <ul className="list nav-list">
          {shown.map(it => (
            <li key={it.name} className={it.name === selected ? 'selected' : ''}>
              <a href={hrefOf(it.name)} className="mono">
                {it.name}
              </a>
              {it.info && <span className="muted small">{it.info}</span>}
              <button
                type="button"
                className="icon danger-text"
                title={`Delete ${it.name}`}
                onClick={() => void remove(it.name)}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
    </aside>
  )
}
