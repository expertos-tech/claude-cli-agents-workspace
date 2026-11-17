import type { ApiErrorBody, Job } from './types'

const REQUEST_TIMEOUT_MS = 30_000

/** Kept above the 5 minutes the service holds the native file dialog open. */
export const FILE_DIALOG_TIMEOUT_MS = 310_000

/** A request refused or failed, in the single error shape of the API. */
export class ApiError extends Error {
  readonly body: ApiErrorBody
  readonly status: number

  /** Keeps the error body as received, because the screen shows it unchanged. */
  constructor(body: ApiErrorBody, status = 0) {
    super(body.message)
    this.body = body
    this.status = status
  }
}

/** Turns anything thrown by a request into the error body shown on screen. */
export function errorBodyOf(error: unknown): ApiErrorBody {
  if (error instanceof ApiError) {
    return error.body
  }
  return { code: 'unexpected_response', message: error instanceof Error ? error.message : String(error) }
}

/** Reads a failed response, whose body is the API error shape except for the 405 of Go. */
function responseError(status: number, text: string): ApiError {
  try {
    const parsed = JSON.parse(text) as { error?: ApiErrorBody }
    if (parsed.error) {
      return new ApiError(parsed.error, status)
    }
  } catch {
    // The body is not JSON, so it goes as received below.
  }
  return new ApiError({ code: 'unexpected_response', message: text }, status)
}

/** Runs a request with a deadline and normalizes every failure to ApiError. */
async function request<Result>(path: string, init: RequestInit, timeoutMs: number): Promise<Result> {
  const deadline = AbortSignal.timeout(timeoutMs)
  const signal = init.signal ? AbortSignal.any([init.signal, deadline]) : deadline
  let response: Response
  let text: string
  try {
    response = await fetch(path, { ...init, signal })
    text = await response.text()
  } catch (error) {
    if (init.signal?.aborted) {
      throw error
    }
    const code = deadline.aborted ? 'request_timeout' : 'network_error'
    throw new ApiError({ code, message: error instanceof Error ? error.message : String(error) })
  }
  if (!response.ok) {
    throw responseError(response.status, text)
  }
  return JSON.parse(text) as Result
}

/** Reads details. Lists do not have REST routes: they come from the live topics. */
export function apiGet<Result>(path: string, signal?: AbortSignal): Promise<Result> {
  return request<Result>(path, signal ? { signal } : {}, REQUEST_TIMEOUT_MS)
}

/** Sends a command. The service answers 403 to a POST without this Content-Type, even with no body. */
export function apiPost<Result>(path: string, body: object = {}, timeoutMs = REQUEST_TIMEOUT_MS): Promise<Result> {
  const init: RequestInit = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }
  return request<Result>(path, init, timeoutMs)
}

/** Starts a mutation, which the service answers with its job. */
export async function postJob(path: string, body: object = {}): Promise<Job> {
  const { job } = await apiPost<{ job: Job }>(path, body)
  return job
}

/** Builds a WebSocket URL on the origin of the page, which is what the service accepts. */
export function webSocketUrl(path: string, query: Record<string, string> = {}): string {
  const search = new URLSearchParams(query).toString()
  return `ws://${location.host}${path}${search ? `?${search}` : ''}`
}

/** Encodes one value of a request path. */
export function segment(value: string): string {
  return encodeURIComponent(value)
}
