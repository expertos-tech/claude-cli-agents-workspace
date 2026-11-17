import { type FormEvent, useId, useState } from 'react'
import type { Image } from '../../api/types'
import { useJob } from '../../api/useJob'
import { useLive } from '../../api/useLive'
import { AvailabilityNotice } from '../../components/AvailabilityNotice'
import { Button } from '../../components/Button'
import { ConfirmButton } from '../../components/ConfirmDialog'
import { DataTable } from '../../components/DataTable'
import { MonoId, shortId } from '../../components/MonoId'
import { Card, Field, Page, PageHeader, uiStyles } from '../../components/ui'
import { createTranslator, formatTimestamp } from '../../i18n'
import type { FeatureRoute } from '../../routing'
import { messages } from './messages'

const t = createTranslator(messages)

const REFERENCE_FORMAT = /^[a-zA-Z0-9][a-zA-Z0-9._:/@-]*$/
const REFERENCE_MAX = 512

interface PullFormProps {
  disabled: boolean
  describedBy: string | undefined
}

/** Asks the service to pull an image. The progress appears in the actions dock. */
function PullForm({ disabled, describedBy }: PullFormProps) {
  const { run } = useJob()
  const [reference, setReference] = useState('')
  const [showError, setShowError] = useState(false)
  const trimmed = reference.trim()
  const valid = REFERENCE_FORMAT.test(trimmed) && trimmed.length <= REFERENCE_MAX

  /** Validates before sending, and clears the field once the service took the request. */
  async function submit(event: FormEvent): Promise<void> {
    event.preventDefault()
    if (!valid) {
      setShowError(true)
      return
    }
    const job = await run('image.pull', trimmed, '/api/images/pull', { reference: trimmed })
    if (job) {
      setReference('')
      setShowError(false)
    }
  }

  return (
    <Card title={t('pullTitle')}>
      <form className={uiStyles.form} onSubmit={submit} noValidate>
        <div className={uiStyles.formRow}>
          <Field
            label={t('referenceLabel')}
            hint={t('referenceHint')}
            error={showError && !valid ? t('referenceInvalid') : null}
            describedBy={describedBy}
          >
            {control => (
              <input
                {...control}
                type="text"
                autoComplete="off"
                spellCheck={false}
                disabled={disabled}
                value={reference}
                onChange={event => setReference(event.target.value)}
              />
            )}
          </Field>
          <Button type="submit" variant="primary" icon="download" disabled={disabled}>
            {t('pull')}
          </Button>
        </div>
      </form>
    </Card>
  )
}

/** The images: list, pull and remove. */
function ImagesPage() {
  const docker = useLive('docker')
  const { run, isBusy } = useJob()
  const noticeId = useId()
  const available = docker.data?.available ?? false
  const rows = docker.data?.images ?? []
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
      <PullForm disabled={!available} describedBy={describedBy} />
      <Card>
        <DataTable<Image>
          caption={t('caption', { count: rows.length })}
          rows={rows}
          rowKey={row => `${row.id}|${row.reference}`}
          identity={{
            id: 'reference',
            header: t('columnReference'),
            cell: row => <MonoId value={row.reference} />,
          }}
          columns={[
            { id: 'id', header: t('columnId'), cell: row => <MonoId value={shortId(row.id)} /> },
            { id: 'size', header: t('columnSize'), cell: row => row.size },
            { id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) },
          ]}
          actions={row => (
            <ConfirmButton
              label={t('remove')}
              ariaLabel={t('removeAria', { reference: row.reference })}
              icon="trash"
              size="compact"
              disabled={!available}
              busy={isBusy(row.reference)}
              describedBy={describedBy}
              dialogTitle={t('removeTitle', { reference: row.reference })}
              confirmLabel={t('remove')}
              irreversible
              onConfirm={() =>
                run('image.remove', row.reference, '/api/images/remove', { reference: row.reference, confirm: true })
              }
            >
              <p>{t('removeBody')}</p>
            </ConfirmButton>
          )}
          emptyText={t('empty')}
          searchText={row => `${row.reference} ${row.id}`}
        />
      </Card>
    </Page>
  )
}

export const route: FeatureRoute = { id: 'images', order: 40, group: 'docker', icon: 'image', Page: ImagesPage }
