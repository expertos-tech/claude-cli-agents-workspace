import { useId } from 'react'
import type { Container } from '../../api/types'
import { useLive } from '../../api/useLive'
import { AvailabilityNotice } from '../../components/AvailabilityNotice'
import { DataTable } from '../../components/DataTable'
import { MonoId, shortId, TruncatedMonoId } from '../../components/MonoId'
import { StatusBadge } from '../../components/StatusBadge'
import { Card, Page, PageHeader, uiStyles } from '../../components/ui'
import { createTranslator, formatTimestamp } from '../../i18n'
import { type FeatureRoute, href, type PageProps } from '../../routing'
import { ContainerActions, containerHealthBadge, containerStateBadge } from './ContainerActions'
import { ContainerDetails } from './ContainerDetails'
import styles from './containers.module.css'
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

/** Key of the group of containers with no Compose project; a project name is never empty. */
const NO_PROJECT = ''

/** Header of a group: the Compose project that published its containers, and how many run. */
function GroupHeader({ project, members }: { project: string; members: Container[] }) {
  const running = members.filter(container => container.state === 'running').length
  return (
    <span className={styles.groupHeader}>
      <span>{project === NO_PROJECT ? t('groupNoProject') : project}</span>
      <span className={uiStyles.hint}>
        {t('groupCount', { count: members.length })} · {t('groupRunning', { count: running })}
      </span>
    </span>
  )
}

/** Containers of each Compose project together, by project name, and the ones without a project last. */
function byProject(rows: Container[]): Container[] {
  const rank = (row: Container) => row.composeProject ?? NO_PROJECT
  return [...rows].sort((a, b) => {
    const left = rank(a)
    const right = rank(b)
    if (left === right) return 0
    if (left === NO_PROJECT) return 1
    if (right === NO_PROJECT) return -1
    return left.localeCompare(right)
  })
}

/** The list of containers, which follows the docker topic, grouped by the Compose project that published them. */
function ContainerList() {
  const docker = useLive('docker')
  const noticeId = useId()
  const available = docker.data?.available ?? false
  const rows = byProject(docker.data?.containers ?? [])
  const grouped = rows.some(row => row.composeProject)
  return (
    <Page>
      <PageHeader eyebrow={t('eyebrow')} title={t('title')} description={t('description')} />
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
            { id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) },
          ]}
          actions={row => (
            <ContainerActions container={row} available={available} describedBy={available ? undefined : noticeId} />
          )}
          emptyText={t('empty')}
          searchText={row => `${row.name} ${row.image} ${row.id} ${row.composeProject ?? ''}`}
          group={
            grouped
              ? {
                  key: row => row.composeProject ?? NO_PROJECT,
                  header: (project, members) => <GroupHeader project={project} members={members} />,
                }
              : undefined
          }
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
