# Functional request: animate the Compose groups of the container consoles

**Project:** claude-cli-agents-workspace

**State:** ready. Size: feature (a bug fix in two tools). Source: the owner (2026-11-17).

## 1. Objective

In the containers screen of `tools/container-console-docker-ce`, a click on a Compose project group shows or hides its
rows in a single frame, and the chevron icon is swapped for another one without moving. The viewer sees no transition
and thinks nothing happened. The toggle must show what it does: the chevron rotates, and the rows grow and shrink in
height. `tools/container-console-colima` has the same bug in its own accordion, and the job dock of both consoles swaps
its chevron the same way.

Cause, read in the code: `web/src/components/DataTable.tsx` swaps `chevronDown` for `chevronUp` and sets `hidden` on
the `<tbody>` of the group, which `DataTable.module.css` turns into `display: none`. Table rows cannot animate
`height`, so the closed state cannot stay `display: none`.

## 3. Business rules

- BR-1: The toggle of a group shows one chevron that rotates: pointing right (closed) to pointing down (open), and
  back, over the UI motion duration.
- BR-2: On a click, the rows of the group grow from zero height to their height while fading in, and shrink back to
  zero while fading out; the rows below move smoothly, without a jump. The content of each cell sits in a wrapper that
  animates `grid-template-rows` from `0fr` to `1fr`, and the cell's vertical padding and bottom border go to zero when
  closed, so a closed row has no height.
- BR-3: A closed group stays out of the accessibility tree and of the tab order once its rows have collapsed
  (`visibility: hidden` after the transition, plus `inert`); its rows stay reachable while they open. `aria-expanded`
  and `aria-controls` keep working as today.
- BR-4: Only a click animates. The first render (groups opened from the browser's memory), a filter that opens every
  group with a match, and rows that the live topic adds or removes show at once, with no transition.
- BR-5: A new token `--motion-ui` (200 ms, easing `ease-out`) holds the duration of interface motion, beside
  `--motion-data`. Both go to `0ms` with the operating system's reduced motion and with the menu switch. That switch is
  renamed "Animations" / "Animações", because it now covers more than data. With motion off, a group opens and closes
  at once, as today, and the result is the same.
- BR-6: The job dock's expand/collapse button of both consoles shows one chevron that rotates by 180° with
  `--motion-ui` instead of swapping `chevronUp` for `chevronDown`. The dock body itself keeps opening at once.
- BR-7: Both consoles get BR-1 to BR-6. `container-console-colima` keeps its own accordion (`group`, `RowGroup`); the
  fix follows its structure and does not merge the two `DataTable` components.
- BR-8: The narrow layouts keep working: under 60 rem the secondary columns stack in the first cell, under 34 rem each
  row is a block; the animation works in both.

## 4. Acceptance criteria

The tools have no automated tests: each criterion is a manual test in a browser, plus the build checks.

- AC-1: Given the containers screen with a Compose project of two or more containers, when the viewer clicks its
  toggle, then the chevron rotates from right to down and the rows grow in height and fade in in about 200 ms; a second
  click reverses both, and the rows below the group slide up without a jump.
- AC-2: Given a closed group, when the viewer presses Tab through the table, then focus never lands in its rows, and
  the accessibility tree (DevTools) shows none of them; when the group is open, its links and actions are reachable.
- AC-3: Given the menu switch "Animations" off, or the system's reduced motion on, when a group or the dock is toggled,
  then it changes at once with no transition, and the CPU and memory bars also stop animating (the current test 10).
- AC-4: Given groups remembered as open, when the page reloads, then they show open with no animation; when the filter
  matches a row of a closed group, then the group shows open at once; when a container of an open group is created or
  removed, then its row appears or vanishes without animating the rest of the group.
- AC-5: Given a width under 34 rem and one between 34 and 60 rem, when a group is toggled, then AC-1 holds.
- AC-6: Given a job in the dock, when the viewer clicks collapse and expand, then its chevron rotates by 180°.
- AC-7: AC-1 to AC-6 hold in `container-console-colima` (built and run with `make build` on this Linux machine against
  docker-ce is enough for the screen behavior).
- AC-8: `make check` passes in both tools; `docs/manual-tests.md` of `container-console-docker-ce` has a test per
  criterion above (test 10 updated for the renamed switch); the pt-BR and es copies of that page stay pending for the
  release translation (`.claude/rules/docs.md`).

## 7. Out of scope

- Animating the dock body, the `<details>` disclosures (job output, full JSON) or page changes.
- Merging the `DataTable` components of the two consoles, or any other change to their behavior.
- A new animation library: CSS only.
- Creating `docs/` for `container-console-colima` (`import-from-fork` BR-11).

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. docker-ce: `--motion-ui` token and switch label, rotating chevron, height animation of the groups, rotating dock chevron; `make check`; manual tests in `docs/manual-tests.md` | medium | A bug in existing UI code, no security or data |
| 2. colima: the same in its own `DataTable` and `JobDock`; `make check` | medium | Same change on a different structure |
| 3. The owner runs AC-1 to AC-7 in the browser (`make build` and the binary of each tool) | low | Visual behavior only a person can judge |

## Execution — 2026-11-18, merged into developer (this merge)

- **Done:** stage 1, `container-console-docker-ce`: the `--motion-ui` token and the switch renamed "Animations", one
  rotating chevron, the height animation of the group rows, the rotating dock chevron, and the "Compose groups"
  manual tests (f824586); the column widths kept (c502181); stage 2, the same in `container-console-colima` on its own
  accordion (ebb1b82). Stage 3, the owner's visual run, is left.
- **Decisions taken while running:** each cell of a group row wraps its content in a grid whose single row goes from
  `1fr` to `0fr`, with the cell's vertical padding and bottom border going to zero; the wrapper is clipped with
  `overflow: visible clip`, because `overflow: hidden` made it a scroll container, which the table layout reads as
  having no minimum width (the state column of the Colima console shrank from 110 to 94 px and cut its badge), and
  4 px above and below keep the focus ring whole; a closed group turns `visibility: hidden` only after its transition
  and is `inert` at once; the groups a click toggled since the filter last changed are the only ones with transitions,
  which is how the first render, the filter and the live rows stay instant; `Button` takes a `className`, used by the
  dock's chevron; in the Colima console the rows of a closed group are now rendered (hidden) instead of unmounted, and
  `inert` goes on each row, since its header shares their `<tbody>`.
- **Deviations:** none from the business rules. In the Colima console the groups still start open and the filter
  still does not open a closed group (BR-7 keeps its behavior), so the filter part of AC-4 applies to docker-ce only.
- **Acceptance criteria:**
  - AC-1: proven in Chrome on both built consoles, with the transitions paused at fixed times: closing, the group's
    height 645 → 205 → 1 px (docker-ce) and 840 → 312 → 67 px, its header (Colima), at 0, 100 and 200 ms, the
    opacity 1 → 0 and the chevron 0° → −90°, and the reverse on opening; the real-time look is the owner's run.
  - AC-2: proven: a link of a closed group cannot take the focus, and the rows compute `visibility: hidden` once
    collapsed; with the group open they take it. The DevTools tree itself was not opened.
  - AC-3: proven for the groups with the menu switch off (no transition runs); the system's reduced motion and the
    dock: pending, the owner's run (the same token).
  - AC-4: the filter proven (no transition when it opens or closes the groups); the reload and the live rows: no
    transition is declared on a first render or on a new row, not run.
  - AC-5: proven at 400 and 700 px of table width, both consoles.
  - AC-6: pending (needs a job in the dock).
  - AC-7: proven for AC-1, AC-2, AC-3 (groups) and AC-5, the Colima console built and run on Linux against docker-ce.
  - AC-8: proven: `make check` passes in both tools; the manual tests are in `docs/manual-tests.md`; the two
    translations are pending for the release.
- **Checks:** `make check` in both tools (gofmt, go vet, go build, tsc); `tests/check.sh --base origin/developer
  --i18n-pending`; the column widths of the Colima console against a build of its previous code (220, 110, 255, 121,
  313, 116, 192 px, equal).
- **Left:** stage 3, the owner's visual run of the "Compose groups" manual tests (AC-3 reduced motion, AC-6); outside
  this request, `make check` of both consoles passes although `npm audit --audit-level=high` reports 4 high
  vulnerabilities (picomatch, under vite), because the Makefile ignores the audit's exit code.
