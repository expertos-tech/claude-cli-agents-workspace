import { type FormEvent, useId, useState } from 'react'
import { apiPost, FILE_DIALOG_TIMEOUT_MS, segment } from '../../api/client'
import type { ComposeProject } from '../../api/types'
import { reportRefusal, useJob } from '../../api/useJob'
import { useLive } from '../../api/useLive'
import { AvailabilityNotice } from '../../components/AvailabilityNotice'
import { Button } from '../../components/Button'
import { ConfirmButton } from '../../components/ConfirmDialog'
import { DataTable } from '../../components/DataTable'
import { MonoId } from '../../components/MonoId'
import { StatusBadge, type Tone } from '../../components/StatusBadge'
import { Card, Field, Page, PageHeader, uiStyles } from '../../components/ui'
import { createTranslator } from '../../i18n'
import type { FeatureRoute } from '../../routing'
import { messages } from './messages'

const t = createTranslator(messages)

/** The part of the path rules the screen can check. The service also checks the file itself. */
function isComposePath(path: string): boolean {
  return path.startsWith('/') && /\.ya?ml$/.test(path) && !path.split('/').includes('..')
}

const TONE_BY_STATE: Record<string, Tone> = {
  running: 'good',
  exited: 'neutral',
  down: 'neutral',
  unknown: 'serious',
}

/** The badge of a project state. A state this version does not know is shown as received. */
function projectBadge(state: string): { tone: Tone; label: string } {
  switch (state) {
    case 'running':
    case 'exited':
    case 'down':
    case 'unknown':
      return { tone: TONE_BY_STATE[state] ?? 'neutral', label: t(`state.${state}`) }
    default:
      return { tone: 'neutral', label: state }
  }
}

/** Adds a project by the native dialog or by the path field. Both work with the VM off. */
function AddProjectCard() {
  const [path, setPath] = useState('')
  const [showError, setShowError] = useState(false)
  const [picking, setPicking] = useState(false)
  const [added, setAdded] = useState<string | null>(null)
  const trimmed = path.trim()
  const valid = isComposePath(trimmed)

  /** Sends the path. The list shows the project when the next snapshot brings it. */
  async function addPath(value: string): Promise<boolean> {
    try {
      const { project } = await apiPost<{ project: ComposeProject }>('/api/compose/projects', { path: value })
      setAdded(project.name)
      return true
    } catch (error) {
      setAdded(null)
      reportRefusal('compose.add', value, error)
      return false
    }
  }

  /** Opens the dialog of the Mac, which only returns the path chosen. */
  async function chooseFile(): Promise<void> {
    setPicking(true)
    try {
      const result = await apiPost<{ path: string; canceled: boolean }>(
        '/api/compose/file-dialog',
        {},
        FILE_DIALOG_TIMEOUT_MS,
      )
      if (!result.canceled) {
        await addPath(result.path)
      }
    } catch (error) {
      reportRefusal('compose.pick', '', error)
    } finally {
      setPicking(false)
    }
  }

  /** Validates the typed path before sending it. */
  async function submit(event: FormEvent): Promise<void> {
    event.preventDefault()
    if (!valid) {
      setShowError(true)
      return
    }
    if (await addPath(trimmed)) {
      setPath('')
      setShowError(false)
    }
  }

  return (
    <Card title={t('addTitle')}>
      <p className={uiStyles.hint}>{t('addDescription')}</p>
      <div className={uiStyles.row}>
        <Button variant="primary" icon="file" busy={picking} onClick={chooseFile}>
          {picking ? t('choosing') : t('chooseFile')}
        </Button>
        {picking && <span className={uiStyles.hint}>{t('choosingHint')}</span>}
      </div>
      <form className={uiStyles.form} onSubmit={submit} noValidate>
        <div className={uiStyles.formRow}>
          <Field label={t('pathLabel')} hint={t('pathHint')} error={showError && !valid ? t('pathInvalid') : null}>
            {control => (
              <input
                {...control}
                type="text"
                autoComplete="off"
                spellCheck={false}
                value={path}
                onChange={event => setPath(event.target.value)}
              />
            )}
          </Field>
          <Button type="submit" icon="plus">
            {t('add')}
          </Button>
        </div>
      </form>
      <p role="status" className={uiStyles.hint}>
        {added ? t('added', { name: added }) : ''}
      </p>
    </Card>
  )
}

interface ProjectActionsProps {
  project: ComposeProject
  available: boolean
  describedBy: string | undefined
}

/** Up, stop and remove. Removing keeps the volumes unless the option is marked. */
function ProjectActions({ project, available, describedBy }: ProjectActionsProps) {
  const { run, isBusy } = useJob()
  const [removeVolumes, setRemoveVolumes] = useState(false)
  const name = project.name
  const path = `/api/compose/projects/${segment(name)}`
  const shared = { size: 'compact', busy: isBusy(name), disabled: !available, 'aria-describedby': describedBy } as const
  return (
    <>
      <Button
        {...shared}
        icon="play"
        aria-label={t('upAria', { name })}
        onClick={() => run('compose.up', name, `${path}/up`)}
      >
        {t('up')}
      </Button>
      <Button
        {...shared}
        icon="stop"
        aria-label={t('stopAria', { name })}
        onClick={() => run('compose.stop', name, `${path}/stop`)}
      >
        {t('stop')}
      </Button>
      <ConfirmButton
        label={t('remove')}
        ariaLabel={t('removeAria', { name })}
        icon="trash"
        size="compact"
        busy={isBusy(name)}
        disabled={!available}
        describedBy={describedBy}
        dialogTitle={t('removeTitle', { name })}
        confirmLabel={t('remove')}
        irreversible
        onConfirm={() => run('compose.remove', name, `${path}/remove`, { confirm: true, removeVolumes })}
        onDialogClosed={() => setRemoveVolumes(false)}
      >
        <p>{t('removeBody')}</p>
        <label className={uiStyles.choice}>
          <input type="checkbox" checked={removeVolumes} onChange={event => setRemoveVolumes(event.target.checked)} />
          <span>{t('removeVolumes')}</span>
        </label>
      </ConfirmButton>
    </>
  )
}

/** The Compose projects: known list, add, up, stop and remove. */
function ComposePage() {
  const docker = useLive('docker')
  const noticeId = useId()
  const available = docker.data?.available ?? false
  const rows = docker.data?.composeProjects ?? []
  const describedBy = available ? undefined : noticeId
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
      <AddProjectCard />
      <Card>
        <DataTable<ComposeProject>
          caption={t('caption', { count: rows.length })}
          rows={rows}
          rowKey={row => row.name}
          identity={{ id: 'name', header: t('columnName'), cell: row => <MonoId value={row.name} /> }}
          status={{
            id: 'state',
            header: t('columnState'),
            cell: row => {
              const badge = projectBadge(row.state)
              return <StatusBadge tone={badge.tone} label={badge.label} />
            },
          }}
          columns={[
            { id: 'status', header: t('columnStatus'), cell: row => row.status },
            {
              id: 'files',
              header: t('columnFiles'),
              cell: row =>
                row.configFiles.length > 0 ? (
                  <ul className={uiStyles.stack}>
                    {row.configFiles.map(file => (
                      <li key={file}>
                        <MonoId value={file} />
                      </li>
                    ))}
                  </ul>
                ) : (
                  t('noFiles')
                ),
            },
          ]}
          actions={row => <ProjectActions project={row} available={available} describedBy={describedBy} />}
          emptyText={t('empty')}
          searchText={row => `${row.name} ${row.configFiles.join(' ')}`}
        />
      </Card>
    </Page>
  )
}

export const route: FeatureRoute = { id: 'compose', order: 70, group: 'docker', icon: 'compose', Page: ComposePage }
