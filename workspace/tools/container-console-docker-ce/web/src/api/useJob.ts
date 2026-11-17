import { useCallback, useEffect, useMemo, useSyncExternalStore } from 'react'
import { errorBodyOf, postJob } from './client'
import type { ApiErrorBody, Job } from './types'
import { useLive } from './useLive'

const DISMISSED_KEY = 'container-console-docker-ce.dismissed-jobs'
const MAX_DISMISSED = 100

/** A request the service refused before it became a job: nothing ran. */
export interface Refusal {
  id: string
  kind: string
  target: string
  error: ApiErrorBody
}

interface DockState {
  /** Jobs answered by a POST, shown until the jobs topic brings them. */
  started: Job[]
  /** Ids of jobs this tab has seen running, whose final state is worth showing. */
  seen: ReadonlySet<string>
  /** Failed jobs this tab has already opened the dock for. */
  announcedFailures: ReadonlySet<string>
  dismissed: ReadonlySet<string>
  refusals: Refusal[]
  collapsed: boolean
}

/** Reads the dismissed ids. They survive a reload, so a dismissed failure does not come back. */
function loadDismissed(): Set<string> {
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(DISMISSED_KEY) ?? '[]')
    return new Set(Array.isArray(stored) ? stored.filter(id => typeof id === 'string') : [])
  } catch {
    return new Set()
  }
}

/** Stores the most recent dismissed ids. The service forgets its jobs long before this fills. */
function saveDismissed(ids: ReadonlySet<string>): void {
  try {
    localStorage.setItem(DISMISSED_KEY, JSON.stringify([...ids].slice(-MAX_DISMISSED)))
  } catch {
    // Without storage the dismissal only lasts until the reload.
  }
}

let dock: DockState = {
  started: [],
  seen: new Set(),
  announcedFailures: new Set(),
  dismissed: loadDismissed(),
  refusals: [],
  collapsed: false,
}
const dockListeners = new Set<() => void>()
let refusalCounter = 0

/** Replaces the dock state and notifies the screen. */
function updateDock(change: Partial<DockState>): void {
  dock = { ...dock, ...change }
  for (const listener of dockListeners) {
    listener()
  }
}

/** Shows a request that failed before it became a job, as received. */
export function reportRefusal(kind: string, target: string, error: unknown): void {
  refusalCounter += 1
  const refusal: Refusal = { id: `refusal-${refusalCounter}`, kind, target, error: errorBodyOf(error) }
  updateDock({ refusals: [refusal, ...dock.refusals], collapsed: false })
}

/** Records a job the service accepted, so that it appears before the next snapshot. */
function trackStarted(job: Job): void {
  updateDock({
    started: [job, ...dock.started],
    seen: new Set(dock.seen).add(job.id),
    collapsed: false,
  })
}

/** Removes one entry from the dock. */
export function dismissEntry(id: string): void {
  if (id.startsWith('refusal-')) {
    updateDock({ refusals: dock.refusals.filter(refusal => refusal.id !== id) })
    return
  }
  const dismissed = new Set(dock.dismissed).add(id)
  saveDismissed(dismissed)
  updateDock({ dismissed })
}

/** Opens or closes the dock. */
export function toggleDock(): void {
  updateDock({ collapsed: !dock.collapsed })
}

/** Notes what a new snapshot brought: jobs seen running, and failures that open the dock. */
function observeJobs(jobs: Job[]): void {
  const running = jobs.filter(job => job.status === 'running' && !dock.seen.has(job.id))
  const failures = jobs.filter(
    job => job.status === 'failed' && !dock.dismissed.has(job.id) && !dock.announcedFailures.has(job.id),
  )
  const known = new Set(jobs.map(job => job.id))
  const started = dock.started.filter(job => !known.has(job.id))
  if (running.length === 0 && failures.length === 0 && started.length === dock.started.length) {
    return
  }
  updateDock({
    started,
    seen: new Set([...dock.seen, ...running.map(job => job.id)]),
    announcedFailures: new Set([...dock.announcedFailures, ...failures.map(job => job.id)]),
    collapsed: failures.length > 0 ? false : dock.collapsed,
  })
}

/** Subscribes to the dock state. */
function subscribeDock(listener: () => void): () => void {
  dockListeners.add(listener)
  return () => dockListeners.delete(listener)
}

/** Reads the current dock state. */
function readDock(): DockState {
  return dock
}

export interface DockEntries {
  jobs: Job[]
  refusals: Refusal[]
  collapsed: boolean
}

/**
 * What the dock shows: refusals, jobs running, every failed job (even from another tab or
 * before a reload) and the jobs this tab saw end. The job data always comes from the topic.
 */
export function useDockEntries(): DockEntries {
  const state = useSyncExternalStore(subscribeDock, readDock)
  const live = useLive('jobs').data?.jobs
  useEffect(() => {
    if (live) {
      observeJobs(live)
    }
  }, [live])
  return useMemo(() => {
    const known = new Set((live ?? []).map(job => job.id))
    const pending = state.started.filter(job => !known.has(job.id))
    const visible = [...pending, ...(live ?? [])].filter(
      job => !state.dismissed.has(job.id) && (job.status !== 'succeeded' || state.seen.has(job.id)),
    )
    return { jobs: visible, refusals: state.refusals, collapsed: state.collapsed }
  }, [live, state])
}

export interface JobRunner {
  /** Sends the POST. Returns the job, or null when the service refused it, which the dock shows. */
  run: (kind: string, target: string, path: string, body?: object) => Promise<Job | null>
  /** True while the jobs topic shows a job running on this target. */
  isBusy: (target: string) => boolean
}

/** Starts mutations and tells which targets have one running. Rows wait for the snapshot. */
export function useJob(): JobRunner {
  const jobs = useLive('jobs').data?.jobs
  const run = useCallback<JobRunner['run']>(async (kind, target, path, body = {}) => {
    try {
      const job = await postJob(path, body)
      trackStarted(job)
      return job
    } catch (error) {
      reportRefusal(kind, target, error)
      return null
    }
  }, [])
  const isBusy = useCallback(
    (target: string) => (jobs ?? []).some(job => job.status === 'running' && job.target === target),
    [jobs],
  )
  return { run, isBusy }
}
