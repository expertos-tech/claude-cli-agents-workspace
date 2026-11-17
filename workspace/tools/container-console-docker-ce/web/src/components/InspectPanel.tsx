import { useEffect, useState } from 'react'
import { apiGet, errorBodyOf } from '../api/client'
import type { ApiErrorBody } from '../api/types'
import { t } from '../i18n/messages'
import { ErrorDetail } from './ErrorDetail'
import { uiStyles } from './ui'

export interface InspectState<Details> {
  data: Details | null
  error: ApiErrorBody | null
}

/** Reads the details of a resource. `refreshKey` changing, such as a new status, reads them again. */
export function useInspect<Details = unknown>(path: string, refreshKey = ''): InspectState<Details> {
  const [state, setState] = useState<InspectState<Details>>({ data: null, error: null })
  useEffect(() => {
    const controller = new AbortController()
    apiGet<Details>(path, controller.signal)
      .then(data => setState({ data, error: null }))
      .catch((error: unknown) => {
        if (!controller.signal.aborted) {
          setState(previous => ({ data: previous.data, error: errorBodyOf(error) }))
        }
      })
    return () => controller.abort()
  }, [path, refreshKey])
  return state
}

interface InspectJsonProps {
  state: InspectState<unknown>
}

/** Everything the service returned about a resource, one disclosure away. */
export function InspectJson({ state }: InspectJsonProps) {
  return (
    <div className={uiStyles.stack}>
      {state.error && (
        <>
          <p>{t('details.unavailable')}</p>
          <ErrorDetail error={state.error} />
        </>
      )}
      {!state.data && !state.error && <p className={uiStyles.hint}>{t('details.loading')}</p>}
      {state.data !== null && (
        <details className={uiStyles.disclosure}>
          <summary>{t('details.fullJson')}</summary>
          <pre className={uiStyles.pre} tabIndex={0} aria-label={t('details.fullJson')}>
            {JSON.stringify(state.data, null, 2)}
          </pre>
        </details>
      )}
    </div>
  )
}
