# git.md

## Repos

- Repos: `custom/`, each folder of `projects/` that holds a `.git` at any depth, and the clones of `tmp/work/`. A commit belongs to one repo. The workspace root is an installation, not a repo: the core has no `.git`, and `guard-bash` refuses a `git init` or `git clone` that would make one in it.
- Run git as `git -C <repo>`, or through `bash scripts/aiwp-cmds.sh run <work>/<clone> -- <command>`. Do not `cd` into a repo in a compound command: the cwd stays there.
- Inspecting a repo that must stay unchanged: `git --no-optional-locks -C <repo>`, because a plain `git status` writes to its `.git`.

## Authorization

- A clone of `tmp/work/` (`AGENTS.md` "Where work happens"): anything, with no question: commit, amend, rebase, reset, branch. Each commit, rewrite or merge is pushed by the clone's own hooks, after a secret scan of the commits that leave; never push it by hand, and never with `--no-verify`.
- `projects/`: read only (`status`, `log`, `diff`, `fetch`...). The `guard-bash` hook refuses any other git command there. It changes only by `bash scripts/aiwp-cmds.sh gate`, `release`, `hotfix`, `hotfix-tag`, `hotfix-down` and `apply` (below), and by the steps of `/normalize-projects`: `developer`, `checkpoint` and `bring` (`bash scripts/aiwp-gate.sh --help`). The core is no repo and changes only by `aiwp update`, run by the person in a terminal.
- The custom layer (`custom/`): commit and push the files the session wrote there (requests, lessons, the project index), by path. A POC is worked on in a clone of `custom/`, like a project.
- A new remote and pushing a tag: only when the human asks. Each request covers that operation only. The tags the workspace pushes: the release tag `vX.Y.Z` of `/merge --main` (`bash scripts/aiwp-cmds.sh release <repo> --tag vX.Y.Z`, annotated, on the released `main`), the patch tag of `/merge --hotfix` (`bash scripts/aiwp-cmds.sh hotfix-tag <repo> vX.Y.Z`, the same way), and the checkpoint tags of `/normalize-projects` (`ai-workspace-migration/<yyyy-mm-dd>/developer` and `.../main`, annotated, on the heads before any change), by `bash scripts/aiwp-cmds.sh checkpoint <repo>` after the human confirms; they are never moved or deleted.
- Never change git config (user, hooks, remotes) unless asked.
- Verifying a push block on a remote: read the effective permissions of each branch the block covers. Never test it with a real push.

## Work area

- One work folder per request: `tmp/work/<yyyy-mm-dd>-<kebab-slug>/`, never `tmp/` itself. Open a clone of each repo the request touches: `bash scripts/aiwp-cmds.sh open <work> <repo>... [--branch <type>/<slug>]` (`<repo>` relative to `projects/`, or `custom` for a POC). Say the clone's path to the human and work only there.
- Base branch: `developer` where the repo has it, else `main`. `projects/<repo>` stays checked out on its base and is never edited.
- Branch name: `<type>/<kebab-description>`, ASCII, lowercase, with the types of "Commits"; it must not exist on the remote yet.
- The clone has the repo's local `.env` files (copied by `open`); install its dependencies there.
- `bash scripts/aiwp-cmds.sh status` lists the clones, what is not pushed and what is not committed; `close <work>` deletes a work folder once everything in it is merged and on the remote.
- A hotfix (`/merge --hotfix`) works on `fix/<slug>`, in `tmp/work/<yyyy-mm-dd>-hotfix-<slug>/`, opened with `--from-main`: from the remote `main`, which is its base. Its conflict with `developer`, when there is one, on `fix/<slug>-developer`, from `developer`.
- A release (`/merge --main`) works on `fix/release-vX-Y-Z`, in `tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/`: the full check and the final review of `developer`, its fixes and the dated CHANGELOG.
- A normalization (`/normalize-projects`) works on `feat/ai-workspace-migration` and goes through the gate like any work, after the human approved its plan and tested the branch.

## Gate

The base of a project receives only what the gate checked: `/merge [<work>/<clone>]` (`rules/skills/merge/SKILL.md`). Before phase 1, `/merge` merges the base into the branch and writes the CHANGELOG section of what enters (`rules/docs.md` "CHANGELOG.md").

1. Phase 1, `bash scripts/aiwp-cmds.sh gate <work>/<clone> --test "<full test command>"` (`--docs-only` when only documentation changed): the base updated from the remote and merged into the branch, the full tests, `validate.sh` with every check, env files and secrets in the commits, and the audit of what leaves the base.
2. The review against the request (`rules/review.md`), then the human's answers when the gate found something the request does not explain.
3. Phase 2, `bash scripts/aiwp-cmds.sh gate --merge <work>/<clone> <sha>`: only the sha phase 1 checked, only if the base did not move; fast-forward, push of the base, the work branch deleted from the remote.

- The normalization branch (`feat/ai-workspace-migration`) is judged on what it adds: line 1 of `README.md` must be the marker of the workspace version, `validate.sh` runs its lint checks on the changed files only, and the secret check is the scan of the commits the branch adds (a new secret or env file fails; one already in the base does not, and is reported by `/normalize-projects`). It applies only to a project that needs it (no marker, or out of date; a `-x-y-z` suffix names a pending migration), and the branch may add or change only documentation, images, `.gitignore` and the sample `.env` (deletions allowed). `--untested` replaces `--test` only when the human chose to go on untested, and `guard-bash` asks before it. The branch stays on the remote after phase 2.
- Never merge with a BLOCKER open or a failing check.
- `main` moves only by `/merge --main <project>`, on the human's explicit request: a release clone with the full check, the final review (`rules/review.md`, since the last tag) and its fixes, the CHANGELOG dated, the gate into `developer`, then `bash scripts/aiwp-cmds.sh release <repo> --tag vX.Y.Z` (`developer` into `main` by fast-forward, and the tag).
- A hotfix (`/merge --hotfix <project> <description>`, on the human's request): a clone from `main`, only what the error needs, phase 1 against `main` and a review of the fix (`rules/review.md`), the human's OK, then `bash scripts/aiwp-cmds.sh hotfix <work>/<clone> <sha>` (`main` by fast-forward), `hotfix-tag <repo> vX.Y.Z` when the human says to publish, and `hotfix-down <repo>`: `main` merged into `developer` (a merge commit; a conflict goes through a `fix/<slug>-developer` clone and the gate).
- Blocked repo: while the remote `main` holds a commit the remote `developer` does not, the gate refuses every merge into that `developer` (except a branch that holds that `main`, which clears it) and `release` refuses; computed from git at each run, so it survives a cancel or a crash, and clears when `developer` holds `main`.
- Terraform changes the cloud only by `bash scripts/aiwp-cmds.sh apply <repo> <module>` (plan from `main`), then `... --apply <plan>` after the human confirms that plan; both on the human's explicit request.

## Waves

A wave is one step of a plan in steps ("Steps and effort" of a request); a request with one step or none is one wave, closed when it ends. A question or read-only work opens none, and neither does `/draft-request`: its own commit and push are its checkpoint.

- A part never goes through the gate on its own: the merge happens only when the human types `/merge` (the gate refuses phase 2 otherwise).
- End of a task: the tests of what changed pass; publish the task's Docker copy (`bash scripts/aiwp-cmds.sh up <work>/<clone>`; a project with no compose stack: nothing to publish); the closing board gives the copy's addresses, what to test (one item per acceptance criterion) and the two ways out. `/pilot` decides who runs the detailed check of the copy (`rules/quality.md` "Verification mode").
- A base that publishes to production (a pipeline of the repo deploys from it, or its docs say so): the gate asks the human before phase 2.

Closing a wave, in this order:

1. Checkpoint of the work: commit in each clone what the session changed ("Commits"). The clone pushes it; `bash scripts/aiwp-cmds.sh status` shows `not-pushed=0`. A push that fails goes to the board; never force it.
2. Resume point. Work left in the plan: append to the request, after a `---`, `## Stopped — <yyyy-mm-dd>`: where the work stopped (the work folder, the clone, its branch and the sha of step 1), the decisions taken, the pending items, and the next steps with their effort ("Steps and effort"). The request stays pending in `custom/requests/`; one typed in the conversation is first written there as `<yyyy-mm-dd>-<kebab-slug>.md` (never overwriting: `-2`, `-3`), with a "Requested" section. Nothing left: nothing appended; `/merge` records the delivery ("Requests").
3. Checkpoint of `custom/`: commit by path only this session's files there (both paths of a move), then push. Other sessions' files stay out.
4. Closing board, the last thing of the reply: it is the delivery report. Its labels stay as below; the values are in the language of the conversation. Then stop: the next wave starts in a new session, from the request.

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WAVE CLOSED: <step>
Done:       <what changed; repo, branch and sha pushed>
Verified:   <check and result>
Copy:       <group agent_<MMDD>-<slug>: each address with its port | none: no compose stack>
Test:       <one item per acceptance criterion: what to do on the copy and what to see>
Left:       <next steps, with effort | nothing: the plan is over>
Pending:    <refused push | none>
Request:    custom/requests/<file>.md | none
➜ Approved: /merge <work>/<clone>   Not approved: bash scripts/aiwp-cmds.sh close <work> --discard
➜ You can clear the context and start a new session[: /request <file>.md]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Requests

A request goes through three folders of `custom/requests/`, one per state of its work:

| Folder | State | Moved by |
| --- | --- | --- |
| `custom/requests/` | Pending: `idea` (decisions open) or `ready` | `/draft-request`, the human, a review finding |
| `custom/requests/qa/<project>/` | On `developer`, not released; a hotfix: on `main`, marked `Merge into developer pending.` | `/merge`, after phase 2; `/merge --hotfix`, once `main` has the fix |
| `custom/requests/done/<project>/` | Released | `/merge --main <project>`; `/merge --hotfix`, once `developer` holds `main` |

- A request never moves while its waves run. `<project>` is the project the release names (`rules/rules.md` "Workspace projects"); a request that touched several projects gets one copy per project.
- At each merge into `developer`, `/merge` appends to the request, after a `---`, `## Execution — <yyyy-mm-dd>, merged into developer at <sha>`: what was done by step with the commits, the decisions taken while running, the deviations from the request, the status of each acceptance criterion (proven: how; pending: what is missing; failed: why), the checks, and what is left. A request with no file gets one in `qa/<project>/` with a "Requested" section that sums up what the human asked.
- `/merge --main` validates everything in `qa/<project>/` against what was done, and adds `Released in <project> vX.Y.Z` to each file it moves to `done/<project>/`.
- There is no backlog: an idea is a pending request in state `idea`, in the adjustment size of `templates/request.md`. A RECOMMENDED finding of a review becomes a `ready` request.
- Commit and push of `custom/` by path, as in "Authorization".

## Commits

- One logical change per commit. Never mix a refactor with a feature, or unrelated files.
- Stage by path, then commit by the same paths: `git add -- <paths>`, then `git commit -F <file> -- <paths>`; a commit by path alone fails for a file git does not track yet. Never `git add -A` or `git add .` without reading what it adds.
- Write the paths out in the command, never in a shell variable: the session's shell may be zsh, which passes an unquoted variable as one word.
- Never stage a secret, `.env`, a credential or personal data. A clone's pre-push hook refuses commits that add `.env` or `local.settings.json` and commits gitleaks finds a secret in, so they never leave the machine; in `custom/`, the `guard-bash` hook refuses such a commit.
- Ignoring a folder at the repo root: anchor the pattern (`/reports/`). An unanchored one hides same-named folders elsewhere.
- Message: Conventional Commits, English, imperative and specific title of at most 72 characters, no final period. A body with at least one bullet: what changed and why.
- A commit made by an agent ends its body with the paragraph `[#automatic-agent-commit]`. No co-author or tool trailer.

```text
<type>(<scope>): <imperative summary>

- <what changed and why>

[#automatic-agent-commit]
```

- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `build`, `ci`. Breaking change: `!` after the scope and a `BREAKING CHANGE:` footer.
- Workspace scopes: `ai` (`AGENTS.md`, `rules/`), `agents`, `skills`, `scripts`, `docker`, `docs`, `decisions`, `projects`, or the item name under `tools/`. Custom layer scopes: `requests`, `docs`, `rules`, `projects`, or the POC name under `custom/pocs/`. Project scopes: the module name; `docs`, `infra`, `deps`.

## Return points

- The work branch is on the remote at every commit: that is the return point of the work. Before a normalization, the checkpoint tags ("Authorization") are the return point of `developer` and `main`. Before rewriting a branch whose commits matter (a rebase that drops commits), an annotated local tag `backup/<yyyy-mm-dd>-<kebab-description>` in the clone. Never push it.
- A local Docker publication always has its checkpoint: `bash scripts/aiwp-cmds.sh up` tags the images it replaces, and `rollback` returns to them.
- Deleting a whole project, POC or tool: `AGENTS.md` "Safety".
