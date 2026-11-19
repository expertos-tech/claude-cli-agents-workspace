# The company-terms list of the maintainer's machine

Status: decided 2026-11-19: option A, as today (no list, no change); kept as the reference for a later setup. No
request. Source: warning W-2 of the `import-workspace` stages (2026-11-19).

## 1. What happens today

- A work clone's hooks push its branch at each commit after a scan of what leaves: every version of the files its
  commits add, their paths, the commit messages, and the author's and committer's names and e-mails
  (`tests/caw-work.sh`, `tests/lib/terms.sh`). A match stops the push with a warning; the owner keeps the term
  (`push --accept-terms`, recorded in `<list>.accepted`, never asked again) or rewrites.
- The list is the first that exists of: `$AIWP_TERMS_FILE`; `$AIWP_WORKSPACE/custom/core-terms.txt` (default
  `$HOME/Development/ai-workspace`); `workspace/custom/core-terms.txt` of the repository.
- With none, the hook prints `SKIP terms scan: no terms list` and the push goes; `tests/check.sh` prints
  `SKIP repo-terms`. The SKIP line shows only in the output of the commit that pushed, which nobody reads in a stage.
- On the maintainer's machine of the `import-workspace` stages there was no list: the 20 commits of the branch reached
  the public repository checked by hand only. The hand check found no company term in the diff or the messages, but
  their author and committer e-mail is on the company's domain, as is most of `developer`'s history. A list with the
  company's name stops the first push on that identity.

## 2. Options

| | A: as today | B: the owner's setup | C: B, and a visible SKIP | D: refuse with no list |
| --- | --- | --- | --- | --- |
| Code change | none | none | small (`caw-work.sh`) | small |
| A term in a file or message | leaves | stopped | stopped | stopped |
| The commit e-mail | leaves | stopped once, then decided | the same | the same |
| An outside contributor | unaffected | unaffected | sees one line | cannot push |

- **B:** the owner writes the list outside the repository (one term per line: the company, its customers, its project
  names, its domains; `#` comments), mode 600, and points `AIWP_TERMS_FILE` at it in the `env` of
  `.claude/settings.local.json` (git-ignored), so every session and every clone's hook sees it.
- **C:** B, and `tests/caw-work.sh open` and `status` print one `attention:` line when no list is found, so the missing
  scan shows where the stage reads, not only in a hook's output.
- **D** is wrong for a public project: a contributor from outside has no company list.

Recommended: **B** when the owner wants it, **C** when a stage next touches `tests/caw-work.sh`.

## 3. Decisions for the owner

- **D-1, where the list lives.** (a) A file of its own, for example `~/.config/aiwp/core-terms.txt`, named by
  `AIWP_TERMS_FILE`. (b) The `custom/core-terms.txt` of the owner's installed workspace, named by `AIWP_WORKSPACE`, so
  the product's scans and this repository's share one list. Recommended: (b) when an installed workspace is in daily
  use, (a) otherwise.
- **D-2, the commit e-mail.** (a) Keep it: accept the term once (`push --accept-terms`). (b) Use the GitHub `noreply`
  address in this repository (`git config user.email`), and in each clone, from now on. What `developer` already holds
  stays: published history is never rewritten. Recommended: (b), since this repository is public.
- **D-3, the visible SKIP (option C).** Recommended: yes, with the next stage that touches `tests/caw-work.sh`.
- **D-4, who writes the list.** The owner writes the terms; the agent may propose the ones it saw in a stage, never
  writes them into a file of the repository, and never prints a matching line in a commit or a report.

## 4. Effort

- B: the owner, a few minutes; then `bash tests/check.sh --all` once to see what the whole repository matches.
- C: one change to `tests/caw-work.sh` with its scenario test, `script-engineer`, effort medium.
