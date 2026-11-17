import type { ReactNode } from 'react'

// JSON with colors, built as React nodes: the text is never injected as HTML.

const tokenRe = /("(?:\\.|[^"\\])*")(\s*:)?|\b(true|false|null)\b|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g

export function JsonView({ value }: { value: unknown }) {
  const text = JSON.stringify(value, null, 2) ?? String(value)
  const nodes: ReactNode[] = []
  let last = 0
  for (const m of text.matchAll(tokenRe)) {
    const i = m.index ?? 0
    if (i > last) nodes.push(text.slice(last, i))
    if (m[1]) {
      nodes.push(
        <span key={i} className={m[2] ? 'j-key' : 'j-str'}>
          {m[1]}
        </span>,
      )
      if (m[2]) nodes.push(m[2])
    } else if (m[3]) {
      nodes.push(
        <span key={i} className="j-lit">
          {m[3]}
        </span>,
      )
    } else {
      nodes.push(
        <span key={i} className="j-num">
          {m[4]}
        </span>,
      )
    }
    last = i + m[0].length
  }
  if (last < text.length) nodes.push(text.slice(last))
  return <pre className="json">{nodes}</pre>
}
