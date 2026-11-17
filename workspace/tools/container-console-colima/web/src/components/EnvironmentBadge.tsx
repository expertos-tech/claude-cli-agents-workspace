import type { EnvironmentState } from '../api/types'
import { useLive } from '../api/useLive'
import { t } from '../i18n/messages'
import { href } from '../routing'
import { StatusBadge, type Tone } from './StatusBadge'

const TONE_BY_STATE: Record<EnvironmentState, Tone> = {
  on: 'good',
  off: 'neutral',
  starting: 'progress',
  stopping: 'progress',
  unknown: 'serious',
}

/** The badge of an environment state, the same on every screen. */
export function EnvironmentStateBadge({ state }: { state: EnvironmentState | undefined }) {
  if (!state) {
    return <StatusBadge tone="neutral" label={t('environment.state.loading')} />
  }
  return <StatusBadge tone={TONE_BY_STATE[state]} label={t(`environment.state.${state}`)} />
}

/** The environment state in the top bar, as a link to the screen that changes it. */
export function EnvironmentBadge() {
  const state = useLive('environment').data?.state
  const label = t('environment.label', {
    state: state ? t(`environment.state.${state}`) : t('environment.state.loading'),
  })
  return (
    <a href={href('environment')} aria-label={label} style={{ textDecoration: 'none' }}>
      <EnvironmentStateBadge state={state} />
    </a>
  )
}
