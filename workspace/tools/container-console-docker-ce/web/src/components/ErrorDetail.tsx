import type { ApiErrorBody } from '../api/types'
import { errorSentence } from '../i18n/errors'
import { t } from '../i18n/messages'
import { uiStyles } from './ui'

interface ErrorDetailProps {
  error: ApiErrorBody
}

/** Shows an error as received, after the sentence of its code when there is one. */
export function ErrorDetail({ error }: ErrorDetailProps) {
  const sentence = errorSentence(error.code, error.params)
  return (
    <div className={uiStyles.stack}>
      {sentence && <p>{sentence}</p>}
      {error.message && (
        <div className={uiStyles.field}>
          <span className={uiStyles.detailTerm}>{t('error.received')}</span>
          <pre className={uiStyles.pre}>{error.message}</pre>
        </div>
      )}
      {error.exitCode !== undefined && (
        <p className={uiStyles.hint}>{t('error.exitCode', { code: String(error.exitCode) })}</p>
      )}
    </div>
  )
}
