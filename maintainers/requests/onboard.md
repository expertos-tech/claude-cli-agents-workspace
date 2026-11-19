# Functional request: `/onboard`, the first-run configuration of the custom layer

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`.
Prerequisite: the `rules` request delivered (`custom/my-rules/` replaces `custom/rules/`, `custom/rules-config.json`,
`/rules`), because this skill writes its files there. Fits **round 2** of `maintainers/requests/README.md`, beside
`fork-my-rules` and `tools-hub`; it does not touch what `import-workspace` and those two change except the session start
hooks, so merge it after `tools-hub` if both add a SessionStart line. Design: `maintainers/plans/distribution.md`
section 12 "Later" (first-run onboarding), which kept it out of 0.1.0 and asked for its own request.

## 1. Objective

A person who just installed the workspace gets a custom layer with only a skeleton (`README.md`, `core-terms.txt`,
`.gitignore`). Today nothing tells them what the layer needs, so the company name, the cloud and tenant, the logos and
the visual identity are asked again in every request that needs them. This request delivers what the owner asked for
the first start ("on the first start, the workspace asks to create the company files: logo, visual identity and the
rest"): the session start detects an incomplete custom layer and tells the session to run `/onboard`, a core skill that
asks once and writes the answers into `custom/`.

## 3. Business rules

- BR-1: detection only at the session start. A SessionStart hook line (a new script or `setup-claude.sh --quiet`)
  checks the custom layer: missing `custom/my-rules/company.md`, or the file still holds the skeleton placeholder
  marker. When incomplete, it adds one line to the session context: "The custom layer is not configured yet. Offer
  the person to run `/onboard`." A hook cannot ask anything (confirmed in the Claude Code docs during the design);
  only the skill asks.
- BR-2: the notice never blocks, never asks on its own and never repeats inside the same session. `/onboard --skip`
  writes a marker in `custom/` (for example a line in `custom/README.md` or `custom/.onboard`) that turns the notice off
  for that workspace; the person can run `/onboard` later at any time.
- BR-3: `/onboard` asks, in one round where possible (`AskUserQuestion` for choices, free text for the rest), and
  writes:

  | Item | How it asks | Where it writes |
  | --- | --- | --- |
  | Company name and its spelling | text | `custom/my-rules/company.md` |
  | Cloud and tenant | options (Azure, AWS, GCP, none) and text | `custom/my-rules/cloud.md` |
  | Logos | file paths or URLs; never redraws, recolors or crops (`rules/frontend.md` "Identity") | the brand folder of the custom layer (decision 2) |
  | Visual identity | colors and fonts typed, or read from a site or repository the person names, with the contrast measured | `custom/my-rules/identity.md` |
  | Git remotes | organization and URL pattern | `custom/my-rules/company.md` |
  | Company terms | company, products, projects | `custom/core-terms.txt` (one extended regular expression per line) |

  Every item can be left empty; an empty item is not invented later (`rules/rules.md` "Custom layer": "No `custom/`:
  what it would name is asked in intake, never invented").
- BR-4: the written files follow the format of the core rules and of the template referenced by
  `templates/request.md` section 9 (`identity.md` is the default visual identity of requests).
- BR-5: run again on a configured layer, the skill shows what exists and changes only what the person asks; it never
  overwrites a file without showing the difference.
- BR-6: at the end: `setup-claude.sh` rebuilds `.claude/`, one commit in `custom/` in the repository's commit
  pattern, never a push (push only on request). It says that open sessions pick the new rules up only when reopened.
- BR-7: secrets never go in: a tenant id is not a secret, but a key, a token or a password typed by the person is
  refused with the reason, and nothing of it is written.
- BR-8: `/onboard` is a core skill but not part of the mandatory core: `custom/rules-config.json` can exclude it, and
  then the notice of BR-1 is not shown either.
- BR-9: `aiwp new` ends by saying that the first session will offer `/onboard`; the README "Quick start" and
  `docs/usage.md` say the same, with translations in `i18n/pt-BR` and `i18n/es` in the same commit.

## 4. Acceptance criteria

- AC-1: Given a new workspace whose custom layer has only the skeleton, when a session opens, then its context holds
  the one-line notice and nothing else is asked or written.
- AC-2: Given `/onboard` answered with a company name, Azure with a tenant, one logo path and two colors, then
  `company.md`, `cloud.md` and `identity.md` exist in `custom/my-rules/`, the logo is copied unchanged, the terms are in
  `core-terms.txt`, `.claude/` is rebuilt and there is exactly one new commit in `custom/`, not pushed.
- AC-3: Given a configured layer, when a session opens, then there is no notice.
- AC-4: Given `/onboard --skip`, when the next session opens, then there is no notice.
- AC-5: Given a token typed as the tenant, then the skill refuses it and no file of `custom/` contains it.
- AC-6: Given `"exclude": ["onboard"]` in `custom/rules-config.json`, then the skill does not show and the notice is
  not given.
- AC-7: The detection script has a suite (complete, skeleton, placeholder left, skip marker, excluded, no `custom/`).

## 7. Out of scope

- Configuring projects (that is `/normalize-projects`) or importing the work of an older workspace (`/import-workspace`).
- Creating the custom repository or its remote (that is `aiwp new --custom <url>`).
- Any question asked by a hook.

## Decisions for the owner

1. **How insistent the notice is.** Options: every session until configured or skipped (recommended: one line, the
   same pattern as the new-version notice); or only once, right after `aiwp new`.
2. **Where logos live.** `custom/brand/<brand>/` (the folder of the older custom layer, recommended: logos are files,
   not rules) or `custom/my-rules/brand/`.
3. **Reading an identity from a site.** Allow the skill to fetch a site or repository the person names to extract
   colors and fonts (recommended, with the person's yes before fetching), or only typed values.
4. **Skeleton marker.** Should `aiwp new` also write a `company.md` with placeholders into the skeleton (so detection
   is "placeholder left"), or detect by the missing file only (recommended: missing file, simpler).

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Detection at the session start, the skip marker, the exclusion, with the suite | medium | A small hook line that must never block a session |
| 2. `/onboard` skill: questions, writing, refusal of secrets, commit in `custom/` | medium | A conversation over files with a clear format |
| 3. `aiwp new` message, README, guide and translations | low | Text only |

The agents of each stage run with the stage's effort, passed in the call.
