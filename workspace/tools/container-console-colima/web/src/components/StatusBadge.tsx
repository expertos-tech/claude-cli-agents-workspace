import { Icon, type IconName } from './Icon'
import styles from './StatusBadge.module.css'

export type Tone = 'good' | 'warning' | 'serious' | 'critical' | 'neutral' | 'progress'

const ICON_BY_TONE: Record<Tone, IconName> = {
  good: 'check',
  warning: 'alert',
  serious: 'alert',
  critical: 'close',
  neutral: 'minus',
  progress: 'hourglass',
}

interface StatusBadgeProps {
  tone: Tone
  label: string
}

/** A status with icon and text together: color alone never carries it. */
export function StatusBadge({ tone, label }: StatusBadgeProps) {
  return (
    <span className={styles.badge}>
      <span className={`${styles.chip} ${styles[tone]}`}>
        <Icon name={ICON_BY_TONE[tone]} size={12} />
      </span>
      <span>{label}</span>
    </span>
  )
}
