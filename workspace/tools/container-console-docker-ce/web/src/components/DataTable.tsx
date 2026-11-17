import { type ReactNode, useId, useState } from 'react'
import { t } from '../i18n/messages'
import styles from './DataTable.module.css'
import { Icon } from './Icon'
import { Field } from './ui'

export interface Column<Row> {
  id: string
  header: string
  cell: (row: Row) => ReactNode
}

/** Rows that share a key collapse under one header the viewer opens and closes. */
export interface RowGrouping<Row> {
  /** The group of a row; undefined keeps the row on its own. */
  key: (row: Row) => string | undefined
  /** Name shown on the toggle. */
  title: (key: string, rows: Row[]) => ReactNode
  /** Accessible name of the toggle. */
  toggleLabel: (key: string, rows: Row[]) => string
  /** Shown beside the toggle, e.g. how many rows are running. */
  summary?: (rows: Row[]) => ReactNode
  /** Where the open groups of this table are remembered in the browser. */
  storageKey: string
}

interface DataTableProps<Row> {
  caption: string
  rows: Row[]
  rowKey: (row: Row) => string
  /** Always visible. */
  identity: Column<Row>
  /** Always visible. */
  status?: Column<Row>
  /** Stacked inside the identity cell when the table has no room for them as columns. */
  columns: Column<Row>[]
  /** Always visible. */
  actions?: (row: Row) => ReactNode
  emptyText: string
  /** Text of a row searched by the filter field. Without it the table has no filter. */
  searchText?: (row: Row) => string
  /** Groups of two rows or more become an accordion; a group of one stays a plain row. */
  grouping?: RowGrouping<Row>
}

type Segment<Row> = { kind: 'row'; row: Row } | { kind: 'group'; key: string; rows: Row[] }

/** Splits the visible rows into plain rows and groups, each group where its first row was. */
function segment<Row>(visible: Row[], all: Row[], grouping: RowGrouping<Row> | undefined): Segment<Row>[] {
  if (!grouping) return visible.map(row => ({ kind: 'row', row }))
  const sizes = new Map<string, number>()
  for (const row of all) {
    const key = grouping.key(row)
    if (key !== undefined) sizes.set(key, (sizes.get(key) ?? 0) + 1)
  }
  const segments: Segment<Row>[] = []
  const groups = new Map<string, Row[]>()
  for (const row of visible) {
    const key = grouping.key(row)
    if (key === undefined || (sizes.get(key) ?? 0) < 2) {
      segments.push({ kind: 'row', row })
      continue
    }
    const members = groups.get(key)
    if (members) {
      members.push(row)
    } else {
      const created = [row]
      groups.set(key, created)
      segments.push({ kind: 'group', key, rows: created })
    }
  }
  return segments
}

/** The open groups remembered for this table; empty when the browser keeps nothing. */
function readOpenGroups(storageKey: string | undefined): Set<string> {
  if (!storageKey) return new Set()
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(storageKey) ?? '[]')
    return new Set(Array.isArray(stored) ? stored.filter(item => typeof item === 'string') : [])
  } catch {
    return new Set()
  }
}

/** Remembers the open groups. Losing them only means the groups start closed. */
function writeOpenGroups(storageKey: string, open: Set<string>): void {
  try {
    localStorage.setItem(storageKey, JSON.stringify([...open]))
  } catch {
    // Storage blocked or full: the choice lasts until the page reloads.
  }
}

/**
 * A real table whose identification, status and actions never leave the screen. It adapts to its
 * own width, so the side menu counts. The explicit roles keep the table semantics on phones,
 * where the rows become grids and browsers would otherwise drop them.
 */
export function DataTable<Row>({
  caption,
  rows,
  rowKey,
  identity,
  status,
  columns,
  actions,
  emptyText,
  searchText,
  grouping,
}: DataTableProps<Row>) {
  const captionId = useId()
  const groupIdPrefix = useId()
  const [query, setQuery] = useState('')
  const [openGroups, setOpenGroups] = useState(() => readOpenGroups(grouping?.storageKey))
  const needle = query.trim().toLowerCase()
  const filtering = Boolean(searchText && needle)
  const visible = searchText && needle ? rows.filter(row => searchText(row).toLowerCase().includes(needle)) : rows
  const columnCount = 1 + (status ? 1 : 0) + columns.length + (actions ? 1 : 0)
  const segments = segment(visible, rows, grouping)

  /** Opens or closes one group and remembers the choice. */
  function toggle(key: string): void {
    setOpenGroups(current => {
      const next = new Set(current)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      if (grouping) writeOpenGroups(grouping.storageKey, next)
      return next
    })
  }

  /** One data row; a member of a group is indented under its header. */
  function renderRow(row: Row, member: boolean) {
    return (
      <tr key={rowKey(row)} role="row" className={member ? `${styles.row} ${styles.memberRow}` : styles.row}>
        <th role="rowheader" scope="row" className={styles.identity}>
          <div className={styles.identityValue}>{identity.cell(row)}</div>
          {columns.length > 0 && (
            <dl className={styles.stacked}>
              {columns.map(column => (
                <div key={column.id} className={styles.stackedItem}>
                  <dt>{column.header}</dt>
                  <dd>{column.cell(row)}</dd>
                </div>
              ))}
            </dl>
          )}
        </th>
        {status && (
          <td role="cell" className={styles.status}>
            {status.cell(row)}
          </td>
        )}
        {columns.map(column => (
          <td key={column.id} role="cell" className={styles.secondary}>
            {column.cell(row)}
          </td>
        ))}
        {actions && (
          <td role="cell" className={styles.actions}>
            <div className={styles.actionList}>{actions(row)}</div>
          </td>
        )}
      </tr>
    )
  }

  /** A group: the header row with the toggle, then its rows, hidden while closed. */
  function renderGroup(key: string, members: Row[], index: number) {
    if (!grouping) return null
    // A filter opens every group with a match, so a match is never hidden.
    const open = filtering || openGroups.has(key)
    const bodyId = `${groupIdPrefix}-group-${index}`
    return [
      <tbody key={`group-head-${key}`} role="rowgroup" className={styles.groupHead}>
        <tr role="row" className={styles.groupRow}>
          <th role="rowheader" scope="rowgroup" colSpan={columnCount} className={styles.groupCell}>
            <div className={styles.groupHeader}>
              <button
                type="button"
                className={styles.groupToggle}
                aria-expanded={open}
                aria-controls={bodyId}
                aria-label={grouping.toggleLabel(key, members)}
                disabled={filtering}
                onClick={() => toggle(key)}
              >
                <Icon name={open ? 'chevronUp' : 'chevronDown'} />
                <span className={styles.groupTitle}>{grouping.title(key, members)}</span>
              </button>
              {grouping.summary && <div className={styles.groupSummary}>{grouping.summary(members)}</div>}
            </div>
          </th>
        </tr>
      </tbody>,
      <tbody key={`group-body-${key}`} id={bodyId} role="rowgroup" hidden={!open}>
        {members.map(row => renderRow(row, true))}
      </tbody>,
    ]
  }

  return (
    <div className={styles.block}>
      {searchText && (
        <Field label={t('table.filter')}>
          {control => (
            <input
              {...control}
              type="search"
              autoComplete="off"
              value={query}
              onChange={event => setQuery(event.target.value)}
            />
          )}
        </Field>
      )}
      <div className={styles.scroller} role="region" aria-labelledby={captionId} tabIndex={0}>
        <table className={styles.table} role="table" aria-labelledby={captionId}>
          <caption id={captionId} className={styles.caption}>
            {caption}
          </caption>
          <thead className={styles.head} role="rowgroup">
            <tr role="row">
              <th role="columnheader" scope="col">
                {identity.header}
              </th>
              {status && (
                <th role="columnheader" scope="col">
                  {status.header}
                </th>
              )}
              {columns.map(column => (
                <th key={column.id} className={styles.secondary} role="columnheader" scope="col">
                  {column.header}
                </th>
              ))}
              {actions && (
                <th role="columnheader" scope="col">
                  {t('table.actions')}
                </th>
              )}
            </tr>
          </thead>
          {visible.length === 0 && (
            <tbody role="rowgroup">
              <tr role="row" className={styles.emptyRow}>
                <td role="cell" colSpan={columnCount} className={styles.empty}>
                  {rows.length === 0 ? emptyText : t('table.noMatches')}
                </td>
              </tr>
            </tbody>
          )}
          {segments.map((part, index) =>
            part.kind === 'group' ? (
              renderGroup(part.key, part.rows, index)
            ) : (
              <tbody key={`row-${rowKey(part.row)}`} role="rowgroup">
                {renderRow(part.row, false)}
              </tbody>
            ),
          )}
        </table>
      </div>
    </div>
  )
}
