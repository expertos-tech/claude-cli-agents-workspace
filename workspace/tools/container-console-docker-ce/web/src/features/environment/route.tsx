import type { EnvironmentSnapshot } from '../../api/types'
import { useLive } from '../../api/useLive'
import { EnvironmentStateBadge } from '../../components/EnvironmentBadge'
import { MonoId } from '../../components/MonoId'
import { Card, DetailList, Notice, Page, PageHeader, uiStyles } from '../../components/ui'
import { bytesToGiB, createTranslator, formatNumber } from '../../i18n'
import type { FeatureRoute } from '../../routing'
import { messages } from './messages'

const t = createTranslator(messages)

/** The state, with what to do when the daemon is not on. The console never runs the command it shows. */
function StateNotice({ environment }: { environment: EnvironmentSnapshot }) {
  if (environment.state === 'off') {
    return (
      <Notice icon="alert">
        <p>{t('stateOff')}</p>
        <pre className={uiStyles.pre}>{t('startCommand')}</pre>
      </Notice>
    )
  }
  return (
    <Notice icon="alert">
      <p>{t('stateUnknown')}</p>
      {environment.reason && <pre className={uiStyles.pre}>{environment.reason}</pre>}
    </Notice>
  )
}

/** The data `docker info` gives. */
function DaemonDetails({ environment }: { environment: EnvironmentSnapshot }) {
  return (
    <DetailList
      items={[
        { term: t('version'), value: <MonoId value={environment.serverVersion ?? ''} /> },
        { term: t('cpus'), value: formatNumber(environment.cpus ?? 0) },
        { term: t('memory'), value: t('memoryValue', { value: bytesToGiB(environment.memoryBytes ?? 0) }) },
        { term: t('driver'), value: <MonoId value={environment.storageDriver ?? ''} /> },
        { term: t('system'), value: environment.operatingSystem ?? '' },
        { term: t('architecture'), value: <MonoId value={environment.architecture ?? ''} /> },
      ]}
    />
  )
}

/** Explains which screens wait for the daemon. */
function UnavailableCard() {
  return (
    <Card title={t('unavailableTitle')}>
      <ul className={uiStyles.bulletList}>
        <li>{t('unavailableDocker')}</li>
        <li>{t('unavailableCompose')}</li>
      </ul>
      <p className={uiStyles.hint}>{t('kubernetesNote')}</p>
    </Card>
  )
}

/** The read-only screen of the Docker daemon. */
function EnvironmentPage() {
  const environment = useLive('environment').data
  return (
    <Page>
      <PageHeader title={t('title')} description={t('description')} />
      {environment && (
        <Card title={t('statusTitle')} actions={<EnvironmentStateBadge state={environment.state} />}>
          {environment.state === 'on' ? (
            <DaemonDetails environment={environment} />
          ) : (
            <StateNotice environment={environment} />
          )}
        </Card>
      )}
      {environment?.state === 'off' && <UnavailableCard />}
    </Page>
  )
}

export const route: FeatureRoute = {
  id: 'environment',
  order: 20,
  group: 'main',
  icon: 'environment',
  Page: EnvironmentPage,
}
