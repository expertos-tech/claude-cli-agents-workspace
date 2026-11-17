import { useState } from 'react'
import { segment } from '../../api/client'
import type { Deployment, KubernetesSnapshot, Pod, Service } from '../../api/types'
import { LinkButton } from '../../components/Button'
import { InspectJson, useInspect } from '../../components/InspectPanel'
import { MonoId } from '../../components/MonoId'
import { StatusBadge } from '../../components/StatusBadge'
import { TerminalView } from '../../components/TerminalView'
import {
  Card,
  type DetailItem,
  DetailList,
  Notice,
  PageHeader,
  SelectField,
  TabsNav,
  uiStyles,
} from '../../components/ui'
import { createTranslator, formatNumber, formatTimestamp } from '../../i18n'
import { href } from '../../routing'
import { messages } from './messages'
import { type NamespacedKind, RemoveNamespace, RemoveNamespaced, ScaleButton } from './ResourceActions'
import { podTone } from './ResourceLists'

const t = createTranslator(messages)

interface AvailabilityProps {
  available: boolean
  describedBy: string | undefined
}

/** The header of a details screen, with the way back to its list. */
function DetailsHeader({ name, tab }: { name: string; tab: string }) {
  return (
    <PageHeader
      title={name}
      actions={
        <LinkButton icon="arrowLeft" href={href('kubernetes', tab)}>
          {t('back')}
        </LinkButton>
      }
    />
  )
}

/** The notice of a resource that left the snapshot. */
function Missing() {
  return (
    <Notice icon="alert">
      <p>{t('missing')}</p>
    </Notice>
  )
}

/** The details of a namespace. */
export function NamespaceDetails({
  name,
  snapshot,
  available,
  describedBy,
}: { name: string; snapshot: KubernetesSnapshot | null } & AvailabilityProps) {
  const row = snapshot?.namespaces.find(item => item.name === name)
  const inspect = useInspect(`/api/kubernetes/namespaces/${segment(name)}`, row?.status ?? '')
  return (
    <>
      <DetailsHeader name={name} tab="namespaces" />
      {snapshot && !row && <Missing />}
      <Card title={t('detailsTitle')}>
        {row && (
          <>
            <div className={uiStyles.row}>
              <StatusBadge tone={row.status === 'Active' ? 'good' : 'progress'} label={row.status} />
              <RemoveNamespace name={name} available={available} describedBy={describedBy} size="regular" />
            </div>
            <DetailList items={[{ term: t('columnCreated'), value: formatTimestamp(row.createdAt) }]} />
          </>
        )}
        <InspectJson state={inspect} />
      </Card>
    </>
  )
}

/** The list facts of a deployment. */
function deploymentItems(row: Deployment): DetailItem[] {
  return [
    { term: t('columnNamespace'), value: <MonoId value={row.namespace} /> },
    { term: t('columnReplicas'), value: formatNumber(row.replicas) },
    { term: t('columnReady'), value: formatNumber(row.ready) },
    { term: t('columnUpdated'), value: formatNumber(row.updated) },
    { term: t('columnAvailable'), value: formatNumber(row.available) },
    { term: t('columnCreated'), value: formatTimestamp(row.createdAt) },
  ]
}

/** The list facts of a service. */
function serviceItems(row: Service): DetailItem[] {
  return [
    { term: t('columnNamespace'), value: <MonoId value={row.namespace} /> },
    { term: t('columnType'), value: row.type },
    { term: t('columnClusterIp'), value: <MonoId value={row.clusterIP} /> },
    {
      term: t('columnPorts'),
      value: row.ports.length > 0 ? <MonoId value={row.ports.join(', ')} /> : t('noPorts'),
    },
    { term: t('columnCreated'), value: formatTimestamp(row.createdAt) },
  ]
}

/** The list facts of a pod. */
function podItems(row: Pod): DetailItem[] {
  return [
    { term: t('columnNamespace'), value: <MonoId value={row.namespace} /> },
    { term: t('columnReady'), value: row.ready },
    { term: t('columnRestarts'), value: formatNumber(row.restarts) },
    { term: t('columnIp'), value: row.ip ? <MonoId value={row.ip} /> : t('noIp') },
    { term: t('columnContainers'), value: row.containers.join(', ') },
    { term: t('columnCreated'), value: formatTimestamp(row.createdAt) },
  ]
}

interface NamespacedDetailsProps extends AvailabilityProps {
  kind: Exclude<NamespacedKind, 'pods'>
  namespace: string
  name: string
  snapshot: KubernetesSnapshot | null
}

/** The details of a deployment or service. */
export function NamespacedDetails({ kind, namespace, name, snapshot, available, describedBy }: NamespacedDetailsProps) {
  const deployment =
    kind === 'deployments'
      ? snapshot?.deployments.find(item => item.namespace === namespace && item.name === name)
      : undefined
  const service =
    kind === 'services'
      ? snapshot?.services.find(item => item.namespace === namespace && item.name === name)
      : undefined
  const row = deployment ?? service
  const refreshKey = deployment ? `${deployment.replicas}|${deployment.ready}` : ''
  const inspect = useInspect(`/api/kubernetes/${kind}/${segment(namespace)}/${segment(name)}`, refreshKey)
  return (
    <>
      <DetailsHeader name={name} tab={kind} />
      {snapshot && !row && <Missing />}
      <Card title={t('detailsTitle')}>
        {row && (
          <div className={uiStyles.row}>
            {deployment && (
              <>
                <StatusBadge
                  tone={deployment.ready === deployment.replicas ? 'good' : 'progress'}
                  label={t('replicasReady', { ready: deployment.ready, replicas: deployment.replicas })}
                />
                <ScaleButton deployment={deployment} available={available} describedBy={describedBy} size="regular" />
              </>
            )}
            <RemoveNamespaced
              kind={kind}
              namespace={namespace}
              name={name}
              available={available}
              describedBy={describedBy}
              size="regular"
            />
          </div>
        )}
        {deployment && <DetailList items={deploymentItems(deployment)} />}
        {service && <DetailList items={serviceItems(service)} />}
        <InspectJson state={inspect} />
      </Card>
    </>
  )
}

/** The summary of a pod, reading its details again when the status changes. */
function PodSummary({
  pod,
  namespace,
  name,
  available,
  describedBy,
}: { pod: Pod | undefined; namespace: string; name: string } & AvailabilityProps) {
  const inspect = useInspect(`/api/kubernetes/pods/${segment(namespace)}/${segment(name)}`, pod?.status ?? '')
  return (
    <Card title={t('detailsTitle')}>
      {pod && (
        <>
          <div className={uiStyles.row}>
            <StatusBadge tone={podTone(pod.status)} label={pod.status} />
            <RemoveNamespaced
              kind="pods"
              namespace={namespace}
              name={name}
              available={available}
              describedBy={describedBy}
              size="regular"
            />
          </div>
          <DetailList items={podItems(pod)} />
        </>
      )}
      <InspectJson state={inspect} />
    </Card>
  )
}

interface PodDetailsProps extends AvailabilityProps {
  namespace: string
  name: string
  view: string | undefined
  snapshot: KubernetesSnapshot | null
}

/** Details, live logs and terminal of a pod. */
export function PodDetails({ namespace, name, view, snapshot, available, describedBy }: PodDetailsProps) {
  const pod = snapshot?.pods.find(item => item.namespace === namespace && item.name === name)
  const containers = pod?.containers ?? []
  const [chosen, setChosen] = useState('')
  const container = containers.includes(chosen) ? chosen : (containers[0] ?? '')
  const socketPath = `${segment(namespace)}/${segment(name)}`
  const query = container ? { container } : undefined
  const picker =
    containers.length > 1 ? (
      <SelectField
        label={t('containerLabel')}
        options={containers.map(item => ({ value: item, label: item }))}
        value={container}
        onChange={event => setChosen(event.target.value)}
      />
    ) : null

  return (
    <>
      <DetailsHeader name={name} tab="pods" />
      {snapshot && !pod && <Missing />}
      <TabsNav
        label={t('viewsLabel')}
        items={[
          {
            label: t('viewSummary'),
            href: href('kubernetes', 'pods', namespace, name),
            icon: 'info',
            current: !view,
          },
          {
            label: t('viewLogs'),
            href: href('kubernetes', 'pods', namespace, name, 'logs'),
            icon: 'logs',
            current: view === 'logs',
          },
          {
            label: t('viewTerminal'),
            href: href('kubernetes', 'pods', namespace, name, 'terminal'),
            icon: 'terminal',
            current: view === 'terminal',
          },
        ]}
      />
      {!view && (
        <PodSummary pod={pod} namespace={namespace} name={name} available={available} describedBy={describedBy} />
      )}
      {view === 'logs' && pod && (
        <Card>
          {picker}
          <TerminalView
            mode="logs"
            path={`/ws/logs/pods/${socketPath}`}
            label={t('logsLabel', { name })}
            query={query}
          />
        </Card>
      )}
      {view === 'terminal' && pod && (
        <Card>
          {picker}
          <TerminalView
            mode="terminal"
            path={`/ws/terminal/pods/${socketPath}`}
            label={t('terminalLabel', { name })}
            query={query}
          />
        </Card>
      )}
    </>
  )
}
