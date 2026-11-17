import { type ReactNode, useEffect, useId, useRef, useState } from 'react'
import { t } from '../i18n/messages'
import { Button } from './Button'
import styles from './ConfirmDialog.module.css'
import type { IconName } from './Icon'
import { StatusBadge } from './StatusBadge'

interface DialogProps {
  open: boolean
  title: string
  onClose: () => void
  variant?: 'center' | 'drawer'
  children: ReactNode
}

/** A native modal: the browser traps the focus, closes on Esc and returns the focus on close. */
export function Dialog({ open, title, onClose, variant = 'center', children }: DialogProps) {
  const titleId = useId()
  const ref = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const dialog = ref.current
    if (open && dialog && !dialog.open) {
      dialog.showModal()
      dialog.querySelector<HTMLElement>('[data-autofocus]')?.focus()
    } else if (!open && dialog?.open) {
      dialog.close()
    }
  }, [open])

  return (
    <dialog ref={ref} className={`${styles.dialog} ${styles[variant]}`} aria-labelledby={titleId} onClose={onClose}>
      <h2 id={titleId} className={variant === 'drawer' ? 'visually-hidden' : styles.title}>
        {title}
      </h2>
      {open && children}
    </dialog>
  )
}

interface ConfirmDialogProps {
  open: boolean
  title: string
  confirmLabel: string
  /** Marks an action that loses data, with the warning in text and icon. */
  irreversible?: boolean
  onConfirm: () => void
  onCancel: () => void
  children: ReactNode
}

/** Asks for explicit confirmation. Cancel, Esc and closing send nothing. */
export function ConfirmDialog({
  open,
  title,
  confirmLabel,
  irreversible = false,
  onConfirm,
  onCancel,
  children,
}: ConfirmDialogProps) {
  return (
    <Dialog open={open} title={title} onClose={onCancel}>
      <div className={styles.body}>{children}</div>
      {irreversible && <StatusBadge tone="critical" label={t('confirm.irreversible')} />}
      <div className={styles.actions}>
        <Button data-autofocus onClick={onCancel}>
          {t('action.cancel')}
        </Button>
        <Button variant="primary" onClick={onConfirm}>
          {confirmLabel}
        </Button>
      </div>
    </Dialog>
  )
}

interface ConfirmButtonProps {
  label: string
  /** Names the target for a screen reader, where several rows have the same visible label. */
  ariaLabel?: string
  icon?: IconName
  variant?: 'primary' | 'secondary'
  size?: 'regular' | 'compact'
  disabled?: boolean
  busy?: boolean
  describedBy?: string
  dialogTitle: string
  confirmLabel: string
  irreversible?: boolean
  onConfirm: () => void
  /** Runs when the dialog closes in any way, to reset options inside it. */
  onDialogClosed?: () => void
  children: ReactNode
}

/** A button that opens its confirmation and runs the action only after it. */
export function ConfirmButton({
  label,
  ariaLabel,
  icon,
  variant,
  size,
  disabled,
  busy,
  describedBy,
  dialogTitle,
  confirmLabel,
  irreversible,
  onConfirm,
  onDialogClosed,
  children,
}: ConfirmButtonProps) {
  const [open, setOpen] = useState(false)

  /** Closes the dialog, which returns the focus to the button. */
  function close(): void {
    setOpen(false)
    onDialogClosed?.()
  }

  return (
    <>
      <Button
        icon={icon}
        variant={variant}
        size={size}
        busy={busy}
        disabled={disabled}
        aria-describedby={describedBy}
        aria-label={ariaLabel}
        onClick={() => setOpen(true)}
      >
        {label}
      </Button>
      <ConfirmDialog
        open={open}
        title={dialogTitle}
        confirmLabel={confirmLabel}
        irreversible={irreversible}
        onCancel={close}
        onConfirm={() => {
          onConfirm()
          close()
        }}
      >
        {children}
      </ConfirmDialog>
    </>
  )
}
