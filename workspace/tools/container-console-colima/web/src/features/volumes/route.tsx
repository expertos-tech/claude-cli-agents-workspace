import type { Volume } from '../../api/types'
import { MonoId } from '../../components/MonoId'
import { NamedResourceScreen } from '../../components/NamedResourceScreen'
import { createTranslator } from '../../i18n'
import type { FeatureRoute, PageProps } from '../../routing'
import { messages } from './messages'

const t = createTranslator(messages)

/** The volumes: list, create, details and remove. */
function VolumesPage({ segments }: PageProps) {
  return (
    <NamedResourceScreen<Volume>
      segments={segments}
      routeId="volumes"
      apiPrefix="/api/volumes"
      jobPrefix="volume"
      t={t}
      rowsOf={docker => docker.volumes}
      nameOf={row => row.name}
      columns={[
        { id: 'driver', header: t('columnDriver'), cell: row => row.driver },
        { id: 'scope', header: t('columnScope'), cell: row => row.scope },
        { id: 'mountpoint', header: t('columnMountpoint'), cell: row => <MonoId value={row.mountpoint} /> },
        { id: 'project', header: t('columnProject'), cell: row => row.composeProject ?? t('noProject') },
      ]}
      searchText={row => `${row.name} ${row.driver} ${row.composeProject ?? ''}`}
    />
  )
}

export const route: FeatureRoute = { id: 'volumes', order: 50, group: 'docker', icon: 'volume', Page: VolumesPage }
