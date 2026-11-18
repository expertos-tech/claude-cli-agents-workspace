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
