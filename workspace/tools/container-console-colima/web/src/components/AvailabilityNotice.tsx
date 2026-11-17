import { t } from '../i18n/messages'
import { href } from '../routing'
import { Notice, uiStyles } from './ui'

const SENTENCES = {
  docker: {
    environment_not_on: 'availability.environment_not_on',
    docker_error: 'availability.docker_error',
  },
  kubernetes: {
    environment_not_on: 'availability.kubernetes_environment_off',
    kubernetes_not_on: 'availability.kubernetes_not_on',
    kubernetes_error: 'availability.kubernetes_error',
  },
} as const

interface AvailabilityNoticeProps {
  /** Id for `aria-describedby` on the controls this notice explains. */
  id?: string
  source: keyof typeof SENTENCES
  /** The topic has not sent its first snapshot yet. */
  loading: boolean
  reasonCode: string | undefined
  reason: string | undefined
}

/** Explains why the actions are disabled instead of hiding them. */
export function AvailabilityNotice({ id, source, loading, reasonCode, reason }: AvailabilityNoticeProps) {
  if (loading) {
    return (
      <Notice id={id}>
        <p>{t('availability.loading')}</p>
      </Notice>
    )
  }
  const sentences: Partial<Record<string, Parameters<typeof t>[0]>> = SENTENCES[source]
  const key = reasonCode ? sentences[reasonCode] : undefined
  const showRaw = reason && (!key || reasonCode?.endsWith('_error'))
  return (
    <Notice id={id} icon="alert">
      {key && <p>{t(key)}</p>}
      {showRaw && <pre className={uiStyles.pre}>{reason}</pre>}
      <p>
        <a href={href('environment')}>{t('availability.goToEnvironment')}</a>
      </p>
    </Notice>
  )
}
