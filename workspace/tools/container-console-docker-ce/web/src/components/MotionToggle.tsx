import { useState } from 'react'
import { t } from '../i18n/messages'
import { uiStyles } from './ui'

const STORAGE_KEY = 'container-console-docker-ce.motion'

/** Reads the choice of the user. Motion is on unless turned off, and the OS setting still applies. */
function readMotionEnabled(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) !== 'off'
  } catch {
    return true
  }
}

/** Writes the choice to the attribute the motion token depends on. */
function applyMotion(enabled: boolean): void {
  if (enabled) {
    delete document.documentElement.dataset.motion
  } else {
    document.documentElement.dataset.motion = 'off'
  }
}

/** Applies the stored choice before the first render. */
export function applyStoredMotion(): void {
  applyMotion(readMotionEnabled())
}

/** The user toggle of data motion. */
export function MotionToggle() {
  const [enabled, setEnabled] = useState(readMotionEnabled)

  /** Applies and stores a new choice. */
  function change(next: boolean): void {
    setEnabled(next)
    applyMotion(next)
    try {
      localStorage.setItem(STORAGE_KEY, next ? 'on' : 'off')
    } catch {
      // Without storage the choice only lasts until the reload.
    }
  }

  return (
    <label className={uiStyles.choice}>
      <input type="checkbox" role="switch" checked={enabled} onChange={event => change(event.target.checked)} />
      <span>{t('nav.motion')}</span>
    </label>
  )
}
