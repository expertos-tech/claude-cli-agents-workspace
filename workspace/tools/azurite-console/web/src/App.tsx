import { useCallback, useEffect, useRef, useState } from 'react'
import { api, errorText, type Overview as OverviewData } from './api.ts'
import { href, tabs, useRoute } from './route.ts'
import { Blobs } from './tabs/Blobs.tsx'
import { Overview } from './tabs/Overview.tsx'
import { Queues } from './tabs/Queues.tsx'
import { Tables } from './tabs/Tables.tsx'
import { FeedbackProvider } from './ui/feedback.tsx'

const refreshMs = 5_000
const autoKey = 'azurite-console.auto'

const serviceLabels = { blob: 'Blob', queue: 'Queue', table: 'Table' } as const

function readAuto(): boolean {
  try {
    return window.localStorage.getItem(autoKey) !== 'off'
  } catch {
    return true
  }
}

function saveAuto(on: boolean): void {
  try {
    window.localStorage.setItem(autoKey, on ? 'on' : 'off')
  } catch {
    // Without storage the choice lasts only for this page.
  }
}

export function App() {
  const route = useRoute()
  const [auto, setAuto] = useState(readAuto)
  const [tick, setTick] = useState(0)
  const [overview, setOverview] = useState<OverviewData | null>(null)
  const [overviewError, setOverviewError] = useState<string | null>(null)
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null)
  const inFlight = useRef<AbortController | null>(null)

  const loadOverview = useCallback(async () => {
    inFlight.current?.abort()
    const ctrl = new AbortController()
    inFlight.current = ctrl
    try {
      setOverview(await api.overview(ctrl.signal))
      setOverviewError(null)
      setUpdatedAt(new Date())
    } catch (err) {
      if (!ctrl.signal.aborted) setOverviewError(errorText(err))
    }
  }, [])

  // biome-ignore lint/correctness/useExhaustiveDependencies: tick is the trigger of the refresh (timer and Refresh button) that reads the overview again
  useEffect(() => {
    void loadOverview()
  }, [loadOverview, tick])

  useEffect(() => {
    if (!auto) return
    const timer = setInterval(() => setTick(t => t + 1), refreshMs)
    return () => clearInterval(timer)
  }, [auto])

  useEffect(() => () => inFlight.current?.abort(), [])

  return (
    <FeedbackProvider>
      <header className="topbar" data-surface="ink">
        <div className="brand">
          <span className="logo">
            <img src="/favicon.png" alt="" width={28} height={28} />
            <h1 className="app-name">
              Claude CLI Agents Workspace
              <span className="tool-name">Azurite Console</span>
            </h1>
          </span>
          <span className="muted">Azurite local{overview?.azurite.version ? ` ${overview.azurite.version}` : ''}</span>
        </div>
        {/* biome-ignore lint/a11y/useAriaPropsSupportedByRole: kept as it was; giving the block a role would change what screen readers announce, out of the scope of this visual pass */}
        <div className="status" aria-label="Service status">
          {(overview?.services ?? []).map(s => (
            <span
              key={s.name}
              className={`pill ${s.up ? 'pill-up' : 'pill-down'}`}
              title={s.error ?? `${s.latency_ms} ms`}
            >
              {serviceLabels[s.name]} {s.up ? `${s.latency_ms} ms` : 'down'}
            </span>
          ))}
          {overviewError && (
            <span className="pill pill-down" title={overviewError}>
              console down
            </span>
          )}
        </div>
        <div className="toolbar">
          <span className="muted" aria-live="polite">
            {updatedAt ? `Updated at ${updatedAt.toLocaleTimeString('en-US')}` : ''}
          </span>
          <label className="check">
            <input
              type="checkbox"
              checked={auto}
              onChange={e => {
                setAuto(e.target.checked)
                saveAuto(e.target.checked)
              }}
            />
            every 5 s
          </label>
          <button type="button" onClick={() => setTick(t => t + 1)}>
            Refresh
          </button>
        </div>
      </header>

      {/* biome-ignore lint/a11y/noNoninteractiveElementToInteractiveRole: the tab roles are kept on purpose; the links change the hash route and are announced as tabs */}
      <nav className="tabs" role="tablist" aria-label="Tabs">
        {tabs.map(t => (
          <a
            key={t.id}
            role="tab"
            aria-selected={route.tab === t.id}
            className={route.tab === t.id ? 'tab active' : 'tab'}
            href={href(t.id)}
          >
            {t.label}
          </a>
        ))}
      </nav>

      <main>
        {overviewError && !overview && (
          <p role="alert" className="error">
            Could not read the status ({overviewError}).
          </p>
        )}
        {route.tab === 'overview' && <Overview overview={overview} tick={tick} />}
        {route.tab === 'blobs' && <Blobs route={route} onChange={() => setTick(t => t + 1)} />}
        {route.tab === 'queues' && <Queues route={route} tick={tick} onChange={() => setTick(t => t + 1)} />}
        {route.tab === 'tables' && <Tables route={route} onChange={() => setTick(t => t + 1)} />}
      </main>
    </FeedbackProvider>
  )
}
