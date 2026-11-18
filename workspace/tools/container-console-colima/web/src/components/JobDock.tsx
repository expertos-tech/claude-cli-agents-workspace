import { useRef } from 'react'
import { dismissEntry, toggleDock, useDockEntries } from '../api/useJob'
import { jobSentence } from '../i18n/jobs'
import { t } from '../i18n/messages'
import { Button } from './Button'
import { JobAlert, RefusalAlert } from './JobAlert'
import styles from './JobDock.module.css'

/** The element that receives the focus of a skip link, a new screen or an empty dock. */
export const MAIN_CONTENT_ID = 'main-content'

/**
 * The single place where actions report back, whatever screen the user is on. It takes its own
 * row in the layout, below the content, so it never covers what has the focus.
 */
export function JobDock() {
  const { jobs, refusals, collapsed } = useDockEntries()
  const running = jobs.filter(job => job.status === 'running').length
  const failed = jobs.filter(job => job.status === 'failed').length + refusals.length
  const summary = [
    running > 0 ? t('dock.summaryRunning', { count: running }) : null,
    failed > 0 ? t('dock.summaryFailed', { count: failed }) : null,
  ]
    .filter(Boolean)
    .join(' ')
  const hasEntries = jobs.length > 0 || refusals.length > 0
  const finished = jobs.filter(job => job.status !== 'running')
  const listRef = useRef<HTMLUListElement>(null)

  /** Removes an entry and keeps the focus nearby, since the button pressed is about to go away. */
  function dismiss(id: string): void {
    const isLastEntry = jobs.length + refusals.length === 1
    ;(isLastEntry ? document.getElementById(MAIN_CONTENT_ID) : listRef.current)?.focus()
    dismissEntry(id)
  }

  /** Removes every finished action. The focus goes to the content if nothing else stays. */
  function clearFinished(): void {
    const nothingStays = finished.length === jobs.length && refusals.length === 0
    ;(nothingStays ? document.getElementById(MAIN_CONTENT_ID) : listRef.current)?.focus()
    for (const job of finished) {
      dismissEntry(job.id)
    }
  }

  return (
    <>
      <div className="visually-hidden" role="status">
        {summary}
      </div>
      {hasEntries && (
        <section className={styles.dock} aria-label={t('dock.label')}>
          <div className={styles.header}>
            <h2 className={styles.title}>{t('dock.title')}</h2>
            <span className={styles.summary}>{summary || t('dock.summaryIdle')}</span>
            <div className={styles.controls}>
              {finished.length > 0 && !collapsed && (
                <Button size="compact" onClick={clearFinished}>
                  {t('action.clearFinished')}
                </Button>
              )}
              <Button
                size="compact"
                icon="chevronDown"
                className={styles.toggle}
                aria-expanded={!collapsed}
                onClick={toggleDock}
              >
                {collapsed ? t('action.expand') : t('action.collapse')}
              </Button>
            </div>
          </div>
          {!collapsed && (
            // biome-ignore lint/a11y/noNoninteractiveTabindex: a scrolling block must take keyboard focus to be scrolled without a mouse; the label names it
            <ul ref={listRef} className={styles.list} tabIndex={0} aria-label={t('dock.title')}>
              {refusals.map(refusal => (
                <li key={refusal.id}>
                  <RefusalAlert
                    subject={jobSentence(refusal.kind, refusal.target)}
                    error={refusal.error}
                    onDismiss={() => dismiss(refusal.id)}
                  />
                </li>
              ))}
              {jobs.map(job => (
                <li key={job.id}>
                  <JobAlert job={job} onDismiss={() => dismiss(job.id)} />
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </>
  )
}
