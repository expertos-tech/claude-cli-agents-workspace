import '@fontsource/poppins/latin-700.css'
import '@fontsource/roboto/latin-400.css'
import '@fontsource/roboto/latin-500.css'
import '@fontsource/roboto/latin-700.css'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import { applyStoredMotion } from './components/MotionToggle'
import { applyStoredTheme } from './components/ThemeSelect'
import { LOCALE } from './i18n'
import './styles/base.css'

const container = document.getElementById('root')
if (!container) {
  throw new Error('the #root element is missing from index.html')
}

document.documentElement.lang = LOCALE
applyStoredMotion()
applyStoredTheme()
createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
