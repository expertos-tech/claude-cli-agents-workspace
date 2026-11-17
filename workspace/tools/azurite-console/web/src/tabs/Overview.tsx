import { type ReactNode, useEffect, useMemo, useState } from 'react'
import { type Activity, api, errorText, type LogLine, type Operation, type Overview as OverviewData } from '../api.ts'
import { formatBytes, formatClock, formatCount, formatTime, plural } from '../format.ts'
import { href } from '../route.ts'

const tails = [200, 500, 1000, 2000, 5000]
// Azurite answers 404 and 409 to checks that are part of normal work (does
// the container exist? create the queue if it does not).
const expected = new Set([404, 409])

function StatusBadge({ status }: { status?: number }) {
  if (!status) return <span className="badge">-</span>
  const cls = status >= 500 ? 'badge-error' : status >= 400 ? 'badge-warn' : 'badge-ok'
  return <span className={`badge ${cls}`}>{status}</span>
}

export function Overview({ overview, tick }: { overview: OverviewData | null; tick: number }) {
  const [tail, setTail] = useState(500)
  const [activity, setActivity] = useState<Activity | null>(null)
  const [ops, setOps] = useState<Operation[]>([])
  const [loadError, setLoadError] = useState<string | null>(null)

  // biome-ignore lint/correctness/useExhaustiveDependencies: tick is the trigger of the refresh that reads the log and the operations again
  useEffect(() => {
    const ctrl = new AbortController()
    Promise.all([api.activity(tail, ctrl.signal), api.operations(ctrl.signal)])
      .then(([a, o]) => {
        setActivity(a)
        setOps(o)
        setLoadError(null)
      })
      .catch(err => {
        if (!ctrl.signal.aborted) setLoadError(errorText(err))
      })
    return () => ctrl.abort()
  }, [tail, tick])

  const blob = overview?.services.find(s => s.name === 'blob')
  const queue = overview?.services.find(s => s.name === 'queue')
  const table = overview?.services.find(s => s.name === 'table')
  const blobs = (overview?.containers ?? []).reduce(
    (acc, c) => ({
      count: acc.count + c.usage.count,
      bytes: acc.bytes + c.usage.bytes,
      truncated: acc.truncated || c.usage.truncated,
    }),
    { count: 0, bytes: 0, truncated: false },
  )
  const messages = (overview?.queues ?? []).reduce((n, q) => n + q.messages, 0)
  const entities = (overview?.tables ?? []).reduce(
    (acc, t) => ({ count: acc.count + t.entities.count, truncated: acc.truncated || t.entities.truncated }),
    { count: 0, truncated: false },
  )

  return (
    <div className="stack">
      {loadError && <p className="error">Could not read the log and the operations ({loadError}).</p>}

      <section className="cards" aria-label="Services">
        <ServiceCard title="Blob" up={blob?.up} latency={blob?.latency_ms} error={blob?.error}>
          <Stat value={formatCount(overview?.containers.length ?? 0)} label="containers" />
          <Stat value={formatCount(blobs.count, blobs.truncated)} label="blobs" />
          <Stat value={formatBytes(blobs.bytes)} label="size" />
        </ServiceCard>
        <ServiceCard title="Queue" up={queue?.up} latency={queue?.latency_ms} error={queue?.error}>
          <Stat value={formatCount(overview?.queues.length ?? 0)} label="queues" />
          <Stat value={formatCount(messages)} label="messages (approx.)" />
        </ServiceCard>
        <ServiceCard title="Table" up={table?.up} latency={table?.latency_ms} error={table?.error}>
          <Stat value={formatCount(overview?.tables.length ?? 0)} label="tables" />
          <Stat value={formatCount(entities.count, entities.truncated)} label="entities" />
        </ServiceCard>
        <div className="card">
          <h2>Azurite</h2>
          {overview?.azurite.error ? (
            <p className="muted">No container information: {overview.azurite.error}</p>
          ) : (
            <>
              <Stat value={overview?.azurite.version || '-'} label="version" />
              <p className="muted small mono">{overview?.azurite.image}</p>
            </>
          )}
          {overview && (
            <p className="muted small">Counts stop at {formatCount(overview.limit)} per container and per table.</p>
          )}
        </div>
      </section>

      <section className="columns3" aria-label="Resources">
        <ResourceList
          title="Containers"
          empty="No containers."
          items={(overview?.containers ?? []).map(c => ({
            name: c.name,
            href: href('blobs', c.name),
            info: `${formatCount(c.usage.count, c.usage.truncated)} ${plural(c.usage.count, 'blob')} · ${formatBytes(c.usage.bytes)}`,
          }))}
        />
        <ResourceList
          title="Queues"
          empty="No queues."
          items={(overview?.queues ?? []).map(q => ({
            name: q.name,
            href: href('queues', q.name),
            info: `${formatCount(q.messages)} ${plural(q.messages, 'message')}`,
          }))}
        />
        <ResourceList
          title="Tables"
          empty="No tables."
          items={(overview?.tables ?? []).map(t => ({
            name: t.name,
            href: href('tables', t.name),
            info: `${formatCount(t.entities.count, t.entities.truncated)} ${plural(t.entities.count, 'entity', 'entities')}`,
          }))}
        />
      </section>

      <ErrorSummary lines={activity?.lines ?? []} ops={ops} />

      <ActivityLog activity={activity} tail={tail} onTail={setTail} />

      <section className="panel">
        <header className="panel-header">
          <h2>Operations from this page</h2>
          <span className="muted small">
            The last {ops.length} actions that changed something, kept in the program memory.
          </span>
        </header>
        {ops.length === 0 ? (
          <p className="empty">No actions yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Action</th>
                  <th>Target</th>
                  <th>Status</th>
                  <th className="num">Duration</th>
                  <th>Error</th>
                </tr>
              </thead>
              <tbody>
                {ops.map((o, i) => (
                  // biome-ignore lint/suspicious/noArrayIndexKey: the rows only show a snapshot replaced whole on each read and keep no state, and two entries can share the same time, so the position completes the key
                  <tr key={`${o.time}-${i}`}>
                    <td>{formatClock(o.time)}</td>
                    <td>{o.name}</td>
                    <td className="mono wrap">{o.target}</td>
                    <td>
                      <StatusBadge status={o.status} />
                    </td>
                    <td className="num">{o.duration_ms} ms</td>
                    <td className="mono">{o.error ?? ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  )
}

function ServiceCard(props: { title: string; up?: boolean; latency?: number; error?: string; children: ReactNode }) {
  const { title, up, latency, error, children } = props
  return (
    <div className="card">
      <header className="card-header">
        <h2>{title}</h2>
        {up === undefined ? (
          <span className="pill">-</span>
        ) : (
          <span className={`pill ${up ? 'pill-up' : 'pill-down'}`}>{up ? `up · ${latency} ms` : 'down'}</span>
        )}
      </header>
      {error ? <p className="error small">{error}</p> : <div className="stats">{children}</div>}
    </div>
  )
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div className="stat">
      <span className="stat-value">{value}</span>
      <span className="stat-label">{label}</span>
    </div>
  )
}

function ResourceList({
  title,
  empty,
  items,
}: {
  title: string
  empty: string
  items: { name: string; href: string; info: string }[]
}) {
  return (
    <div className="panel">
      <header className="panel-header">
        <h2>{title}</h2>
      </header>
      {items.length === 0 ? (
        <p className="empty">{empty}</p>
      ) : (
        <ul className="list">
          {items.map(it => (
            <li key={it.name}>
              <a href={it.href} className="mono">
                {it.name}
              </a>
              <span className="muted small">{it.info}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function ErrorSummary({ lines, ops }: { lines: LogLine[]; ops: Operation[] }) {
  const groups = useMemo(() => {
    const m = new Map<string, { service: string; status: number; resource: string; count: number; last: string }>()
    for (const l of lines) {
      if (!l.status || l.status < 400 || expected.has(l.status)) continue
      const resource = (l.resource ?? '').split('/')[0] || '(account)'
      const key = `${l.service}|${l.status}|${resource}`
      const g = m.get(key)
      if (g) {
        g.count++
        if (l.time > g.last) g.last = l.time
      } else {
        m.set(key, { service: l.service ?? '', status: l.status, resource, count: 1, last: l.time })
      }
    }
    return [...m.values()].sort((a, b) => b.count - a.count)
  }, [lines])
  const expectedCount = lines.filter(l => l.status && expected.has(l.status)).length
  const failedOps = ops.filter(o => o.status >= 400)

  return (
    <section className="panel">
      <header className="panel-header">
        <h2>Errors</h2>
        <span className="muted small">
          In the part of the log read, without the {expectedCount} expected 404 and 409 (existence checks), and in the
          actions of this page.
        </span>
      </header>
      {groups.length === 0 && failedOps.length === 0 ? (
        <p className="empty">No errors.</p>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Source</th>
                <th>Service</th>
                <th>Resource</th>
                <th>Status</th>
                <th className="num">Count</th>
                <th>Last</th>
              </tr>
            </thead>
            <tbody>
              {groups.map(g => (
                <tr key={`${g.service}|${g.status}|${g.resource}`}>
                  <td>log</td>
                  <td>{g.service}</td>
                  <td className="mono">{g.resource}</td>
                  <td>
                    <StatusBadge status={g.status} />
                  </td>
                  <td className="num">{g.count}</td>
                  <td>{formatTime(g.last)}</td>
                </tr>
              ))}
              {failedOps.map((o, i) => (
                // biome-ignore lint/suspicious/noArrayIndexKey: the rows only show a snapshot replaced whole on each read and keep no state, and two entries can share the same time, so the position completes the key
                <tr key={`op-${o.time}-${i}`}>
                  <td>page</td>
                  <td>{o.name}</td>
                  <td className="mono wrap">{o.target}</td>
                  <td>
                    <StatusBadge status={o.status} />
                  </td>
                  <td className="num">1</td>
                  <td>
                    {formatTime(o.time)} <span className="mono small">{o.error}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}

function ActivityLog({
  activity,
  tail,
  onTail,
}: {
  activity: Activity | null
  tail: number
  onTail: (n: number) => void
}) {
  const [service, setService] = useState('')
  const [caller, setCaller] = useState('')
  const [onlyErrors, setOnlyErrors] = useState(false)
  const [hideExpected, setHideExpected] = useState(true)
  const [showRaw, setShowRaw] = useState(false)
  const [text, setText] = useState('')

  const lines = activity?.lines ?? []
  const callers = useMemo(() => [...new Set(lines.map(l => l.caller || l.ip || '').filter(Boolean))].sort(), [lines])
  const shown = lines.filter(l => {
    if (l.raw !== undefined && l.raw !== '')
      return showRaw && (!text || l.raw.toLowerCase().includes(text.toLowerCase()))
    if (service && l.service !== service) return false
    if (caller && (l.caller || l.ip) !== caller) return false
    if (onlyErrors && (!l.status || l.status < 400 || (hideExpected && expected.has(l.status)))) return false
    if (text && !`${l.method} ${l.resource} ${l.query}`.toLowerCase().includes(text.toLowerCase())) return false
    return true
  })

  return (
    <section className="panel">
      <header className="panel-header">
        <h2>Activity</h2>
        <span className="muted small">
          {activity?.available
            ? `Access log of container ${activity.container}, newest first.`
            : activity
              ? `Azurite log unavailable: ${activity.reason}`
              : 'Reading the log…'}
        </span>
      </header>
      <div className="filters">
        <label className="field-inline">
          Lines
          <select value={tail} onChange={e => onTail(Number(e.target.value))}>
            {tails.map(n => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </label>
        <label className="field-inline">
          Service
          <select value={service} onChange={e => setService(e.target.value)}>
            <option value="">all</option>
            <option value="blob">blob</option>
            <option value="queue">queue</option>
            <option value="table">table</option>
            <option value="account">account</option>
          </select>
        </label>
        <label className="field-inline">
          Caller
          <select value={caller} onChange={e => setCaller(e.target.value)}>
            <option value="">all</option>
            {callers.map(c => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <label className="check">
          <input type="checkbox" checked={onlyErrors} onChange={e => setOnlyErrors(e.target.checked)} />
          errors only
        </label>
        <label className="check">
          <input
            type="checkbox"
            checked={hideExpected}
            disabled={!onlyErrors}
            onChange={e => setHideExpected(e.target.checked)}
          />
          without 404 and 409
        </label>
        <label className="check">
          <input type="checkbox" checked={showRaw} onChange={e => setShowRaw(e.target.checked)} />
          Azurite messages
        </label>
        <input
          className="grow"
          type="search"
          placeholder="Filter by text"
          value={text}
          onChange={e => setText(e.target.value)}
        />
        <span className="muted small">
          {shown.length} of {lines.length}
        </span>
      </div>
      {shown.length === 0 ? (
        <p className="empty">No lines.</p>
      ) : (
        <div className="table-wrap scroll">
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Caller</th>
                <th>Service</th>
                <th>Method</th>
                <th>Resource</th>
                <th>Status</th>
                <th className="num">Bytes</th>
              </tr>
            </thead>
            <tbody>
              {shown.map((l, i) =>
                l.raw ? (
                  // biome-ignore lint/suspicious/noArrayIndexKey: the log lines only show a snapshot replaced whole on each read and keep no state, and a line has no id of its own, so the position is the key
                  <tr key={i} className="raw">
                    <td>{formatClock(l.time)}</td>
                    <td colSpan={6} className="mono wrap">
                      {l.raw}
                    </td>
                  </tr>
                ) : (
                  // biome-ignore lint/suspicious/noArrayIndexKey: the log lines only show a snapshot replaced whole on each read and keep no state, and a line has no id of its own, so the position is the key
                  <tr key={i}>
                    <td>{formatClock(l.time)}</td>
                    <td title={l.ip}>{l.caller || l.ip}</td>
                    <td>{l.service}</td>
                    <td className="mono">{l.method}</td>
                    <td className="mono wrap" title={l.query}>
                      {l.resource || '(account)'}
                      {l.query ? <span className="muted">?{l.query}</span> : null}
                    </td>
                    <td>
                      <StatusBadge status={l.status} />
                    </td>
                    <td className="num">{l.bytes >= 0 ? formatBytes(l.bytes) : '-'}</td>
                  </tr>
                ),
              )}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}
