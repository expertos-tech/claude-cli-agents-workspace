import { useEffect, useRef } from 'react'
import type { ApiErrorBody, Job } from '../api/types'
import { formatTime } from '../i18n'
import { jobSentence } from '../i18n/jobs'
import { t } from '../i18n/messages'
import { Button } from './Button'
import { ErrorDetail } from './ErrorDetail'
import styles from './JobAlert.module.css'
import { StatusBadge, type Tone } from './StatusBadge'
import { uiStyles } from './ui'

const TONE_BY_STATUS: Record<Job['status'], Tone> = {
  running: 'progress',
  succeeded: 'good',
  failed: 'critical',
}

interface JobOutputProps {
  job: Job
  subject: string
}

/** The output lines of a job, following the end while it runs. */
function JobOutput({ job, subject }: JobOutputProps) {
  const ref = useRef<HTMLPreElement>(null)
  // biome-ignore lint/correctness/useExhaustiveDependencies: scrolls to the end each time a new output line arrives
  useEffect(() => {
    if (ref.current) {
      ref.current.scrollTop = ref.current.scrollHeight
    }
  }, [job.output.length])
  return (
    <details className={uiStyles.disclosure} open={job.status !== 'succeeded'}>
      <summary>{t('dock.output')}</summary>
      {/* biome-ignore lint/a11y: a scrolling block must take keyboard focus to be scrolled without a mouse; the label names it */}
      <pre ref={ref} className={uiStyles.pre} tabIndex={0} aria-label={t('dock.outputLabel', { subject })}>
        {job.output.join('\n')}
      </pre>
    </details>
  )
}

interface JobAlertProps {
  job: Job
  onDismiss: () => void
}

/** One action: what it is, its real state, its output and the error as received. */
export function JobAlert({ job, onDismiss }: JobAlertProps) {
  const subject = jobSentence(job.kind, job.target)
  return (
    <article className={styles.alert} role={job.status === 'failed' ? 'alert' : undefined}>
      <div className={styles.header}>
        <div className={styles.summary}>
          <StatusBadge tone={TONE_BY_STATUS[job.status]} label={t(`job.status.${job.status}`)} />
          <strong className={styles.subject}>{subject}</strong>
          <span className={uiStyles.hint}>{t('dock.startedAt', { time: formatTime(job.startedAt) })}</span>
        </div>
        {job.status !== 'running' && (
          <Button size="compact" icon="close" aria-label={t('action.dismiss', { subject })} onClick={onDismiss}>
            {t('action.dismissShort')}
          </Button>
        )}
      </div>
      {job.error && <ErrorDetail error={job.error} />}
      {job.output.length > 0 && <JobOutput key={job.status} job={job} subject={subject} />}
    </article>
  )
}

interface RefusalAlertProps {
  subject: string
  error: ApiErrorBody
  onDismiss: () => void
}

/** A request refused before becoming a job: nothing ran, and the reason appears as received. */
export function RefusalAlert({ subject, error, onDismiss }: RefusalAlertProps) {
  return (
    <article className={styles.alert} role="alert">
      <div className={styles.header}>
        <div className={styles.summary}>
          <StatusBadge tone="critical" label={t('job.status.refused')} />
          <strong className={styles.subject}>{subject}</strong>
        </div>
        <Button size="compact" icon="close" aria-label={t('action.dismiss', { subject })} onClick={onDismiss}>
          {t('action.dismissShort')}
        </Button>
      </div>
      <ErrorDetail error={error} />
    </article>
  )
}
