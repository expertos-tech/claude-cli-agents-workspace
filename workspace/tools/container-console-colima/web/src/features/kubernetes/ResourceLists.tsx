import { useState } from 'react'
import type { Deployment, KubernetesSnapshot, Namespace, Pod, Service } from '../../api/types'
import { DataTable } from '../../components/DataTable'
import { MonoId } from '../../components/MonoId'
import { StatusBadge, type Tone } from '../../components/StatusBadge'
import { Card, SelectField, uiStyles } from '../../components/ui'
import { createTranslator, formatNumber, formatTimestamp } from '../../i18n'
import { href } from '../../routing'
import { messages } from './messages'
import { RemoveNamespace, RemoveNamespaced, ScaleButton } from './ResourceActions'

const t = createTranslator(messages)

const ALL_NAMESPACES = ''

const TONE_BY_POD_STATUS: Record<string, Tone> = {
  Running: 'good',
  Succeeded: 'neutral',
  Completed: 'neutral',
  Pending: 'progress',
  ContainerCreating: 'progress',
  PodInitializing: 'progress',
  Terminating: 'progress',
  Failed: 'critical',
  CrashLoopBackOff: 'critical',
  Error: 'critical',
  ImagePullBackOff: 'critical',
  ErrImagePull: 'critical',
}

/** The tone of a status printed by Kubernetes, which is itself shown as received. */
export function podTone(status: string): Tone {
  return TONE_BY_POD_STATUS[status] ?? 'warning'
}

interface ListProps {
  snapshot: KubernetesSnapshot | null
  available: boolean
  describedBy: string | undefined
}

/** The namespaces of the snapshot, for the filter. */
function namespaceOptions(snapshot: KubernetesSnapshot | null): { value: string; label: string }[] {
  return [
    { value: ALL_NAMESPACES, label: t('filterAll') },
    ...(snapshot?.namespaces ?? []).map(item => ({ value: item.name, label: item.name })),
  ]
}

/** Keeps the filter by namespace of a list and the rows that pass it. */
function useNamespaceFilter<Row extends { namespace: string }>(rows: Row[]) {
  const [namespace, setNamespace] = useState(ALL_NAMESPACES)
  const visible = namespace === ALL_NAMESPACES ? rows : rows.filter(row => row.namespace === namespace)
  return { namespace, setNamespace, visible }
}

/** The list of namespaces. */
export function NamespaceList({ snapshot, available, describedBy }: ListProps) {
  const rows = snapshot?.namespaces ?? []
  return (
    <Card>
      <DataTable<Namespace>
        caption={t('namespacesCaption', { count: rows.length })}
        rows={rows}
        rowKey={row => row.name}
        identity={{
          id: 'name',
          header: t('columnName'),
          cell: row => (
            <a href={href('kubernetes', 'namespaces', row.name)}>
              <MonoId value={row.name} />
            </a>
          ),
        }}
        status={{
          id: 'status',
          header: t('columnStatus'),
          cell: row => <StatusBadge tone={row.status === 'Active' ? 'good' : 'progress'} label={row.status} />,
        }}
        columns={[{ id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) }]}
        actions={row => <RemoveNamespace name={row.name} available={available} describedBy={describedBy} />}
        emptyText={t('namespacesEmpty')}
        searchText={row => row.name}
      />
    </Card>
  )
}

/** The list of pods. */
export function PodList({ snapshot, available, describedBy }: ListProps) {
  const rows = snapshot?.pods ?? []
  const filter = useNamespaceFilter(rows)
  return (
    <Card>
      <SelectField
        label={t('filterNamespace')}
        options={namespaceOptions(snapshot)}
        value={filter.namespace}
        onChange={event => filter.setNamespace(event.target.value)}
      />
      <DataTable<Pod>
        caption={t('podsCaption', { count: filter.visible.length })}
        rows={filter.visible}
        rowKey={row => `${row.namespace}/${row.name}`}
        identity={{
          id: 'name',
          header: t('columnName'),
          cell: row => (
            <>
              <a href={href('kubernetes', 'pods', row.namespace, row.name)}>
                <MonoId value={row.name} />
              </a>
              <span className={uiStyles.hint}>
                <MonoId value={row.namespace} />
              </span>
            </>
          ),
        }}
        status={{
          id: 'status',
          header: t('columnStatus'),
          cell: row => <StatusBadge tone={podTone(row.status)} label={row.status} />,
        }}
        columns={[
          { id: 'ready', header: t('columnReady'), cell: row => row.ready },
          { id: 'restarts', header: t('columnRestarts'), cell: row => formatNumber(row.restarts) },
          { id: 'ip', header: t('columnIp'), cell: row => (row.ip ? <MonoId value={row.ip} /> : t('noIp')) },
          { id: 'containers', header: t('columnContainers'), cell: row => row.containers.join(', ') },
          { id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) },
        ]}
        actions={row => (
          <RemoveNamespaced
            kind="pods"
            namespace={row.namespace}
            name={row.name}
            available={available}
            describedBy={describedBy}
          />
        )}
        emptyText={t('podsEmpty')}
        searchText={row => `${row.name} ${row.namespace} ${row.status}`}
      />
    </Card>
  )
}

/** The list of deployments. */
export function DeploymentList({ snapshot, available, describedBy }: ListProps) {
  const rows = snapshot?.deployments ?? []
  const filter = useNamespaceFilter(rows)
  return (
    <Card>
      <SelectField
        label={t('filterNamespace')}
        options={namespaceOptions(snapshot)}
        value={filter.namespace}
        onChange={event => filter.setNamespace(event.target.value)}
      />
      <DataTable<Deployment>
        caption={t('deploymentsCaption', { count: filter.visible.length })}
        rows={filter.visible}
        rowKey={row => `${row.namespace}/${row.name}`}
        identity={{
          id: 'name',
          header: t('columnName'),
          cell: row => (
            <>
              <a href={href('kubernetes', 'deployments', row.namespace, row.name)}>
                <MonoId value={row.name} />
              </a>
              <span className={uiStyles.hint}>
                <MonoId value={row.namespace} />
              </span>
            </>
          ),
        }}
        status={{
          id: 'ready',
          header: t('columnReady'),
          cell: row => (
            <StatusBadge
              tone={row.ready === row.replicas ? 'good' : 'progress'}
              label={t('replicasReady', { ready: row.ready, replicas: row.replicas })}
            />
          ),
        }}
        columns={[
          { id: 'updated', header: t('columnUpdated'), cell: row => formatNumber(row.updated) },
          { id: 'available', header: t('columnAvailable'), cell: row => formatNumber(row.available) },
          { id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) },
        ]}
        actions={row => (
          <>
            <ScaleButton deployment={row} available={available} describedBy={describedBy} />
            <RemoveNamespaced
              kind="deployments"
              namespace={row.namespace}
              name={row.name}
              available={available}
              describedBy={describedBy}
            />
          </>
        )}
        emptyText={t('deploymentsEmpty')}
        searchText={row => `${row.name} ${row.namespace}`}
      />
    </Card>
  )
}

/** The list of services. */
export function ServiceList({ snapshot, available, describedBy }: ListProps) {
  const rows = snapshot?.services ?? []
  const filter = useNamespaceFilter(rows)
  return (
    <Card>
      <SelectField
        label={t('filterNamespace')}
        options={namespaceOptions(snapshot)}
        value={filter.namespace}
        onChange={event => filter.setNamespace(event.target.value)}
      />
      <DataTable<Service>
        caption={t('servicesCaption', { count: filter.visible.length })}
        rows={filter.visible}
        rowKey={row => `${row.namespace}/${row.name}`}
        identity={{
          id: 'name',
          header: t('columnName'),
          cell: row => (
            <>
              <a href={href('kubernetes', 'services', row.namespace, row.name)}>
                <MonoId value={row.name} />
              </a>
              <span className={uiStyles.hint}>
                <MonoId value={row.namespace} />
              </span>
            </>
          ),
        }}
        columns={[
          { id: 'type', header: t('columnType'), cell: row => row.type },
          { id: 'clusterIP', header: t('columnClusterIp'), cell: row => <MonoId value={row.clusterIP} /> },
          {
            id: 'ports',
            header: t('columnPorts'),
            cell: row => (row.ports.length > 0 ? <MonoId value={row.ports.join(', ')} /> : t('noPorts')),
          },
          { id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) },
        ]}
        actions={row => (
          <RemoveNamespaced
            kind="services"
            namespace={row.namespace}
            name={row.name}
            available={available}
            describedBy={describedBy}
          />
        )}
        emptyText={t('servicesEmpty')}
        searchText={row => `${row.name} ${row.namespace} ${row.type}`}
      />
    </Card>
  )
}
