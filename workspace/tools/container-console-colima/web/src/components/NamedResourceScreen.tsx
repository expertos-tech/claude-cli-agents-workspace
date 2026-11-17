import { type FormEvent, type ReactNode, useId, useState } from 'react'
import { segment } from '../api/client'
import type { DockerSnapshot } from '../api/types'
import { useJob } from '../api/useJob'
import { useLive } from '../api/useLive'
import type { Translator } from '../i18n'
import { href } from '../routing'
import { AvailabilityNotice } from './AvailabilityNotice'
import { Button, LinkButton } from './Button'
import { ConfirmButton } from './ConfirmDialog'
import { type Column, DataTable } from './DataTable'
import { InspectJson, useInspect } from './InspectPanel'
import { MonoId } from './MonoId'
import { Card, Field, Page, PageHeader, uiStyles } from './ui'

const NAME_FORMAT = /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/
const NAME_MAX = 255

/** The dictionary keys each screen of this kind must have. */
export type NamedResourceKey =
  | 'eyebrow'
  | 'title'
  | 'description'
  | 'caption'
  | 'empty'
  | 'createTitle'
  | 'nameLabel'
  | 'nameHint'
  | 'nameInvalid'
  | 'create'
  | 'remove'
  | 'removeAria'
  | 'removeTitle'
  | 'removeBody'
  | 'detailsBack'
  | 'detailsMissing'
  | 'columnName'

interface NamedResourceScreenProps<Row> {
  /** Hash segments after the feature id: empty is the list, one is the details of that name. */
  segments: string[]
  /** Id of the feature, which is the first segment of its address. */
  routeId: string
  /** REST prefix, such as `/api/volumes`. */
  apiPrefix: string
  /** Prefix of the job kinds, such as `volume`. */
  jobPrefix: string
  t: Translator<NamedResourceKey>
  rowsOf: (docker: DockerSnapshot) => Row[]
  nameOf: (row: Row) => string
  columns: Column<Row>[]
  searchText: (row: Row) => string
}

/** The create form. It is disabled, with the reason beside it, while Docker is not available. */
function CreateForm({
  t,
  disabled,
  describedBy,
  onCreate,
}: {
  t: Translator<NamedResourceKey>
  disabled: boolean
  describedBy: string | undefined
  onCreate: (name: string) => Promise<boolean>
}) {
  const [name, setName] = useState('')
  const [showError, setShowError] = useState(false)
  const trimmed = name.trim()
  const valid = NAME_FORMAT.test(trimmed) && trimmed.length <= NAME_MAX

  /** Validates before sending, and clears the field once the service took the request. */
  async function submit(event: FormEvent): Promise<void> {
    event.preventDefault()
    if (!valid) {
      setShowError(true)
      return
    }
    if (await onCreate(trimmed)) {
      setName('')
      setShowError(false)
    }
  }

  return (
    <Card title={t('createTitle')}>
      <form className={uiStyles.form} onSubmit={submit} noValidate>
        <div className={uiStyles.formRow}>
          <Field
            label={t('nameLabel')}
            hint={t('nameHint')}
            error={showError && !valid ? t('nameInvalid') : null}
            describedBy={describedBy}
          >
            {control => (
              <input
                {...control}
                type="text"
                autoComplete="off"
                spellCheck={false}
                disabled={disabled}
                value={name}
                onChange={event => setName(event.target.value)}
              />
            )}
          </Field>
          <Button type="submit" variant="primary" icon="plus" disabled={disabled}>
            {t('create')}
          </Button>
        </div>
      </form>
    </Card>
  )
}

/** The details of one resource: what the list knows plus the whole inspect. */
function Details<Row>({
  name,
  routeId,
  apiPrefix,
  t,
  rows,
  nameOf,
  columns,
  actions,
}: {
  name: string
  routeId: string
  apiPrefix: string
  t: Translator<NamedResourceKey>
  rows: Row[]
  nameOf: (row: Row) => string
  columns: Column<Row>[]
  actions: (row: Row) => ReactNode
}) {
  const row = rows.find(item => nameOf(item) === name)
  const inspect = useInspect(`${apiPrefix}/${segment(name)}`)
  return (
    <Page>
      <PageHeader
        eyebrow={t('title')}
        title={name}
        actions={
          <>
            <LinkButton icon="arrowLeft" href={href(routeId)}>
              {t('detailsBack')}
            </LinkButton>
            {row && actions(row)}
          </>
        }
      />
      <Card>
        {!row && <p>{t('detailsMissing')}</p>}
        {row && (
          <dl className={uiStyles.details}>
            {columns.map(column => (
              <div key={column.id} className={uiStyles.detail}>
                <dt className={uiStyles.detailTerm}>{column.header}</dt>
                <dd>{column.cell(row)}</dd>
              </div>
            ))}
          </dl>
        )}
        <InspectJson state={inspect} />
      </Card>
    </Page>
  )
}

/** Volumes and networks have the same actions, so they share this screen. */
export function NamedResourceScreen<Row>({
  segments,
  routeId,
  apiPrefix,
  jobPrefix,
  t,
  rowsOf,
  nameOf,
  columns,
  searchText,
}: NamedResourceScreenProps<Row>) {
  const docker = useLive('docker')
  const { run, isBusy } = useJob()
  const noticeId = useId()
  const available = docker.data?.available ?? false
  const rows = docker.data ? rowsOf(docker.data) : []

  /** The remove button with its confirmation. Cancelling sends nothing. */
  function removeButton(row: Row) {
    const name = nameOf(row)
    return (
      <ConfirmButton
        label={t('remove')}
        ariaLabel={t('removeAria', { name })}
        icon="trash"
        size="compact"
        disabled={!available}
        busy={isBusy(name)}
        describedBy={available ? undefined : noticeId}
        dialogTitle={t('removeTitle', { name })}
        confirmLabel={t('remove')}
        irreversible
        onConfirm={() => run(`${jobPrefix}.remove`, name, `${apiPrefix}/${segment(name)}/remove`, { confirm: true })}
      >
        <p>{t('removeBody', { name })}</p>
      </ConfirmButton>
    )
  }

  const detailsName = segments[0]
  if (detailsName) {
    return (
      <Details
        name={detailsName}
        routeId={routeId}
        apiPrefix={apiPrefix}
        t={t}
        rows={rows}
        nameOf={nameOf}
        columns={columns}
        actions={removeButton}
      />
    )
  }

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
      <CreateForm
        t={t}
        disabled={!available}
        describedBy={available ? undefined : noticeId}
        onCreate={async name => (await run(`${jobPrefix}.create`, name, apiPrefix, { name })) !== null}
      />
      <Card>
        <DataTable
          caption={t('caption', { count: rows.length })}
          rows={rows}
          rowKey={nameOf}
          identity={{
            id: 'name',
            header: t('columnName'),
            cell: row => (
              <a href={href(routeId, nameOf(row))}>
                <MonoId value={nameOf(row)} />
              </a>
            ),
          }}
          columns={columns}
          actions={removeButton}
          emptyText={t('empty')}
          searchText={searchText}
        />
      </Card>
    </Page>
  )
}
