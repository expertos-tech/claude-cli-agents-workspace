import { FitAddon } from '@xterm/addon-fit'
import { Terminal } from '@xterm/xterm'
import '@xterm/xterm/css/xterm.css'
import { useEffect, useRef, useState } from 'react'
import { webSocketUrl } from '../api/client'
import type { ApiErrorBody } from '../api/types'
import { t } from '../i18n/messages'
import { Button } from './Button'
import { ErrorDetail } from './ErrorDetail'
import { StatusBadge, type Tone } from './StatusBadge'
import styles from './TerminalView.module.css'
import { uiStyles } from './ui'

/** Well under the 64 KiB the service accepts per frame, so a paste can never close the connection. */
const INPUT_FRAME_BYTES = 32 * 1024

type Connection =
  | { phase: 'connecting' | 'open' | 'ended' | 'lost' }
  | { phase: 'exited'; exitCode: number }
  | { phase: 'error'; error: ApiErrorBody }

/** Reads a token of the design system, so the terminal never holds a raw color value. */
function cssToken(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim()
}

/** Sends bytes to the terminal in frames the service accepts. */
function sendInput(socket: WebSocket, bytes: Uint8Array<ArrayBuffer>): void {
  if (socket.readyState !== WebSocket.OPEN) {
    return
  }
  for (let start = 0; start < bytes.length; start += INPUT_FRAME_BYTES) {
    socket.send(bytes.subarray(start, start + INPUT_FRAME_BYTES))
  }
}

/** Reads a control frame into the next connection state, or null when it is not one. */
function controlFrameState(data: string): Connection | null {
  try {
    const frame = JSON.parse(data) as Partial<ApiErrorBody> & { type?: string }
    switch (frame.type) {
      case 'end':
        return { phase: 'ended' }
      case 'exit':
        return { phase: 'exited', exitCode: frame.exitCode ?? 0 }
      case 'error':
        return {
          phase: 'error',
          error: {
            code: frame.code ?? '',
            message: frame.message ?? '',
            exitCode: frame.exitCode,
            params: frame.params,
          },
        }
      default:
        return null
    }
  } catch {
    return null
  }
}

/** Creates the xterm instance with the options of each mode and the colors of the tokens. */
function createTerminal(mode: 'logs' | 'terminal'): Terminal {
  const isLogs = mode === 'logs'
  return new Terminal({
    convertEol: isLogs,
    disableStdin: isLogs,
    cursorBlink: false,
    scrollback: 10_000,
    fontFamily: cssToken('--font-mono'),
    fontSize: 13,
    theme: {
      background: cssToken('--terminal-bg'),
      foreground: cssToken('--terminal-fg'),
      cursor: cssToken('--terminal-fg'),
      selectionBackground: cssToken('--terminal-selection'),
    },
  })
}

/** Returns the badge of a connection state. */
function badgeOf(connection: Connection): { tone: Tone; label: string } {
  switch (connection.phase) {
    case 'connecting':
      return { tone: 'progress', label: t('terminal.status.connecting') }
    case 'open':
      return { tone: 'good', label: t('terminal.status.open') }
    case 'ended':
      return { tone: 'neutral', label: t('terminal.status.ended') }
    case 'exited':
      return { tone: 'neutral', label: t('terminal.status.exited', { code: String(connection.exitCode) }) }
    case 'lost':
      return { tone: 'serious', label: t('terminal.status.lost') }
    case 'error':
      return { tone: 'critical', label: t('terminal.status.error') }
  }
}

interface TerminalViewProps {
  /** WebSocket path, already encoded. */
  path: string
  mode: 'logs' | 'terminal'
  label: string
  query?: Record<string, string>
}

/**
 * Live logs and terminal share this view. A socket lives only while the view is open: closing it
 * ends the process on the host. It does not reconnect by itself, because that would repeat the
 * logs or open another shell, so the user decides with the button.
 */
export function TerminalView({ path, mode, label, query }: TerminalViewProps) {
  const hostRef = useRef<HTMLDivElement>(null)
  const terminalRef = useRef<Terminal | null>(null)
  const exitTargetRef = useRef<HTMLParagraphElement>(null)
  const [connection, setConnection] = useState<Connection>({ phase: 'connecting' })
  const [attempt, setAttempt] = useState(0)
  const queryKey = JSON.stringify(query ?? {})

  useEffect(() => {
    const host = hostRef.current
    if (!host) {
      return
    }
    setConnection({ phase: 'connecting' })
    const terminal = createTerminal(mode)
    const fit = new FitAddon()
    terminal.loadAddon(fit)
    terminal.open(host)
    fit.fit()
    terminalRef.current = terminal

    // Tab must stay in the shell, so Shift+Esc is the way out by keyboard (WCAG 2.1.2).
    // Logs take no input, so Tab just moves on.
    terminal.attachCustomKeyEventHandler(event => {
      if (mode === 'logs') {
        return event.key !== 'Tab'
      }
      if (event.type === 'keydown' && event.key === 'Escape' && event.shiftKey) {
        exitTargetRef.current?.focus()
        return false
      }
      return true
    })

    const baseQuery: Record<string, string> = JSON.parse(queryKey)
    const sizeQuery: Record<string, string> =
      mode === 'terminal' ? { cols: String(terminal.cols), rows: String(terminal.rows) } : {}
    const socket = new WebSocket(webSocketUrl(path, { ...baseQuery, ...sizeQuery }))
    socket.binaryType = 'arraybuffer'
    let finished = false

    socket.onopen = () => setConnection({ phase: 'open' })
    socket.onmessage = event => {
      if (event.data instanceof ArrayBuffer) {
        terminal.write(new Uint8Array(event.data))
        return
      }
      const next = controlFrameState(String(event.data))
      if (next) {
        finished = true
        setConnection(next)
      }
    }
    socket.onclose = () => {
      if (!finished) {
        setConnection({ phase: 'lost' })
      }
    }

    const encoder = new TextEncoder()
    const inputs =
      mode === 'terminal'
        ? [
            terminal.onData(data => sendInput(socket, encoder.encode(data))),
            terminal.onBinary(data =>
              sendInput(
                socket,
                Uint8Array.from(data, char => char.charCodeAt(0)),
              ),
            ),
            terminal.onResize(({ cols, rows }) => {
              if (socket.readyState === WebSocket.OPEN) {
                socket.send(JSON.stringify({ type: 'resize', cols, rows }))
              }
            }),
          ]
        : []

    const observer = new ResizeObserver(() => fit.fit())
    observer.observe(host)
    if (mode === 'terminal') {
      terminal.focus()
    }

    return () => {
      finished = true
      observer.disconnect()
      for (const input of inputs) {
        input.dispose()
      }
      socket.close()
      terminal.dispose()
      terminalRef.current = null
    }
  }, [path, mode, queryKey, attempt])

  // The name of the resource may arrive after the connection, and must not reopen it.
  useEffect(() => {
    terminalRef.current?.textarea?.setAttribute('aria-label', `${t('terminal.input')}: ${label}`)
  }, [label, attempt])

  const badge = badgeOf(connection)
  const canReconnect = connection.phase !== 'connecting' && connection.phase !== 'open'
  return (
    <section className={styles.view} aria-label={label}>
      <div className={styles.toolbar}>
        <StatusBadge tone={badge.tone} label={badge.label} />
        <Button size="compact" icon="restart" disabled={!canReconnect} onClick={() => setAttempt(value => value + 1)}>
          {t('action.reconnect')}
        </Button>
      </div>
      {connection.phase === 'error' && <ErrorDetail error={connection.error} />}
      <div className={styles.frame}>
        <div ref={hostRef} className={styles.host} />
      </div>
      <p ref={exitTargetRef} className={uiStyles.hint} tabIndex={-1}>
        {mode === 'terminal'
          ? `${t('terminal.exitHint')} ${t('terminal.reconnectShell')}`
          : t('terminal.reconnectLogs')}
      </p>
    </section>
  )
}
