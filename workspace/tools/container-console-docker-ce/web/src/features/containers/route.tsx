import { useId } from 'react'
import type { Container } from '../../api/types'
import { useLive } from '../../api/useLive'
import { AvailabilityNotice } from '../../components/AvailabilityNotice'
import { DataTable, type RowGrouping } from '../../components/DataTable'
import { MonoId, shortId, TruncatedMonoId } from '../../components/MonoId'
import { StatusBadge, type Tone } from '../../components/StatusBadge'
import { Card, Page, PageHeader, uiStyles } from '../../components/ui'
import { createTranslator, formatTimestamp } from '../../i18n'
import { type FeatureRoute, href, type PageProps } from '../../routing'
import { ContainerActions, containerHealthBadge, containerStateBadge } from './ContainerActions'
import { ContainerDetails } from './ContainerDetails'
import { messages } from './messages'

const t = createTranslator(messages)

/** The state, and the health check when the container has one. */
function ContainerStatus({ container }: { container: Container }) {
  const state = containerStateBadge(container.state)
  const health = containerHealthBadge(container.health)
  return (
    <div className={uiStyles.stack}>
      <StatusBadge tone={state.tone} label={state.label} />
      {health && <StatusBadge tone={health.tone} label={health.label} />}
    </div>
  )
}

/** The tone of a group by how many of its containers run: all, some or none. */
function groupTone(running: number, total: number): Tone {
  if (running === total) return 'good'
  return running === 0 ? 'neutral' : 'warning'
}

/** How many containers of a Compose project run, and how many fail their health check. */
function GroupSummary({ rows }: { rows: Container[] }) {
  const running = rows.filter(row => row.state === 'running').length
  const unhealthy = rows.filter(row => row.health === 'unhealthy').length
  return (
    <>
      <StatusBadge tone={groupTone(running, rows.length)} label={t('groupRunning', { count: rows.length, running })} />
      {unhealthy > 0 && <StatusBadge tone="critical" label={t('groupUnhealthy', { count: unhealthy })} />}
    </>
  )
}

/** Containers of one Compose project, two or more, open and close together. */
const BY_COMPOSE_PROJECT: RowGrouping<Container> = {
  key: row => row.composeProject || undefined,
  title: (key, rows) => (
    <>
      <MonoId value={key} />
      <span className={uiStyles.hint}>{t('groupCount', { count: rows.length })}</span>
    </>
  ),
  toggleLabel: (key, rows) => t('groupToggle', { project: key, count: rows.length }),
  summary: rows => <GroupSummary rows={rows} />,
  storageKey: 'container-console-docker-ce.containers.open-projects',
}

/** The list of containers, which follows the docker topic. */
function ContainerList() {
  const docker = useLive('docker')
  const noticeId = useId()
  const available = docker.data?.available ?? false
  const rows = docker.data?.containers ?? []
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
      <Card>
        <DataTable<Container>
          caption={t('caption', { count: rows.length })}
          rows={rows}
          rowKey={row => row.id}
          identity={{
            id: 'name',
            header: t('columnName'),
            cell: row => (
              <>
                <a href={href('containers', row.id)}>
                  <MonoId value={row.name} />
                </a>
                <span className={uiStyles.hint}>
                  <MonoId value={shortId(row.id)} />
                </span>
              </>
            ),
          }}
          status={{
            id: 'state',
            header: t('columnState'),
            cell: row => <ContainerStatus container={row} />,
          }}
          columns={[
            { id: 'image', header: t('columnImage'), cell: row => <TruncatedMonoId value={row.image} /> },
            { id: 'status', header: t('columnStatus'), cell: row => row.status },
            {
              id: 'ports',
              header: t('columnPorts'),
              cell: row => (row.ports ? <MonoId value={row.ports} /> : t('noPorts')),
            },
            { id: 'project', header: t('columnProject'), cell: row => row.composeProject ?? t('noProject') },
            { id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) },
          ]}
          actions={row => (
            <ContainerActions container={row} available={available} describedBy={available ? undefined : noticeId} />
          )}
          emptyText={t('empty')}
          searchText={row => `${row.name} ${row.image} ${row.id} ${row.composeProject ?? ''}`}
          grouping={BY_COMPOSE_PROJECT}
        />
      </Card>
    </Page>
  )
}

/** Chooses between the list and the details of one container. */
function ContainersPage({ segments }: PageProps) {
  const [id, view] = segments
  return id ? <ContainerDetails id={id} view={view} /> : <ContainerList />
}

export const route: FeatureRoute = {
  id: 'containers',
  order: 30,
  group: 'docker',
  icon: 'container',
  Page: ContainersPage,
}
