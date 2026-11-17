import type { EnvironmentSnapshot } from '../../api/types'
import { useLive } from '../../api/useLive'
import { LinkButton } from '../../components/Button'
import { EnvironmentStateBadge } from '../../components/EnvironmentBadge'
import { Icon, type IconName } from '../../components/Icon'
import { Card, Meter, Notice, Page, PageHeader, uiStyles } from '../../components/ui'
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
    case 'starting':
      return t('starting')
    case 'stopping':
      return t('stopping')
    case 'unknown':
      return t('unknown')
    case 'on':
      return null
  }
}

/** The state of the environment, what it has allocated and the way to change it. */
function EnvironmentCard({ environment }: { environment: EnvironmentSnapshot }) {
  const { usage, host } = environment
  const memory = bytesToGiB(usage.memoryBytes)
  const hostMemory = bytesToGiB(host.memoryBytes)
  const sentence = stateSentence(environment)
  return (
    <Card
      title={t('environmentTitle')}
      actions={
        environment.state === 'off' ? (
          <LinkButton variant="primary" icon="play" href={href('environment')}>
            {t('turnOn')}
          </LinkButton>
        ) : (
          <LinkButton icon="environment" href={href('environment')}>
            {t('manage')}
          </LinkButton>
        )
      }
    >
      <div className={uiStyles.row}>
        <EnvironmentStateBadge state={environment.state} />
        <span className={uiStyles.hint}>
          {t('profile')}: {environment.profile}
        </span>
        {environment.state === 'on' && (
          <span className={uiStyles.hint}>
            {t('mode')}: {environment.kubernetes.enabled ? t('modeKubernetes') : t('modeDocker')}
          </span>
        )}
      </div>
      {sentence && (
        <Notice>
          <p>{sentence}</p>
          {environment.reason && <pre className={uiStyles.pre}>{environment.reason}</pre>}
        </Notice>
      )}
      <div className={styles.metrics}>
        <div className={uiStyles.metric}>
          <span className={uiStyles.detailTerm}>{t('cpus')}</span>
          <span className={uiStyles.figure}>{t('cpusValue', { used: usage.cpus, total: host.cpus })}</span>
          <Meter ratio={host.cpus > 0 ? usage.cpus / host.cpus : 0} />
        </div>
        <div className={uiStyles.metric}>
          <span className={uiStyles.detailTerm}>{t('memory')}</span>
          <span className={uiStyles.figure}>
            {hostMemory > 0
              ? t('memoryValue', { used: memory, total: hostMemory })
              : t('memoryValueNoTotal', { used: memory })}
          </span>
          <Meter ratio={hostMemory > 0 ? memory / hostMemory : 0} />
        </div>
        <div className={uiStyles.metric}>
          <span className={uiStyles.detailTerm}>{t('disk')}</span>
          <span className={uiStyles.figure}>{t('diskValue', { used: bytesToGiB(usage.diskBytes) })}</span>
        </div>
      </div>
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

/** The home screen: environment state and how many resources exist. */
function OverviewPage() {
  const environment = useLive('environment').data
  const docker = useLive('docker').data
  const kubernetesOn = environment?.state === 'on' && environment.kubernetes.enabled
  const kubernetes = useLive('kubernetes', kubernetesOn).data
  const dockerReady = docker?.available === true
  const kubernetesReady = kubernetesOn && kubernetes?.available === true
  const running = docker?.containers.filter(item => item.state === 'running').length ?? 0
  const dockerCount = (count: number | undefined): number | null => (dockerReady ? (count ?? 0) : null)
  const clusterCount = (count: number | undefined): number | null => (kubernetesReady ? (count ?? 0) : null)
  const clusterUnavailable = kubernetesOn ? t('unavailable') : t('kubernetesOff')

  return (
    <Page>
      <PageHeader eyebrow={t('eyebrow')} title={t('title')} description={t('description')} />
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
            unavailableText={clusterUnavailable}
          />
          <CountCard
            label={t('pods')}
            icon="kubernetes"
            to={href('kubernetes', 'pods')}
            count={clusterCount(kubernetes?.pods.length)}
            unavailableText={clusterUnavailable}
          />
          <CountCard
            label={t('deployments')}
            icon="kubernetes"
            to={href('kubernetes', 'deployments')}
            count={clusterCount(kubernetes?.deployments.length)}
            unavailableText={clusterUnavailable}
          />
          <CountCard
            label={t('services')}
            icon="kubernetes"
            to={href('kubernetes', 'services')}
            count={clusterCount(kubernetes?.services.length)}
            unavailableText={clusterUnavailable}
          />
        </ul>
      </Card>
    </Page>
  )
}

export const route: FeatureRoute = { id: 'overview', order: 10, group: 'main', icon: 'home', Page: OverviewPage }
