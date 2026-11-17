import { segment } from '../../api/client'
import type { Container } from '../../api/types'
import { useJob } from '../../api/useJob'
import { Button } from '../../components/Button'
import { ConfirmButton } from '../../components/ConfirmDialog'
import type { Tone } from '../../components/StatusBadge'
import { createTranslator } from '../../i18n'
import { messages } from './messages'

const t = createTranslator(messages)

const STATES = ['running', 'exited', 'created', 'paused', 'restarting', 'removing', 'dead'] as const
type KnownState = (typeof STATES)[number]

const TONE_BY_STATE: Record<KnownState, Tone> = {
  running: 'good',
  exited: 'neutral',
  created: 'neutral',
  paused: 'warning',
  restarting: 'progress',
  removing: 'progress',
  dead: 'critical',
}

/** The badge of a container state. A state this version does not know is shown as received. */
export function containerStateBadge(state: string): { tone: Tone; label: string } {
  const known = STATES.find(item => item === state)
  return known ? { tone: TONE_BY_STATE[known], label: t(`state.${known}`) } : { tone: 'neutral', label: state }
}

/** The badge of a health check, or null when the container has none. */
export function containerHealthBadge(health: string | undefined): { tone: Tone; label: string } | null {
  switch (health) {
    case 'healthy':
      return { tone: 'good', label: t('health.healthy') }
    case 'unhealthy':
      return { tone: 'critical', label: t('health.unhealthy') }
    case 'starting':
      return { tone: 'progress', label: t('health.starting') }
    default:
      return null
  }
}

interface ContainerActionsProps {
  container: Container
  /** False while the environment or Docker is not available. */
  available: boolean
  describedBy?: string
  size?: 'regular' | 'compact'
}

/** Start, stop, restart and remove. Each one waits for the snapshot to change the row. */
export function ContainerActions({ container, available, describedBy, size = 'compact' }: ContainerActionsProps) {
  const { run, isBusy } = useJob()
  const name = container.name
  const path = `/api/containers/${segment(name)}`
  const busy = isBusy(name)
  const running = container.state === 'running' || container.state === 'restarting'
  const shared = { size, busy, disabled: !available, 'aria-describedby': describedBy }
  return (
    <>
      {running ? (
        <Button
          {...shared}
          icon="stop"
          aria-label={t('stopAria', { name })}
          onClick={() => run('container.stop', name, `${path}/stop`)}
        >
          {t('stop')}
        </Button>
      ) : (
        <Button
          {...shared}
          icon="play"
          aria-label={t('startAria', { name })}
          onClick={() => run('container.start', name, `${path}/start`)}
        >
          {t('start')}
        </Button>
      )}
      <Button
        {...shared}
        icon="restart"
        aria-label={t('restartAria', { name })}
        onClick={() => run('container.restart', name, `${path}/restart`)}
      >
        {t('restart')}
      </Button>
      <ConfirmButton
        label={t('remove')}
        ariaLabel={t('removeAria', { name })}
        icon="trash"
        size={size}
        busy={busy}
        disabled={!available}
        describedBy={describedBy}
        dialogTitle={t('removeTitle', { name })}
        confirmLabel={t('remove')}
        irreversible
        onConfirm={() => run('container.remove', name, `${path}/remove`, { confirm: true })}
      >
        <p>{t('removeBody')}</p>
      </ConfirmButton>
    </>
  )
}
