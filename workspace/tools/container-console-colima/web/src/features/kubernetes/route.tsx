import { useId } from 'react'
import { useLive } from '../../api/useLive'
import { AvailabilityNotice } from '../../components/AvailabilityNotice'
import { KubernetesToggle } from '../../components/KubernetesToggle'
import { Card, Page, PageHeader, TabsNav } from '../../components/ui'
import { createTranslator } from '../../i18n'
import { type FeatureRoute, href, type PageProps } from '../../routing'
import { ApplyYaml } from './ApplyYaml'
import { messages } from './messages'
import { NamespaceDetails, NamespacedDetails, PodDetails } from './ResourceDetails'
import { DeploymentList, NamespaceList, PodList, ServiceList } from './ResourceLists'

const t = createTranslator(messages)

const TABS = [
  { id: 'namespaces', label: 'tabNamespaces' },
  { id: 'pods', label: 'tabPods' },
  { id: 'deployments', label: 'tabDeployments' },
  { id: 'services', label: 'tabServices' },
  { id: 'apply', label: 'tabApply' },
] as const

/** The Kubernetes area. Addresses: `tab`, `namespaces/name`, `kind/namespace/name[/logs|terminal]`. */
function KubernetesPage({ segments }: PageProps) {
  const [tab = 'pods', first, second, view] = segments
  const environment = useLive('environment').data
  const live = useLive('kubernetes')
  const noticeId = useId()
  const snapshot = live.data
  const available = snapshot?.available ?? false
  const shared = { snapshot, available, describedBy: available ? undefined : noticeId }

  const availability = !available && (
    <AvailabilityNotice
      id={noticeId}
      source="kubernetes"
      loading={!snapshot}
      reasonCode={snapshot?.reasonCode}
      reason={snapshot?.reason}
    />
  )

  if (tab === 'namespaces' && first) {
    return (
      <Page>
        {availability}
        <NamespaceDetails name={first} {...shared} />
      </Page>
    )
  }
  if (tab === 'pods' && first && second) {
    return (
      <Page>
        {availability}
        <PodDetails namespace={first} name={second} view={view} {...shared} />
      </Page>
    )
  }
  if ((tab === 'deployments' || tab === 'services') && first && second) {
    return (
      <Page>
        {availability}
        <NamespacedDetails kind={tab} namespace={first} name={second} {...shared} />
      </Page>
    )
  }

  return (
    <Page>
      <PageHeader eyebrow={t('eyebrow')} title={t('title')} description={t('description')} />
      {environment && (
        <Card title={t('modeTitle')}>
          <KubernetesToggle environment={environment} kubernetes={snapshot} />
        </Card>
      )}
      {availability}
      <TabsNav
        label={t('tabsLabel')}
        items={TABS.map(item => ({
          label: t(item.label),
          href: href('kubernetes', item.id),
          current: item.id === tab,
        }))}
      />
      {tab === 'namespaces' && <NamespaceList {...shared} />}
      {tab === 'pods' && <PodList {...shared} />}
      {tab === 'deployments' && <DeploymentList {...shared} />}
      {tab === 'services' && <ServiceList {...shared} />}
      {tab === 'apply' && <ApplyYaml available={available} describedBy={shared.describedBy} />}
    </Page>
  )
}

export const route: FeatureRoute = {
  id: 'kubernetes',
  order: 80,
  group: 'cluster',
  icon: 'kubernetes',
  Page: KubernetesPage,
}
