const units = ['B', 'KB', 'MB', 'GB', 'TB']

export function formatBytes(n: number): string {
  let v = n
  let i = 0
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  return `${v.toLocaleString('en-US', { maximumFractionDigits: i === 0 ? 0 : 1 })} ${units[i]}`
}

export function formatTime(iso?: string): string {
  return iso ? new Date(iso).toLocaleString('en-US') : '-'
}

export function formatClock(iso?: string): string {
  return iso ? new Date(iso).toLocaleTimeString('en-US') : '-'
}

/** A count that stopped at the limit shows as "10,000+". */
export function formatCount(n: number, truncated = false): string {
  return `${n.toLocaleString('en-US')}${truncated ? '+' : ''}`
}

/** The singular or plural form of a noun for a count. */
export function plural(n: number, one: string, many = `${one}s`): string {
  return n === 1 ? one : many
}

export function parseJSON(text: string): { ok: true; value: unknown } | { ok: false; error: string } {
  try {
    return { ok: true, value: JSON.parse(text) }
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) }
  }
}

/** A string that holds a JSON object or array, parsed; null otherwise. */
export function embeddedJSON(value: unknown): unknown {
  if (typeof value !== 'string') return null
  const s = value.trim()
  if (!(s.startsWith('{') || s.startsWith('['))) return null
  const r = parseJSON(s)
  return r.ok ? r.value : null
}

const base64Re = /^[A-Za-z0-9+/]+={0,2}$/

/** The UTF-8 text of a base64 string, or null when it is not one. */
export function decodeBase64(text: string): string | null {
  const s = text.trim()
  if (s.length < 8 || s.length % 4 !== 0 || !base64Re.test(s)) return null
  try {
    const bytes = Uint8Array.from(atob(s), c => c.charCodeAt(0))
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    return null
  }
}

/** Seconds from now until iso, never negative. */
export function secondsUntil(iso: string | undefined, now: number): number {
  if (!iso) return 0
  return Math.max(0, Math.round((new Date(iso).getTime() - now) / 1000))
}
