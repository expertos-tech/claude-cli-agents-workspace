import { useSyncExternalStore } from 'react'
import { webSocketUrl } from './client'
import type { ApiErrorBody, LiveSnapshots, Topic } from './types'

const FIRST_RETRY_MS = 250
const MAX_RETRY_MS = 2_000
/** Pages sharing a topic swap in the same tick: this keeps the socket across the navigation. */
const IDLE_CLOSE_MS = 1_000

export type LiveStatus = 'idle' | 'connecting' | 'open' | 'reconnecting'

export interface LiveState<Snapshot> {
  data: Snapshot | null
  status: LiveStatus
  error: ApiErrorBody | null
}

const IDLE_STATE: LiveState<never> = { data: null, status: 'idle', error: null }

const connectionListeners = new Set<() => void>()

/** Tells the reconnection banner that the status of a topic changed. */
function notifyConnection(): void {
  for (const listener of connectionListeners) {
    listener()
  }
}

/** One WebSocket per topic, shared by every subscriber and closed when the last one leaves. */
class TopicStore<Snapshot> {
  state: LiveState<Snapshot> = IDLE_STATE
  private readonly listeners = new Set<() => void>()
  private socket: WebSocket | null = null
  private retryTimer: number | undefined
  private closeTimer: number | undefined
  private attempts = 0
  private readonly topic: Topic

  /** Creates the idle store of a topic. */
  constructor(topic: Topic) {
    this.topic = topic
  }

  /** Adds a subscriber and opens the socket when it is the first. */
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener)
    window.clearTimeout(this.closeTimer)
    if (!this.socket && this.retryTimer === undefined) {
      this.update({ status: 'connecting' })
      this.connect()
    }
    return () => {
      this.listeners.delete(listener)
      if (this.listeners.size === 0) {
        this.closeTimer = window.setTimeout(this.stop, IDLE_CLOSE_MS)
      }
    }
  }

  /** Merges a change into the state and notifies whoever depends on it. */
  private update(change: Partial<LiveState<Snapshot>>): void {
    this.state = { ...this.state, ...change }
    for (const listener of this.listeners) {
      listener()
    }
    notifyConnection()
  }

  /** Opens the socket. With no subscriber, the service stops watching the topic. */
  private connect(): void {
    const socket = new WebSocket(webSocketUrl(`/ws/live/${this.topic}`))
    this.socket = socket
    socket.onmessage = event => this.receive(event.data)
    socket.onclose = () => {
      if (this.socket === socket) {
        this.socket = null
        this.scheduleRetry()
      }
    }
  }

  /** Applies one control frame. An invalid frame is ignored, since the next snapshot replaces all. */
  private receive(data: unknown): void {
    if (typeof data !== 'string') {
      return
    }
    let frame: { type?: string; data?: Snapshot } & Partial<ApiErrorBody>
    try {
      frame = JSON.parse(data)
    } catch {
      return
    }
    if (frame.type === 'snapshot' && frame.data !== undefined) {
      this.attempts = 0
      this.update({ data: frame.data, status: 'open', error: null })
    } else if (frame.type === 'error') {
      this.update({ error: { code: frame.code ?? '', message: frame.message ?? '' } })
    }
  }

  /** Tries again with a growing wait of at most 2 s, while the banner is on. */
  private scheduleRetry(): void {
    const delay = Math.min(FIRST_RETRY_MS * 2 ** this.attempts, MAX_RETRY_MS)
    this.attempts += 1
    this.update({ status: 'reconnecting' })
    this.retryTimer = window.setTimeout(() => {
      this.retryTimer = undefined
      this.connect()
    }, delay)
  }

  /** Closes everything once the last subscriber is gone. The last snapshot stays until the next. */
  private stop = (): void => {
    window.clearTimeout(this.retryTimer)
    this.retryTimer = undefined
    const socket = this.socket
    this.socket = null
    socket?.close()
    this.attempts = 0
    this.update({ status: 'idle' })
  }
}

const stores = new Map<Topic, TopicStore<unknown>>()

/** Returns the single store of a topic. */
function storeOf(topic: Topic): TopicStore<unknown> {
  let store = stores.get(topic)
  if (!store) {
    store = new TopicStore<unknown>(topic)
    stores.set(topic, store)
  }
  return store
}

/** Subscribes nothing, for a topic the caller does not need right now. */
function subscribeNothing(): () => void {
  return () => undefined
}

/**
 * Follows the snapshots of a topic. With `enabled` false no socket is opened, which spares the
 * service the processes behind a topic the screen does not need.
 */
export function useLive<Name extends Topic>(topic: Name, enabled = true): LiveState<LiveSnapshots[Name]> {
  const store = storeOf(topic)
  const state = useSyncExternalStore(enabled ? store.subscribe : subscribeNothing, () =>
    enabled ? store.state : IDLE_STATE,
  )
  return state as LiveState<LiveSnapshots[Name]>
}

/** Subscribes to the connection status of every topic. */
function subscribeConnection(listener: () => void): () => void {
  connectionListeners.add(listener)
  return () => connectionListeners.delete(listener)
}

/** Tells whether any topic in use has lost its socket. */
function anyTopicReconnecting(): boolean {
  for (const store of stores.values()) {
    if (store.state.status === 'reconnecting') {
      return true
    }
  }
  return false
}

/** True while a live socket is lost, which drives the reconnection banner. */
export function useLiveConnectionLost(): boolean {
  return useSyncExternalStore(subscribeConnection, anyTopicReconnecting)
}
