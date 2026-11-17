import { useCallback, useEffect, useMemo, useState } from 'react'
import { ApiError, api, type EntityPage, type EntityValue, type Table } from '../api.ts'
import { embeddedJSON, formatTime, parseJSON, plural } from '../format.ts'
import { go, href, type Route } from '../route.ts'
import { useFeedback } from '../ui/feedback.tsx'
import { JsonView } from '../ui/JsonView.tsx'
import { Sidebar } from '../ui/Sidebar.tsx'

const pageSizes = [20, 100, 500, 1000]
const examples = [
  "PartitionKey eq 'example'",
  "PartitionKey eq 'example' and RowKey ge 'a' and RowKey lt 'b'",
  "Timestamp ge datetime'2026-11-16T00:00:00Z'",
  "Status eq 'PENDING'",
]
const fixedColumns = ['PartitionKey', 'RowKey', 'Timestamp']

/** The properties that are data, without the keys, Timestamp and the OData annotations. */
function dataKeys(e: EntityValue): string[] {
  return Object.keys(e).filter(k => !k.startsWith('odata.') && !k.endsWith('@odata.type') && !fixedColumns.includes(k))
}

function keyOf(e: EntityValue): string {
  return JSON.stringify([e.PartitionKey, e.RowKey])
}

function cell(v: unknown): string {
  if (v === null || v === undefined) return ''
  const s = typeof v === 'string' ? v : JSON.stringify(v)
  return s.length > 80 ? `${s.slice(0, 80)}…` : s
}

/** The entity as it is edited: without odata.etag, which goes apart as the version read. */
function editable(e: EntityValue): string {
  const copy: EntityValue = {}
  for (const [k, v] of Object.entries(e)) {
    if (!k.startsWith('odata.')) copy[k] = v
  }
  return JSON.stringify(copy, null, 2)
}

export function Tables({ route, onChange }: { route: Route; onChange: () => void }) {
  const fb = useFeedback()
  const [tables, setTables] = useState<Table[]>([])
  const name = route.resource

  const loadTables = useCallback(async () => {
    try {
      setTables(await api.tables())
    } catch (err) {
      fb.error(err, 'List tables')
    }
  }, [fb])

  useEffect(() => {
    void loadTables()
  }, [loadTables])

  return (
    <div className="split">
      <Sidebar
        title="Tables"
        noun="table"
        items={tables.map(t => ({ name: t.name }))}
        selected={name}
        hrefOf={n => href('tables', n)}
        rule="3 to 63 characters: letters and digits, starting with a letter."
        onCreate={async n => {
          await api.createTable(n)
          await loadTables()
          onChange()
          go('tables', n)
        }}
        onDelete={async n => {
          await api.deleteTable(n)
          await loadTables()
          onChange()
          if (n === name) go('tables')
        }}
      />
      {name ? <TablePanel key={name} name={name} onChange={onChange} /> : <p className="empty grow">Choose a table.</p>}
    </div>
  )
}

type Editor = { isNew: boolean; text: string; etag: string; error: string | null; conflict: boolean }

function TablePanel({ name, onChange }: { name: string; onChange: () => void }) {
  const fb = useFeedback()
  const [draft, setDraft] = useState('')
  const [filter, setFilter] = useState('')
  const [top, setTop] = useState(100)
  // pages holds the continuation of each page read, to go forward and back.
  const [pages, setPages] = useState<{ pk?: string; rk?: string }[]>([{}])
  const [page, setPage] = useState<EntityPage | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [editor, setEditor] = useState<Editor | null>(null)
  const current = pages[pages.length - 1]

  const load = useCallback(async () => {
    setLoading(true)
    try {
      setPage(await api.entities(name, filter, top, current.pk, current.rk))
      setError(null)
    } catch (err) {
      setError(err instanceof ApiError ? [err.message, err.detail].filter(Boolean).join(': ') : String(err))
      setPage(null)
    } finally {
      setLoading(false)
    }
  }, [name, filter, top, current])

  useEffect(() => {
    setSelected(new Set())
    void load()
  }, [load])

  const entities = page?.entities ?? []
  const columns = useMemo(() => {
    const set = new Set<string>()
    for (const e of entities) for (const k of dataKeys(e)) set.add(k)
    return [...set].sort()
  }, [entities])

  const changed = () => {
    setSelected(new Set())
    void load()
    onChange()
  }

  function apply() {
    setFilter(draft.trim())
    setPages([{}])
  }

  async function deleteSelected() {
    const keys = entities.filter(e => selected.has(keyOf(e)))
    const ok = await fb.confirm({
      title: `Delete ${keys.length} ${plural(keys.length, 'entity', 'entities')}?`,
      message: <p>From {name}, whatever their version.</p>,
      confirmLabel: 'Delete',
    })
    if (!ok) return
    let done = 0
    for (const e of keys) {
      try {
        await api.deleteEntity(name, String(e.PartitionKey), String(e.RowKey))
        done++
      } catch (err) {
        fb.error(err, 'Delete entity')
        break
      }
    }
    if (done) fb.ok(`Deleted ${done} ${plural(done, 'entity', 'entities')}.`)
    changed()
  }

  async function deleteByFilter() {
    let count: number
    try {
      count = (await api.deleteByFilter(name, filter, true)).count
    } catch (err) {
      fb.error(err, 'Count')
      return
    }
    const ok = await fb.confirm({
      title: `Delete ${count} ${plural(count, 'entity', 'entities')}?`,
      message: filter ? (
        <p>
          All that the filter <code>{filter}</code> matches, not only those on this page.
        </p>
      ) : (
        <p>No filter: every entity of {name}. The table stays.</p>
      ),
      typeToConfirm: filter ? undefined : name,
      confirmLabel: 'Delete',
    })
    if (!ok) return
    try {
      const r = await api.deleteByFilter(name, filter, false)
      fb.ok(`Deleted ${r.count} ${plural(r.count, 'entity', 'entities')}.`)
    } catch (err) {
      fb.error(err, 'Delete by filter')
    }
    setPages([{}])
    changed()
  }

  function exportPage() {
    const blob = new Blob([JSON.stringify(entities, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${name}-page-${pages.length}.json`
    a.click()
    URL.revokeObjectURL(url)
  }

  const allSelected = entities.length > 0 && entities.every(e => selected.has(keyOf(e)))

  return (
    <section className="grow stack">
      <div className="panel">
        <header className="panel-header wrap-row">
          <h2 className="mono">{name}</h2>
          <div className="actions">
            <button
              type="button"
              onClick={() =>
                setEditor({
                  isNew: true,
                  text: JSON.stringify({ PartitionKey: '', RowKey: '' }, null, 2),
                  etag: '',
                  error: null,
                  conflict: false,
                })
              }
            >
              New entity
            </button>
            <button
              type="button"
              className="danger"
              disabled={selected.size === 0}
              onClick={() => void deleteSelected()}
            >
              Delete selected ({selected.size})
            </button>
            <button type="button" className="danger" onClick={() => void deleteByFilter()}>
              {filter ? 'Delete all matching' : 'Delete all'}
            </button>
            <button type="button" className="secondary" disabled={entities.length === 0} onClick={exportPage}>
              Export page
            </button>
          </div>
        </header>
        <form
          className="filters"
          onSubmit={e => {
            e.preventDefault()
            apply()
          }}
        >
          <input
            className="grow mono"
            list="filter-examples"
            placeholder="OData filter, for example PartitionKey eq 'x'"
            value={draft}
            onChange={e => setDraft(e.target.value)}
            spellCheck={false}
          />
          <datalist id="filter-examples">
            {examples.map(x => (
              <option key={x} value={x} />
            ))}
          </datalist>
          <label className="field-inline">
            Per page
            <select
              value={top}
              onChange={e => {
                setTop(Number(e.target.value))
                setPages([{}])
              }}
            >
              {pageSizes.map(n => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </label>
          <button type="submit" disabled={loading}>
            Query
          </button>
          <button type="button" className="secondary" onClick={() => void load()} disabled={loading}>
            Refresh
          </button>
        </form>
        {error && <p className="error">{error}</p>}
        {page && entities.length === 0 ? (
          <p className="empty">No entities{filter ? ' for this filter' : ''}.</p>
        ) : (
          <div className="table-wrap scroll">
            <table>
              <thead>
                <tr>
                  <th className="check-col">
                    <input
                      type="checkbox"
                      aria-label="Select all"
                      checked={allSelected}
                      onChange={e => setSelected(e.target.checked ? new Set(entities.map(keyOf)) : new Set())}
                    />
                  </th>
                  {fixedColumns.map(c => (
                    <th key={c}>{c}</th>
                  ))}
                  {columns.map(c => (
                    <th key={c}>{c}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {entities.map(e => {
                  const k = keyOf(e)
                  return (
                    <tr key={k}>
                      <td className="check-col">
                        <input
                          type="checkbox"
                          aria-label="Select"
                          checked={selected.has(k)}
                          onChange={ev => {
                            const next = new Set(selected)
                            if (ev.target.checked) next.add(k)
                            else next.delete(k)
                            setSelected(next)
                          }}
                        />
                      </td>
                      <td className="mono">
                        <button
                          type="button"
                          className="link"
                          onClick={() =>
                            setEditor({
                              isNew: false,
                              text: editable(e),
                              etag: String(e['odata.etag'] ?? ''),
                              error: null,
                              conflict: false,
                            })
                          }
                        >
                          {cell(e.PartitionKey) || '(empty)'}
                        </button>
                      </td>
                      <td className="mono">{cell(e.RowKey)}</td>
                      <td>{formatTime(typeof e.Timestamp === 'string' ? e.Timestamp : undefined)}</td>
                      {columns.map(c => (
                        <td
                          key={c}
                          className="mono small"
                          title={typeof e[c] === 'string' ? (e[c] as string) : JSON.stringify(e[c])}
                        >
                          {cell(e[c])}
                        </td>
                      ))}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
        <div className="more">
          <span className="muted small">
            Page {pages.length} · {entities.length} {plural(entities.length, 'entity', 'entities')}
          </span>
          <button
            type="button"
            className="secondary"
            disabled={pages.length === 1 || loading}
            onClick={() => setPages([{}])}
          >
            First
          </button>
          <button
            type="button"
            className="secondary"
            disabled={pages.length === 1 || loading}
            onClick={() => setPages(p => p.slice(0, -1))}
          >
            Previous
          </button>
          <button
            type="button"
            className="secondary"
            disabled={!page?.next_partition_key || loading}
            onClick={() => setPages(p => [...p, { pk: page?.next_partition_key, rk: page?.next_row_key }])}
          >
            Next
          </button>
        </div>
      </div>
      {editor && (
        <EntityEditor
          table={name}
          editor={editor}
          setEditor={setEditor}
          onSaved={() => {
            void load()
            onChange()
          }}
        />
      )}
    </section>
  )
}

function EntityEditor(props: {
  table: string
  editor: Editor
  setEditor: (e: Editor | null) => void
  onSaved: () => void
}) {
  const { table, editor, setEditor, onSaved } = props
  const fb = useFeedback()
  const [mode, setMode] = useState<'merge' | 'replace'>('merge')
  const parsed = parseJSON(editor.text)
  const value =
    parsed.ok && typeof parsed.value === 'object' && parsed.value !== null && !Array.isArray(parsed.value)
      ? (parsed.value as EntityValue)
      : null
  const embedded = value ? Object.entries(value).filter(([, v]) => embeddedJSON(v) !== null) : []

  function set(patch: Partial<Editor>) {
    setEditor({ ...editor, ...patch })
  }

  async function run(label: string, fn: (v: EntityValue) => Promise<void>) {
    if (!value) return
    try {
      await fn(value)
      onSaved()
    } catch (err) {
      if (err instanceof ApiError) {
        set({ error: [err.message, err.detail].filter(Boolean).join(': '), conflict: err.status === 412 })
      }
      fb.error(err, label)
    }
  }

  async function reload() {
    if (!value) return
    try {
      const e = await api.entity(table, String(value.PartitionKey), String(value.RowKey))
      setEditor({ isNew: false, text: editable(e.value), etag: e.etag, error: null, conflict: false })
    } catch (err) {
      fb.error(err, 'Reload')
    }
  }

  async function remove() {
    if (!value) return
    const ok = await fb.confirm({
      title: 'Delete the entity?',
      message: (
        <p className="mono">
          ({String(value.PartitionKey)}, {String(value.RowKey)})
        </p>
      ),
      confirmLabel: 'Delete',
    })
    if (!ok) return
    await run('Delete', async v => {
      await api.deleteEntity(table, String(v.PartitionKey), String(v.RowKey), editor.etag)
      fb.ok('Entity deleted.')
      setEditor(null)
    })
  }

  return (
    <div className="panel">
      <header className="panel-header wrap-row">
        <h2>{editor.isNew ? 'New entity' : 'Entity'}</h2>
        {!editor.isNew && <span className="mono muted small">ETag {editor.etag}</span>}
        <div className="actions">
          {!editor.isNew && (
            <>
              <label className="field-inline">
                Save as
                <select value={mode} onChange={e => setMode(e.target.value as 'merge' | 'replace')}>
                  <option value="merge">merge (keeps the other properties)</option>
                  <option value="replace">replace (keeps only what is here)</option>
                </select>
              </label>
              <button
                type="button"
                disabled={!value}
                onClick={() =>
                  void run('Save', async v => {
                    const r = await api.updateEntity(table, v, editor.etag, mode)
                    fb.ok('Entity saved.')
                    set({ etag: r.etag, error: null, conflict: false })
                  })
                }
              >
                Save
              </button>
            </>
          )}
          <button
            type="button"
            className={editor.isNew ? '' : 'secondary'}
            disabled={!value}
            onClick={() =>
              void run('Insert', async v => {
                const r = await api.insertEntity(table, v)
                fb.ok('Entity inserted.')
                set({ isNew: false, etag: r.etag, error: null, conflict: false })
              })
            }
          >
            {editor.isNew ? 'Insert' : 'Insert as new'}
          </button>
          {!editor.isNew && (
            <>
              <button type="button" className="secondary" onClick={() => void reload()}>
                Reload
              </button>
              <button type="button" className="danger" onClick={() => void remove()}>
                Delete
              </button>
            </>
          )}
          <button type="button" className="secondary" onClick={() => setEditor(null)}>
            Close
          </button>
        </div>
      </header>
      {editor.error && (
        <p className="error">
          {editor.error}
          {editor.conflict && (
            <>
              {' '}
              <button type="button" className="link" onClick={() => void reload()}>
                Reload the current version
              </button>
            </>
          )}
        </p>
      )}
      <p className="muted small">
        Types that JSON does not tell apart go in annotations, such as <code>"Total@odata.type": "Edm.Int64"</code> with
        the value as text; also <code>Edm.DateTime</code>, <code>Edm.Guid</code> and <code>Edm.Binary</code> (base64).{' '}
        <code>Timestamp</code> belongs to the service and is not written.
        {editor.isNew ? '' : ' To change PartitionKey or RowKey, use "Insert as new" and delete the old one.'}
      </p>
      <textarea
        className="editor"
        rows={16}
        value={editor.text}
        onChange={e => set({ text: e.target.value })}
        spellCheck={false}
      />
      {!parsed.ok && <p className="error small">Invalid JSON: {parsed.error}</p>}
      {parsed.ok && !value && <p className="error small">The entity must be a JSON object.</p>}
      {embedded.map(([k, v]) => (
        <div key={k}>
          <h3 className="small">
            <code>{k}</code> contains JSON
          </h3>
          <JsonView value={embeddedJSON(v)} />
        </div>
      ))}
    </div>
  )
}
