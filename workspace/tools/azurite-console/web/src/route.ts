import { useEffect, useState } from 'react'

// The tab and the selection live in the hash, so a reload keeps the place:
// #/blobs/<container>/<folder...>, #/queues/<queue>, #/tables/<table>.

export type Tab = 'overview' | 'blobs' | 'queues' | 'tables'

export const tabs: { id: Tab; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'blobs', label: 'Blobs' },
  { id: 'queues', label: 'Queues' },
  { id: 'tables', label: 'Tables' },
]

export type Route = { tab: Tab; resource: string; rest: string }

function parse(hash: string): Route {
  const [tab = '', resource = '', ...rest] = hash.replace(/^#\/?/, '').split('/')
  const known = tabs.some(t => t.id === tab)
  return {
    tab: known ? (tab as Tab) : 'overview',
    resource: decodeURIComponent(resource),
    rest: rest.map(decodeURIComponent).join('/'),
  }
}

export function href(tab: Tab, resource = '', rest = ''): string {
  let h = `#/${tab}`
  if (resource) h += `/${encodeURIComponent(resource)}`
  if (resource && rest) h += `/${rest.split('/').map(encodeURIComponent).join('/')}`
  return h
}

export function go(tab: Tab, resource = '', rest = ''): void {
  window.location.hash = href(tab, resource, rest)
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parse(window.location.hash))
  useEffect(() => {
    const onChange = () => setRoute(parse(window.location.hash))
    window.addEventListener('hashchange', onChange)
    return () => window.removeEventListener('hashchange', onChange)
  }, [])
  return route
}
