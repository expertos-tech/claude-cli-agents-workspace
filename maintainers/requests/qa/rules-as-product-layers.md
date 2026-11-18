# Functional request: the maintenance rules as layers over the product rules

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** at the repository root, where the project is maintained; it changes the
maintenance (`.claude/rules/`, `CLAUDE.md`, `tests/check.sh`), never the product. Source: the merge review of
`validators-warn-not-block` (2026-11-18), a WARNING on AC-7: the hard rules live in two lists, the product's
`workspace/rules/security.md` and its mirror `.claude/rules/security.md`, and nothing fails when they drift. The owner
chose the fix: the same layering the `caw-*` skills already use.

## 1. Objective

Each maintenance rule that has a product counterpart holds only what is different here. It points at the product
rule, which stays the one source, and below it says what to ignore, how the names map, and the rules of this
repository that win. A product rule that changes reaches the maintenance with no copy to update, and the suite fails
when a layer points at nothing or loses one of its sections.

## 3. Business rules

- BR-1: the six maintenance rules with a product counterpart become layers: `security.md`, `review.md`, `models.md`,
  `git.md`, `docs.md`, `scripts.md` of `.claude/rules/`, over the same-named file of `workspace/rules/`.
  `process.md` and `product.md` have no counterpart and stay as they are.
- BR-2: a layer has the shape of a `caw-*` skill layer (`CLAUDE.md` "Layout"): the first line points at the product
  rule, then `---` and the sections "Ignore from the product rule", "Mapping" and "CAW rules", which win where they
  differ. A layer never repeats a line of the product rule: what is the same is only in the product rule.
- BR-3: the content of each layer is what the maintenance rule says today that the product rule does not, so no
  maintenance rule is lost or weakened by the move. In particular `security.md` keeps this repository's hard rules
  (the push of `developer` only by `/caw-merge`, the public repository, the company-term warning with
  `push --accept-terms`) as its "CAW rules" and "Mapping", over the product's closed list.
- BR-4: what the session reads is the product rule and the layer, both, every time the layer applies, as one rule.
  A product rule scoped by `paths:` (the product's `security.md`, `scripts.md`, `docs.md`) applies here whenever its
  layer applies, whatever file is touched.
- BR-5: `CLAUDE.md` "Layout" says the layers of rules are, with the layers of skills, the cases where this session
  follows a product file as instructions; nothing else of `workspace/` is read as instructions.
- BR-6: `tests/check.sh` (the `caw-layers` check) also checks every layer of `.claude/rules/`: its first line names an
  existing `workspace/rules/` file (the same-named one), and it holds its three sections; a `.claude/rules/<name>.md`
  with a product `workspace/rules/<name>.md` that is not a layer fails, and so does a layer whose product rule is gone.

## 4. Acceptance criteria

- AC-1: Given the six rules of BR-1, then each starts with its pointer line and holds the three sections, and
  `bash tests/check.sh --base origin/developer --i18n-pending` passes.
- AC-2: Given a maintenance session at the root, when it starts, then it holds the content of each product rule of
  BR-1 and of its layer (proven by a run: a question about a rule that lives only in the product rule, such as the
  closed list of hard rules, is answered from it).
- AC-3: Given a layer whose pointer names a missing product rule, or with one of its sections removed, or a
  maintenance rule with a product counterpart and no pointer, then `caw-layers` fails, each in a scenario test.
- AC-4: Given the maintenance rules before the change, then every rule they held is in the product rule or in the
  layer after it (a table of the moved lines in the request's Execution block).
- AC-5: Given a line added to the product's hard rules, then the maintenance reads it with no change to
  `.claude/rules/security.md`.

## 7. Out of scope

- Changing what any rule says, product or maintenance: only where it lives.
- The product's own rules and how an installed workspace loads them.
- `process.md`, `product.md`, and the skill layers, which already work this way.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. The mechanism: check whether an `@` import inside `.claude/rules/*.md` loads the product file, and whether `claudeMdExcludes` (`workspace/**`) blocks it; choose the loading (Assumed decisions) and prove it on one rule | medium | It decides the shape of every layer |
| 2. The six layers (BR-1 to BR-4), each with what the maintenance rule says that the product does not | medium | Rules with a clear scope |
| 3. `caw-layers` for rules, with its scenario tests (BR-6, AC-3) | medium | A check of the suite |
| 4. `CLAUDE.md` "Layout" and `docs/maintenance.md` | low | Documentation |

The subagents of each step run with the step's effort, passed in the call.

## Assumed decisions

- Open: how the product rule reaches the session. Decided: an `@workspace/rules/<name>.md` import on the first line,
  loaded with the layer, when step 1 proves it works under `claudeMdExcludes`; otherwise the skills' form ("Read that
  file in full and follow it, with the sections below over it"), and the rule loads the product file on its first
  use. Reason: the import keeps the product rule in context with no step for the agent to forget.
- Open: the extra context of six product rules in every maintenance session (about 435 lines). Decided: accepted.
  Reason: the maintenance edits these rules, and a rule half loaded is the drift this request removes.
- Open: a product rule scoped by `paths:` loaded always here. Decided: yes (BR-4). Reason: this session edits the
  product as code of every kind, so the scope by path does not fit it.

---

## Execution — 2026-11-18, merged into developer

Done, by step:

- Step 1, the mechanism (medium): headless runs proved that an `@` import in `.claude/rules/*.md` resolves relative
  to the file, that `claudeMdExcludes` blocks one into `workspace/`, and that a file with `paths:` does not load
  through an import; so the product rule is read, not imported (the request's fallback decision).
- Step 2, the six layers (medium): `64542ef` (with step 4: `CLAUDE.md` "Layout", `docs/maintenance.md`).
- Step 3, `caw-layers` for rules (medium): `69e6386` (`tests/lib/layers.sh`, `tests/test-caw-layers.sh`).
- Step 5, added while running (high): `16529da` the session index, a SessionStart hook at the root
  (`tests/caw-session-index.py`, `.claude/session-index.md`); `cb25762` the `@` pointer line it defines.
- `b946b09`, merged by `703cbef`: the pending requests (`validators-follow-ups`, `warnings-board`,
  `preferred-language` with its plan) and this request, committed on `developer` and taken into this merge (W-2).
- Changelog: `13dfd68`.

Decisions taken while running (the owner, 2026-11-18):

- D-1: when to read each product rule is a session index built by a SessionStart hook at the root from the
  product's own index (`workspace/AGENTS.md` "Reference") with `.claude/session-index.md` over it; this lifts
  "`.claude/` at the root has no hooks" for this one hook. The product keeps its index in `AGENTS.md`, no hook there.
- D-2: `quality.md`, `frontend.md`, `infra.md`, `rules.md` and `machine-load.md` stay out of the maintenance index.
- D-3: the index is built in this branch, as step 5 (effort high).
- D-4: the layers apply the whole product rule, with the sections the maintenance never had (security "Personal
  data" and "Dependencies", the subagent brief format, review "Never praise", the script naming, `git
  --no-optional-locks`, the anchored `.gitignore`): the intent of BR-4. A section is trimmed through the layer's
  "Ignore" only when it gets in the way.
- D-5: the hook defines the pointer: a line holding only `@<path>`, in the root `CLAUDE.md` or a rule or skill of
  `.claude/`, names a file to read in full from the root when the file holding it applies; any other `@` (a package,
  a handle, a decorator, a file read as code, `workspace/` included, and the source line of the session index) is
  not one. The layers' "Read that file in full" paragraph is gone: the `@` line carries the reading.
- D-6: the company-terms scan ran with the owner's list on the whole tree; the default lookup finding no list is
  accepted (W-1).

Deviations from the request:

- Step 5 and the hook go beyond the four steps (D-1, D-3); AC-2 holds by the index at the session start plus the
  read on demand, not by the product rule's full text at the start.
- This merge also carries `b946b09`, the other pending requests (W-2).

Acceptance criteria:

- AC-1: proven: each of the six layers starts with its pointer and holds the three sections (`caw-layers`); the suite
  passes.
- AC-2: proven by headless runs: a session answered five questions that only the product rules answer (masking by
  key words, the brief lines, the anchored `.gitignore`, the reviewer's limits, the closed list of hard rules); a
  session quoted the index line of `git.md` and said `quality.md` is not in it; a session judged three `@` cases right.
- AC-3: proven: `tests/test-caw-layers.sh` (21 scenarios): a missing product rule, each section removed, no pointer
  with a counterpart, a pointer to another rule, the index layer and the hook entry.
- AC-4: proven: the table below.
- AC-5: proven: a headless run with a row added only to the product's hard rules listed it, with
  `.claude/rules/security.md` unchanged; `tests/test-caw-session-index.sh` proves the same for a row added to the
  product index.

Checks: `bash tests/check.sh --base origin/developer --i18n-pending` with the owner's terms list, rc 0 (`repo-terms`,
`caw-layers`, `caw-layers-tests`, `caw-session-index`, `caw-work` pass; 52 translations pending);
`tests/test-caw-session-index.sh` 17, `tests/test-caw-layers.sh` 21; ruff and shellcheck clean; markdownlint (the
product's pinned image and rules) on the 16 changed Markdown files: 0 issues.

Warnings of the stages, decided by the owner: W-1 no terms list in the default lookup: accepted; W-2 request files
not committed at the root: fixed (`b946b09`, merged); W-3 markdownlint not run: fixed (installed as the product's
image and run, 0 issues).

Left: nothing of this request. Follow-ups: `warnings-board.md`, `preferred-language.md`.

### AC-4: where each line of the maintenance rules went

P = the product rule `workspace/rules/<name>.md` (same text, or the same with the layer's Mapping); L-I / L-M / L-C =
the layer's "Ignore from the product rule" / "Mapping" / "CAW rules".

| Rule | Line before | Now |
| --- | --- | --- |
| security | This repository is public | L-C |
| security | Validators protect against mistakes; the owner's decision; warn once, never refuse or reopen | P "Hard rules" + L-M (validators, the owner) |
| security | Row: a secret in clear | P |
| security | Row: deleting a remote, rewriting published history (any force push, moved tag) | L-C "Hard rules here" (over P's row) |
| security | Row: `developer`/`main` moved outside `/caw-merge` | L-C (P's `projects/` row in L-I) |
| security | Row: a merge without the owner's order | L-C (over P's row) + L-M |
| security | Row: a product hard rule weakened with no plan | L-C |
| security | Row: a change nobody asked for that cannot be undone | P |
| security | Warnings: product format, gathered once, the owner decides | P "Warnings" + L-M (stage, `/caw-merge`, `/caw-draft-request`) |
| security | Never write a company term, personal path...; check.sh scan; term = warning with confirmation; secret = hard rule | L-C (adds the `push --accept-terms` command, BR-3) |
| security | Never print a matching line of the terms list | L-C |
| security | Private analyses of real use in `tmp/` or custom layer | L-C |
| security | `.env` never read or edited; settings deny the other secret files | P "Secrets" + L-M (`.claude/settings.json`) |
| security | Fixtures use `acme`, `example.com`, `billing-api` | L-C (P "Test and example data" for the rest) |
| security | Weakening a product protection needs approval and the merge review | L-C |
| security | Secrets in the product follow `workspace/rules/security.md`, code here | L-C (reworded: the file is also code here) |
| review | The same rules as the product, with this repo's hard rules | the pointer + L-M (`security.md`) |
| review | Two roles: developer during stages; tech lead at the merge | P + L-M (stages); "the suite closes each stage" L-C |
| review | Into `developer`: `origin/developer..<sha>`, effort medium | P + L-M (range); "already reviewed by the merge that brought it" L-C |
| review | Into `main`: since the last tag, widened; high | P |
| review | When the owner asks, with the owner's effort | P (further round) + L-C (effort) |
| review | One reviewer per merge; split; a script's difference only | P |
| review | Clean context; brief: range, requests of `qa/`, owner's words, what the suite proved, authorizations | P + L-M (`maintainers/requests/qa/`, the suite) |
| review | Brief: changelog sections of the range | L-C |
| review | Q1 with Execution blocks and changelogs at every merge | P (Q1) + L-C (at every merge) |
| review | Q2, Q3 (protection: hook, deny rule, gate, file mode) | P + L-M |
| review | Check findings against authorizations; report defects with path:line; hotfix rule | P |
| review | The return review (focused, light, approach change, third round) | P |
| review | BLOCKER list | P |
| review | A security BLOCKER needs a second clean-context review | L-C |
| review | WARNING: never blocks; at `developer` listed once, fix / `ready` request / accept; at the release per warning | P + L-C + L-M (request path) |
| review | A finding is not accepted only because it came | P |
| review | Report format | P |
| models | Every subagent call states model and effort; inheriting is a mistake | L-C |
| models | The three models, full ids, aliases; Fable only by name | P (hook parts in L-I) |
| models | Effort high for hooks, installer, security, risky; else the stage's | L-C |
| models | Merge reviews by base; nothing above high | P |
| models | Table: requirements-analyst, reviewer, return review, verifier, web-researcher | P + L-M (gaps of a plan or request) |
| models | Table: script-engineer (opus, high/medium), translations row | L-C |
| models | Table: docs-writer for docs in English | P + L-M |
| models | Default no subagent; when to delegate; at most 4 | P "When to delegate" |
| models | Brief contents and return format, 30 lines | P "Brief", "Return format" (`VERIFICATION:` in L-I) |
| models | Subagents never commit or push | P |
| git | One logical change per commit | P |
| git | Stage and commit by path; never `add -A` blindly | P |
| git | Both paths of a move in the same commit | L-C |
| git | Paths written out, never in a shell variable | P |
| git | Message format; agent marker; template | P |
| git | No Co-Authored-By and no generated-with line, commits or PRs | P (co-author) + L-C (generated-with, PRs) |
| git | Types (with `style`) and scopes | P + L-C (`style`, the scope list) |
| git | `developer` default; `main` only by `/caw-merge --main`; maintenance alone never released | L-C |
| git | Work clone by `caw-work.sh open`; hooks push after the terms scan; refuse developer/main/tag/force; never by hand or `--no-verify` | P "Authorization" + L-M + L-C (what the hooks refuse) |
| git | `/caw-merge` pushes `developer`, the one prompt; other pushes only on request | L-C |
| git | Never rewrite published history | L-C |
| git | Tags only through `/caw-merge --main` | L-C |
| git | Never change git config unless asked | P |
| git | Work branch `<type>/<kebab>`; release clone `fix/release-vX-Y-Z` | P "Work area" |
| docs | English, direct, no generic intro, one role per page | P "Placement and language", "Writing" |
| docs | Docs in the same commit as what they describe | P |
| docs | Translations: which files, the language links line, once per release, line 1 hash, strict suite, links | L-C (P's same-commit line in L-I) |
| docs | Root `docs/` documents the project; root README short | L-C |
| docs | `maintainers/` is public | L-C |
| docs | Decision records follow the product's | P "Decision records" + L-M |
| scripts | Style of `workspace/scripts/`: shebang, `set -euo`, args validated, no hard-coded path, `git -C` | P "Writing a script" |
| scripts | `-uo` with explicit checks, `--help` contents, exit codes 0/1/2 | L-C |
| scripts | Portable forms for macOS | L-C |
| scripts | Python `python3 -I`, stdlib first, docstrings | L-C |
| scripts | Scenario tests in `workspace/scripts/tests/`, suite listed in `check-workspace.sh` | P + L-M |
| scripts | A script in `tests/` exercised by running it; `bash -n` and shellcheck by hand | L-C |
| scripts | Lint and format through the product's containers; ruff | L-C |
| scripts | 3 minutes in the background; never edit a running script | P "Running" |
| scripts | Temporary files to the scratchpad or `tmp/` | P + L-M |
