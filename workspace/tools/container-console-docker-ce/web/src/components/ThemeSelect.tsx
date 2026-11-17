import { useSyncExternalStore } from 'react'
import { t } from '../i18n/messages'
import { SelectField } from './ui'

/** public/theme-init.js reads the same key before the first paint. */
const STORAGE_KEY = 'container-console-docker-ce.theme'
const CHOICES = ['system', 'dark', 'light'] as const

type ThemeChoice = (typeof CHOICES)[number]

const OPTIONS = CHOICES.map(choice => ({ value: choice, label: t(`nav.theme.${choice}`) }))

/** The side menu exists twice, in the sidebar and in the drawer, and both show the same choice. */
const listeners = new Set<() => void>()
let current = readStoredChoice()

/** Reads a stored or selected value. Anything else means following the operating system. */
function parseChoice(value: string | null): ThemeChoice {
  return CHOICES.find(choice => choice === value) ?? 'system'
}

/** Reads the choice of the user. */
function readStoredChoice(): ThemeChoice {
  try {
    return parseChoice(localStorage.getItem(STORAGE_KEY))
  } catch {
    return 'system'
  }
}

/** Writes the choice to the attribute that sets the color-scheme of the root. */
function applyTheme(choice: ThemeChoice): void {
  if (choice === 'system') {
    delete document.documentElement.dataset.theme
  } else {
    document.documentElement.dataset.theme = choice
  }
}

/** Keeps the page and the control in agreement even if public/theme-init.js did not load. */
export function applyStoredTheme(): void {
  applyTheme(current)
}

/** Applies and stores a new choice. */
function chooseTheme(choice: ThemeChoice): void {
  current = choice
  applyTheme(choice)
  try {
    localStorage.setItem(STORAGE_KEY, choice)
  } catch {
    // Without storage the choice only lasts until the reload.
  }
  for (const listener of listeners) {
    listener()
  }
}

/** Registers a mounted control and returns how to remove it. */
function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** The user choice between following the operating system, dark and light. */
export function ThemeSelect() {
  const choice = useSyncExternalStore(subscribe, () => current)
  return (
    <SelectField
      label={t('nav.theme')}
      value={choice}
      options={OPTIONS}
      onChange={event => chooseTheme(parseChoice(event.target.value))}
    />
  )
}
