#!/usr/bin/env bash
# The only ways into projects/: the gate (a clone of tmp/work/ into the base), the release (developer into main), the
# Terraform apply from main, and the steps of /normalize-projects (developer, checkpoint, bring). Called through
# scripts/aiwp-cmds.sh.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/aiwp-cmds.sh gate | release | hotfix | hotfix-tag | hotfix-down | apply | developer | checkpoint | bring ...
       (this file: scripts/aiwp-gate.sh)

gate <work>/<clone> [--test "<command>" | --docs-only | --untested]
      Phase 1, checks. In the source repo (projects/<repo>, clean and on its base): fast-forward the base to the
      remote. Prints the state of the project (scripts/aiwp-project-state.sh): with no marker or out of date, an
      attention: line, never a failure. In the clone: merge the updated base into the branch and push it; run the
      full test command (--test, required unless every changed file is documentation and --docs-only is given); run
      scripts/validate.sh --path <clone>: first its secrets check alone (gitleaks and trivy's secret scanner; a
      failure refuses: a secret, or a tracked .env or local.settings.json, is a hard rule, rules/security.md), then
      every other check (--skip secrets; vuln is then the vulnerability scanner only), whose failures are warnings,
      not refusals: one "WARNING: <what> — <why> — <what the person can do>" line per failed check, printed at the
      end and written under "## Warnings" of the audit, for /merge to list; validate.sh that exits 2 or fails with
      no FAIL line (it could not run) still refuses. Refuse env files and secrets in
      base..HEAD; write the audit of what leaves the base (deleted or renamed-away files, removed or disabled tests,
      destructive SQL, infra and dependency changes, large deletions, the warnings) to tmp/work/<work>/gate-<clone>.md.
      The tests and checks must leave the tracked files unchanged. On success records the checked sha and prints the
      merge command.
      While a hotfix on main waits to be merged into developer (the remote main is not in the remote developer), the
      gate of a clone of developer refuses and says so, unless the branch holds that main: it is the merge of main
      into developer (fix/<slug>-developer), which clears the wait.
      A hotfix clone (open --from-main; base main, branch fix/<slug>) is judged against main: projects/<repo> stays
      clean on developer, main is fast-forwarded to the remote, the updated main is merged into the branch, and a
      branch that holds a commit of the remote developer that main does not have (a merge or a reset that brought
      unreleased work in) is refused; a cherry-pick of the fix passes. Same tests, validate, secrets and audit; it
      prints the hotfix command instead of the merge command.
      The normalization (/normalize-projects, branch feat/ai-workspace-migration, or
      feat/ai-workspace-migration-<x>-<y>-<z> for a later version) is judged on what the branch adds,
      because what is there today is reported, never fixed by it: the project must need it (state none or out of date;
      a -x-y-z suffix names a pending migration); line 1 of README.md must be the marker of this workspace VERSION;
      the branch may add or change only documentation, images, .gitignore and the sample .env (deletions are
      allowed); validate.sh runs only its lint
      checks, only on the files the branch changed, and their failures are warnings as above; the secret check is the
      scan of the commits the branch adds
      (their added lines: a new secret or env file still fails, one already in the base does not); --untested is
      accepted when the person chose to go on without running the branch, and the audit says so.
gate --merge <work>/<clone> <sha>
      Phase 2, merge. Only the sha phase 1 passed, still the clone's HEAD and on the remote, and only when the base did
      not move: fetches the branch from the remote into the source repo, merge --ff-only, pushes the base, deletes the
      remote work branch (a normalization branch stays on the remote, as its record), then destroys the clone's
      Docker copy groups (aiwp-cmds.sh _destroy-copies: by label, agent_ names only; a failure is reported and the
      merge stands). The review against the request
      and the human's answers happen between the two phases. Refuses a hotfix clone (its command is hotfix) and, like
      phase 1, a clone of developer while a hotfix waits to be merged down.
      The person's order, first of all: inside a Claude Code session (CLAUDECODE set) it runs only when the person
      typed /merge in this session (CLAUDE_CODE_SESSION_ID): the UserPromptSubmit hook (scripts/session-title.py)
      appends an "order" line to .history/merge-orders/<session id>, and a phase 2 that merges appends a "merged"
      line there. It needs an order newer than the last merge, not newer than phase 1, because /merge runs phase 1
      itself: the order always comes first. One /merge covers the clones of one work, each merged once (the repos of
      one request, of one release); a clone already merged under it, or a clone of another work, needs a new /merge.
      The order expires after 12 hours (MERGE_ORDER_TTL). The hook records what the person typed with /merge: a
      <work> or <work>/<clone> limits the order to that work; --main or --hotfix <project> to the repos of
      projects/<project> (the repo itself or one inside it); an argument that names neither is refused; no argument:
      the clone of the session, any work. Refused with no session id or no such order. Outside Claude Code (the person in a terminal) it runs as above.
release <repo> [--pr-if-refused] [--tag vX.Y.Z]
      developer -> main of projects/<repo>: pushes the developer commit to main of the remote (a fast-forward), then
      moves the local main ref (the checkout stays on developer). A remote that refuses the push (a protected main)
      leaves main unchanged and fails; with --pr-if-refused it opens a pull request developer -> main instead (gh)
      and exits 0. --tag: after main moved, an annotated tag vX.Y.Z on it, then pushed alone (no remote: local
      only); a tag of that name on another commit, here or on the remote, fails before main moves (a tag is never
      moved), on the same commit it is kept; a pull request opened instead leaves it for after the merge. Only on
      the human's request. Refused while a hotfix on main waits to be merged into developer.
hotfix <work>/<clone> <sha> [--pr-if-refused]
      The fix of a hotfix clone into main (production), after its gate, the review and the human's OK. The same guards
      as gate --merge: only the sha the gate checked, still the clone's HEAD, clean and on the remote fix branch, and
      only when main did not move. projects/<repo> stays clean on developer. Pushes the sha to main of the remote (a
      fast-forward), then moves the local main ref, deletes the remote fix branch and prints the next steps. No tag.
      A remote that refuses (a protected main) leaves main unchanged and fails; with --pr-if-refused it opens a pull
      request fix/<slug> -> main (gh) and exits 0: the tag waits for its merge (a known limit). Only on the human's
      request.
hotfix-tag <repo> vX.Y.Z
      The release tag of a hotfix (the patch version), when the human says publish: an annotated tag on the head of
      main (fast-forwarded to the remote), pushed alone (no remote: local only). Only while main waits to be merged
      into developer; else refused (a release is tagged by release --tag). The tag rules of release --tag: a tag on
      another commit, here or on the remote, fails and is never moved; on the same commit it is kept; a lightweight
      local tag of that name is refused.
hotfix-down <repo>
      Merges main into developer of projects/<repo> (clean, on developer; both fast-forwarded to the remote) after a
      hotfix: main already in developer, nothing to do. Builds the merge with git merge-tree --write-tree (git 2.38 or
      later) without touching the checkout; on a conflict nothing changes, it lists the files and exits 1 (resolve it
      in a clone of developer on fix/<slug>-developer, merging origin/main there, through /merge). Clean: a standard
      merge commit "Merge branch 'main' into developer" (never a rebase), pushed to developer (a fast-forward), then
      the checkout fast-forwards to it; no tests run, the fix was tested before main. A refused push changes nothing.
      No remote: local only, said. Only on the human's request.
developer <repo> [--create]
      Brings projects/<repo> to developer, for /normalize-projects: needs a remote (none: fails, the person creates
      the repository first) and a clean checkout; a checkout on another branch is switched only when that branch has
      nothing the remote lacks. developer not on the remote: fails, unless --create, which pushes the local developer,
      else main of the remote, as developer. Only after the person confirms.
checkpoint <repo> [--date <yyyy-mm-dd>]
      The return point of /normalize-projects, before any change: on projects/<repo> (clean, on developer, both bases
      updated from the remote), annotated tags ai-workspace-migration/<date>/developer and .../main on their heads,
      then pushed to the remote. A tag that exists on another commit, here or on the remote, is never moved: it
      fails. Only after the person confirms.
bring <git-url | folder> <path relative to projects/>
      For /normalize-projects --from: clones a project into projects/<path>. A folder (outside the workspace) keeps
      every local branch and tag, its origin becomes the folder's own origin remote (none: no remote, reported), and
      what a clone cannot carry is reported: uncommitted files (names only), stashes, local commits that remote lacks (per branch: not on the remote, or N commit(s) the remote does not have).
      The checkout ends on developer, else main.
apply <repo> <module folder>
      Phase 1: in a temporary worktree of main (equal to the remote) under tmp/work/_apply/, terraform init and plan
      -out, prints the plan and the apply command, and records it as the latest plan of that module. Changes nothing
      in the cloud; projects/<repo> stays on developer.
apply <repo> <module folder> --apply <plan file>
      Phase 2: only the latest plan shown for that module, unchanged (sha256), from the same main commit; terraform
      apply of that plan file in a new temporary worktree of main. Only on the human's request, confirmed before it
      runs.

<repo>: a repo folder relative to projects/, at any depth, a repo inside another one included (billing/billing-api,
where billing/ may be a repo itself); a path belongs to the nearest .git above it. bring may put a project inside a
repo. A clean checkout: git status shows nothing but the repos inside it, ignored by it or not, and the commits of
the ones it tracks as gitlinks.

Terraform runs on the host when it is on PATH, else in the workspace Docker toolbox with the ARM_* and TF_VAR_*
variables of the environment (the image has no az CLI). AIWP_TERRAFORM replaces it (tests), and AIWP_GH replaces gh.
Exit: 0 ok; 1 refused or failed; 2 usage error.
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work_root="$root/tmp/work"
cmds="$root/scripts/aiwp-cmds.sh"
[ -r "$root/scripts/lib/projects.sh" ] || { echo "error: scripts/lib/projects.sh not found" >&2; exit 2; }
# shellcheck source=lib/projects.sh
. "$root/scripts/lib/projects.sh"
# The branch of /normalize-projects: the first one, or the one of a later version when that one is on the remote.
NORMALIZATION_RE='^feat/ai-workspace-migration(-[0-9]+-[0-9]+-[0-9]+)?$'
# The checks of validate.sh that judge only the files they are given; the others judge the whole tree.
LINT_CHECKS="shell,dockerfile,markdown,mermaid,python,typescript"
# The only files a normalization adds or changes: documentation, its images, .gitignore and the sample .env. Deleting
# a file (an instruction file whose content moved) is allowed and listed in the audit; code, infrastructure and
# dependencies are an ordinary request's.
NORMALIZATION_FILES_RE='(\.(md|mmd|png|jpe?g|gif|svg|webp)|(^|/)\.gitignore|(^|/)([^/]*\.)?env\.(example|sample))$'
# The person's orders to merge, one file per Claude Code session, written by the UserPromptSubmit hook
# (scripts/session-title.py, an "order" line per /merge typed) and by phase 2 (a "merged" line per merge). The session
# id names the file, so it is a plain name: the same pattern as the hook's.
MERGE_ORDERS="$root/.history/merge-orders"
SESSION_ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
REFUSED_ORDER="refused: the merge happens only when the person types /merge in this session"
# An order older than this many seconds is spent: a /merge typed hours ago, refused or declined, is no order now.
MERGE_ORDER_TTL=43200
ORDER_FILE=""
# The WARNING lines of a phase 1 (validate_warn), one per line: printed at its end and written into its audit.
WARNINGS=""

# Prints an error and exits with the given code.
die() {
  local code="$1"
  shift
  echo "error: $*" >&2
  exit "$code"
}

# Prints the physical path of a folder, or fails.
physical() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# Resolves <work>/<clone> to a clone made by aiwp-cmds.sh open, or exits 1.
clone_path() {
  local path
  path="$(physical "$work_root/${1#tmp/work/}")" || die 1 "not found: $1"
  case "$path/" in "$work_root"/*/*/) ;; *) die 1 "refused: $1 is not a clone under tmp/work/<work>/" ;; esac
  git -C "$path" config --get aiwp.source >/dev/null || die 1 "not a clone made by aiwp-cmds.sh open: $1"
  echo "$path"
}

# Resolves a repo of projects/ (relative path), or exits 1.
project_repo() {
  local src
  case "$1" in /* | *..* | '') die 2 "<repo> is a folder relative to projects/: $1" ;; esac
  src="$(physical "$root/projects/$1")" || die 1 "repo not found: projects/$1"
  [ "$(git -C "$src" rev-parse --show-toplevel 2>/dev/null)" = "$src" ] || die 1 "not the root of a git repo: projects/$1"
  echo "$src"
}

# Fails unless the checkout of a source repo has no change. A repo inside it, ignored or not, is not a change of it
# (projects_changes): any layout of projects/ passes.
require_clean() {
  local changes
  changes="$(projects_changes "$1")" || die 1 "git status failed in ${1#"$root"/}: tell the human"
  [ -z "$changes" ] || die 1 "${1#"$root"/} has changes in its checkout; nobody edits projects/: tell the human"
}

# Fails unless a repo checkout has no change and is on the given branch.
require_clean_on() {
  local repo="$1" branch="$2" current
  require_clean "$repo"
  current="$(git -C "$repo" symbolic-ref -q --short HEAD || echo detached)"
  [ "$current" = "$branch" ] || die 1 "${repo#"$root"/} is on $current, not $branch: tell the human"
}

# Brings a local branch of the source repo to its remote by fast-forward (no remote: nothing to do). A branch that is
# not checked out and is ahead of its remote branch only with commits the remote holds on other branches (a local main
# whose work developer already carries) is realigned to the remote branch: nothing is lost. A branch with commits the
# remote does not have (checked out or not) fails, saying whether it is ahead or diverged; so does a remote that lacks
# the branch.
sync_branch() {
  local repo="$1" branch="$2" ahead behind
  git -C "$repo" remote get-url origin >/dev/null 2>&1 || return 0
  timeout 120 git -C "$repo" fetch -q origin "$branch" || die 1 "could not fetch $branch of ${repo#"$root"/} from the remote"
  git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null ||
    die 1 "the fetch of $branch of ${repo#"$root"/} left no origin/$branch (a fetch refspec that skips it?): tell the human"
  if ! git -C "$repo" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    git -C "$repo" branch -q --no-track "$branch" "refs/remotes/origin/$branch" || die 1 "could not create $branch of ${repo#"$root"/} from the remote"
    return 0
  fi
  ahead="$(git -C "$repo" rev-list --count "refs/remotes/origin/$branch..refs/heads/$branch")"
  behind="$(git -C "$repo" rev-list --count "refs/heads/$branch..refs/remotes/origin/$branch")"
  [ "$ahead" != 0 ] || [ "$behind" != 0 ] || return 0
  if [ "$ahead" = 0 ]; then
    if [ "$(git -C "$repo" symbolic-ref -q --short HEAD)" = "$branch" ]; then
      git -C "$repo" merge -q --ff-only "origin/$branch" || die 1 "$branch of ${repo#"$root"/} could not fast-forward to the remote: tell the human"
    else
      git -C "$repo" fetch -q . "origin/$branch:$branch" || die 1 "$branch of ${repo#"$root"/} could not fast-forward to the remote: tell the human"
    fi
    return 0
  fi
  if [ "$(git -C "$repo" symbolic-ref -q --short HEAD)" = "$branch" ]; then
    [ "$behind" != 0 ] || die 1 "$branch of ${repo#"$root"/} is checked out $ahead commit(s) ahead of origin/$branch: tell the human (push them, or move them to a branch)"
  else
    # Whether its commits are on the remote is judged on the remote's live branches: a pruning fetch drops the
    # tracking refs of branches deleted there, so a stale ref never vouches for a commit.
    timeout 120 git -C "$repo" fetch -q --prune origin || die 1 "could not fetch from the remote of ${repo#"$root"/}"
    if [ -z "$(git -C "$repo" rev-list -n 1 "refs/heads/$branch" --not --remotes=origin)" ]; then
      git -C "$repo" update-ref "refs/heads/$branch" "refs/remotes/origin/$branch" "$(git -C "$repo" rev-parse "refs/heads/$branch")" ||
        die 1 "could not realign $branch of ${repo#"$root"/} to the remote"
      echo "realigned: $branch of ${repo#"$root"/} to origin/$branch (its local commits are all on the remote)"
      return 0
    fi
  fi
  if [ "$behind" = 0 ]; then
    die 1 "$branch of ${repo#"$root"/} is $ahead commit(s) ahead of the remote, with commits the remote does not have: tell the human (push them, or move them to a branch)"
  fi
  die 1 "$branch of ${repo#"$root"/} diverged from the remote ($ahead ahead, $behind behind): tell the human"
}

# The path of a source repo to show: projects/<repo>, or custom.
shown() {
  printf '%s\n' "${1#"$root"/}"
}

# Prints why a repo is blocked by a hotfix on main that developer does not hold yet, with the way out.
hotfix_reason() {
  local src="$1" rel
  rel="${src#"$root"/projects/}"
  echo "a hotfix on main of $(shown "$src") is not merged into developer yet: merge it down first (bash scripts/aiwp-cmds.sh hotfix-down $rel; when it conflicts, a fix/<slug>-developer clone of developer through /merge)"
}

# Succeeds when a hotfix waits to be merged down: the repo has main and developer and main is not an ancestor of
# developer. With a remote, the remote's branches, fetched here; with none, the local ones. Sets HOTFIX_MAIN to the main
# commit judged. A repo without main or developer never waits.
hotfix_pending() {
  local repo="$1" lines m d rc=0
  HOTFIX_MAIN=""
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    lines="$(timeout 120 git -C "$repo" ls-remote origin refs/heads/main refs/heads/developer)" ||
      die 1 "could not read the branches of the remote of $(shown "$repo")"
    m="$(printf '%s\n' "$lines" | awk '$2 == "refs/heads/main" { print $1 }')"
    d="$(printf '%s\n' "$lines" | awk '$2 == "refs/heads/developer" { print $1 }')"
    [ -n "$m" ] && [ -n "$d" ] || return 1
    timeout 120 git -C "$repo" fetch -q --no-tags origin "+refs/heads/main:refs/remotes/origin/main" \
      "+refs/heads/developer:refs/remotes/origin/developer" || die 1 "could not fetch main and developer of $(shown "$repo")"
    m="$(git -C "$repo" rev-parse refs/remotes/origin/main)"
    d="$(git -C "$repo" rev-parse refs/remotes/origin/developer)"
  else
    m="$(git -C "$repo" rev-parse -q --verify refs/heads/main)" || return 1
    d="$(git -C "$repo" rev-parse -q --verify refs/heads/developer)" || return 1
  fi
  HOTFIX_MAIN="$m"
  git -C "$repo" merge-base --is-ancestor "$m" "$d" || rc=$?
  [ "$rc" != 0 ]
}

# Succeeds when a commit of the clone holds the main commit HOTFIX_MAIN: the branch that merges main into developer.
holds_hotfix_main() {
  local clone="$1" sha="$2"
  [ -n "$HOTFIX_MAIN" ] && git -C "$clone" cat-file -e "$HOTFIX_MAIN^{commit}" 2>/dev/null &&
    git -C "$clone" merge-base --is-ancestor "$HOTFIX_MAIN" "$sha"
}

# Fails when a hotfix clone brings commits of developer that main does not have (a merge or a reset that took
# unreleased work in): every commit of base_sha..sha reachable from developer (the remote's, fetched; with no remote,
# the local one). A cherry-pick makes a new commit and passes: the review judges what it depends on.
require_no_developer_work() {
  local src="$1" clone="$2" sha="$3" base_sha="$4" dev_ref=refs/heads/developer dev bases leaked
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    timeout 120 git -C "$src" fetch -q --no-tags origin "+refs/heads/developer:refs/remotes/origin/developer" ||
      die 1 "could not fetch developer of $(shown "$src") from the remote"
    dev_ref=refs/remotes/origin/developer
  fi
  git -C "$clone" fetch -q --no-tags "$src" "$dev_ref" || die 1 "could not read developer of $(shown "$src")"
  dev="$(git -C "$clone" rev-parse FETCH_HEAD)"
  bases="$(git -C "$clone" merge-base --all "$sha" "$dev" || true)"
  [ -n "$bases" ] || return 0
  # shellcheck disable=SC2086  # bases is a list of commits, split on purpose
  leaked="$(git -C "$clone" rev-list --count $bases --not "$base_sha")"
  [ "$leaked" = 0 ] && return 0
  # shellcheck disable=SC2086
  git -C "$clone" log --oneline -n 10 $bases --not "$base_sha" >&2
  die 1 "refused: the branch holds $leaked commit(s) of developer that main does not have (above): a hotfix starts from main and takes only the fix. Rebuild it from origin/main (a cherry-pick of the fix is fine) and run the gate again"
}

# Writes the audit of base..HEAD of a clone, in Markdown, to the given file.
write_audit() {
  local clone="$1" range="$2" out="$3" f n
  {
    echo "# Gate audit: ${clone#"$work_root"/}"
    echo
    echo "- Range: \`$range\` ($(git -C "$clone" rev-list --count "$range") commits)"
    echo "- Generated at: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo
    echo "## Deleted files"
    echo
    git -C "$clone" diff --no-renames --name-only --diff-filter=D "$range" | sed 's/^/- /' | grep . || echo "none"
    echo
    echo "## Removed or disabled tests"
    echo
    git -C "$clone" diff --no-renames --name-only --diff-filter=D "$range" |
      grep -E '(^|/)(tests?|__tests__|spec)(/|$)|[._-](test|spec)\.[a-z]+$|_test\.go$|Tests?\.cs$' | sed 's/^/- deleted test file: /' || true
    git -C "$clone" diff --no-renames -U0 --no-color "$range" | awk '
      /^--- / { old = substr($0, 7); next }
      /^\+\+\+ / { file = ($0 == "+++ /dev/null") ? old : substr($0, 7); next }
      /^-[^-]/ && /(^-[[:space:]]*(it|test|describe)\(|def test_|func Test|\[Fact\]|\[Test\]|\[Theory\]|@Test)/ { removed[file]++ }
      /^\+[^+]/ && /(\.skip\(|(^|[^[:alnum:]_])x(it|describe)\(|\.only\(|@Disabled|@Ignore|\[Ignore|pytest\.mark\.skip|t\.Skip\()/ { disabled[file]++ }
      /^-[^-]/ && /(expect\(|assert|Assert\.)/ { asserts_out[file]++ }
      /^\+[^+]/ && /(expect\(|assert|Assert\.)/ { asserts_in[file]++ }
      END {
        for (f in removed) printf "- %s: %d test case(s) removed\n", f, removed[f]
        for (f in disabled) printf "- %s: %d test(s) disabled (skip, only, ignore)\n", f, disabled[f]
        for (f in asserts_out) if (asserts_out[f] > asserts_in[f] + 0) printf "- %s: %d fewer assert(s)\n", f, asserts_out[f] - asserts_in[f]
      }' | sort
    echo
    echo "## Destructive SQL and migrations"
    echo
    git -C "$clone" diff -U0 --no-color "$range" | awk '
      /^\+\+\+ / { file = substr($0, 7); next }
      /^\+[^+]/ && toupper($0) ~ /(DROP[[:space:]]+(TABLE|COLUMN|DATABASE|SCHEMA|INDEX)|TRUNCATE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE.*DROP|DROPCOLUMN|DROPTABLE)/ { print "- " file ": " substr($0, 2, 160) }'
    git -C "$clone" diff --name-only "$range" | grep -Ei '(^|/)migrations?/|\.sql$' | sed 's/^/- changed migration: /' || true
    echo
    echo "## Infrastructure"
    echo
    git -C "$clone" diff --name-status "$range" |
      grep -Ei '\.(tf|tfvars|hcl)$|(^|[/[:space:]])(docker-)?compose[^/]*\.ya?ml$|(^|[/[:space:]])Dockerfile[^/]*$|(^|[/[:space:]])(k8s|kubernetes|helm|deploy)/|\.bicep$' | sed 's/^/- /' || true
    echo
    echo "## Dependencies"
    echo
    git -C "$clone" diff --name-only "$range" |
      { grep -E '(^|/)(package\.json|go\.mod|requirements[^/]*\.txt|pyproject\.toml|Cargo\.toml|[^/]*\.csproj|Directory\.Packages\.props|pom\.xml|build\.gradle(\.kts)?)$' || true; } |
      while IFS= read -r f; do
        n="$(git -C "$clone" diff -U0 "$range" -- "$f" | grep -c '^-[^-]' || true)"
        echo "- $f: $n line(s) removed or replaced"
      done
    echo
    echo "## Sample configuration"
    echo
    git -C "$clone" diff -U0 --no-color "$range" -- '*.env.example' '*.env.sample' '*appsettings*.json' | awk '
      /^\+\+\+ / { file = substr($0, 7); next }
      /^-[^-]/ { line = substr($0, 2); if (line !~ /[=:]/) { print "- " file ": removed a line with no key (never copied here)"; next } sub(/[[:space:]]*[=:].*/, "", line); print "- " file ": removed the line of " substr(line, 1, 80) " (its value is never copied here)" }'
    echo
    echo "## Large removals (more than 200 lines in one file)"
    echo
    git -C "$clone" diff --numstat "$range" | awk '$2 != "-" && $2 > 200 { print "- " $3 ": -" $2 " +" $1 }'
  } >"$out"
}

# Prints yes when every changed file of the range is documentation.
docs_only() {
  local clone="$1" range="$2" f
  while IFS= read -r f; do
    case "$f" in *.md | *.mmd) ;; *) echo no; return ;; esac
  done < <(git -C "$clone" diff --no-renames --name-only "$range")
  echo yes
}

# Fails unless line 1 of README.md at a commit of the clone is the marker of this workspace's VERSION.
require_marker() {
  local clone="$1" sha="$2" want line
  want="<!-- AI-WORKSPACE-PROJECT $(tr -d '[:space:]' <"$root/VERSION") -->"
  line="$(git -C "$clone" show "$sha:README.md" 2>/dev/null | head -n 1 | tr -d '\r')" || true
  [ "$line" = "$want" ] || die 1 "a normalization ends with the marker on line 1 of README.md: $want"
}

# Fails when a normalization range adds or changes a file outside documentation, images, .gitignore and the sample
# .env (deletions are allowed).
require_normalization_scope() {
  local clone="$1" range="$2" off
  off="$(git -C "$clone" diff --no-renames --name-only --diff-filter=d "$range" | grep -v -E "$NORMALIZATION_FILES_RE" || true)"
  [ -z "$off" ] || die 1 "a normalization changes only documentation, images, .gitignore and the sample .env (it rewrites no code, infrastructure or dependency); move these to an ordinary request: $(echo "$off" | tr '\n' ' ')"
}

# Fails unless the source repo needs the normalization its branch name claims: the state of projects/<repo> (its
# developer is the base just updated) is none or outdated, and a -x-y-z suffix names a pending migration.
require_normalization_state() {
  local src="$1" branch="$2" rel line kind state pending suffix
  case "$src/" in "$root/projects/"*) rel="${src#"$root"/projects/}" ;; *) die 1 "$branch is the branch of /normalize-projects, for a project of projects/ only" ;; esac
  line="$(bash "$root/scripts/aiwp-project-state.sh" --porcelain -- "$rel" 2>/dev/null | head -n 1)" || true
  IFS=$'\t' read -r kind _ _ state _ _ pending _ <<<"$line"
  [ "$kind" = project ] || die 1 "the state of projects/$rel cannot be read: no normalization gate without it"
  case "$state" in
    none | outdated) ;;
    *) die 1 "$branch is the branch of /normalize-projects, and projects/$rel needs no normalization (state $state): use another branch" ;;
  esac
  suffix="${branch#feat/ai-workspace-migration}"
  if [ -n "$suffix" ]; then
    suffix="${suffix#-}"
    suffix="${suffix//-/.}"
    case ",$pending," in *",$suffix,"*) ;; *) die 1 "$branch names no pending migration of projects/$rel (pending: $pending)" ;; esac
  fi
}

# Writes to file $3 the files the range changes that exist at the sha, relative to the workspace root.
changed_files() {
  local clone="$1" range="$2" out="$3" f
  : >"$out"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$clone/$f" ] && printf '%s\n' "${clone#"$root"/}/$f" >>"$out"
  done < <(git -C "$clone" diff --no-renames --name-only --diff-filter=d "$range")
}

# Prints the WARNING line (rules/security.md "Warnings") of a check of scripts/validate.sh that failed on the clone
# (workspace-relative path $2): not a hard rule, so phase 1 goes on and the person decides at /merge.
check_warning() {
  local check="$1" rel="$2" why fix
  fix="read its output above (bash scripts/validate.sh --path $rel --only $check --verbose); fix it in the clone and run the gate again, or merge it as it is"
  case "$check" in
    vuln) why="trivy found a HIGH or CRITICAL dependency vulnerability (its secret scanner runs in secrets, a hard rule)" ;;
    iac) why="trivy found a HIGH or CRITICAL misconfiguration in Terraform, Dockerfile or Kubernetes files" ;;
    terraform) why="a Terraform module fails fmt, init, validate or tflint" ;;
    coverage) why="a module is under 85% of lines or branches, or its tests fail under coverage" ;;
    shell | dockerfile | markdown | mermaid | python | typescript) why="lint or format findings enter the base with the branch" ;;
    *) why="its findings enter the base with the branch" ;;
  esac
  printf 'WARNING: the %s check of validate.sh failed on %s — %s — %s\n' "$check" "$rel" "$why" "$fix"
}

# Runs scripts/validate.sh with the arguments after $1 (the clone, workspace-relative), its output shown as it goes, and
# adds to WARNINGS one WARNING line per check that failed (its FAIL line): a failed check that is not a hard rule never
# refuses. validate.sh exiting 2, or failing with no FAIL line, judged nothing: that refuses.
validate_warn() {
  local rel="$1" log rc=0 failed c
  shift
  log="$(mktemp)" || die 1 "could not create a temporary file for the output of validate"
  bash "$root/scripts/validate.sh" "$@" 2>&1 | tee "$log" || rc=$?
  failed="$(sed -n 's/^FAIL \([a-z][a-z]*\)$/\1/p' "$log")"
  rm -f "$log"
  [ "$rc" != 0 ] || return 0
  [ "$rc" = 1 ] && [ -n "$failed" ] || die 1 "validate could not run its checks (exit $rc, above): fix that and run the gate again"
  for c in $failed; do
    [ "$c" != secrets ] || die 1 "the secrets check failed (above): a secret, or a tracked .env or local.settings.json, never enters the base"
    WARNINGS="$WARNINGS$(check_warning "$c" "$rel")"$'\n'
    echo "not refused: $c is not a hard rule (rules/security.md); its WARNING is in the summary below and in the audit"
  done
}

# gate phase 1: checks and audit.
cmd_gate_check() {
  local given="$1" test_cmd="$2" docs_flag="$3" untested="$4" clone src base branch work name sha range report record
  local base_sha normalization=0 files hotfix=0 blocked=0
  clone="$(clone_path "$given")"
  src="$(git -C "$clone" config --get aiwp.source)"
  base="$(git -C "$clone" config --get aiwp.base)"
  branch="$(git -C "$clone" config --get aiwp.branch)"
  work="$(basename "$(dirname "$clone")")"
  name="$(basename "$clone")"
  [[ "$branch" =~ $NORMALIZATION_RE ]] && normalization=1
  [ "$(git -C "$clone" config --get aiwp.hotfix || true)" != 1 ] || hotfix=1
  [ "$untested" = 0 ] || [ "$normalization" = 1 ] || die 2 "--untested is only for a normalization (feat/ai-workspace-migration)"
  [ -z "$(git -C "$clone" status --porcelain)" ] || die 1 "the clone has changes not committed: commit them first"
  [ "$(git -C "$clone" symbolic-ref -q --short HEAD)" = "$branch" ] || die 1 "the clone is not on $branch"
  if [ "$hotfix" = 1 ]; then
    # A hotfix clone is judged against main; projects/<repo> stays on developer and main is only a ref there.
    [ "$base" = main ] && [[ "$branch" =~ ^fix/ ]] || die 1 "a hotfix clone has the base main and a fix/ branch: open it again with open --from-main"
    require_clean_on "$src" developer
    echo "== 1/6 base: main of $(shown "$src") (hotfix: the checkout stays on developer)"
    sync_branch "$src" main
  else
    require_clean_on "$src" "$base"
    echo "== 1/6 base: $base of $(shown "$src")"
    sync_branch "$src" "$base"
    # While a hotfix on main waits to be merged down, developer takes only the branch that merges main into it.
    if [ "$base" = developer ] && hotfix_pending "$src"; then
      if holds_hotfix_main "$clone" HEAD; then blocked=2; else blocked=1; fi
    fi
  fi
  case "$src/" in "$root/projects/"*) [ "$normalization" = 1 ] || bash "$cmds" _state-note "${src#"$root"/projects/}" ;; esac
  [ "$blocked" != 1 ] || die 1 "refused: $(hotfix_reason "$src")"
  [ "$blocked" != 2 ] || echo "hotfix pending: $branch holds main ($(git -C "$clone" rev-parse --short "$HOTFIX_MAIN")), so it is the merge of main into developer that clears it"
  echo "== 2/6 merge of the updated base into $branch"
  # The base is the sha of projects/<repo>, read here; no ref of the clone, which the session can move, stands for it.
  base_sha="$(git -C "$src" rev-parse "refs/heads/$base")"
  git -C "$clone" cat-file -e "$base_sha^{commit}" 2>/dev/null ||
    timeout 120 git -C "$clone" fetch -q origin "$base" 2>/dev/null || true
  git -C "$clone" cat-file -e "$base_sha^{commit}" 2>/dev/null || git -C "$clone" fetch -q "$src" "$base_sha"
  if ! git -C "$clone" merge -q --no-edit "$base_sha" 2>&1; then
    git -C "$clone" merge --abort 2>/dev/null || true
    die 1 "conflict merging $base: resolve it in the clone (git merge origin/$base), commit, and run the gate again"
  fi
  bash "$cmds" push "$work/$name" || die 1 "the branch is not on the remote: run the gate again after the push works"
  sha="$(git -C "$clone" rev-parse HEAD)"
  range="$base_sha..$sha"
  [ "$(git -C "$clone" rev-list --count "$range")" -gt 0 ] || die 1 "$branch adds nothing to $base"
  [ "$hotfix" = 0 ] || require_no_developer_work "$src" "$clone" "$sha" "$base_sha"
  if [ "$normalization" = 1 ]; then
    echo "normalization: judged on what $branch adds"
    require_normalization_state "$src" "$branch"
    require_marker "$clone" "$sha"
    require_normalization_scope "$clone" "$range"
  fi
  echo "== 3/6 tests"
  if [ "$docs_flag" = 1 ]; then
    [ "$(docs_only "$clone" "$range")" = yes ] || die 2 "--docs-only, but the branch changes more than documentation"
    echo "SKIP tests: documentation only"
  elif [ "$untested" = 1 ]; then
    echo "SKIP tests: the person chose to go on with the normalization untested"
  else
    [ -n "$test_cmd" ] || die 2 "--test \"<full test command of the project>\" is required (its README, \"How to test\")"
    (cd "$clone" && bash -c "$test_cmd") || die 1 "the tests failed: fix in the clone and run the gate again"
  fi
  if [ "$normalization" = 1 ]; then
    echo "== 4/6 validate, the lint checks on the files the normalization changed"
    files="$work_root/$work/.gate-files-$name"
    # The list goes whatever happens next, a refusal included.
    trap 'rm -f "${files:-}"' EXIT
    changed_files "$clone" "$range" "$files"
    if [ -s "$files" ]; then
      # Lint findings are warnings, never a refusal (validate_warn).
      validate_warn "${clone#"$root"/}" --path "${clone#"$root"/}" --only "$LINT_CHECKS" --files "$files"
    else
      echo "SKIP validate: the normalization only deletes files"
    fi
    rm -f "$files"
    trap - EXIT
  else
    echo "== 4/6 validate: secrets, a hard rule, then every other check, whose failures are warnings"
    bash "$root/scripts/validate.sh" --path "${clone#"$root"/}" --only secrets ||
      die 1 "the secrets check failed (above): a secret, or a tracked .env or local.settings.json, never enters the base: remove it from the branch in the clone (rotate a key that left the machine) and run the gate again"
    validate_warn "${clone#"$root"/}" --path "${clone#"$root"/}" --skip secrets
  fi
  # What passed must be the commit that is recorded: a test or a check that rewrote a tracked file (a formatter, lint
  # --fix, a snapshot update) passed on another tree.
  [ "$(git -C "$clone" rev-parse HEAD)" = "$sha" ] && [ -z "$(git -C "$clone" status --porcelain --untracked-files=no)" ] ||
    die 1 "the tests or the checks changed tracked files of the clone: commit the change, or make them not write, and run the gate again"
  echo "== 5/6 env files and secrets of every commit entering $base"
  [ "$normalization" = 0 ] || echo "the added lines only: what the base already holds is reported by /normalize-projects, never judged here"
  bash "$cmds" _scan-range "$clone" "$sha" "$base_sha" || die 1 "env files or secrets in the commits: rewrite the branch in the clone"
  echo "== 6/6 audit"
  report="$work_root/$work/gate-$name.md"
  write_audit "$clone" "$range" "$report"
  if [ "$normalization" = 1 ]; then
    {
      echo
      echo "## Normalization"
      echo
      echo "- Judged on what the branch adds: marker checked, lint checks on the changed files, secrets in the added lines."
      if [ "$untested" = 1 ]; then echo "- Tests: not run; the person chose to go on untested."; fi
    } >>"$report"
  fi
  # The checks that failed but are not hard rules: /merge lists them in its summary, the person decides.
  {
    echo
    echo "## Warnings"
    echo
    if [ -n "$WARNINGS" ]; then printf '%s' "$WARNINGS" | sed 's/^/- /'; else echo "none"; fi
  } >>"$report"
  record="$work_root/$work/.gate-$name"
  printf '%s %s %s\n' "$sha" "$base_sha" "$(date +%s)" >"$record"
  echo
  if [ -n "$WARNINGS" ]; then
    printf '%s' "$WARNINGS"
    echo "gate: checks passed for $sha, with $(printf '%s' "$WARNINGS" | grep -c '^WARNING:') warning(s): not refused, listed in the audit under Warnings for the person to decide at /merge"
  else
    echo "gate: checks passed for $sha"
  fi
  echo "audit: ${report#"$root"/}"
  if [ "$hotfix" = 1 ]; then
    echo "next: review the fix ($range) against the error it fixes; with no BLOCKER open and the human's OK, the"
    echo "      fix goes into main (production): bash scripts/aiwp-cmds.sh hotfix $work/$name $sha"
    return 0
  fi
  echo "next: review the audit and the diff ($range) against the request; ask the human only what the request does"
  echo "      not explain; then: bash scripts/aiwp-cmds.sh gate --merge $work/$name $sha"
}

# The person's order of a merge (BR-13), checked before anything else of phase 2. Outside Claude Code (CLAUDECODE
# unset: the person in a terminal) there is nothing to check. Inside, the session (CLAUDE_CODE_SESSION_ID) must have an
# "order" line (a /merge the person typed, recorded by the UserPromptSubmit hook) newer than its last merge. Newer
# than the last merge and not than phase 1: /merge runs phase 1 itself, so its order always comes before phase 1. Each
# "merged" line after the last order binds that order to its work: one /merge takes the clones of one work in (the
# repos of a request, of a release), each once; another work, or the same clone again, needs a new /merge. The last
# order must be younger than MERGE_ORDER_TTL, and when the person typed a target with it (session-title.py: "work
# <work>", "main <project>", "hotfix <project>"), the clone must be of that work, or its repo that project or inside
# it; an argument that named neither ("text") is refused. Sets ORDER_FILE for record_merge.
require_merge_order() {
  local work="$1" name="$2" src="$3" id="${CLAUDE_CODE_SESSION_ID:-}" file verdict target
  ORDER_FILE=""
  [ -n "${CLAUDECODE:-}" ] || return 0
  [ -n "$id" ] || die 1 "$REFUSED_ORDER (no CLAUDE_CODE_SESSION_ID in this environment); never ask the person to let you run it: offer /merge"
  [[ "$id" =~ $SESSION_ID_RE ]] || die 1 "$REFUSED_ORDER (CLAUDE_CODE_SESSION_ID is not a session id)"
  file="$MERGE_ORDERS/$id"
  { [ -f "$file" ] && [ ! -L "$file" ]; } || die 1 "$REFUSED_ORDER: no /merge from this session yet; never ask the person to let you run it: offer /merge"
  verdict="$(awk -F '\t' -v work="$work" -v clone="$work/$name" -v now="$(date -u +%s)" -v ttl="$MERGE_ORDER_TTL" '
    # Seconds since 1970 of a UTC time yyyy-mm-ddThh:mm:ssZ (days from the civil date), -1 when it is not one.
    function epoch(t,  y, m, d) {
      if (t !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) return -1
      y = substr(t, 1, 4) + 0; m = substr(t, 6, 2) + 0; d = substr(t, 9, 2) + 0
      if (m <= 2) { y--; m += 12 }
      return (365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d - 719469) * 86400 \
        + substr(t, 12, 2) * 3600 + substr(t, 15, 2) * 60 + substr(t, 18, 2)
    }
    $1 == "order" { orders++; bound = ""; at = $2; kind = $3; target = $4; next }
    $1 == "merged" && orders {
      if (bound == "") { bound = $3; sub(/\/.*/, "", bound) }
      merged[$3] = orders
    }
    END {
      if (!orders) print "none"
      else if (epoch(at) < 0 || now - epoch(at) > ttl) print "expired " at
      else if (merged[clone] == orders) print "used"
      else if (kind == "text") print "text"
      else if (kind == "work" && target != work) print "target the work " target
      else {
        verdict = (bound != "" && bound != work) ? "other " bound : "ok"
        # A project typed: the shell compares physical paths (a project or projects/ may be a link).
        if ((kind == "main" || kind == "hotfix") && target != "") print "project\t" target "\t" verdict
        else print verdict
      }
    }' "$file")" || die 1 "$REFUSED_ORDER: could not read .history/merge-orders/$id"
  if [[ "$verdict" == project$'\t'* ]]; then
    IFS=$'\t' read -r _ target verdict <<<"$verdict"
    in_project "$src" "$target" || verdict="target the project $target"
  fi
  case "$verdict" in
    ok) ORDER_FILE="$file" ;;
    none) die 1 "$REFUSED_ORDER: no /merge from this session yet; never ask the person to let you run it: offer /merge" ;;
    expired\ *) die 1 "$REFUSED_ORDER: the last /merge (${verdict#expired }) is older than $((MERGE_ORDER_TTL / 3600)) hours; a merge now needs a new /merge from the person" ;;
    text) die 1 "$REFUSED_ORDER: the last /merge named neither a work nor a project; the person types /merge, /merge <work>[/<clone>], /merge --main <project> or /merge --hotfix <project>" ;;
    target\ *) die 1 "$REFUSED_ORDER: the last /merge was for ${verdict#target }, not $work/$name; this merge needs its own /merge from the person" ;;
    used) die 1 "$REFUSED_ORDER: the last /merge already merged $work/$name; another merge needs a new /merge from the person" ;;
    other\ *) die 1 "$REFUSED_ORDER: the last /merge took in the work ${verdict#other }; $work is another work and needs a new /merge from the person" ;;
    *) die 1 "$REFUSED_ORDER: could not read .history/merge-orders/$id" ;;
  esac
}

# Succeeds when a source repo (a physical path, as aiwp.source holds it) is projects/<project> or lies inside it, both
# compared physically: a project, or projects/ itself, may be a link to a folder elsewhere.
in_project() {
  local src="$1" project="$2" top
  case "/$project/" in */../* | */./* | //*) return 1 ;; esac
  top="$(physical "$root/projects/$project")" || return 1
  [ "$src" = "$top" ] || [[ "$src" == "$top"/* ]]
}

# Records that a merge used the person's order (require_merge_order), once the base moved: a "merged" line, appended in
# one write. A failure here does not undo the merge; it is said.
record_merge() {
  local clone="$1" sha="$2"
  [ -n "$ORDER_FILE" ] || return 0
  printf 'merged\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$clone" "$sha" >>"$ORDER_FILE" 2>/dev/null ||
    echo "attention: could not record this merge in ${ORDER_FILE#"$root"/}, so the /merge stays open: tell the person"
}

# gate phase 2: the merge of the checked sha. The person's order comes first (require_merge_order).
cmd_gate_merge() {
  local given="$1" want="$2" clone src base branch work name record sha base_then
  clone="$(clone_path "$given")"
  work="$(basename "$(dirname "$clone")")"
  name="$(basename "$clone")"
  src="$(git -C "$clone" config --get aiwp.source)"
  require_merge_order "$work" "$name" "$src"
  base="$(git -C "$clone" config --get aiwp.base)"
  branch="$(git -C "$clone" config --get aiwp.branch)"
  record="$work_root/$work/.gate-$name"
  [ "$(git -C "$clone" config --get aiwp.hotfix || true)" != 1 ] ||
    die 1 "$work/$name is a hotfix clone: its fix goes into main by bash scripts/aiwp-cmds.sh hotfix $work/$name <sha>, never by gate --merge"
  [ -f "$record" ] || die 1 "phase 1 did not pass for this clone: run bash scripts/aiwp-cmds.sh gate $work/$name first"
  read -r sha base_then _ <"$record"
  [ "$(git -C "$clone" rev-parse "$want" 2>/dev/null)" = "$sha" ] || die 1 "$want is not the sha phase 1 checked ($sha)"
  [ "$(git -C "$clone" rev-parse HEAD)" = "$sha" ] || die 1 "the clone moved after phase 1: run the gate again"
  [ -z "$(git -C "$clone" status --porcelain --untracked-files=no)" ] || die 1 "the clone has tracked changes after phase 1: run the gate again"
  require_clean_on "$src" "$base"
  sync_branch "$src" "$base"
  [ "$(git -C "$src" rev-parse "$base")" = "$base_then" ] || die 1 "$base moved after phase 1: run the gate again"
  if [ "$base" = developer ] && hotfix_pending "$src" && ! holds_hotfix_main "$clone" "$sha"; then
    die 1 "refused: $(hotfix_reason "$src")"
  fi
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    timeout 120 git -C "$src" fetch -q origin "$branch" || die 1 "could not fetch $branch from the remote"
    [ "$(git -C "$src" rev-parse FETCH_HEAD)" = "$sha" ] || die 1 "the remote $branch is not $sha: push it and run the gate again"
  else
    git -C "$src" rev-parse -q --verify "refs/heads/$branch" >/dev/null || die 1 "$branch not found in ${src#"$root"/}"
    [ "$(git -C "$src" rev-parse "refs/heads/$branch")" = "$sha" ] || die 1 "$branch in ${src#"$root"/} is not $sha"
  fi
  git -C "$src" merge -q --ff-only "$sha" || die 1 "$base cannot fast-forward to $sha: run the gate again"
  echo "merged: $sha into $base of ${src#"$root"/}"
  record_merge "$work/$name" "$sha"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    timeout 120 git -C "$src" push -q origin "$base" || die 1 "merged locally, but the push of $base failed: push it (git -C ${src#"$root"/} push origin $base)"
    echo "pushed: $base"
    if [[ "$branch" =~ $NORMALIZATION_RE ]]; then
      echo "kept on the remote: $branch, the record of the normalization"
    else
      timeout 120 git -C "$src" push -q origin --delete "$branch" 2>/dev/null && echo "deleted from the remote: $branch" ||
        echo "attention: $branch is still on the remote"
    fi
  else
    git -C "$src" branch -q -d "$branch" 2>/dev/null || true
  fi
  rm -f "$record"
  # The task's Docker copy served its purpose: its groups go, by label and agent_ name only. A failure is said and
  # never undoes or fails the merge.
  bash "$cmds" _destroy-copies "$work/$name" ||
    echo "attention: a Docker copy group of $work/$name was not destroyed (above); the merge stands; bash scripts/aiwp-cmds.sh close $work destroys it"
  echo "next: bash scripts/aiwp-cmds.sh close $work"
}

# Checks the release tag vX.Y.Z before anything moves: a tag of that name on another commit, here or on the remote,
# fails (a tag is never moved), and so do a lightweight local tag and two different tag objects here and there. Sets
# TAG_REMOTE to the remote's tag object when the remote already holds it on that commit.
tag_check() {
  local src="$1" tag="$2" commit="$3" lines remote_commit
  TAG_REMOTE=""
  if git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    [ "$(git -C "$src" rev-parse "refs/tags/$tag^{commit}")" = "$commit" ] ||
      die 1 "$tag exists on another commit; a tag is never moved: main is unchanged, choose another version"
    [ "$(git -C "$src" cat-file -t "refs/tags/$tag")" = tag ] ||
      die 1 "$tag exists here as a lightweight tag; a release tag is annotated and never moved: main is unchanged, tell the human"
  fi
  git -C "$src" remote get-url origin >/dev/null 2>&1 || return 0
  lines="$(timeout 120 git -C "$src" ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}")" ||
    die 1 "could not read the tags of the remote: main is unchanged"
  TAG_REMOTE="$(printf '%s\n' "$lines" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')"
  remote_commit="$(printf '%s\n' "$lines" | awk -v r="refs/tags/$tag^{}" '$2 == r { print $1 }')"
  [ -n "$remote_commit" ] || remote_commit="$TAG_REMOTE"
  [ -z "$TAG_REMOTE" ] || [ "$remote_commit" = "$commit" ] ||
    die 1 "$tag exists on the remote on another commit; a tag is never moved: main is unchanged, choose another version"
  if [ -n "$TAG_REMOTE" ] && git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    [ "$(git -C "$src" rev-parse "refs/tags/$tag")" = "$TAG_REMOTE" ] ||
      die 1 "$tag exists here and on the remote as different tags; a tag is never moved: main is unchanged, tell the human"
  fi
  return 0
}

# Creates the annotated tag on the commit, or takes the remote's when it holds it there already (never a second tag
# object of the same name), then pushes it alone (no remote: local only). Runs after tag_check, once main is there.
tag_publish() {
  local src="$1" tag="$2" commit="$3"
  if ! git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    if [ -n "$TAG_REMOTE" ]; then
      timeout 120 git -C "$src" fetch -q origin "refs/tags/$tag:refs/tags/$tag" ||
        die 1 "main was released; $tag is on the remote but could not be fetched: git -C $(shown "$src") fetch origin refs/tags/$tag:refs/tags/$tag"
    else
      git -C "$src" tag -a "$tag" -m "$tag" "$commit" || die 1 "main was released, but the tag $tag could not be created"
    fi
  fi
  echo "tagged: $tag at $(git -C "$src" rev-parse --short "refs/tags/$tag^{commit}")"
  if ! git -C "$src" remote get-url origin >/dev/null 2>&1; then
    echo "no remote: $tag is local only"
    return 0
  fi
  if [ -n "$TAG_REMOTE" ]; then
    echo "pushed: $tag (already on the remote)"
    return 0
  fi
  timeout 120 git -C "$src" push -q origin "refs/tags/$tag:refs/tags/$tag" ||
    die 1 "main was released, but the push of $tag failed: the tag is local only. Push it: git -C $(shown "$src") push origin refs/tags/$tag"
  echo "pushed: $tag"
}

# release: developer -> main. The remote's main moves first, by a push of the developer commit (a fast-forward), and
# the local main ref only after it, so a remote that refuses (a protected main) leaves both as they were. With --tag, an
# annotated tag on the released main, pushed alone; a tag on another commit, here or on the remote, fails before main
# moves, and a tag is never moved.
cmd_release() {
  local src repo="${1:-}" pr=0 tag="" tagged=0 dev_sha url
  [ $# -eq 0 ] || shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr-if-refused)
        [ "$pr" = 0 ] || die 2 "--pr-if-refused given twice"
        pr=1
        ;;
      --tag)
        [ "$tagged" = 0 ] || die 2 "--tag given twice"
        [ $# -ge 2 ] || die 2 "--tag needs a version: --tag vX.Y.Z"
        tagged=1
        tag="$2"
        shift
        ;;
      *) die 2 "unknown option: $1" ;;
    esac
    shift
  done
  [ "$tagged" = 0 ] || [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 2 "--tag must be vX.Y.Z (for example v1.2.0): $tag"
  src="$(project_repo "$repo")"
  require_clean_on "$src" developer
  git -C "$src" rev-parse -q --verify refs/heads/main >/dev/null || die 1 "${src#"$root"/} has no main"
  sync_branch "$src" developer
  sync_branch "$src" main
  git -C "$src" merge-base --is-ancestor main developer || die 1 "refused: $(hotfix_reason "$src")"
  dev_sha="$(git -C "$src" rev-parse refs/heads/developer)"
  # Checked before main moves: a tag on another commit stops the release with nothing changed.
  [ -z "$tag" ] || tag_check "$src" "$tag" "$dev_sha"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    if ! timeout 120 git -C "$src" push -q origin "$dev_sha:refs/heads/main"; then
      [ "$pr" = 1 ] || die 1 "the remote refused the push of main (a protected branch?); main is unchanged. A pull request instead: bash scripts/aiwp-cmds.sh release $repo --pr-if-refused${tag:+ --tag $tag}"
      echo "the remote refused the push of main; main is unchanged: opening a pull request developer -> main"
      url="$(cd "$src" && timeout 120 "${AIWP_GH:-gh}" pr create --base main --head developer \
        --title "Release developer into main" \
        --body "Release of developer ($(git -C "$src" rev-parse --short "$dev_sha")) into main, opened by aiwp-cmds.sh release because the remote refused the direct push of main.")" ||
        die 1 "the pull request could not be opened: open it on the git server (developer -> main)"
      echo "pull request: $url"
      [ -z "$tag" ] || echo "no tag yet: $tag waits for the merge of the pull request; after it, with main equal to developer: bash scripts/aiwp-cmds.sh release $repo --tag $tag"
      return 0
    fi
  fi
  git -C "$src" fetch -q . developer:main || die 1 "main cannot fast-forward to developer"
  echo "released: main of ${src#"$root"/} at $(git -C "$src" rev-parse --short main)"
  [ -z "$tag" ] || tag_publish "$src" "$tag" "$dev_sha"
}

# hotfix: the fix of a hotfix clone into main, the sha phase 1 checked against main. The remote's main moves first, by a
# push of that sha (a fast-forward), then the local main ref; projects/<repo> stays on developer. A remote that refuses
# leaves main as it was and fails; with --pr-if-refused a pull request fix/<slug> -> main is opened instead.
cmd_hotfix() {
  local given="" want="" pr=0 clone src branch work name record sha base_then rel url
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr-if-refused)
        [ "$pr" = 0 ] || die 2 "--pr-if-refused given twice"
        pr=1
        ;;
      -*) die 2 "unknown option: $1" ;;
      *)
        if [ -z "$given" ]; then given="$1"; elif [ -z "$want" ]; then want="$1"; else die 2 "usage: hotfix <work>/<clone> <sha> [--pr-if-refused]"; fi
        ;;
    esac
    shift
  done
  [ -n "$given" ] && [ -n "$want" ] || die 2 "usage: hotfix <work>/<clone> <sha> [--pr-if-refused]"
  clone="$(clone_path "$given")"
  src="$(git -C "$clone" config --get aiwp.source)"
  branch="$(git -C "$clone" config --get aiwp.branch)"
  work="$(basename "$(dirname "$clone")")"
  name="$(basename "$clone")"
  rel="${src#"$root"/projects/}"
  [ "$(git -C "$clone" config --get aiwp.hotfix || true)" = 1 ] && [ "$(git -C "$clone" config --get aiwp.base)" = main ] ||
    die 1 "$work/$name is not a hotfix clone (open --from-main): its work goes into developer by gate --merge"
  record="$work_root/$work/.gate-$name"
  [ -f "$record" ] || die 1 "the gate did not pass for this clone: run bash scripts/aiwp-cmds.sh gate $work/$name first; main is unchanged"
  read -r sha base_then _ <"$record"
  [ "$(git -C "$clone" rev-parse "$want" 2>/dev/null)" = "$sha" ] || die 1 "$want is not the sha the gate checked ($sha); main is unchanged"
  [ "$(git -C "$clone" rev-parse HEAD)" = "$sha" ] || die 1 "the clone moved after the gate: run the gate again; main is unchanged"
  [ -z "$(git -C "$clone" status --porcelain --untracked-files=no)" ] || die 1 "the clone has tracked changes after the gate: run the gate again; main is unchanged"
  require_clean_on "$src" developer
  sync_branch "$src" main
  [ "$(git -C "$src" rev-parse refs/heads/main)" = "$base_then" ] || die 1 "main moved after the gate: run the gate again; main is unchanged"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    timeout 120 git -C "$src" fetch -q origin "$branch" || die 1 "could not fetch $branch from the remote; main is unchanged"
    [ "$(git -C "$src" rev-parse FETCH_HEAD)" = "$sha" ] || die 1 "the remote $branch is not $sha: push it and run the gate again; main is unchanged"
  else
    [ "$(git -C "$src" rev-parse -q --verify "refs/heads/$branch" || true)" = "$sha" ] || die 1 "$branch in $(shown "$src") is not $sha; main is unchanged"
  fi
  git -C "$src" merge-base --is-ancestor "$base_then" "$sha" || die 1 "main cannot fast-forward to $sha: run the gate again; main is unchanged"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    if ! timeout 120 git -C "$src" push -q origin "$sha:refs/heads/main"; then
      [ "$pr" = 1 ] || die 1 "the remote refused the push of main (a protected branch?); main is unchanged. A pull request instead: bash scripts/aiwp-cmds.sh hotfix $work/$name $sha --pr-if-refused"
      echo "the remote refused the push of main; main is unchanged: opening a pull request $branch -> main"
      url="$(cd "$src" && timeout 120 "${AIWP_GH:-gh}" pr create --base main --head "$branch" \
        --title "Hotfix $branch into main" \
        --body "Hotfix $branch ($(git -C "$src" rev-parse --short "$sha")) into main, checked by the gate against main, opened by aiwp-cmds.sh hotfix because the remote refused the direct push of main.")" ||
        die 1 "the pull request could not be opened: open it on the git server ($branch -> main)"
      echo "pull request: $url"
      echo "no tag yet: the tag waits for the merge of the pull request (a known limit: no command tags it yet; after the merge the human tags the commit of main by hand, if publishing); after the merge: bash scripts/aiwp-cmds.sh hotfix-down $rel"
      return 0
    fi
  fi
  git -C "$src" update-ref refs/heads/main "$sha" "$base_then" ||
    die 1 "main of the remote is at $sha, but the local main could not move: run git -C $(shown "$src") fetch origin main:main"
  echo "into main: $sha of $(shown "$src")"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    echo "pushed: main"
    timeout 120 git -C "$src" push -q origin --delete "$branch" 2>/dev/null && echo "deleted from the remote: $branch" ||
      echo "attention: $branch is still on the remote"
  else
    echo "no remote: main moved locally only"
    git -C "$src" branch -q -D "$branch" 2>/dev/null || true
  fi
  rm -f "$record"
  echo "next: ask the human whether to publish to production with the fix; yes: bash scripts/aiwp-cmds.sh hotfix-tag $rel vX.Y.Z"
  echo "      (the patch version); then, whatever the answer: bash scripts/aiwp-cmds.sh hotfix-down $rel"
}

# hotfix-tag: the release tag of a hotfix, on the head of main, while main waits to be merged into developer.
cmd_hotfix_tag() {
  [ $# -eq 2 ] || die 2 "usage: hotfix-tag <repo> vX.Y.Z"
  local repo="$1" tag="$2" src head
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 2 "the tag must be vX.Y.Z (for example v1.2.1): $tag"
  src="$(project_repo "$repo")"
  require_clean_on "$src" developer
  git -C "$src" rev-parse -q --verify refs/heads/developer >/dev/null || die 1 "$(shown "$src") has no developer"
  sync_branch "$src" main
  hotfix_pending "$src" ||
    die 1 "no hotfix pending in $(shown "$src"): main is already in developer. A release is tagged by bash scripts/aiwp-cmds.sh release $repo --tag $tag"
  head="$(git -C "$src" rev-parse refs/heads/main)"
  [ "$head" = "$HOTFIX_MAIN" ] || die 1 "main of the remote moved while tagging: run again"
  tag_check "$src" "$tag" "$head"
  tag_publish "$src" "$tag" "$head"
  echo "next: bash scripts/aiwp-cmds.sh hotfix-down $repo"
}

# Fails unless git has merge-tree --write-tree (2.38 or later), which builds a merge without touching the checkout.
require_merge_tree() {
  local v major minor
  v="$(git version | awk '{ print $3 }')"
  IFS=. read -r major minor _ <<<"$v"
  if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]] && { [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -ge 38 ]; }; }; then
    return 0
  fi
  die 1 "hotfix-down needs git 2.38 or later (git merge-tree --write-tree), this is git $v: update git, or merge main into developer in a fix/<slug>-developer clone through /merge"
}

# hotfix-down: main into developer by a standard merge commit, built off the checkout (git merge-tree) so a conflict
# changes nothing; pushed, then the checked-out developer fast-forwards to it. No tests: the fix was tested before main.
cmd_hotfix_down() {
  [ $# -eq 1 ] || die 2 "usage: hotfix-down <repo>"
  local repo="$1" src out rc=0 tree dev main merge
  src="$(project_repo "$repo")"
  require_clean_on "$src" developer
  if ! git -C "$src" rev-parse -q --verify refs/heads/main >/dev/null; then
    if ! git -C "$src" remote get-url origin >/dev/null 2>&1 ||
      ! timeout 120 git -C "$src" ls-remote --exit-code -q origin refs/heads/main >/dev/null 2>&1; then
      die 1 "$(shown "$src") has no main: nothing to merge down"
    fi
  fi
  sync_branch "$src" developer
  sync_branch "$src" main
  if git -C "$src" merge-base --is-ancestor refs/heads/main refs/heads/developer; then
    echo "nothing to do: main of $(shown "$src") is already in developer"
    return 0
  fi
  require_merge_tree
  dev="$(git -C "$src" rev-parse refs/heads/developer)"
  main="$(git -C "$src" rev-parse refs/heads/main)"
  out="$(git -C "$src" merge-tree --write-tree --name-only --no-messages "$dev" "$main")" || rc=$?
  case "$rc" in
    0) tree="$(printf '%s\n' "$out" | head -n 1)" ;;
    1)
      echo "conflict merging main into developer of $(shown "$src"); nothing changed. Conflicting files:" >&2
      printf '%s\n' "$out" | tail -n +2 | grep . | sed 's/^/  /' >&2
      die 1 "resolve it in a clone of developer: bash scripts/aiwp-cmds.sh open <yyyy-mm-dd>-<slug>-developer $repo --branch fix/<slug>-developer; there git fetch origin main, git merge origin/main, resolve every conflict (CHANGELOG.md: the Unreleased section of developer stays on top, the dated patch section goes below it) and adapt the fix so the bug stays fixed on developer; then take it through /merge"
      ;;
    *) die 1 "git merge-tree failed (exit $rc): nothing changed; tell the human" ;;
  esac
  merge="$(git -C "$src" commit-tree "$tree" -p "$dev" -p "$main" -m "Merge branch 'main' into developer")" ||
    die 1 "the merge commit could not be created: nothing changed; tell the human"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    timeout 120 git -C "$src" push -q origin "$merge:refs/heads/developer" ||
      die 1 "the remote refused the push of developer; nothing changed: tell the human"
  fi
  git -C "$src" merge -q --ff-only "$merge" ||
    die 1 "developer of the remote is at $merge, but the local developer could not fast-forward to it: tell the human"
  echo "merged down: main ($(git -C "$src" rev-parse --short "$main")) into developer of $(shown "$src") at $(git -C "$src" rev-parse --short "$merge")"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    echo "pushed: developer"
  else
    echo "no remote: developer merged locally only"
  fi
}

# Fails unless the repo has an origin remote.
require_remote() {
  git -C "$1" remote get-url origin >/dev/null 2>&1 ||
    die 1 "${1#"$root"/} has no remote: create the repository on the git server, add it as origin, and run again"
}

# developer: projects/<repo> on developer, with developer on the remote.
cmd_developer() {
  local src create=0 current
  src="$(project_repo "${1:-}")"
  case "${2:-}" in
    "") ;;
    --create) create=1 ;;
    *) die 2 "unknown option: $2" ;;
  esac
  require_remote "$src"
  require_clean "$src"
  timeout 120 git -C "$src" fetch -q --prune origin || die 1 "could not fetch from the remote of ${src#"$root"/}"
  if ! git -C "$src" rev-parse -q --verify refs/remotes/origin/developer >/dev/null; then
    [ "$create" = 1 ] || die 1 "developer is not on the remote of ${src#"$root"/}: ask the person, then run again with --create"
    if git -C "$src" rev-parse -q --verify refs/heads/developer >/dev/null; then
      timeout 120 git -C "$src" push -q origin refs/heads/developer:refs/heads/developer || die 1 "the push of developer failed"
      echo "created on the remote: developer, from the local developer"
    else
      git -C "$src" rev-parse -q --verify refs/remotes/origin/main >/dev/null || die 1 "the remote has neither developer nor main"
      timeout 120 git -C "$src" push -q origin refs/remotes/origin/main:refs/heads/developer || die 1 "the push of developer failed"
      echo "created on the remote: developer, from main"
    fi
    timeout 120 git -C "$src" fetch -q origin developer || die 1 "could not fetch developer"
  fi
  if ! git -C "$src" rev-parse -q --verify refs/heads/developer >/dev/null; then
    git -C "$src" branch -q developer refs/remotes/origin/developer
  fi
  current="$(git -C "$src" symbolic-ref -q --short HEAD || echo detached)"
  if [ "$current" != developer ]; then
    # The branch left behind must hold nothing the remote lacks: switching never strands work in projects/.
    [ -z "$(git -C "$src" rev-list -n 1 HEAD --not --remotes=origin)" ] ||
      die 1 "${src#"$root"/} is on $current, with commits not on the remote: push them first (tell the human)"
    git -C "$src" switch -q developer
    echo "switched: ${src#"$root"/} from $current to developer"
  fi
  sync_branch "$src" developer
  echo "developer: ${src#"$root"/} at $(git -C "$src" rev-parse --short developer), on the remote"
}

# checkpoint: annotated tags on the heads of developer and main, pushed. Never moves a tag.
cmd_checkpoint() {
  local src day tags=() b tag sha have remote_tags
  src="$(project_repo "${1:-}")"
  day="$(date +%Y-%m-%d)"
  case "${2:-}" in
    "") ;;
    --date) day="${3:-}" ;;
    *) die 2 "unknown option: $2" ;;
  esac
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die 2 "--date must be yyyy-mm-dd: $day"
  require_remote "$src"
  require_clean_on "$src" developer
  sync_branch "$src" developer
  if timeout 120 git -C "$src" ls-remote --exit-code -q origin refs/heads/main >/dev/null 2>&1; then
    sync_branch "$src" main
  fi
  remote_tags="$(timeout 120 git -C "$src" ls-remote origin "refs/tags/ai-workspace-migration/$day/*")" ||
    die 1 "could not read the tags of the remote"
  for b in developer main; do
    git -C "$src" rev-parse -q --verify "refs/heads/$b" >/dev/null || { echo "attention: no $b: no checkpoint tag for it"; continue; }
    tag="ai-workspace-migration/$day/$b"
    sha="$(git -C "$src" rev-parse "refs/heads/$b")"
    if git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      [ "$(git -C "$src" rev-parse "refs/tags/$tag^{commit}")" = "$sha" ] ||
        die 1 "$tag exists on another commit; a tag is never moved: use another --date"
    else
      git -C "$src" tag -a "$tag" -m "Checkpoint before the normalization of the workspace: $b at $sha" "$sha"
    fi
    have="$(printf '%s\n' "$remote_tags" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')"
    [ -z "$have" ] || [ "$have" = "$(git -C "$src" rev-parse "refs/tags/$tag")" ] ||
      die 1 "$tag exists on the remote with another object; a tag is never moved: use another --date"
    tags+=("refs/tags/$tag")
  done
  [ "${#tags[@]}" -gt 0 ] || die 1 "no developer or main to tag"
  timeout 120 git -C "$src" push -q origin "${tags[@]}" || die 1 "the push of the checkpoint tags failed: nothing changed in the project"
  for tag in "${tags[@]}"; do
    echo "pushed: ${tag#refs/tags/} at $(git -C "$src" rev-parse --short "$tag^{commit}")"
  done
  echo "return point: the commits of these tags; they are never moved or deleted"
}

# Prints what a clone of a local folder cannot carry: uncommitted files (names only), stashes, local commits the
# folder's remote lacks, per branch.
source_leftovers() {
  local from="$1" files stashes b n only=""
  files="$(git --no-optional-locks -C "$from" status --porcelain 2>/dev/null | cut -c4- || true)"
  if [ -n "$files" ]; then
    echo "attention: uncommitted in the source, not brought (a clone carries only commits):"
    printf '%s\n' "$files" | sed 's/^/  /'
  fi
  stashes="$(git -C "$from" stash list 2>/dev/null | wc -l | tr -d ' ')"
  [ "$stashes" = 0 ] || echo "attention: $stashes stash(es) in the source, not brought"
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    n="$(git -C "$from" rev-list --count "refs/heads/$b" --not --remotes=origin 2>/dev/null || echo 0)"
    [ "$n" != 0 ] || continue
    # A branch the remote has, but behind the local one, is named with its count; a branch the remote lacks, alone.
    if git -C "$from" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      only+=" $b ($n commit(s) the remote does not have)"
    else
      only+=" $b (not on the remote)"
    fi
  done < <(git -C "$from" for-each-ref --format='%(refname:short)' refs/heads/)
  [ -z "$only" ] || echo "brought, not on the source's remote:$only"
}

# bring: a project cloned into projects/<path>, from a git URL or a local folder.
cmd_bring() {
  local from="${1:-}" rel="${2:-}" dest url local_src="" ref branch
  [ -n "$from" ] && [ -n "$rel" ] && [ $# -eq 2 ] || die 2 "usage: bring <git-url | folder> <path relative to projects/>"
  [[ "$rel" =~ ^[a-z0-9]+(-[a-z0-9]+)*(/[a-z0-9]+(-[a-z0-9]+)*)*$ ]] || die 2 "<path> is kebab-case folders joined by /: $rel"
  dest="$root/projects/$rel"
  [ ! -e "$dest" ] || die 1 "projects/$rel exists already"
  if [ -d "$from" ]; then
    local_src="$(physical "$from")"
    case "$local_src/" in "$root/"*) die 1 "the source is inside this workspace: $from" ;; esac
    [ "$(git -C "$local_src" rev-parse --show-toplevel 2>/dev/null)" = "$local_src" ] || die 1 "not the root of a git repo: $from"
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -n "$local_src" ]; then
    git clone -q --no-checkout "$local_src" "$dest" || die 1 "could not clone $from"
    # Every local branch and tag of the folder, the ones never pushed included.
    git -C "$dest" fetch -q --update-head-ok --tags "$local_src" '+refs/heads/*:refs/heads/*' || die 1 "could not fetch the branches of $from"
    git -C "$dest" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r ref; do
      git -C "$dest" update-ref -d "$ref"
    done
    url="$(git -C "$local_src" remote get-url origin 2>/dev/null || true)"
    if [ -n "$url" ]; then
      git -C "$dest" remote set-url origin "$url"
      timeout 120 git -C "$dest" fetch -q origin 2>/dev/null || echo "attention: could not fetch from the remote of the source; run the fetch later"
      echo "origin: the source's remote"
    else
      git -C "$dest" remote remove origin
      echo "attention: the source has no remote; /normalize-projects stops at stage 2 until the repository has one"
    fi
    source_leftovers "$local_src"
  else
    git clone -q --no-checkout "$from" "$dest" || die 1 "could not clone $from"
  fi
  # The clone has no checkout yet: -f writes the files of the branch chosen, developer, else main, else master, else
  # the default branch.
  for branch in developer main master ""; do
    if [ -z "$branch" ]; then
      git -C "$dest" checkout -q -f
    elif git -C "$dest" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
      git -C "$dest" checkout -q -f "$branch"
    elif git -C "$dest" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
      git -C "$dest" checkout -q -f -b "$branch" "origin/$branch"
    else
      continue
    fi
    break
  done
  echo "brought: projects/$rel, on $(git -C "$dest" symbolic-ref -q --short HEAD || echo detached)"
}

# Runs terraform in a module folder: AIWP_TERRAFORM, else the host binary, else the Docker toolbox, where the
# workspace is /work, so host paths in the arguments are mapped there.
tf() {
  local module="$1" var arg envs=() mapped=()
  shift
  if [ -n "${AIWP_TERRAFORM:-}" ]; then
    (cd "$module" && "$AIWP_TERRAFORM" "$@")
  elif command -v terraform >/dev/null 2>&1; then
    (cd "$module" && terraform "$@")
  else
    for var in $(compgen -e | grep -E '^(ARM_|TF_VAR_)' || true); do envs+=(-e "$var"); done
    for arg in "$@"; do mapped+=("${arg//"$root"\//\/work\/}"); done
    WORKSPACE_DIR="$root" docker compose --progress quiet -f "$root/docker/compose.yaml" run --rm -T \
      -w "/work/${module#"$root"/}" ${envs[@]+"${envs[@]}"} terraform "${mapped[@]}"
  fi
}

# Prints the sha256 of a file.
file_sha() {
  sha256sum "$1" | cut -d' ' -f1
}

# apply phase 1 (plan) or phase 2 (apply of the latest plan shown). Terraform runs in a temporary worktree of main
# under tmp/work/_apply/: projects/<repo> stays on developer, untouched, whatever happens.
cmd_apply() {
  local repo="${1:-}" module_rel="${2:-}" mode="${3:-}" plan_arg="${4:-}" src plans key latest plan main_sha wt module
  local want_plan want_sum want_main rc=0 private
  [ -n "$repo" ] && [ -n "$module_rel" ] || die 2 "usage: apply <repo> <module folder> [--apply <plan file>]"
  src="$(project_repo "$repo")"
  case "$module_rel" in /* | *..*) die 2 "<module folder> is relative to projects/$repo" ;; esac
  require_clean_on "$src" developer
  sync_branch "$src" main
  main_sha="$(git -C "$src" rev-parse refs/heads/main)"
  plans="$work_root/_apply"
  mkdir -p "$plans"
  key="${repo//\//-}--${module_rel//\//-}"
  latest="$plans/$key.latest"
  if [ "$mode" = --apply ]; then
    [ -f "$latest" ] || die 1 "no plan shown for $repo $module_rel: run phase 1 first"
    read -r want_plan want_sum want_main <"$latest"
    plan="$(physical "$(dirname "$plan_arg")" 2>/dev/null)/$(basename "$plan_arg")"
    [ "$plan" = "$want_plan" ] || die 1 "not the latest plan shown for $repo $module_rel ($want_plan)"
    # The plan is copied before it is checked, and the copy is what applies: the file under tmp/work cannot change
    # between the check and the apply.
    [ -f "$plan" ] || die 1 "plan file not found: $plan_arg"
    private="$(mktemp -d)"
    cp "$plan" "$private/plan.tfplan"
    [ "$(file_sha "$private/plan.tfplan")" = "$want_sum" ] || { rm -rf "$private"; die 1 "the plan file changed since it was shown: plan again"; }
    [ "$main_sha" = "$want_main" ] || die 1 "main changed since the plan: plan again"
  else
    [ -z "$mode" ] || die 2 "unknown option: $mode"
  fi
  wt="$plans/wt-$key-$(date +%Y%m%d-%H%M%S)-$$"
  git -C "$src" worktree add -q --detach "$wt" "$main_sha"
  # shellcheck disable=SC2064  # the paths go in already expanded: the trap runs after this function returns
  trap "git -C $(printf '%q' "$src") worktree remove --force $(printf '%q' "$wt") 2>/dev/null; git -C $(printf '%q' "$src") worktree prune" EXIT
  module="$(physical "$wt/$module_rel")" || die 1 "module folder not found on main: $module_rel"
  tf "$module" init -input=false
  if [ "$mode" = --apply ]; then
    cp "$private/plan.tfplan" "$plans/.applying-$$.tfplan"
    rm -rf "$private"
    tf "$module" apply -input=false "$plans/.applying-$$.tfplan" || rc=$?
    rm -f "$plans/.applying-$$.tfplan"
    [ "$rc" -eq 0 ] || die 1 "terraform apply failed (exit $rc)"
    rm -f "$plan" "$latest"
    echo "applied: projects/$repo/$module_rel at main $(git -C "$src" rev-parse --short main)"
    return 0
  fi
  plan="$plans/$key-$(date +%Y%m%d-%H%M%S).tfplan"
  tf "$module" plan -input=false -out="$plan"
  printf '%s %s %s\n' "$plan" "$(file_sha "$plan")" "$main_sha" >"$latest"
  tf "$module" show -no-color "$plan"
  echo
  echo "plan: ${plan#"$root"/} (main $(git -C "$src" rev-parse --short main))"
  echo "next, only on the human's request and after the human confirms this plan:"
  echo "      bash scripts/aiwp-cmds.sh apply $repo $module_rel --apply ${plan#"$root"/}"
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
command="$1"
shift
case "$command" in
  --help | -h | help) usage ;;
  gate)
    if [ "${1:-}" = --merge ]; then
      [ $# -eq 3 ] || die 2 "usage: gate --merge <work>/<clone> <sha>"
      cmd_gate_merge "$2" "$3"
    else
      given="${1:-}"
      [ -n "$given" ] || die 2 "usage: gate <work>/<clone> [--test \"<command>\" | --docs-only | --untested]"
      shift
      test_cmd=""
      docs=0
      untested=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --test) [ $# -ge 2 ] || die 2 "--test needs a value"; test_cmd="$2"; shift ;;
          --docs-only) docs=1 ;;
          --untested) untested=1 ;;
          *) die 2 "unknown option: $1" ;;
        esac
        shift
      done
      [ $((docs + untested + (${#test_cmd} > 0 ? 1 : 0))) -le 1 ] || die 2 "use one of --test, --docs-only and --untested"
      cmd_gate_check "$given" "$test_cmd" "$docs" "$untested"
    fi
    ;;
  release) cmd_release "$@" ;;
  hotfix) cmd_hotfix "$@" ;;
  hotfix-tag) cmd_hotfix_tag "$@" ;;
  hotfix-down) cmd_hotfix_down "$@" ;;
  apply) cmd_apply "$@" ;;
  developer) cmd_developer "$@" ;;
  checkpoint) cmd_checkpoint "$@" ;;
  bring) cmd_bring "$@" ;;
  *) echo "error: unknown command: $command" >&2; usage >&2; exit 2 ;;
esac
