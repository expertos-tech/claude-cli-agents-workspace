import { type FormEvent, useId, useState } from 'react'
import { segment } from '../../api/client'
import type { Deployment } from '../../api/types'
import { useJob } from '../../api/useJob'
import { Button } from '../../components/Button'
import { ConfirmButton, Dialog } from '../../components/ConfirmDialog'
import { Field, uiStyles } from '../../components/ui'
import { createTranslator } from '../../i18n'
import { messages } from './messages'

const t = createTranslator(messages)

const MAX_REPLICAS = 1000

export type NamespacedKind = 'pods' | 'deployments' | 'services'

const REMOVE_TEXT = {
  pods: { title: 'removePodTitle', body: 'removePodBody' },
  deployments: { title: 'removeDeploymentTitle', body: 'removeDeploymentBody' },
  services: { title: 'removeServiceTitle', body: 'removeServiceBody' },
} as const

interface RemoveProps {
  name: string
  available: boolean
  describedBy: string | undefined
  size?: 'regular' | 'compact'
}

/** The label a job gives a namespaced resource, used to know when it is busy. */
export function resourceTarget(kind: NamespacedKind, namespace: string, name: string): string {
  return `${kind}/${namespace}/${name}`
}

/** Removes a pod, deployment or service after the confirmation. */
export function RemoveNamespaced({
  kind,
  namespace,
  name,
  available,
  describedBy,
  size = 'compact',
}: RemoveProps & { kind: NamespacedKind; namespace: string }) {
  const { run, isBusy } = useJob()
  const target = resourceTarget(kind, namespace, name)
  const text = REMOVE_TEXT[kind]
  return (
    <ConfirmButton
      label={t('remove')}
      ariaLabel={t('removeAria', { name })}
      icon="trash"
      size={size}
      busy={isBusy(target)}
      disabled={!available}
      describedBy={describedBy}
      dialogTitle={t(text.title, { name })}
      confirmLabel={t('remove')}
      irreversible
      onConfirm={() =>
        run('kubernetes.remove', target, `/api/kubernetes/${kind}/${segment(namespace)}/${segment(name)}/remove`, {
          confirm: true,
        })
      }
    >
      <p>{t(text.body, { namespace, name })}</p>
    </ConfirmButton>
  )
}

/** Removes a namespace after the confirmation that says everything in it goes too. */
export function RemoveNamespace({ name, available, describedBy, size = 'compact' }: RemoveProps) {
  const { run, isBusy } = useJob()
  const target = `namespaces/${name}`
  return (
    <ConfirmButton
      label={t('remove')}
      ariaLabel={t('removeAria', { name })}
      icon="trash"
      size={size}
      busy={isBusy(target)}
      disabled={!available}
      describedBy={describedBy}
      dialogTitle={t('removeNamespaceTitle', { name })}
      confirmLabel={t('remove')}
      irreversible
      onConfirm={() =>
        run('kubernetes.remove', target, `/api/kubernetes/namespaces/${segment(name)}/remove`, { confirm: true })
      }
    >
      <p>{t('removeNamespaceBody', { name })}</p>
    </ConfirmButton>
  )
}

/** Asks for a replica count and scales the deployment. */
export function ScaleButton({
  deployment,
  available,
  describedBy,
  size = 'compact',
}: {
  deployment: Deployment
  available: boolean
  describedBy: string | undefined
  size?: 'regular' | 'compact'
}) {
  const { run, isBusy } = useJob()
  const formId = useId()
  const [open, setOpen] = useState(false)
  const [value, setValue] = useState('')
  const [showError, setShowError] = useState(false)
  const { namespace, name } = deployment
  const target = resourceTarget('deployments', namespace, name)
  const replicas = /^\d+$/.test(value.trim()) ? Number(value.trim()) : null
  const valid = replicas !== null && replicas <= MAX_REPLICAS

  /** Opens the dialog with the current number of replicas. */
  function openDialog(): void {
    setValue(String(deployment.replicas))
    setShowError(false)
    setOpen(true)
  }

  /** Validates, closes the dialog and sends the request. */
  function submit(event: FormEvent): void {
    event.preventDefault()
    if (!valid) {
      setShowError(true)
      return
    }
    setOpen(false)
    void run('kubernetes.scale', target, `/api/kubernetes/deployments/${segment(namespace)}/${segment(name)}/scale`, {
      replicas,
    })
  }

  return (
    <>
      <Button
        size={size}
        icon="scale"
        busy={isBusy(target)}
        disabled={!available}
        aria-describedby={describedBy}
        aria-label={t('scaleAria', { name })}
        onClick={openDialog}
      >
        {t('scale')}
      </Button>
      <Dialog open={open} title={t('scaleTitle', { name })} onClose={() => setOpen(false)}>
        <form id={formId} className={uiStyles.form} onSubmit={submit} noValidate>
          <Field
            label={t('scaleLabel')}
            hint={t('scaleHint', { max: MAX_REPLICAS })}
            error={showError && !valid ? t('scaleInvalid', { max: MAX_REPLICAS }) : null}
          >
            {control => (
              <input
                {...control}
                type="text"
                inputMode="numeric"
                autoComplete="off"
                value={value}
                onChange={event => setValue(event.target.value)}
              />
            )}
          </Field>
          <div className={uiStyles.row}>
            <Button onClick={() => setOpen(false)}>{t('cancel')}</Button>
            <Button type="submit" variant="primary">
              {t('scaleSubmit')}
            </Button>
          </div>
        </form>
      </Dialog>
    </>
  )
}
