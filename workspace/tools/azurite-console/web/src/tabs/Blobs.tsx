import { useCallback, useEffect, useRef, useState } from 'react'
import {
  api,
  type BlobItem,
  type BlobProps,
  blobPath,
  type Container,
  errorText,
  type Listing,
  type Usage,
} from '../api.ts'
import { formatBytes, formatTime, parseJSON, plural } from '../format.ts'
import { go, href, type Route } from '../route.ts'
import { useFeedback } from '../ui/feedback.tsx'
import { JsonView } from '../ui/JsonView.tsx'
import { Sidebar } from '../ui/Sidebar.tsx'

const previewBytes = 256 * 1024
const textExt = /\.(json|txt|csv|log|xml|html?|md|ya?ml|ini|env|sql|js|ts)$/i
const imageTypes = /^image\/(png|jpeg|gif|webp)$/

export function Blobs({ route, onChange }: { route: Route; onChange: () => void }) {
  const fb = useFeedback()
  const [containers, setContainers] = useState<Container[]>([])
  const name = route.resource
  const folder = route.rest

  const loadContainers = useCallback(async () => {
    try {
      setContainers(await api.containers())
    } catch (err) {
      fb.error(err, 'List containers')
    }
  }, [fb])

  useEffect(() => {
    void loadContainers()
  }, [loadContainers])

  return (
    <div className="split">
      <Sidebar
        title="Containers"
        noun="container"
        items={containers.map(c => ({ name: c.name }))}
        selected={name}
        hrefOf={n => href('blobs', n)}
        rule="3 to 63 characters: lowercase letters, digits and hyphens."
        onCreate={async n => {
          await api.createContainer(n)
          await loadContainers()
          onChange()
          go('blobs', n)
        }}
        onDelete={async n => {
          await api.deleteContainer(n)
          await loadContainers()
          onChange()
          if (n === name) go('blobs')
        }}
      />
      {name ? (
        <Folder key={name} container={name} folder={folder} onChange={onChange} />
      ) : (
        <p className="empty grow">Choose a container.</p>
      )}
    </div>
  )
}

function Folder({ container, folder, onChange }: { container: string; folder: string; onChange: () => void }) {
  const fb = useFeedback()
  const [filter, setFilter] = useState('')
  const [listing, setListing] = useState<Listing | null>(null)
  const [loading, setLoading] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [detail, setDetail] = useState<string | null>(null)
  const [progress, setProgress] = useState('')
  const fileInput = useRef<HTMLInputElement>(null)

  const load = useCallback(
    async (marker?: string) => {
      setLoading(true)
      try {
        const page = await api.list(container, folder + filter, marker)
        setListing(prev =>
          marker && prev
            ? {
                prefixes: [...prev.prefixes, ...page.prefixes],
                blobs: [...prev.blobs, ...page.blobs],
                next_marker: page.next_marker,
              }
            : page,
        )
      } catch (err) {
        fb.error(err, 'List blobs')
        if (!marker) setListing(null)
      } finally {
        setLoading(false)
      }
    },
    [container, folder, filter, fb],
  )

  useEffect(() => {
    setSelected(new Set())
    void load()
  }, [load])

  const changed = () => {
    setSelected(new Set())
    void load()
    onChange()
  }

  async function upload(files: FileList) {
    const list = [...files]
    let done = 0
    for (const f of list) {
      setProgress(`Uploading ${done + 1} of ${list.length}: ${f.name}`)
      try {
        await api.upload(container, folder + f.name, f)
        done++
      } catch (err) {
        fb.error(err, `Upload ${f.name}`)
        break
      }
    }
    setProgress('')
    if (done) fb.ok(`Uploaded ${done} ${plural(done, 'file')} to ${container}/${folder}.`)
    changed()
  }

  async function deleteSelected() {
    const names = [...selected]
    const ok = await fb.confirm({
      title: `Delete ${names.length} ${plural(names.length, 'blob')}?`,
      message: (
        <ul className="mono small">
          {names.slice(0, 10).map(n => (
            <li key={n}>{n}</li>
          ))}
          {names.length > 10 && <li>and {names.length - 10} more</li>}
        </ul>
      ),
      confirmLabel: 'Delete',
    })
    if (!ok) return
    let done = 0
    for (const n of names) {
      try {
        await api.deleteBlob(container, n)
        done++
      } catch (err) {
        fb.error(err, `Delete ${n}`)
        break
      }
    }
    if (done) fb.ok(`Deleted ${done} ${plural(done, 'blob')}.`)
    if (detail && names.includes(detail)) setDetail(null)
    changed()
  }

  async function deleteFolder(prefix: string) {
    let usage: Usage
    try {
      usage = await api.usage(container, prefix)
    } catch (err) {
      fb.error(err, 'Count the folder')
      return
    }
    const ok = await fb.confirm({
      title: `Delete folder ${prefix}?`,
      message: (
        <p>
          Deletes {usage.count} {plural(usage.count, 'blob')}, {formatBytes(usage.bytes)}, in <code>{container}</code>.
        </p>
      ),
      confirmLabel: 'Delete folder',
    })
    if (!ok) return
    try {
      const r = await api.deletePrefix(container, prefix)
      fb.ok(`Deleted ${r.count} ${plural(r.count, 'blob')} from ${prefix}.`)
    } catch (err) {
      fb.error(err, `Delete ${prefix}`)
    }
    if (prefix === folder) go('blobs', container, parentOf(prefix))
    changed()
  }

  async function empty() {
    let usage: Usage
    try {
      usage = await api.usage(container, '')
    } catch (err) {
      fb.error(err, 'Count the container')
      return
    }
    const ok = await fb.confirm({
      title: `Empty ${container}?`,
      message: (
        <p>
          Deletes all {usage.count} {plural(usage.count, 'blob')}, {formatBytes(usage.bytes)}. The container stays.
        </p>
      ),
      typeToConfirm: container,
      confirmLabel: 'Empty',
    })
    if (!ok) return
    try {
      const r = await api.emptyContainer(container)
      fb.ok(`Deleted ${r.count} ${plural(r.count, 'blob')}.`)
    } catch (err) {
      fb.error(err, `Empty ${container}`)
    }
    setDetail(null)
    go('blobs', container)
    changed()
  }

  const crumbs = folder.split('/').filter(Boolean)
  const blobs = listing?.blobs ?? []
  const allSelected = blobs.length > 0 && blobs.every(b => selected.has(b.name))

  return (
    <section className="grow stack">
      <div className="panel">
        <header className="panel-header wrap-row">
          <nav className="crumbs" aria-label="Folder">
            <a href={href('blobs', container)} className="mono">
              {container}
            </a>
            {crumbs.map((c, i) => (
              // biome-ignore lint/suspicious/noArrayIndexKey: the pieces of the current folder path never reorder, and the same name can repeat at two depths, so the position is the stable key
              <span key={i}>
                <span className="muted"> / </span>
                <a href={href('blobs', container, `${crumbs.slice(0, i + 1).join('/')}/`)} className="mono">
                  {c}
                </a>
              </span>
            ))}
          </nav>
          <div className="actions">
            <button type="button" className="secondary" onClick={() => void load()} disabled={loading}>
              {loading ? 'Reading…' : 'Refresh'}
            </button>
            <button type="button" onClick={() => fileInput.current?.click()} disabled={!!progress}>
              Upload files
            </button>
            <input
              ref={fileInput}
              type="file"
              multiple
              hidden
              onChange={e => {
                if (e.target.files?.length) void upload(e.target.files)
                e.target.value = ''
              }}
            />
            <button
              type="button"
              className="danger"
              disabled={selected.size === 0}
              onClick={() => void deleteSelected()}
            >
              Delete selected ({selected.size})
            </button>
            {folder && (
              <button type="button" className="danger" onClick={() => void deleteFolder(folder)}>
                Delete this folder
              </button>
            )}
            <button type="button" className="danger" onClick={() => void empty()}>
              Empty container
            </button>
          </div>
        </header>
        <div className="filters">
          <label className="field-inline grow">
            Prefix
            <span className="mono muted">{folder}</span>
            <input
              className="grow"
              type="search"
              placeholder="starts with…"
              value={filter}
              onChange={e => setFilter(e.target.value)}
              spellCheck={false}
            />
          </label>
          {progress && <span className="muted small">{progress}</span>}
        </div>
        {listing && listing.prefixes.length === 0 && blobs.length === 0 ? (
          <p className="empty">Empty folder.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th className="check-col">
                    <input
                      type="checkbox"
                      aria-label="Select all"
                      checked={allSelected}
                      onChange={e => setSelected(e.target.checked ? new Set(blobs.map(b => b.name)) : new Set())}
                    />
                  </th>
                  <th>Name</th>
                  <th className="num">Size</th>
                  <th>Type</th>
                  <th>Modified</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {(listing?.prefixes ?? []).map(p => (
                  <tr key={p}>
                    <td />
                    <td className="mono">
                      <a href={href('blobs', container, p)}>{p.slice(folder.length)}</a>
                    </td>
                    <td className="num muted">folder</td>
                    <td />
                    <td />
                    <td className="row-actions">
                      <button type="button" className="link danger-text" onClick={() => void deleteFolder(p)}>
                        delete
                      </button>
                    </td>
                  </tr>
                ))}
                {blobs.map(b => (
                  <tr key={b.name} className={detail === b.name ? 'selected' : ''}>
                    <td className="check-col">
                      <input
                        type="checkbox"
                        aria-label={`Select ${b.name}`}
                        checked={selected.has(b.name)}
                        onChange={e => {
                          const next = new Set(selected)
                          if (e.target.checked) next.add(b.name)
                          else next.delete(b.name)
                          setSelected(next)
                        }}
                      />
                    </td>
                    <td className="mono">
                      <button type="button" className="link" onClick={() => setDetail(b.name)}>
                        {b.name.slice(folder.length)}
                      </button>
                    </td>
                    <td className="num">{formatBytes(b.size)}</td>
                    <td className="mono small">{b.content_type}</td>
                    <td>{formatTime(b.last_modified)}</td>
                    <td className="row-actions">
                      <a href={`${blobPath(container, b.name)}?download`} className="small">
                        download
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {listing?.next_marker && (
          <div className="more">
            <button
              type="button"
              className="secondary"
              disabled={loading}
              onClick={() => void load(listing.next_marker)}
            >
              Load more
            </button>
          </div>
        )}
      </div>
      {detail && (
        <BlobDetail
          key={detail}
          container={container}
          name={detail}
          onClose={() => setDetail(null)}
          onDeleted={() => {
            setDetail(null)
            changed()
          }}
        />
      )}
    </section>
  )
}

function parentOf(prefix: string): string {
  const parts = prefix.split('/').filter(Boolean)
  parts.pop()
  return parts.length ? `${parts.join('/')}/` : ''
}

type PreviewKind = 'pdf' | 'image' | 'text' | 'none'

function previewKind(b: BlobItem): PreviewKind {
  const ct = (b.content_type ?? '').split(';')[0].trim()
  if (ct === 'application/pdf' || /\.pdf$/i.test(b.name)) return 'pdf'
  if (imageTypes.test(ct)) return 'image'
  if (ct.startsWith('text/') || ct === 'application/json' || ct.endsWith('+json') || textExt.test(b.name)) return 'text'
  return 'none'
}

function BlobDetail({
  container,
  name,
  onClose,
  onDeleted,
}: {
  container: string
  name: string
  onClose: () => void
  onDeleted: () => void
}) {
  const fb = useFeedback()
  const [props, setProps] = useState<BlobProps | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [text, setText] = useState<{ text: string; total: number } | null>(null)
  const [forceText, setForceText] = useState(false)

  useEffect(() => {
    api.properties(container, name).then(setProps, err => setError(errorText(err)))
  }, [container, name])

  const kind = props ? (forceText ? 'text' : previewKind(props)) : 'none'

  useEffect(() => {
    if (kind !== 'text') return
    api.preview(container, name, previewBytes).then(setText, err => setError(errorText(err)))
  }, [container, name, kind])

  async function remove() {
    const ok = await fb.confirm({
      title: 'Delete the blob?',
      message: <p className="mono">{name}</p>,
      confirmLabel: 'Delete',
    })
    if (!ok) return
    try {
      await api.deleteBlob(container, name)
      fb.ok(`Deleted ${name}.`)
      onDeleted()
    } catch (err) {
      fb.error(err, `Delete ${name}`)
    }
  }

  const url = blobPath(container, name)
  const parsed = text ? parseJSON(text.text) : null

  return (
    <div className="panel">
      <header className="panel-header wrap-row">
        <h2 className="mono wrap">{name}</h2>
        <div className="actions">
          <a className="button secondary" href={`${url}?download`}>
            Download
          </a>
          <button type="button" className="danger" onClick={() => void remove()}>
            Delete
          </button>
          <button type="button" className="secondary" onClick={onClose}>
            Close
          </button>
        </div>
      </header>
      {error && <p className="error">{error}</p>}
      {props && (
        <div className="detail">
          <dl className="props">
            <dt>Size</dt>
            <dd>
              {formatBytes(props.size)} ({props.size.toLocaleString('en-US')} bytes)
            </dd>
            <dt>Content-Type</dt>
            <dd className="mono">{props.content_type || '-'}</dd>
            <dt>Type</dt>
            <dd>{props.blob_type || '-'}</dd>
            <dt>Created</dt>
            <dd>{formatTime(props.created)}</dd>
            <dt>Modified</dt>
            <dd>{formatTime(props.last_modified)}</dd>
            <dt>ETag</dt>
            <dd className="mono">{props.etag}</dd>
            <dt>MD5</dt>
            <dd className="mono">{props.md5 || '-'}</dd>
            {Object.entries(props.metadata ?? {}).map(([k, v]) => (
              <div key={k} className="contents">
                <dt>meta: {k}</dt>
                <dd className="mono">{v}</dd>
              </div>
            ))}
          </dl>
          <div className="preview">
            {kind === 'pdf' && <iframe title={`Preview of ${name}`} src={url} />}
            {kind === 'image' && <img alt={`Preview of ${name}`} src={url} />}
            {kind === 'text' &&
              text &&
              (parsed?.ok ? <JsonView value={parsed.value} /> : <pre className="json">{text.text}</pre>)}
            {kind === 'text' && text && text.total > previewBytes && (
              <p className="muted small">
                Showing the first {formatBytes(previewBytes)} of {formatBytes(text.total)}.
              </p>
            )}
            {kind === 'none' && (
              <p className="empty">
                No preview for this type.{' '}
                <button type="button" className="link" onClick={() => setForceText(true)}>
                  View as text
                </button>
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
