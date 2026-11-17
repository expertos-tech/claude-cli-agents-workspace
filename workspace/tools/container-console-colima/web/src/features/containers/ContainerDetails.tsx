import { useEffect, useId, useState } from 'react'
import { apiGet, errorBodyOf, segment } from '../../api/client'
import type { ApiErrorBody, Container, ContainerStats } from '../../api/types'
import { useLive } from '../../api/useLive'
import { AvailabilityNotice } from '../../components/AvailabilityNotice'
import { LinkButton } from '../../components/Button'
import { ErrorDetail } from '../../components/ErrorDetail'
import { InspectJson, useInspect } from '../../components/InspectPanel'
import { MonoId } from '../../components/MonoId'
import { StatusBadge } from '../../components/StatusBadge'
import { TerminalView } from '../../components/TerminalView'
import { Card, DetailList, Meter, Notice, Page, PageHeader, TabsNav, uiStyles } from '../../components/ui'
import { createTranslator, formatTimestamp } from '../../i18n'
import { href } from '../../routing'
import { ContainerActions, containerHealthBadge, containerStateBadge } from './ContainerActions'
import { messages } from './messages'

const t = createTranslator(messages)

/** The contract: `docker stats` takes about 1 s, and it is read every 2 s while this view is open. */
const STATS_INTERVAL_MS = 2_000

/** Reads the resource usage every 2 s while the view is open and the container runs. */
function useContainerStats(id: string, enabled: boolean): { stats: ContainerStats | null; error: ApiErrorBody | null } {
  const [state, setState] = useState<{ stats: ContainerStats | null; error: ApiErrorBody | null }>({
    stats: null,
    error: null,
  })
  useEffect(() => {
    if (!enabled) {
      setState({ stats: null, error: null })
      return
    }
    const controller = new AbortController()
    let timer: number | undefined
    /** Reads once and schedules the next read only after this one ends, so reads never overlap. */
    async function read(): Promise<void> {
      try {
        const stats = await apiGet<ContainerStats>(`/api/containers/${segment(id)}/stats`, controller.signal)
        setState({ stats, error: null })
      } catch (error) {
        if (controller.signal.aborted) {
          return
        }
        setState(previous => ({ stats: previous.stats, error: errorBodyOf(error) }))
      }
      timer = window.setTimeout(read, STATS_INTERVAL_MS)
    }
    void read()
    return () => {
      controller.abort()
      window.clearTimeout(timer)
    }
  }, [id, enabled])
  return state
}

/** Reads a percentage printed by the CLI as a 0 to 1 ratio. */
function ratioOf(percent: string): number {
  const value = Number.parseFloat(percent)
  return Number.isNaN(value) ? 0 : value / 100
}

/** The resource usage of the container. */
function UsageCard({ container }: { container: Container }) {
  const running = container.state === 'running'
  const { stats, error } = useContainerStats(container.id, running)
  return (
    <Card title={t('usageTitle')}>
      {!running && <p className={uiStyles.hint}>{t('usageNotRunning')}</p>}
      {running && !stats && !error && <p className={uiStyles.hint}>{t('usageLoading')}</p>}
      {error && <ErrorDetail error={error} />}
      {stats && (
        <>
          <div className={uiStyles.grid}>
            <div className={uiStyles.metric}>
              <span className={uiStyles.detailTerm}>{t('cpu')}</span>
              <span className={uiStyles.figure}>{stats.cpuPercent}</span>
              <Meter ratio={ratioOf(stats.cpuPercent)} />
            </div>
            <div className={uiStyles.metric}>
              <span className={uiStyles.detailTerm}>{t('memoryPercent')}</span>
              <span className={uiStyles.figure}>{stats.memoryPercent}</span>
              <Meter ratio={ratioOf(stats.memoryPercent)} />
            </div>
          </div>
          <DetailList
            items={[
              { term: t('memory'), value: stats.memoryUsage },
              { term: t('network'), value: stats.networkIO },
              { term: t('block'), value: stats.blockIO },
              { term: t('pids'), value: stats.pids },
            ]}
          />
        </>
      )}
    </Card>
  )
}

/** The fields of `docker inspect` this screen highlights. The rest stays in the full JSON. */
interface ContainerInspect {
  Id?: string
  HostConfig?: { RestartPolicy?: { Name?: string } }
  NetworkSettings?: { Networks?: Record<string, unknown> }
  Mounts?: { Source?: string; Destination?: string; Name?: string }[]
}

/** What the list knows about the container plus the highlights of the inspect. */
function SummaryCard({ container }: { container: Container }) {
  const inspect = useInspect<ContainerInspect>(
    `/api/containers/${segment(container.id)}`,
    `${container.state}|${container.status}`,
  )
  const networks = Object.keys(inspect.data?.NetworkSettings?.Networks ?? {})
  const mounts = inspect.data?.Mounts ?? []
  return (
    <Card title={t('summaryTitle')}>
      <DetailList
        items={[
          { term: t('fullId'), value: <MonoId value={container.id} /> },
          { term: t('columnImage'), value: <MonoId value={container.image} /> },
          { term: t('columnStatus'), value: container.status },
          { term: t('columnPorts'), value: container.ports ? <MonoId value={container.ports} /> : t('noPorts') },
          { term: t('columnProject'), value: container.composeProject ?? t('noProject') },
          { term: t('columnCreated'), value: formatTimestamp(container.createdAt) },
          { term: t('command'), value: <MonoId value={container.command} /> },
          { term: t('restartPolicy'), value: inspect.data?.HostConfig?.RestartPolicy?.Name ?? t('none') },
          { term: t('networks'), value: networks.length > 0 ? networks.join(', ') : t('none') },
          {
            term: t('mounts'),
            value:
              mounts.length > 0 ? (
                <ul className={uiStyles.stack}>
                  {mounts.map(mount => (
                    <li key={mount.Destination}>
                      <MonoId value={`${mount.Name ?? mount.Source ?? ''} → ${mount.Destination ?? ''}`} />
                    </li>
                  ))}
                </ul>
              ) : (
                t('none')
              ),
          },
        ]}
      />
      <InspectJson state={inspect} />
    </Card>
  )
}

interface ContainerDetailsProps {
  /** Id of the container, as in the address. */
  id: string
  view: string | undefined
}

/** Details, resource usage, live logs and terminal of one container. */
export function ContainerDetails({ id, view }: ContainerDetailsProps) {
  const docker = useLive('docker')
  const noticeId = useId()
  const container = docker.data?.containers.find(item => item.id === id)
  const available = docker.data?.available ?? false
  const name = container?.name ?? id
  const badge = container ? containerStateBadge(container.state) : null
  const health = containerHealthBadge(container?.health)
  const socketId = segment(id)

  return (
    <Page>
      <PageHeader
        eyebrow={t('title')}
        title={name}
        actions={
          <LinkButton icon="arrowLeft" href={href('containers')}>
            {t('back')}
          </LinkButton>
        }
      />
      {!available && (
        <AvailabilityNotice
          id={noticeId}
          source="docker"
          loading={!docker.data}
          reasonCode={docker.data?.reasonCode}
          reason={docker.data?.reason}
        />
      )}
      {available && !container && (
        <Notice icon="alert">
          <p>{t('missing')}</p>
        </Notice>
      )}
      {container && (
        <Card>
          <div className={uiStyles.row}>
            {badge && <StatusBadge tone={badge.tone} label={badge.label} />}
            {health && <StatusBadge tone={health.tone} label={health.label} />}
            <ContainerActions
              container={container}
              available={available}
              describedBy={available ? undefined : noticeId}
              size="regular"
            />
          </div>
        </Card>
      )}
      <TabsNav
        label={t('tabsLabel')}
        items={[
          { label: t('tabSummary'), href: href('containers', id), icon: 'info', current: !view },
          { label: t('tabLogs'), href: href('containers', id, 'logs'), icon: 'logs', current: view === 'logs' },
          {
            label: t('tabTerminal'),
            href: href('containers', id, 'terminal'),
            icon: 'terminal',
            current: view === 'terminal',
          },
        ]}
      />
      {!view && container && (
        <>
          <UsageCard container={container} />
          <SummaryCard container={container} />
        </>
      )}
      {view === 'logs' && container && (
        <Card>
          <TerminalView mode="logs" path={`/ws/logs/containers/${socketId}`} label={t('logsLabel', { name })} />
        </Card>
      )}
      {view === 'terminal' && container && (
        <Card>
          {container.state !== 'running' ? (
            <Notice icon="alert">
              <p>{t('terminalNotRunning')}</p>
            </Notice>
          ) : (
            <TerminalView
              mode="terminal"
              path={`/ws/terminal/containers/${socketId}`}
              label={t('terminalLabel', { name })}
            />
          )}
        </Card>
      )}
    </Page>
  )
}
