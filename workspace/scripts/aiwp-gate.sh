#!/usr/bin/env bash
# The only ways into projects/: the gate (a clone of tmp/work/ into the base), the release (developer into main), the
# Terraform apply from main, and the steps of /normalize-projects (developer, checkpoint, bring). Called through
# scripts/aiwp-cmds.sh.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/aiwp-cmds.sh gate | release | apply | developer | checkpoint | bring ...   (this file: scripts/aiwp-gate.sh)

gate <work>/<clone> [--test "<command>" | --docs-only | --untested]
      Phase 1, checks. In the source repo (projects/<repo>, clean and on its base): fast-forward the base to the
      remote. Prints the state of the project (scripts/aiwp-project-state.sh): with no marker or out of date, an
      attention: line, never a failure. In the clone: merge the updated base into the branch and push it; run the
      full test command (--test, required unless every changed file is documentation and --docs-only is given); run
      scripts/validate.sh --path <clone> with every check; refuse env files and secrets in base..HEAD; write the audit
      of what leaves the base (deleted or renamed-away files, removed or disabled tests, destructive SQL, infra and
      dependency changes, large deletions) to tmp/work/<work>/gate-<clone>.md. The tests and checks must leave the
      tracked files unchanged. On success records the checked sha and prints the merge command.
      The normalization (/normalize-projects, branch feat/ai-workspace-migration, or
      feat/ai-workspace-migration-<x>-<y>-<z> for a later version) is judged on what the branch adds,
      because what is there today is reported, never fixed by it: the project must need it (state none or out of date;
      a -x-y-z suffix names a pending migration); line 1 of README.md must be the marker of this workspace VERSION;
      the branch may add or change only documentation, images, .gitignore and the sample .env (deletions are
      allowed); validate.sh runs only its lint
      checks, only on the files the branch changed; the secret check is the scan of the commits the branch adds
      (their added lines: a new secret or env file still fails, one already in the base does not); --untested is
      accepted when the person chose to go on without running the branch, and the audit says so.
gate --merge <work>/<clone> <sha>
      Phase 2, merge. Only the sha phase 1 passed, still the clone's HEAD and on the remote, and only when the base did
      not move: fetches the branch from the remote into the source repo, merge --ff-only, pushes the base, deletes the
      remote work branch (a normalization branch stays on the remote, as its record). The review against the request
      and the human's answers happen between the two phases.
release <repo> [--pr-if-refused] [--tag vX.Y.Z]
      developer -> main of projects/<repo>: pushes the developer commit to main of the remote (a fast-forward), then
      moves the local main ref (the checkout stays on developer). A remote that refuses the push (a protected main)
      leaves main unchanged and fails; with --pr-if-refused it opens a pull request developer -> main instead (gh)
      and exits 0. --tag: after main moved, an annotated tag vX.Y.Z on it, then pushed alone (no remote: local
      only); a tag of that name on another commit, here or on the remote, fails before main moves (a tag is never
      moved), on the same commit it is kept; a pull request opened instead leaves it for after the merge. Only on
      the human's request.
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

Terraform runs on the host when it is on PATH, else in the workspace Docker toolbox with the ARM_* and TF_VAR_*
variables of the environment (the image has no az CLI). AIWP_TERRAFORM replaces it (tests), and AIWP_GH replaces gh.
Exit: 0 ok; 1 refused or failed; 2 usage error.
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work_root="$root/tmp/work"
cmds="$root/scripts/aiwp-cmds.sh"
# The branch of /normalize-projects: the first one, or the one of a later version when that one is on the remote.
NORMALIZATION_RE='^feat/ai-workspace-migration(-[0-9]+-[0-9]+-[0-9]+)?$'
# The checks of validate.sh that judge only the files they are given; the others judge the whole tree.
LINT_CHECKS="shell,dockerfile,markdown,mermaid,python,typescript"
# The only files a normalization adds or changes: documentation, its images, .gitignore and the sample .env. Deleting
# a file (an instruction file whose content moved) is allowed and listed in the audit; code, infrastructure and
# dependencies are an ordinary request's.
NORMALIZATION_FILES_RE='(\.(md|mmd|png|jpe?g|gif|svg|webp)|(^|/)\.gitignore|(^|/)([^/]*\.)?env\.(example|sample))$'

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

# Fails unless a repo checkout has no change and is on the given branch.
require_clean_on() {
  local repo="$1" branch="$2" current
  [ -z "$(git -C "$repo" status --porcelain)" ] || die 1 "${repo#"$root"/} has changes in its checkout; nobody edits projects/: tell the human"
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

# gate phase 1: checks and audit.
cmd_gate_check() {
  local given="$1" test_cmd="$2" docs_flag="$3" untested="$4" clone src base branch work name sha range report record
  local base_sha normalization=0 files
  clone="$(clone_path "$given")"
  src="$(git -C "$clone" config --get aiwp.source)"
  base="$(git -C "$clone" config --get aiwp.base)"
  branch="$(git -C "$clone" config --get aiwp.branch)"
  work="$(basename "$(dirname "$clone")")"
  name="$(basename "$clone")"
  [[ "$branch" =~ $NORMALIZATION_RE ]] && normalization=1
  [ "$untested" = 0 ] || [ "$normalization" = 1 ] || die 2 "--untested is only for a normalization (feat/ai-workspace-migration)"
  [ -z "$(git -C "$clone" status --porcelain)" ] || die 1 "the clone has changes not committed: commit them first"
  [ "$(git -C "$clone" symbolic-ref -q --short HEAD)" = "$branch" ] || die 1 "the clone is not on $branch"
  require_clean_on "$src" "$base"
  echo "== 1/6 base: $base of ${src#"$root"/}"
  sync_branch "$src" "$base"
  case "$src/" in "$root/projects/"*) [ "$normalization" = 1 ] || bash "$cmds" _state-note "${src#"$root"/projects/}" ;; esac
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
    changed_files "$clone" "$range" "$files"
    if [ -s "$files" ]; then
      bash "$root/scripts/validate.sh" --path "${clone#"$root"/}" --only "$LINT_CHECKS" --files "$files" ||
        { rm -f "$files"; die 1 "validate failed: fix in the clone and run the gate again"; }
    else
      echo "SKIP validate: the normalization only deletes files"
    fi
    rm -f "$files"
  else
    echo "== 4/6 validate, every check"
    bash "$root/scripts/validate.sh" --path "${clone#"$root"/}" || die 1 "validate failed: fix in the clone and run the gate again"
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
  record="$work_root/$work/.gate-$name"
  printf '%s %s %s\n' "$sha" "$base_sha" "$(date +%s)" >"$record"
  echo
  echo "gate: checks passed for $sha"
  echo "audit: ${report#"$root"/}"
  echo "next: review the audit and the diff ($range) against the request; ask the human only what the request does"
  echo "      not explain; then: bash scripts/aiwp-cmds.sh gate --merge $work/$name $sha"
}

# gate phase 2: the merge of the checked sha.
cmd_gate_merge() {
  local given="$1" want="$2" clone src base branch work name record sha base_then
  clone="$(clone_path "$given")"
  src="$(git -C "$clone" config --get aiwp.source)"
  base="$(git -C "$clone" config --get aiwp.base)"
  branch="$(git -C "$clone" config --get aiwp.branch)"
  work="$(basename "$(dirname "$clone")")"
  name="$(basename "$clone")"
  record="$work_root/$work/.gate-$name"
  [ -f "$record" ] || die 1 "phase 1 did not pass for this clone: run bash scripts/aiwp-cmds.sh gate $work/$name first"
  read -r sha base_then _ <"$record"
  [ "$(git -C "$clone" rev-parse "$want" 2>/dev/null)" = "$sha" ] || die 1 "$want is not the sha phase 1 checked ($sha)"
  [ "$(git -C "$clone" rev-parse HEAD)" = "$sha" ] || die 1 "the clone moved after phase 1: run the gate again"
  [ -z "$(git -C "$clone" status --porcelain --untracked-files=no)" ] || die 1 "the clone has tracked changes after phase 1: run the gate again"
  require_clean_on "$src" "$base"
  sync_branch "$src" "$base"
  [ "$(git -C "$src" rev-parse "$base")" = "$base_then" ] || die 1 "$base moved after phase 1: run the gate again"
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    timeout 120 git -C "$src" fetch -q origin "$branch" || die 1 "could not fetch $branch from the remote"
    [ "$(git -C "$src" rev-parse FETCH_HEAD)" = "$sha" ] || die 1 "the remote $branch is not $sha: push it and run the gate again"
  else
    git -C "$src" rev-parse -q --verify "refs/heads/$branch" >/dev/null || die 1 "$branch not found in ${src#"$root"/}"
    [ "$(git -C "$src" rev-parse "refs/heads/$branch")" = "$sha" ] || die 1 "$branch in ${src#"$root"/} is not $sha"
  fi
  git -C "$src" merge -q --ff-only "$sha" || die 1 "$base cannot fast-forward to $sha: run the gate again"
  echo "merged: $sha into $base of ${src#"$root"/}"
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
  echo "next: bash scripts/aiwp-cmds.sh close $work"
}

# release: developer -> main. The remote's main moves first, by a push of the developer commit (a fast-forward), and
# the local main ref only after it, so a remote that refuses (a protected main) leaves both as they were. With --tag, an
# annotated tag on the released main, pushed alone; a tag on another commit, here or on the remote, fails before main
# moves, and a tag is never moved.
cmd_release() {
  local src repo="${1:-}" pr=0 tag="" tagged=0 dev_sha url remote_tag="" remote_commit="" lines
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
  git -C "$src" merge-base --is-ancestor main developer || die 1 "main has commits that are not in developer: tell the human"
  dev_sha="$(git -C "$src" rev-parse refs/heads/developer)"
  if [ -n "$tag" ]; then
    # Checked before main moves: a tag on another commit stops the release with nothing changed.
    if git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      [ "$(git -C "$src" rev-parse "refs/tags/$tag^{commit}")" = "$dev_sha" ] ||
        die 1 "$tag exists on another commit; a tag is never moved: main is unchanged, choose another version"
      [ "$(git -C "$src" cat-file -t "refs/tags/$tag")" = tag ] ||
        die 1 "$tag exists here as a lightweight tag; a release tag is annotated and never moved: main is unchanged, tell the human"
    fi
    if git -C "$src" remote get-url origin >/dev/null 2>&1; then
      lines="$(timeout 120 git -C "$src" ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}")" ||
        die 1 "could not read the tags of the remote: main is unchanged"
      remote_tag="$(printf '%s\n' "$lines" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')"
      remote_commit="$(printf '%s\n' "$lines" | awk -v r="refs/tags/$tag^{}" '$2 == r { print $1 }')"
      [ -n "$remote_commit" ] || remote_commit="$remote_tag"
      [ -z "$remote_tag" ] || [ "$remote_commit" = "$dev_sha" ] ||
        die 1 "$tag exists on the remote on another commit; a tag is never moved: main is unchanged, choose another version"
      if [ -n "$remote_tag" ] && git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        [ "$(git -C "$src" rev-parse "refs/tags/$tag")" = "$remote_tag" ] ||
          die 1 "$tag exists here and on the remote as different tags; a tag is never moved: main is unchanged, tell the human"
      fi
    fi
  fi
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
  [ -n "$tag" ] || return 0
  if ! git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    if [ -n "$remote_tag" ]; then
      # The remote already holds the tag on this commit: take that one, never a second tag object of the same name.
      timeout 120 git -C "$src" fetch -q origin "refs/tags/$tag:refs/tags/$tag" ||
        die 1 "main was released; $tag is on the remote but could not be fetched: git -C ${src#"$root"/} fetch origin refs/tags/$tag:refs/tags/$tag"
    else
      git -C "$src" tag -a "$tag" -m "$tag" "$dev_sha" || die 1 "main was released, but the tag $tag could not be created"
    fi
  fi
  echo "tagged: $tag at $(git -C "$src" rev-parse --short "refs/tags/$tag^{commit}")"
  if ! git -C "$src" remote get-url origin >/dev/null 2>&1; then
    echo "no remote: $tag is local only"
    return 0
  fi
  if [ -n "$remote_tag" ]; then
    echo "pushed: $tag (already on the remote)"
    return 0
  fi
  timeout 120 git -C "$src" push -q origin "refs/tags/$tag:refs/tags/$tag" ||
    die 1 "main was released, but the push of $tag failed: the tag is local only. Push it: git -C ${src#"$root"/} push origin refs/tags/$tag"
  echo "pushed: $tag"
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
  [ -z "$(git -C "$src" status --porcelain)" ] || die 1 "${src#"$root"/} has changes in its checkout; nobody edits projects/: tell the human"
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
  # shellcheck source=lib/projects.sh
  . "$root/scripts/lib/projects.sh"
  projects_check_repo_root "$root" "projects/$rel" || exit 1
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
  apply) cmd_apply "$@" ;;
  developer) cmd_developer "$@" ;;
  checkpoint) cmd_checkpoint "$@" ;;
  bring) cmd_bring "$@" ;;
  *) echo "error: unknown command: $command" >&2; usage >&2; exit 2 ;;
esac
