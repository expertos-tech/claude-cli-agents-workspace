import { type ReactNode, type SelectHTMLAttributes, useId } from 'react'
import { Icon, type IconName } from './Icon'
import styles from './ui.module.css'

interface PageHeaderProps {
  title: string
  description?: string
  actions?: ReactNode
}

/** Page title with its optional description and actions. */
export function PageHeader({ title, description, actions }: PageHeaderProps) {
  return (
    <header className={styles.pageHeader}>
      <div className={styles.pageHeading}>
        <h1 className={styles.pageTitle}>{title}</h1>
        {description && <p className={styles.pageDescription}>{description}</p>}
      </div>
      {actions && <div className={styles.row}>{actions}</div>}
    </header>
  )
}

interface PageProps {
  children: ReactNode
}

/** Column of a screen, with the spacing between its blocks. */
export function Page({ children }: PageProps) {
  return <div className={styles.page}>{children}</div>
}

interface CardProps {
  title?: string
  actions?: ReactNode
  children: ReactNode
}

/** Surface of a block of content. */
export function Card({ title, actions, children }: CardProps) {
  return (
    <section className={styles.card}>
      {(title || actions) && (
        <div className={styles.cardHeader}>
          {title && <h2 className={styles.cardTitle}>{title}</h2>}
          {actions && <div className={styles.row}>{actions}</div>}
        </div>
      )}
      {children}
    </section>
  )
}

/** Props a form control receives from its Field, to be tied to the label, hint and error. */
export interface ControlProps {
  id: string
  className: string | undefined
  'aria-describedby'?: string
  'aria-invalid'?: true
}

interface FieldProps {
  label: string
  hint?: string
  error?: string | null
  multiline?: boolean
  /** Id of an explanation outside the field, such as why it is disabled. */
  describedBy?: string
  children: (control: ControlProps) => ReactNode
}

/** Label, control, hint and error, tied together so a screen reader reads all of them. */
export function Field({ label, hint, error, multiline = false, describedBy: outsideId, children }: FieldProps) {
  const id = useId()
  const hintId = hint ? `${id}-hint` : undefined
  const errorId = error ? `${id}-error` : undefined
  const describedBy = [hintId, errorId, outsideId].filter(Boolean).join(' ') || undefined
  const control: ControlProps = {
    id,
    className: multiline ? `${styles.input} ${styles.textarea}` : styles.input,
    'aria-describedby': describedBy,
    'aria-invalid': error ? true : undefined,
  }
  return (
    <div className={styles.field}>
      <label className={styles.label} htmlFor={id}>
        {label}
      </label>
      {children(control)}
      {hint && (
        <span id={hintId} className={styles.hint}>
          {hint}
        </span>
      )}
      {error && (
        <span id={errorId} className={styles.fieldError}>
          <Icon name="alert" size={14} />
          <span>{error}</span>
        </span>
      )}
    </div>
  )
}

interface SelectFieldProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label: string
  options: { value: string; label: string }[]
}

/** A native select with its label. */
export function SelectField({ label, options, ...rest }: SelectFieldProps) {
  return (
    <Field label={label}>
      {control => (
        <select {...rest} {...control}>
          {options.map(option => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      )}
    </Field>
  )
}

interface NoticeProps {
  icon?: IconName
  id?: string
  children: ReactNode
}

/** A block of explanation in the page flow, such as why the actions are unavailable. */
export function Notice({ icon = 'info', id, children }: NoticeProps) {
  return (
    <div className={styles.notice} id={id}>
      <Icon name={icon} size={18} />
      <div className={styles.noticeBody}>{children}</div>
    </div>
  )
}

export interface DetailItem {
  term: string
  value: ReactNode
}

interface DetailListProps {
  items: DetailItem[]
}

/** A list of labeled values. */
export function DetailList({ items }: DetailListProps) {
  return (
    <dl className={styles.details}>
      {items.map(item => (
        <div key={item.term} className={styles.detail}>
          <dt className={styles.detailTerm}>{item.term}</dt>
          <dd>{item.value}</dd>
        </div>
      ))}
    </dl>
  )
}

interface TabItem {
  label: string
  href: string
  icon?: IconName
  current: boolean
}

interface TabsNavProps {
  label: string
  items: TabItem[]
}

/** Links between the views of a screen. Each view has its own address. */
export function TabsNav({ label, items }: TabsNavProps) {
  return (
    <nav className={styles.tabs} aria-label={label}>
      {items.map(item => (
        <a key={item.href} className={styles.tab} href={item.href} aria-current={item.current ? 'page' : undefined}>
          {item.icon && <Icon name={item.icon} />}
          {item.label}
        </a>
      ))}
    </nav>
  )
}

interface MeterProps {
  /** From 0 to 1. */
  ratio: number
}

/** Bar of a value whose number is always written beside it, so it is only decorative. */
export function Meter({ ratio }: MeterProps) {
  const percent = Math.min(Math.max(ratio, 0), 1) * 100
  return (
    <div className={styles.meter} aria-hidden="true">
      <div className={styles.meterFill} style={{ width: `${percent}%` }} />
    </div>
  )
}

export { styles as uiStyles }
