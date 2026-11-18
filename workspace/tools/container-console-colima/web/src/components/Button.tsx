import type { AnchorHTMLAttributes, ButtonHTMLAttributes, MouseEvent, ReactNode, Ref } from 'react'
import styles from './Button.module.css'
import { Icon, type IconName } from './Icon'

type Variant = 'primary' | 'secondary'
type Size = 'regular' | 'compact'

/** Joins the classes of a button, plus one from the caller. */
function classesOf(variant: Variant, size: Size, extra?: string): string {
  return [styles.button, styles[variant], styles[size], extra].filter(Boolean).join(' ')
}

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
  size?: Size
  icon?: IconName
  /** An action on this target is running. Unlike `disabled`, the button keeps the keyboard focus. */
  busy?: boolean
  ref?: Ref<HTMLButtonElement>
  children: ReactNode
}

/** The button of the whole console. It submits nothing unless `type="submit"` is asked for. */
export function Button({
  variant = 'secondary',
  size = 'regular',
  icon,
  busy = false,
  type = 'button',
  className,
  onClick,
  children,
  ...rest
}: ButtonProps) {
  /** Ignores a click while the target is busy. */
  function handleClick(event: MouseEvent<HTMLButtonElement>): void {
    if (busy) {
      event.preventDefault()
      return
    }
    onClick?.(event)
  }

  return (
    <button
      {...rest}
      type={type}
      className={classesOf(variant, size, className)}
      aria-disabled={busy || undefined}
      onClick={handleClick}
    >
      {icon && <Icon name={busy ? 'hourglass' : icon} />}
      <span>{children}</span>
    </button>
  )
}

interface LinkButtonProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  variant?: Variant
  size?: Size
  icon?: IconName
  children: ReactNode
}

/** A link with the look of a button, for navigation between screens. */
export function LinkButton({ variant = 'secondary', size = 'regular', icon, children, ...rest }: LinkButtonProps) {
  return (
    <a {...rest} className={classesOf(variant, size)}>
      {icon && <Icon name={icon} />}
      <span>{children}</span>
    </a>
  )
}

interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  icon: IconName
  label: string
}

/** A button with only an icon. `label` is its accessible name. */
export function IconButton({ icon, label, type = 'button', ...rest }: IconButtonProps) {
  return (
    <button {...rest} type={type} className={styles.iconButton} aria-label={label}>
      <Icon name={icon} size={20} />
    </button>
  )
}
