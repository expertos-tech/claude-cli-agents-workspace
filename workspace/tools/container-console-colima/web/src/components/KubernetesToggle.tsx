import type { EnvironmentSnapshot, KubernetesSnapshot } from '../api/types'
import { useJob } from '../api/useJob'
import { t } from '../i18n/messages'
import { Button } from './Button'
import { ConfirmButton } from './ConfirmDialog'
import { StatusBadge, type Tone } from './StatusBadge'
import { uiStyles } from './ui'

/** Reads the state of Kubernetes for the badge. */
function badgeOf(environment: EnvironmentSnapshot): { tone: Tone; label: string } {
  const { enabled, transition } = environment.kubernetes
  if (transition === 'starting') {
    return { tone: 'progress', label: t('kubernetes.state.starting') }
  }
  if (transition === 'stopping') {
    return { tone: 'progress', label: t('kubernetes.state.stopping') }
  }
  return enabled
    ? { tone: 'good', label: t('kubernetes.state.on') }
    : { tone: 'neutral', label: t('kubernetes.state.off') }
}

interface KubernetesToggleProps {
  environment: EnvironmentSnapshot
  kubernetes: KubernetesSnapshot | null
}

/** Turns Kubernetes on and off without restarting the VM. Turning off lists the pods that stop. */
export function KubernetesToggle({ environment, kubernetes }: KubernetesToggleProps) {
  const { run, isBusy } = useJob()
  const badge = badgeOf(environment)
  const environmentOn = environment.state === 'on'
  const inTransition = environment.kubernetes.transition !== undefined
  const disabled = !environmentOn || inTransition
  const busy = isBusy(environment.profile)
  const pods = kubernetes?.pods ?? []
  const reason = !environmentOn
    ? t('kubernetes.needsEnvironment')
    : inTransition
      ? t('kubernetes.transitionRunning')
      : null

  return (
    <div className={uiStyles.stack}>
      <div className={uiStyles.row}>
        <StatusBadge tone={badge.tone} label={badge.label} />
        {environment.kubernetes.enabled ? (
          <ConfirmButton
            label={t('kubernetes.stop')}
            icon="stop"
            disabled={disabled}
            busy={busy}
            dialogTitle={t('kubernetes.stopTitle')}
            confirmLabel={t('kubernetes.stop')}
            onConfirm={() =>
              run('kubernetes.stop', environment.profile, '/api/environment/kubernetes/stop', { confirm: true })
            }
          >
            {pods.length === 0 ? (
              <p>{t('kubernetes.stopBodyNone')}</p>
            ) : (
              <>
                <p>{t('kubernetes.stopBody')}</p>
                <ul className={uiStyles.bulletList}>
                  {pods.map(pod => (
                    <li key={`${pod.namespace}/${pod.name}`}>{`${pod.namespace}/${pod.name}`}</li>
                  ))}
                </ul>
              </>
            )}
          </ConfirmButton>
        ) : (
          <Button
            icon="play"
            disabled={disabled}
            busy={busy}
            onClick={() => run('kubernetes.start', environment.profile, '/api/environment/kubernetes/start')}
          >
            {t('kubernetes.start')}
          </Button>
        )}
      </div>
      {reason && <p className={uiStyles.hint}>{reason}</p>}
    </div>
  )
}
