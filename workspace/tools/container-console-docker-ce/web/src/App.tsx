import {
  Component,
  type ErrorInfo,
  type MouseEvent,
  type ReactNode,
  type RefObject,
  useEffect,
  useRef,
  useState,
} from 'react'
import styles from './App.module.css'
import { useLiveConnectionLost } from './api/useLive'
import { IconButton } from './components/Button'
import { Dialog } from './components/ConfirmDialog'
import { EnvironmentBadge } from './components/EnvironmentBadge'
import { Icon } from './components/Icon'
import { JobDock, MAIN_CONTENT_ID } from './components/JobDock'
import { MotionToggle } from './components/MotionToggle'
import { ThemeSelect } from './components/ThemeSelect'
import { Notice, Page, PageHeader } from './components/ui'
import { t } from './i18n/messages'
import { type FeatureRoute, type FeatureShellMessages, href, type NavGroup, useHashRoute } from './routing'

const routeModules = import.meta.glob<{ route: FeatureRoute }>('./features/*/route.tsx', { eager: true })
const messageModules = import.meta.glob<{ messages: FeatureShellMessages }>('./features/*/messages.ts', {
  eager: true,
})

interface Feature extends FeatureRoute {
  label: string
}

/** Joins each feature folder with its dictionary. A new area of the console is only a new folder. */
function discoverFeatures(): Feature[] {
  return Object.entries(routeModules)
    .map(([path, module]) => {
      const dictionary = messageModules[path.replace('route.tsx', 'messages.ts')]
      return { ...module.route, label: dictionary?.messages.nav ?? module.route.id }
    })
    .sort((left, right) => left.order - right.order)
}

const FEATURES = discoverFeatures()
const NAV_GROUPS: NavGroup[] = ['main', 'docker', 'cluster']

interface SideMenuProps {
  currentId: string | undefined
  onNavigate?: () => void
}

/** The menu of every screen, grouped. The current screen is marked with color and aria-current. */
function SideMenu({ currentId, onNavigate }: SideMenuProps) {
  return (
    <nav className={styles.menu} aria-label={t('nav.label')}>
      <p className={styles.product}>{t('app.name')}</p>
      {NAV_GROUPS.map(group => (
        <div key={group} className={styles.menuGroup}>
          <p className={styles.menuGroupTitle}>{t(`nav.group.${group}`)}</p>
          <ul className={styles.menuList}>
            {FEATURES.filter(feature => feature.group === group).map(feature => (
              <li key={feature.id}>
                <a
                  className={styles.menuItem}
                  href={href(feature.id)}
                  aria-current={feature.id === currentId ? 'page' : undefined}
                  onClick={onNavigate}
                >
                  <Icon name={feature.icon} size={18} />
                  {feature.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      ))}
      <div className={styles.menuFooter}>
        <ThemeSelect />
        <MotionToggle />
      </div>
    </nav>
  )
}

/** Shows the screen of the current hash. An empty hash opens the first screen, the overview. */
function useCurrentFeature(): { feature: Feature | undefined; segments: string[]; path: string } {
  const [featureId, ...segments] = useHashRoute()
  const feature = featureId ? FEATURES.find(item => item.id === featureId) : FEATURES[0]
  return { feature, segments, path: `${featureId ?? ''}/${segments.join('/')}` }
}

/** Moves the focus and scroll to the new screen and names the document after it. */
function useScreenChange(mainRef: RefObject<HTMLElement | null>, path: string, label: string | undefined): void {
  const firstRender = useRef(true)
  useEffect(() => {
    document.title = label ? t('app.documentTitle', { page: label }) : t('app.name')
    if (firstRender.current) {
      firstRender.current = false
      return
    }
    const main = mainRef.current
    main?.scrollTo(0, 0)
    // A view that took the focus for itself, like the terminal, or a tab still on screen, keeps it.
    const active = document.activeElement
    if (main && (active === main || !main.contains(active))) {
      main.focus({ preventScroll: true })
    }
  }, [mainRef, path, label])
}

/** The whole shell: top bar, side menu, content and the actions dock. */
function Shell() {
  const { feature, segments, path } = useCurrentFeature()
  const [drawerOpen, setDrawerOpen] = useState(false)
  const mainRef = useRef<HTMLElement>(null)
  const connectionLost = useLiveConnectionLost()
  useScreenChange(mainRef, path, feature?.label)

  return (
    <div className={styles.app}>
      <a className={styles.skipLink} href={`#${MAIN_CONTENT_ID}`} onClick={skipToContent}>
        {t('app.skipToContent')}
      </a>
      <header className={styles.topBar} data-surface="ink">
        <div className={styles.menuButton}>
          <IconButton
            icon="menu"
            label={t('nav.open')}
            aria-expanded={drawerOpen}
            onClick={() => setDrawerOpen(true)}
          />
        </div>
        <a href={href()} className={styles.logoLink}>
          <img src="/favicon.png" alt="" width={28} height={28} />
          <span className={styles.appName}>
            {t('app.project')}
            <span className={styles.toolName}>{t('app.name')}</span>
          </span>
        </a>
        <div className={styles.topBarEnd}>
          <EnvironmentBadge />
        </div>
      </header>
      <div className={styles.body}>
        <aside className={styles.sidebar} data-surface="ink">
          <SideMenu currentId={feature?.id} />
        </aside>
        <Dialog variant="drawer" open={drawerOpen} title={t('nav.label')} onClose={() => setDrawerOpen(false)}>
          <div className={styles.drawerContent} data-surface="ink">
            <div className={styles.drawerHeader}>
              <IconButton icon="close" label={t('nav.close')} onClick={() => setDrawerOpen(false)} />
            </div>
            <SideMenu currentId={feature?.id} onNavigate={() => setDrawerOpen(false)} />
          </div>
        </Dialog>
        <div className={styles.column}>
          {connectionLost && (
            <div className={styles.banner} role="status">
              <Icon name="alert" size={18} />
              <span>{t('live.lost')}</span>
            </div>
          )}
          <main id={MAIN_CONTENT_ID} ref={mainRef} className={styles.main} tabIndex={-1}>
            <CrashBoundary key={feature?.id ?? 'none'}>
              {feature ? <feature.Page segments={segments} /> : <NotFound />}
            </CrashBoundary>
          </main>
          <JobDock />
        </div>
      </div>
    </div>
  )
}

/** Follows the skip link without touching the hash, which holds the route. */
function skipToContent(event: MouseEvent<HTMLAnchorElement>): void {
  event.preventDefault()
  document.getElementById(MAIN_CONTENT_ID)?.focus()
}

/** The screen of an address that matches no feature. */
function NotFound() {
  return (
    <Page>
      <PageHeader title={t('app.notFoundTitle')} description={t('app.notFoundBody')} />
    </Page>
  )
}

interface CrashBoundaryProps {
  children: ReactNode
}

/** Keeps the menu and the dock on screen if a page breaks while rendering. */
class CrashBoundary extends Component<CrashBoundaryProps, { failed: boolean }> {
  override state = { failed: false }

  /** Marks the page as failed. */
  static getDerivedStateFromError(): { failed: boolean } {
    return { failed: true }
  }

  /** Leaves the cause in the browser console for whoever maintains the console. */
  override componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error(error, info.componentStack)
  }

  /** Renders the page or the explanation of the failure. */
  override render(): ReactNode {
    if (!this.state.failed) {
      return this.props.children
    }
    return (
      <Page>
        <Notice icon="alert">
          <strong>{t('app.crashTitle')}</strong>
          <p>{t('app.crashBody')}</p>
        </Notice>
      </Page>
    )
  }
}

/** The root of the console. */
export function App() {
  return <Shell />
}
