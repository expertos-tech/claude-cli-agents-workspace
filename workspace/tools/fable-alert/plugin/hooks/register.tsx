import type { EngineInterface, Register, Timer } from 'claude-code'
import { atom, read, update } from 'claude-code'

// Whether the tint is on, and with it the band. The host holds it, so a hot reload keeps it.
// The terminal starts on its own background: nothing to write unless Fable.
const isFable = atom({ plugin: 'fable-alert', key: 'isFable' } as const, false)

// Dark red background for the whole terminal while Fable is active.
const TINT = '#420c0c'
const SET_TINT = `\\033]11;${TINT}\\007` // OSC 11: set default background
const RESET_TINT = '\\033]111\\007' // OSC 111: back to the terminal's own background

// The child has no controlling terminal, so walk up to the first ancestor
// that owns one (the claude process) and write the escape sequence there.
const WRITE_TO_SESSION_TTY = `
p=$PPID
i=0
while [ "$i" -lt 8 ] && [ -n "$p" ] && [ "$p" != 1 ]; do
  t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
  case "$t" in
    ''|'??') ;;
    *) printf "$1" > "/dev/$t" && exit 0 ;;
  esac
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  i=$((i + 1))
done
exit 1
`

/** Writes the tint (Fable) or the reset of it to the session's terminal, through a child process. */
function paint($: EngineInterface, fable: boolean) {
  return $.process.run(['sh', '-c', WRITE_TO_SESSION_TTY, 'fable-alert', fable ? SET_TINT : RESET_TINT], {
    timeoutMs: 3000,
  })
}

/** Writes the tint or its reset, then records it, which also draws or hides the band. */
async function applyTint($: EngineInterface, fable: boolean) {
  await paint($, fable)
  // The band appears or goes away right after the write, which moves the
  // prompt and redraws it over anything the write may have disturbed.
  await update($, isFable, () => fable)
}

// Wait for the startup screen to finish drawing before the first check, so the
// escape sequence never lands in the middle of it.
const FIRST_CHECK_MS = 2000

/** Hooks the session and the band above the prompt; this closure tracks only the module's own timers and calls. */
export const register: Register = on => {
  let isBusy = false
  let isEnded = false
  let timers: Timer[] = []

  /** Cancels every pending timer. */
  const stop = () => {
    for (const t of timers) t.cancel()
    timers = []
  }

  /** Starts watching the model once the startup screen is drawn. */
  on('session.start', async ($, e, next) => {
    isEnded = false
    stop()

    /** Makes the tint and the band follow the current model; skips while a previous call runs. */
    const sync = async () => {
      if (isBusy) return
      isBusy = true
      try {
        const fable = /fable/i.test(await $.session.model())
        const isTinted = await read($, isFable)
        if (!isEnded && fable !== isTinted) {
          await applyTint($, fable)
          // The session ended while the tint was being written: undo it.
          if (isEnded && fable) await applyTint($, false)
        }
      } catch {
        // Try again on the next tick.
      } finally {
        isBusy = false
      }
    }

    timers.push(
      /** Runs the first check and starts the one-second polling. */
      $.clock.after(FIRST_CHECK_MS, () => {
        void sync()
        timers.push($.clock.every(1000, () => void sync()))
      }),
    )

    return next(e)
  })

  /** Stops watching unless the process goes on, and gives the terminal its own background back. */
  on('session.end', async ($, e, next) => {
    // A /clear or a /resume keeps the process going with no new session.start,
    // so the timers keep watching the model.
    if (e.reason !== 'clear' && e.reason !== 'resume') {
      isEnded = true
      stop()
    }
    // A failed read counts as tinted: a needless reset is harmless, a missed one leaves the terminal red.
    if (await read($, isFable).catch(() => true)) {
      try {
        await paint($, false)
      } catch {
        // The exit goes on regardless.
      }
      await update($, isFable, () => false)
    }

    return next(e)
  })

  /** Draws the band while the tint is on, unless a survey is taking that space. */
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || !(await read($, isFable))) {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box borderStyle="round" borderColor="red" paddingX={1} width={e.props.bodyColumns}>
        <Text color="red" bold>
          FABLE ACTIVE
        </Text>
        <Text dimColor>{'  '}consome a cota semanal do Fable. Use /model para trocar.</Text>
      </Box>
    )
  })
}
