import type { EnvironmentSnapshot } from '../../api/types'
import { useLive } from '../../api/useLive'
import { LinkButton } from '../../components/Button'
import { EnvironmentStateBadge } from '../../components/EnvironmentBadge'
import { Icon, type IconName } from '../../components/Icon'
import { Card, Notice, Page, PageHeader, uiStyles } from '../../components/ui'
import { bytesToGiB, createTranslator, formatNumber } from '../../i18n'
import { type FeatureRoute, href } from '../../routing'
import { messages } from './messages'
import styles from './overview.module.css'

const t = createTranslator(messages)

/** The state sentence of everything but `on`, which needs none. */
function stateSentence(environment: EnvironmentSnapshot): string | null {
  switch (environment.state) {
    case 'off':
      return t('off')
    case 'unknown':
      return t('unknown')
    case 'on':
      return null
  }
}

/** The state of the daemon, its main data and the way to the screen with the rest. */
function EnvironmentCard({ environment }: { environment: EnvironmentSnapshot }) {
  const sentence = stateSentence(environment)
  return (
    <Card
      title={t('environmentTitle')}
      actions={
        <LinkButton icon="environment" href={href('environment')}>
          {t('details')}
        </LinkButton>
      }
    >
      <div className={uiStyles.row}>
        <EnvironmentStateBadge state={environment.state} />
      </div>
      {sentence && (
        <Notice>
          <p>{sentence}</p>
          {environment.state === 'unknown' && environment.reason && (
            <pre className={uiStyles.pre}>{environment.reason}</pre>
          )}
        </Notice>
      )}
      {environment.state === 'on' && (
        <div className={styles.metrics}>
          <div className={uiStyles.metric}>
            <span className={uiStyles.detailTerm}>{t('version')}</span>
            <span className={uiStyles.figure}>{environment.serverVersion}</span>
          </div>
          <div className={uiStyles.metric}>
            <span className={uiStyles.detailTerm}>{t('cpus')}</span>
            <span className={uiStyles.figure}>{formatNumber(environment.cpus ?? 0)}</span>
          </div>
          <div className={uiStyles.metric}>
            <span className={uiStyles.detailTerm}>{t('memory')}</span>
            <span className={uiStyles.figure}>
              {t('memoryValue', { value: bytesToGiB(environment.memoryBytes ?? 0) })}
            </span>
          </div>
        </div>
      )}
    </Card>
  )
}

interface CountCardProps {
  label: string
  icon: IconName
  to: string
  /** Null when the topic does not have the list. */
  count: number | null
  detail?: string
  unavailableText: string
}

/** A count that links to its screen. */
function CountCard({ label, icon, to, count, detail, unavailableText }: CountCardProps) {
  return (
    <li>
      <a className={styles.countCard} href={to}>
        <span className={styles.countLabel}>
          <Icon name={icon} />
          {label}
        </span>
        {count === null ? (
          <span className={styles.countUnavailable}>{unavailableText}</span>
        ) : (
          <span className={uiStyles.figure}>{formatNumber(count)}</span>
        )}
        {detail && <span className={uiStyles.hint}>{detail}</span>}
      </a>
    </li>
  )
}

/** The home screen: daemon state and how many resources exist. */
function OverviewPage() {
  const environment = useLive('environment').data
  const docker = useLive('docker').data
  const kubernetes = useLive('kubernetes').data
  const dockerReady = docker?.available === true
  const kubernetesReady = kubernetes?.available === true
  const running = docker?.containers.filter(item => item.state === 'running').length ?? 0
  const dockerCount = (count: number | undefined): number | null => (dockerReady ? (count ?? 0) : null)
  const clusterCount = (count: number | undefined): number | null => (kubernetesReady ? (count ?? 0) : null)

  return (
    <Page>
      <PageHeader title={t('title')} description={t('description')} />
      {environment ? <EnvironmentCard environment={environment} /> : <Notice>{t('loading')}</Notice>}
      <Card title={t('resourcesTitle')}>
        <ul className={styles.counts}>
          <CountCard
            label={t('containers')}
            icon="container"
            to={href('containers')}
            count={dockerCount(docker?.containers.length)}
            detail={dockerReady ? t('containersValue', { running, count: docker?.containers.length ?? 0 }) : undefined}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('images')}
            icon="image"
            to={href('images')}
            count={dockerCount(docker?.images.length)}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('volumes')}
            icon="volume"
            to={href('volumes')}
            count={dockerCount(docker?.volumes.length)}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('networks')}
            icon="network"
            to={href('networks')}
            count={dockerCount(docker?.networks.length)}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('compose')}
            icon="compose"
            to={href('compose')}
            count={docker ? docker.composeProjects.length : null}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('namespaces')}
            icon="kubernetes"
            to={href('kubernetes', 'namespaces')}
            count={clusterCount(kubernetes?.namespaces.length)}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('pods')}
            icon="kubernetes"
            to={href('kubernetes', 'pods')}
            count={clusterCount(kubernetes?.pods.length)}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('deployments')}
            icon="kubernetes"
            to={href('kubernetes', 'deployments')}
            count={clusterCount(kubernetes?.deployments.length)}
            unavailableText={t('unavailable')}
          />
          <CountCard
            label={t('services')}
            icon="kubernetes"
            to={href('kubernetes', 'services')}
            count={clusterCount(kubernetes?.services.length)}
            unavailableText={t('unavailable')}
          />
        </ul>
      </Card>
    </Page>
  )
}

export const route: FeatureRoute = { id: 'overview', order: 10, group: 'main', icon: 'home', Page: OverviewPage }
