import { useEffect, useId, useState } from 'react'
import { apiGet } from '../../api/client'
import type { CleanupItem, CleanupSummary } from '../../api/types'
import { useJob } from '../../api/useJob'
import { useLive } from '../../api/useLive'
import { AvailabilityNotice } from '../../components/AvailabilityNotice'
import { ConfirmButton } from '../../components/ConfirmDialog'
import { MonoId } from '../../components/MonoId'
import { Card, Notice, Page, PageHeader, uiStyles } from '../../components/ui'
import { createTranslator, formatNumber } from '../../i18n'
import type { FeatureRoute } from '../../routing'
import styles from './Cleanup.module.css'
import { messages } from './messages'

const t = createTranslator(messages)

const JOB_KIND = 'docker.cleanup'

type Category = 'containers' | 'images' | 'networks' | 'volumes'

const CATEGORIES: Category[] = ['containers', 'images', 'networks', 'volumes']

type SummaryState = { phase: 'loading' } | { phase: 'failed' } | { phase: 'ready'; summary: CleanupSummary }

/**
 * Reads the summary again whenever the Docker snapshot changes or a cleanup ends, so it always
 * describes what a click would remove now.
 */
function useCleanupSummary(available: boolean, refreshKey: unknown): SummaryState {
  const [state, setState] = useState<SummaryState>({ phase: 'loading' })
  useEffect(() => {
    if (!available) return
    const controller = new AbortController()
    apiGet<CleanupSummary>('/api/cleanup', controller.signal)
      .then(summary => setState({ phase: 'ready', summary }))
      .catch(() => {
        if (!controller.signal.aborted) setState({ phase: 'failed' })
      })
    return () => controller.abort()
  }, [available, refreshKey])
  return state
}

/** One kind of resource: how many there are, and the list behind a disclosure. */
function CategoryRow({ category, items }: { category: Category; items: CleanupItem[] }) {
  return (
    <div className={styles.category}>
      <dt className={styles.term}>{t(category)}</dt>
      <dd className={styles.value}>
        <span className={styles.count}>{items.length === 0 ? t('none') : formatNumber(items.length)}</span>
        {items.length > 0 && (
          <details className={styles.disclosure}>
            <summary>{t('showList', { count: items.length })}</summary>
            <ul className={styles.list}>
              {items.map(item => (
                <li key={item.id}>
                  <MonoId value={item.name} />
                  {item.detail && <span className={uiStyles.hint}>{item.detail}</span>}
                </li>
              ))}
            </ul>
          </details>
        )}
      </dd>
    </div>
  )
}

/** The text of the confirmation: what goes, what stays, and that it acts on the state at that time. */
function ConfirmationBody({ summary, withVolumes }: { summary: CleanupSummary; withVolumes: boolean }) {
  return (
    <>
      <p>
        {t('cleanBody', {
          containers: summary.containers.length,
          images: summary.images.length,
          networks: summary.networks.length,
          buildCache: summary.buildCache,
        })}
      </p>
      <p>{withVolumes ? t('cleanVolumes', { volumes: summary.volumes.length }) : t('cleanKeepsVolumes')}</p>
      <p>{t('cleanRace')}</p>
    </>
  )
}

/** True when the cleanup would remove nothing, volumes counted only when chosen. */
function isEmpty(summary: CleanupSummary, withVolumes: boolean): boolean {
  const counted = withVolumes ? CATEGORIES : CATEGORIES.filter(category => category !== 'volumes')
  return counted.every(category => summary[category].length === 0) && /^0(\.0+)?\s*B$/i.test(summary.buildCache)
}

/** The summary of what is not in use and the button that removes it. */
function CleanupPage() {
  const docker = useLive('docker')
  const jobs = useLive('jobs').data?.jobs ?? []
  const { run } = useJob()
  const noticeId = useId()
  const volumesHintId = useId()
  const [withVolumes, setWithVolumes] = useState(false)
  const available = docker.data?.available ?? false
  const running = jobs.some(job => job.kind === JOB_KIND && job.status === 'running')
  const state = useCleanupSummary(available, `${JSON.stringify(docker.data)}|${running}`)
  const summary = state.phase === 'ready' ? state.summary : null
  const empty = summary ? isEmpty(summary, withVolumes) : true

  return (
    <Page>
      <PageHeader title={t('title')} description={t('description')} />
      {!available && (
        <AvailabilityNotice
          id={noticeId}
          source="docker"
          loading={!docker.data}
          reasonCode={docker.data?.reasonCode}
          reason={docker.data?.reason}
        />
      )}
      {available && state.phase === 'loading' && <Notice icon="hourglass">{t('loading')}</Notice>}
      {available && state.phase === 'failed' && <Notice icon="alert">{t('loadFailed')}</Notice>}
      {running && <Notice icon="hourglass">{t('running')}</Notice>}
      {summary && (
        <Card title={t('summaryTitle')}>
          <dl className={styles.summary}>
            {CATEGORIES.map(category => (
              <CategoryRow key={category} category={category} items={summary[category]} />
            ))}
            <div className={styles.category}>
              <dt className={styles.term}>{t('buildCache')}</dt>
              <dd className={styles.value}>
                <span className={styles.count}>{summary.buildCache}</span>
              </dd>
            </div>
          </dl>
          <div className={styles.option}>
            <input
              id={`${volumesHintId}-input`}
              type="checkbox"
              className={styles.checkbox}
              checked={withVolumes}
              aria-describedby={volumesHintId}
              onChange={event => setWithVolumes(event.target.checked)}
            />
            <label htmlFor={`${volumesHintId}-input`}>{t('includeVolumes')}</label>
            <span id={volumesHintId} className={`${uiStyles.hint} ${styles.optionHint}`}>
              {t('includeVolumesHint')}
            </span>
          </div>
          {empty ? (
            <Notice icon="check">{t('nothing')}</Notice>
          ) : (
            <div>
              <ConfirmButton
                label={t('clean')}
                icon="trash"
                variant="primary"
                busy={running}
                disabled={!available || running}
                describedBy={available ? undefined : noticeId}
                dialogTitle={t('cleanTitle')}
                confirmLabel={t('clean')}
                irreversible
                onConfirm={() =>
                  run(JOB_KIND, withVolumes ? 'volumes' : '', '/api/cleanup', {
                    confirm: true,
                    volumes: withVolumes,
                  })
                }
              >
                <ConfirmationBody summary={summary} withVolumes={withVolumes} />
              </ConfirmButton>
            </div>
          )}
        </Card>
      )}
    </Page>
  )
}

export const route: FeatureRoute = { id: 'cleanup', order: 75, group: 'docker', icon: 'trash', Page: CleanupPage }
