import { Fragment } from 'react'
import styles from './MonoId.module.css'

/** Above this length a piece with no break point may not fit a phone, so it scrolls in its own box. */
const LONG_PIECE = 24
const SHORT_ID_LENGTH = 12

interface MonoIdProps {
  value: string
}

/** Shows an id, endpoint or path in monospace, breaking only after `.`, `/` or `-`. */
export function MonoId({ value }: MonoIdProps) {
  const pieces = value.split(/(?<=[./-])/)
  const scrolls = pieces.some(piece => piece.length > LONG_PIECE)
  return (
    <code className={styles.id} tabIndex={scrolls ? 0 : undefined}>
      {pieces.map((piece, index) => (
        // The pieces of a fixed string never reorder, so the position is a stable key.
        <Fragment key={index}>
          {piece}
          <wbr />
        </Fragment>
      ))}
    </code>
  )
}

/** Shows a long value in monospace on one line, cut with an ellipsis. Hovering shows the whole value. */
export function TruncatedMonoId({ value }: MonoIdProps) {
  return (
    <code className={styles.truncated} title={value}>
      {value}
    </code>
  )
}

/** Shortens a long Docker id to the 12 characters the CLI itself prints. */
export function shortId(id: string): string {
  const [prefix, hash] = id.startsWith('sha256:') ? ['sha256:', id.slice('sha256:'.length)] : ['', id]
  return `${prefix}${hash.slice(0, SHORT_ID_LENGTH)}`
}
