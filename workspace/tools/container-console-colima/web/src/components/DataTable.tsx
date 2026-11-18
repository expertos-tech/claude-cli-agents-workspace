// biome-ignore-all lint/a11y/noRedundantRoles: the narrow layout changes the table display (DataTable.module.css), and the explicit roles keep its table semantics for screen readers
// biome-ignore-all lint/a11y/useSemanticElements: same reason; the elements are already the semantic ones, the roles are kept on purpose
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

export interface RowGroup<Row> {
  /** Rows with the same key share a group, in the order the first one of each appears. */
  key: (row: Row) => string
  /** Header of a group, built from the rows the filter left in it. */
  header: (key: string, rows: Row[]) => ReactNode
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
  /** Splits the rows into groups, each under a header row that opens and closes it, like an accordion. */
  group?: RowGroup<Row>
}

/** The rows by group key, keeping the order of the rows inside each group and between groups. */
function groupRows<Row>(rows: Row[], key: (row: Row) => string): [string, Row[]][] {
  const groups = new Map<string, Row[]>()
  for (const row of rows) {
    const value = key(row)
    const members = groups.get(value)
    if (members) members.push(row)
    else groups.set(value, [row])
  }
  return [...groups]
}

/** The content of a cell of a group, wrapped so it can shrink to no height. */
function Collapsible({ children }: { children: ReactNode }) {
  return (
    <div className={styles.collapse}>
      <div className={styles.collapseInner}>{children}</div>
    </div>
  )
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
  group,
}: DataTableProps<Row>) {
  const captionId = useId()
  const [query, setQuery] = useState('')
  const [collapsed, setCollapsed] = useState<ReadonlySet<string>>(new Set())
  // Groups the viewer toggled since the filter last changed: only they animate.
  const [clicked, setClicked] = useState<ReadonlySet<string>>(new Set())
  const toggle = (key: string) => {
    setClicked(current => (current.has(key) ? current : new Set(current).add(key)))
    setCollapsed(current => {
      const next = new Set(current)
      if (!next.delete(key)) next.add(key)
      return next
    })
  }
  const needle = query.trim().toLowerCase()
  const visible = searchText && needle ? rows.filter(row => searchText(row).toLowerCase().includes(needle)) : rows
  const columnCount = 1 + (status ? 1 : 0) + columns.length + (actions ? 1 : 0)

  /**
   * One data row. A member of a closed group keeps its place with no height, out of sight, of the
   * tab order and of the accessibility tree; its cells can collapse.
   */
  function renderRow(row: Row, member?: { open: boolean }) {
    const cell = (content: ReactNode) => (member ? <Collapsible>{content}</Collapsible> : content)
    return (
      <tr
        key={rowKey(row)}
        role="row"
        className={member ? `${styles.row} ${styles.memberRow}` : styles.row}
        inert={member ? !member.open : undefined}
      >
        <th role="rowheader" scope="row" className={styles.identity}>
          {cell(
            <>
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
            </>,
          )}
        </th>
        {status && (
          <td role="cell" className={styles.status}>
            {cell(status.cell(row))}
          </td>
        )}
        {columns.map(column => (
          <td key={column.id} role="cell" className={styles.secondary}>
            {cell(column.cell(row))}
          </td>
        ))}
        {actions && (
          <td role="cell" className={styles.actions}>
            {cell(<div className={styles.actionList}>{actions(row)}</div>)}
          </td>
        )}
      </tr>
    )
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
              onChange={event => {
                // The rows a filter adds or removes change at once; only a click on a toggle animates.
                setClicked(new Set())
                setQuery(event.target.value)
              }}
            />
          )}
        </Field>
      )}
      {/* biome-ignore lint/a11y/noNoninteractiveTabindex: a scrolling region must take keyboard focus to be scrolled without a mouse */}
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
          {group
            ? groupRows(visible, group.key).map(([key, members]) => {
                const open = !collapsed.has(key)
                return (
                  <tbody
                    key={key}
                    role="rowgroup"
                    className={styles.group}
                    data-open={open}
                    data-animate={clicked.has(key) || undefined}
                  >
                    <tr role="row" className={styles.groupRow}>
                      <th role="rowheader" scope="rowgroup" colSpan={columnCount} className={styles.groupHeader}>
                        <button
                          type="button"
                          className={styles.groupToggle}
                          aria-expanded={open}
                          onClick={() => toggle(key)}
                        >
                          <span className={styles.chevron}>
                            <Icon name="chevronDown" />
                          </span>
                          {group.header(key, members)}
                        </button>
                      </th>
                    </tr>
                    {members.map(row => renderRow(row, { open }))}
                  </tbody>
                )
              })
            : visible.length > 0 && <tbody role="rowgroup">{visible.map(row => renderRow(row))}</tbody>}
        </table>
      </div>
    </div>
  )
}
