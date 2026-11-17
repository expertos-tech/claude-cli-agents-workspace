// Client of the API of the azurite-console program (internal/api).

export type ServiceName = 'blob' | 'queue' | 'table'

export type ServiceState = { name: ServiceName; up: boolean; latency_ms: number; error?: string }
export type Usage = { count: number; bytes: number; truncated: boolean }
export type Count = { count: number; truncated: boolean }
export type Queue = { name: string; messages: number }

export type Overview = {
  services: ServiceState[]
  containers: { name: string; usage: Usage }[]
  queues: Queue[]
  tables: { name: string; entities: Count }[]
  azurite: { image?: string; version?: string; error?: string }
  limit: number
}

export type LogLine = {
  time: string
  ip?: string
  caller?: string
  method?: string
  resource?: string
  query?: string
  status?: number
  bytes: number
  raw?: string
  service?: string
}

export type Activity = { available: boolean; reason?: string; container?: string; image?: string; lines: LogLine[] }

export type Operation = {
  time: string
  name: string
  target: string
  status: number
  duration_ms: number
  error?: string
}

export type Container = { name: string; last_modified?: string }
export type BlobItem = { name: string; size: number; content_type?: string; last_modified?: string; etag?: string }
export type Listing = { prefixes: string[]; blobs: BlobItem[]; next_marker?: string }
export type BlobProps = BlobItem & {
  md5?: string
  created?: string
  blob_type?: string
  metadata?: Record<string, string>
}

export type Message = {
  id: string
  text: string
  inserted?: string
  expires?: string
  dequeue_count: number
  pop_receipt?: string
  next_visible?: string
}
export type Receipt = { pop_receipt: string; next_visible?: string }

export type Table = { name: string }
export type EntityValue = Record<string, unknown>
export type EntityPage = { entities: EntityValue[]; next_partition_key?: string; next_row_key?: string }
export type Entity = { value: EntityValue; etag: string }

/** A problem document of the API, thrown by every call that fails. */
export class ApiError extends Error {
  status: number
  code: string
  detail: string
  fields: string[]

  constructor(status: number, code: string, title: string, detail: string, fields: string[]) {
    super(title)
    this.status = status
    this.code = code
    this.detail = detail
    this.fields = fields
  }
}

/** The text of an error for the page: title, detail and invalid fields. */
export function errorText(err: unknown): string {
  if (err instanceof ApiError) {
    const parts = [err.message]
    if (err.detail) parts.push(err.detail)
    if (err.fields.length) parts.push(`fields: ${err.fields.join(', ')}`)
    return parts.join(' · ')
  }
  return err instanceof Error ? err.message : String(err)
}

async function fail(res: Response): Promise<never> {
  let body: { code?: string; title?: string; detail?: string; errors?: { field: string }[] } = {}
  try {
    body = await res.json()
  } catch {
    // Not a problem document (the program is down, or a proxy answered).
  }
  throw new ApiError(
    res.status,
    body.code ?? '',
    body.title ?? `HTTP ${res.status}`,
    body.detail ?? '',
    (body.errors ?? []).map(e => e.field),
  )
}

// The page is in English, so the messages of the API are too, whatever the browser language.
const language = { 'Accept-Language': 'en' }

async function call<T>(method: string, path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  const init: RequestInit = { method, signal, cache: 'no-store', headers: language }
  if (body !== undefined) {
    init.body = JSON.stringify(body)
    init.headers = { ...language, 'Content-Type': 'application/json' }
  }
  let res: Response
  try {
    res = await fetch(path, init)
  } catch (err) {
    if (signal?.aborted) throw err
    throw new ApiError(0, 'network', 'azurite-console did not respond', 'check that the Go program is running', [])
  }
  if (!res.ok) return fail(res)
  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}

const enc = encodeURIComponent

/** The path of a blob, with each segment encoded and the slashes kept. */
export function blobPath(container: string, name: string): string {
  return `/api/containers/${enc(container)}/blobs/${name.split('/').map(enc).join('/')}`
}

// query keeps empty strings: an entity may have an empty PartitionKey or RowKey.
function query(params: Record<string, string | number | undefined>): string {
  const q = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined) q.set(k, String(v))
  }
  const s = q.toString()
  return s ? `?${s}` : ''
}

export const api = {
  overview: (signal?: AbortSignal) => call<Overview>('GET', '/api/overview', undefined, signal),
  activity: (tail: number, signal?: AbortSignal) =>
    call<Activity>('GET', `/api/activity${query({ tail })}`, undefined, signal),
  operations: (signal?: AbortSignal) => call<Operation[]>('GET', '/api/operations', undefined, signal),

  containers: () => call<Container[]>('GET', '/api/containers'),
  createContainer: (name: string) => call<unknown>('POST', '/api/containers', { name }),
  deleteContainer: (name: string) => call<void>('DELETE', `/api/containers/${enc(name)}`),
  emptyContainer: (name: string) => call<Usage>('POST', `/api/containers/${enc(name)}/empty`),
  list: (name: string, prefix: string, marker?: string) =>
    call<Listing>('GET', `/api/containers/${enc(name)}/list${query({ prefix, marker })}`),
  usage: (name: string, prefix: string) => call<Usage>('GET', `/api/containers/${enc(name)}/usage${query({ prefix })}`),
  deletePrefix: (name: string, prefix: string) =>
    call<Usage>('DELETE', `/api/containers/${enc(name)}/prefix${query({ prefix })}`),
  properties: (name: string, path: string) => call<BlobProps>('GET', `${blobPath(name, path)}?props`),
  deleteBlob: (name: string, path: string) => call<void>('DELETE', blobPath(name, path)),
  async upload(name: string, path: string, file: File): Promise<void> {
    let res: Response
    try {
      res = await fetch(blobPath(name, path), {
        method: 'PUT',
        body: file,
        headers: { ...language, 'Content-Type': file.type || 'application/octet-stream' },
      })
    } catch {
      throw new ApiError(0, 'network', 'azurite-console did not respond', '', [])
    }
    if (!res.ok) return fail(res)
  },
  /** The first max bytes of a blob, as text, and the size of the whole blob. */
  async preview(name: string, path: string, max: number): Promise<{ text: string; total: number }> {
    const res = await fetch(`${blobPath(name, path)}?max=${max}`, { cache: 'no-store', headers: language })
    if (!res.ok) return fail(res)
    return { text: await res.text(), total: Number(res.headers.get('X-Blob-Size') ?? 0) }
  },

  queues: (signal?: AbortSignal) => call<Queue[]>('GET', '/api/queues', undefined, signal),
  createQueue: (name: string) => call<unknown>('POST', '/api/queues', { name }),
  deleteQueue: (name: string) => call<void>('DELETE', `/api/queues/${enc(name)}`),
  clearQueue: (name: string) => call<void>('POST', `/api/queues/${enc(name)}/clear`),
  peek: (name: string, n = 32, signal?: AbortSignal) =>
    call<Message[]>('GET', `/api/queues/${enc(name)}/peek${query({ n })}`, undefined, signal),
  receive: (name: string, count: number, visibility_seconds: number) =>
    call<Message[]>('POST', `/api/queues/${enc(name)}/receive`, { count, visibility_seconds }),
  send: (name: string, text: string, delay_seconds: number, ttl_seconds: number) =>
    call<void>('POST', `/api/queues/${enc(name)}/messages`, { text, delay_seconds, ttl_seconds }),
  updateMessage: (name: string, id: string, pop_receipt: string, text: string, visibility_seconds: number) =>
    call<Receipt>('PUT', `/api/queues/${enc(name)}/messages/${enc(id)}`, { pop_receipt, text, visibility_seconds }),
  deleteMessage: (name: string, id: string, pop_receipt: string) =>
    call<void>('DELETE', `/api/queues/${enc(name)}/messages/${enc(id)}${query({ pop_receipt })}`),
  moveMessage: (name: string, id: string, pop_receipt: string, text: string, to: string) =>
    call<void>('POST', `/api/queues/${enc(name)}/messages/${enc(id)}/move`, { pop_receipt, text, to }),

  tables: () => call<Table[]>('GET', '/api/tables'),
  createTable: (name: string) => call<unknown>('POST', '/api/tables', { name }),
  deleteTable: (name: string) => call<void>('DELETE', `/api/tables/${enc(name)}`),
  entities: (name: string, filter: string, top: number, next_pk?: string, next_rk?: string) =>
    call<EntityPage>('GET', `/api/tables/${enc(name)}/entities${query({ filter, top, next_pk, next_rk })}`),
  entity: (name: string, pk: string, rk: string) =>
    call<Entity>('GET', `/api/tables/${enc(name)}/entity${query({ pk, rk })}`),
  insertEntity: (name: string, entity: EntityValue) =>
    call<{ etag: string }>('POST', `/api/tables/${enc(name)}/entities`, { entity }),
  updateEntity: (name: string, entity: EntityValue, etag: string, mode: 'merge' | 'replace') =>
    call<{ etag: string }>('PUT', `/api/tables/${enc(name)}/entities`, { entity, etag, mode }),
  deleteEntity: (name: string, pk: string, rk: string, etag?: string) =>
    call<void>('DELETE', `/api/tables/${enc(name)}/entities${query({ pk, rk, etag })}`),
  deleteByFilter: (name: string, filter: string, dry_run: boolean) =>
    call<{ count: number }>('POST', `/api/tables/${enc(name)}/delete-by-filter`, { filter, dry_run }),
}
