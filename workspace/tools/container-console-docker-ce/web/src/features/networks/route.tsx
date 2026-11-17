import type { Network } from '../../api/types'
import { MonoId, shortId } from '../../components/MonoId'
import { NamedResourceScreen } from '../../components/NamedResourceScreen'
import { createTranslator, formatTimestamp } from '../../i18n'
import type { FeatureRoute, PageProps } from '../../routing'
import { messages } from './messages'

const t = createTranslator(messages)

/** The networks: list, create, details and remove. */
function NetworksPage({ segments }: PageProps) {
  return (
    <NamedResourceScreen<Network>
      segments={segments}
      routeId="networks"
      apiPrefix="/api/networks"
      jobPrefix="network"
      t={t}
      rowsOf={docker => docker.networks}
      nameOf={row => row.name}
      columns={[
        { id: 'id', header: t('columnId'), cell: row => <MonoId value={shortId(row.id)} /> },
        { id: 'driver', header: t('columnDriver'), cell: row => row.driver },
        { id: 'scope', header: t('columnScope'), cell: row => row.scope },
        {
          id: 'internal',
          header: t('columnInternal'),
          cell: row => (row.internal ? t('internalYes') : t('internalNo')),
        },
        { id: 'project', header: t('columnProject'), cell: row => row.composeProject ?? t('noProject') },
        { id: 'created', header: t('columnCreated'), cell: row => formatTimestamp(row.createdAt) },
      ]}
      searchText={row => `${row.name} ${row.id} ${row.driver} ${row.composeProject ?? ''}`}
    />
  )
}

export const route: FeatureRoute = { id: 'networks', order: 60, group: 'docker', icon: 'network', Page: NetworksPage }
