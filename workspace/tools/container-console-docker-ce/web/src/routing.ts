import { type ComponentType, useSyncExternalStore } from 'react'
import type { IconName } from './components/Icon'

/** Props of a feature page: the hash segments after the feature id. */
export interface PageProps {
  segments: string[]
}

export type NavGroup = 'main' | 'docker' | 'cluster'

/** What each `features/<name>/route.tsx` exports as `route`. */
export interface FeatureRoute {
  id: string
  order: number
  group: NavGroup
  icon: IconName
  Page: ComponentType<PageProps>
}

/** What each `features/<name>/messages.ts` must have for the shell. */
export interface FeatureShellMessages {
  nav: string
}

/** Subscribes to changes of the hash. */
function subscribeHash(listener: () => void): () => void {
  window.addEventListener('hashchange', listener)
  return () => window.removeEventListener('hashchange', listener)
}

/** Reads the current hash. */
function readHash(): string {
  return location.hash
}

/** Decodes one hash segment, keeping it as written if it is malformed. */
function decodeSegment(value: string): string {
  try {
    return decodeURIComponent(value)
  } catch {
    return value
  }
}

/** Follows the hash route, split in decoded segments. `#/a/b` gives `["a", "b"]`. */
export function useHashRoute(): string[] {
  const hash = useSyncExternalStore(subscribeHash, readHash)
  return hash.replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeSegment)
}

/** Builds the href of a screen from its segments. */
export function href(...segments: string[]): string {
  return `#/${segments.map(encodeURIComponent).join('/')}`
}
