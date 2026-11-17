import { createContext, type ReactNode, useCallback, useContext, useEffect, useRef, useState } from 'react'
import { errorText } from '../api.ts'

// Toasts for the result of each action and a confirmation dialog for the
// destructive ones, shared by every tab.

type Toast = { id: number; kind: 'ok' | 'error'; text: string }

type Confirm = {
  title: string
  message: ReactNode
  /** When set, the button stays disabled until this exact text is typed. */
  typeToConfirm?: string
  confirmLabel?: string
}

type Feedback = {
  ok: (text: string) => void
  error: (err: unknown, prefix?: string) => void
  confirm: (c: Confirm) => Promise<boolean>
}

const FeedbackContext = createContext<Feedback | null>(null)

export function useFeedback(): Feedback {
  const ctx = useContext(FeedbackContext)
  if (!ctx) throw new Error('useFeedback outside FeedbackProvider')
  return ctx
}

let nextId = 1

export function FeedbackProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const [pending, setPending] = useState<(Confirm & { resolve: (v: boolean) => void }) | null>(null)

  const push = useCallback((kind: Toast['kind'], text: string) => {
    const id = nextId++
    setToasts(t => [...t, { id, kind, text }])
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), kind === 'error' ? 9000 : 4000)
  }, [])

  const value = useRef<Feedback>({
    ok: text => push('ok', text),
    error: (err, prefix) => push('error', prefix ? `${prefix}: ${errorText(err)}` : errorText(err)),
    confirm: c => new Promise<boolean>(resolve => setPending({ ...c, resolve })),
  })

  return (
    <FeedbackContext.Provider value={value.current}>
      {children}
      <div className="toasts" aria-live="polite">
        {toasts.map(t => (
          <div key={t.id} className={`toast toast-${t.kind}`} role={t.kind === 'error' ? 'alert' : 'status'}>
            <span>{t.text}</span>
            <button
              type="button"
              className="link"
              onClick={() => setToasts(all => all.filter(x => x.id !== t.id))}
              aria-label="Close"
            >
              ×
            </button>
          </div>
        ))}
      </div>
      {pending && (
        <ConfirmDialog
          {...pending}
          onClose={v => {
            pending.resolve(v)
            setPending(null)
          }}
        />
      )}
    </FeedbackContext.Provider>
  )
}

function ConfirmDialog({
  title,
  message,
  typeToConfirm,
  confirmLabel,
  onClose,
}: Confirm & { onClose: (v: boolean) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const [typed, setTyped] = useState('')
  useEffect(() => {
    ref.current?.showModal()
  }, [])
  const ready = !typeToConfirm || typed === typeToConfirm
  return (
    <dialog ref={ref} className="dialog" onCancel={() => onClose(false)}>
      <form
        method="dialog"
        onSubmit={e => {
          e.preventDefault()
          if (ready) onClose(true)
        }}
      >
        <h2>{title}</h2>
        <div className="dialog-body">{message}</div>
        {typeToConfirm && (
          <label className="field">
            <span>
              Type <code>{typeToConfirm}</code> to confirm
            </span>
            <input autoFocus value={typed} onChange={e => setTyped(e.target.value)} spellCheck={false} />
          </label>
        )}
        <div className="dialog-actions">
          <button type="button" className="secondary" onClick={() => onClose(false)}>
            Cancel
          </button>
          {/* biome-ignore lint/a11y/noAutofocus: the confirm dialog opens on its first control, the confirm button when there is nothing to type */}
          <button type="submit" className="danger" disabled={!ready} autoFocus={!typeToConfirm}>
            {confirmLabel ?? 'Confirm'}
          </button>
        </div>
      </form>
    </dialog>
  )
}
