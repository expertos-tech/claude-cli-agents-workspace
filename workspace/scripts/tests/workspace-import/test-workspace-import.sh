#!/usr/bin/env bash
# Scenarios of scripts/workspace-import.py (/import-workspace), end to end with real git and no model: an invented older
# workspace (acme, billing-api) with local bare remotes, imported into a throwaway workspace whose validate.sh is a stub.
# The real workspace is never touched. AC-n: the acceptance criteria of the request import-workspace.
# Run: bash scripts/tests/workspace-import/test-workspace-import.sh [--only <test_name>]
# check takes the status of the test right before it on purpose: SC2319 does not apply.
# shellcheck disable=SC2319
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../.." && pwd)"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'chmod -R u+rwX "$BASE" 2>/dev/null; rm -rf "$BASE"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDECODE CLAUDE_CODE_SESSION_ID
FAILED=0
COUNT=0
OUT=""
RC=0
CURRENT=""
W=""
OLD=""
REMOTES=""
TODAY="$(date +%Y-%m-%d)"
# The value of the .env files of the older workspace: it must reach no file of the workspace.
ENV_VALUE="acme-env-value-7Qx2Lm9Zr4"

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) check "has [$1]" 0 ;; *) check "missing [$1]" 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; *) check "absent [$1]" 0 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
eq() { [ "$2" = "$3" ]; check "$1: expected [$2] got [$3]" $?; }
file_has() { grep -qF -- "$2" "$1"; check "$1 has [$2]" $?; }

# Runs the script from the workspace root.
imp() {
  OUT="$(cd "$W" && timeout 120 python3 -I -B scripts/workspace-import.py "$@" 2>&1)"
  RC=$?
}

# A throwaway workspace: the scripts the import calls, projects/, tmp/, a custom/ repository, a tool in tools/, and a
# stub validate.sh that fails secrets when a listed file holds LEAKED (exit VALIDATE_RC instead, when set).
workspace() {
  W="$BASE/ws.$CURRENT"
  mkdir -p "$W/scripts/lib" "$W/projects" "$W/tmp" "$W/custom" "$W/tools/observability/src"
  cp "$SCRIPTS/workspace-import.py" "$SCRIPTS/prompt-log.py" "$SCRIPTS/aiwp-cmds.sh" "$SCRIPTS/aiwp-gate.sh" "$W/scripts/"
  cp "$SCRIPTS/lib/projects.sh" "$W/scripts/lib/"
  cat >"$W/scripts/validate.sh" <<'STUB'
#!/usr/bin/env bash
root="$(cd "$(dirname "$0")/.." && pwd)"
echo "validate $*" >>"$root/validate.log"
[ -z "${VALIDATE_RC:-}" ] || { echo "error: docker is not running"; exit "$VALIDATE_RC"; }
files=""
while [ $# -gt 0 ]; do
  case "$1" in --files) files="$2"; shift ;; esac
  shift
done
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -q LEAKED "$root/$f"; then echo "FAIL secrets"; exit 1; fi
done <"$files"
echo "PASS secrets"
STUB
  printf '{"name": "observability"}\n' >"$W/tools/observability/package.json"
  printf 'export const panel = "latency";\n' >"$W/tools/observability/src/panel.js"
  printf 'export const alert = "errors";\n' >"$W/tools/observability/src/alert.js"
  git init -q -b main "$W/custom"
  printf '# custom\n' >"$W/custom/README.md"
  git -C "$W/custom" add README.md
  git -C "$W/custom" commit -q -m init
}

# A bare remote $REMOTES/$1.git with one commit on main (file $1.txt); prints nothing.
remote() {
  local seed="$BASE/seed.$CURRENT.$1"
  git init -q --bare -b main "$REMOTES/$1.git"
  git init -q -b main "$seed"
  printf '%s\n' "$1" >"$seed/$1.txt"
  git -C "$seed" add -A
  git -C "$seed" commit -q -m "first $1"
  git -C "$seed" push -q "$REMOTES/$1.git" main
  rm -rf "$seed"
}

# Commits a file in a repository.
commit_in() { # repo, file, content
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add -- "$2"
  git -C "$1" commit -q -m "change $2"
}

# The older workspace, invented: the folder is a repository itself (the older workspace), with rules, a backlog, a
# .env; projects/billing-api (clean, with a worktree with changes and a detached worktree), projects/acme with
# projects/acme/billing-web nested, projects/reports with a branch never pushed, a work clone of billing-api in
# tmp/work/ with a branch never pushed, notes/ (a repository of its own: data), a code folder with no git and one
# that is a tool of this workspace (by name) and another one (by files).
older() {
  OLD="$BASE/old.$CURRENT"
  REMOTES="$BASE/remotes.$CURRENT"
  mkdir -p "$OLD" "$REMOTES"
  for r in billing-api acme billing-web reports notes; do remote "$r"; done
  git init -q -b main "$OLD"
  printf 'projects/\ntmp/\nnotes/\nworktrees/\n.env\n' >"$OLD/.gitignore"
  printf '# Older workspace\n' >"$OLD/CLAUDE.md"
  printf '# Agents\n' >"$OLD/AGENTS.md"
  mkdir -p "$OLD/rules" "$OLD/.claude/skills/queue" "$OLD/backlog/done"
  printf '# Review rule\n' >"$OLD/rules/review.md"
  printf '{}\n' >"$OLD/.claude/settings.json"
  printf -- '---\nname: queue\n---\n' >"$OLD/.claude/skills/queue/SKILL.md"
  printf '# Export invoices as CSV\n\nThe billing API exports the invoices of a month as CSV.\n\n- One row per invoice.\n' \
    >"$OLD/backlog/2026-11-09-export-invoices.md"
  printf '# Faster session queue\n\nThe review queue of the sessions waits too long.\n' >"$OLD/backlog/session-queue.md"
  printf '# Done long ago\n' >"$OLD/backlog/done/shipped.md"
  printf '# Backlog\n' >"$OLD/backlog/README.md"
  git -C "$OLD" add -A
  git -C "$OLD" commit -q -m "older workspace"
  printf 'API_TOKEN=%s\n' "$ENV_VALUE" >"$OLD/.env"
  mkdir -p "$OLD/projects" "$OLD/tmp/work/2026-10-01-fix-totals" "$OLD/worktrees"
  git clone -q "$REMOTES/billing-api.git" "$OLD/projects/billing-api"
  printf '.env\n' >"$OLD/projects/billing-api/.git/info/exclude"
  printf 'API_TOKEN=%s\n' "$ENV_VALUE" >"$OLD/projects/billing-api/.env"
  git -C "$OLD/projects/billing-api" worktree add -q -b feat/wt "$OLD/worktrees/billing-api-wt"
  printf 'changed\n' >>"$OLD/worktrees/billing-api-wt/billing-api.txt"
  printf 'new\n' >"$OLD/worktrees/billing-api-wt/draft.txt"
  git -C "$OLD/projects/billing-api" worktree add -q --detach "$OLD/worktrees/billing-api-spike"
  commit_in "$OLD/worktrees/billing-api-spike" spike.txt spike
  git clone -q "$REMOTES/acme.git" "$OLD/projects/acme"
  printf 'billing-web/\n' >"$OLD/projects/acme/.gitignore"
  git -C "$OLD/projects/acme" add .gitignore
  git -C "$OLD/projects/acme" commit -q -m ignore
  git -C "$OLD/projects/acme" push -q origin main
  git clone -q "$REMOTES/billing-web.git" "$OLD/projects/acme/billing-web"
  git clone -q "$REMOTES/reports.git" "$OLD/projects/reports"
  git -C "$OLD/projects/reports" switch -q -c feat/never-pushed
  commit_in "$OLD/projects/reports" monthly.txt monthly
  git -C "$OLD/projects/reports" switch -q main
  git clone -q "$REMOTES/billing-api.git" "$OLD/tmp/work/2026-10-01-fix-totals/billing-api"
  git -C "$OLD/tmp/work/2026-10-01-fix-totals/billing-api" switch -q -c fix/never-pushed
  commit_in "$OLD/tmp/work/2026-10-01-fix-totals/billing-api" totals.txt totals
  git clone -q "$REMOTES/notes.git" "$OLD/notes"
  mkdir -p "$OLD/tools/acme-cli" "$OLD/tools/observability" "$OLD/extras/dashboards/src"
  printf '{"name": "acme-cli"}\n' >"$OLD/tools/acme-cli/package.json"
  printf 'console.log("acme");\n' >"$OLD/tools/acme-cli/index.js"
  # The .env files are unreadable and one is a FIFO: a scan that opened one would fail or hang.
  printf 'API_TOKEN=%s\n' "$ENV_VALUE" >"$OLD/tools/acme-cli/.env"
  mkfifo "$OLD/tools/acme-cli/.env.local"
  chmod 000 "$OLD/.env" "$OLD/projects/billing-api/.env" "$OLD/tools/acme-cli/.env"
  printf '{"name": "observability"}\n' >"$OLD/tools/observability/package.json"
  cp "$W/tools/observability/package.json" "$OLD/extras/dashboards/package.json"
  cp "$W/tools/observability/src/panel.js" "$W/tools/observability/src/alert.js" "$OLD/extras/dashboards/src/"
}

# A fingerprint of a folder: every path with its type, mode, size and modification time, the content hash of each
# readable regular file, and the refs of each repository; a change anywhere changes it.
fingerprint() {
  python3 -I -c '
import hashlib, os, stat, sys
for top, dirs, files in sorted(os.walk(sys.argv[1])):
    for name in sorted(dirs + files):
        path = os.path.join(top, name)
        info = os.lstat(path)
        line = [path, oct(info.st_mode), str(info.st_size), str(info.st_mtime_ns)]
        if stat.S_ISREG(info.st_mode) and os.access(path, os.R_OK):
            with open(path, "rb") as handle:
                line.append(hashlib.sha256(handle.read()).hexdigest())
        print(" ".join(line))
' "$1"
}

# The refs of every bare remote.
remote_refs() {
  local r
  for r in "$REMOTES"/*.git; do
    echo "$r"
    git -C "$r" for-each-ref --format='%(refname) %(objectname)'
  done
}

# The import of the main fixture up to the plan, with the answers of the person.
import_to_plan() {
  imp scan "$OLD"
  rc_is 0
  imp answer R-1 data
  rc_is 0
  imp answer C-1 project
  rc_is 0
  imp answer B-1 billing-api --title "Export invoices as CSV"
  rc_is 0
  imp answer B-2 workspace
  rc_is 0
  imp plan
  rc_is 0
}

test_scan_reads_the_older_workspace_and_asks_only_judgement() {
  workspace
  older
  imp scan "$OLD"
  rc_is 0
  has "state: custom/migrations/import-$TODAY.json"
  has "the older workspace itself is a repository, not brought"
  has "questions: 2 open"
  imp questions --json
  rc_is 0
  has '"id": "R-1"'
  has "$OLD/notes"
  has '"id": "C-1"'
  has "$OLD/tools/acme-cli"
  hasnt '"id": "P-'
  hasnt '"id": "B-'
  # The backlog questions come once every repository is settled.
  imp answer R-1 data
  rc_is 0
  imp questions
  rc_is 0
  has "B-1"
  has "Export invoices as CSV"
  has "allowed: acme, acme/billing-web, billing-api, reports, workspace"
  has "B-2"
  hasnt "Done long ago"
  imp scan "$OLD"
  rc_is 0
  has "state: custom/migrations/import-$TODAY-2.json"
}

test_ac1_to_ac6_the_import_brings_projects_branches_and_requests() {
  workspace
  older
  local before_refs pending req
  before_refs="$(remote_refs)"
  import_to_plan
  local plan="$W/custom/migrations/import-$TODAY.md"
  [ -f "$plan" ]; check "plan written" $?
  # AC-6 and AC-4: the plan lists what is not imported.
  file_has "$plan" "$OLD/CLAUDE.md\`: an instruction file"
  file_has "$plan" "$OLD/rules/\`: an instruction file"
  file_has "$plan" "$OLD/.claude/\`: an instruction file"
  file_has "$plan" "$OLD/notes\`: data of the older workspace"
  file_has "$plan" "git -C $OLD/tools/acme-cli init -b main"
  file_has "$plan" "$OLD/tools/observability\`: covered by \`tools/observability\` of this workspace (its name)"
  file_has "$plan" "$OLD/extras/dashboards\`: covered by \`tools/observability\` of this workspace (most of its files)"
  file_has "$plan" "the older workspace itself"
  file_has "$plan" "Faster session queue"
  imp apply --yes
  rc_is 0
  has "import applied"
  has "nothing was pushed"
  # AC-1: the three repositories at their paths, the branch never pushed, each origin the source's remote.
  local p
  for p in billing-api acme acme/billing-web reports; do
    eq "repo projects/$p" "$W/projects/$p" "$(git -C "$W/projects/$p" rev-parse --show-toplevel 2>/dev/null)"
  done
  eq "origin of billing-api" "$REMOTES/billing-api.git" "$(git -C "$W/projects/billing-api" remote get-url origin)"
  eq "origin of the nested one" "$REMOTES/billing-web.git" "$(git -C "$W/projects/acme/billing-web" remote get-url origin)"
  eq "origin of reports" "$REMOTES/reports.git" "$(git -C "$W/projects/reports" remote get-url origin)"
  eq "branch never pushed" "$(git -C "$OLD/projects/reports" rev-parse feat/never-pushed)" \
    "$(git -C "$W/projects/reports" rev-parse -q --verify refs/heads/feat/never-pushed)"
  eq "nothing pushed" "$before_refs" "$(remote_refs)"
  [ ! -e "$W/projects/notes" ] && [ ! -e "$W/projects/acme-cli" ] && [ ! -e "$W/projects/observability" ]
  check "AC-4: data, code folders and tools not brought" $?
  # AC-2: the worktree's branch, and import/<worktree-name> at the detached HEAD.
  eq "worktree branch" "$(git -C "$OLD/projects/billing-api" rev-parse feat/wt)" \
    "$(git -C "$W/projects/billing-api" rev-parse -q --verify refs/heads/feat/wt)"
  eq "detached worktree" "$(git -C "$OLD/worktrees/billing-api-spike" rev-parse HEAD)" \
    "$(git -C "$W/projects/billing-api" rev-parse -q --verify refs/heads/import/billing-api-spike)"
  # AC-3: the branch of the work clone, a local branch of the project.
  eq "work clone branch" "$(git -C "$OLD/tmp/work/2026-10-01-fix-totals/billing-api" rev-parse fix/never-pushed)" \
    "$(git -C "$W/projects/billing-api" rev-parse -q --verify refs/heads/fix/never-pushed)"
  pending="$W/custom/requests/$TODAY-billing-api-pending-work.md"
  [ -f "$pending" ]; check "pending-work request" $?
  file_has "$pending" "**Project:** billing-api"
  file_has "$pending" "**State:** ready"
  file_has "$pending" "Compare each with the base when you work on it"
  file_has "$pending" "\`$OLD/worktrees/billing-api-wt\` (worktree of $OLD/projects/billing-api), branch \`feat/wt\`"
  file_has "$pending" "\`billing-api.txt\`"
  file_has "$pending" "\`draft.txt\`"
  file_has "$pending" "\`$OLD/worktrees/billing-api-spike\`"
  file_has "$pending" "\`$OLD/tmp/work/2026-10-01-fix-totals/billing-api\` (work clone)"
  file_has "$pending" "Branch \`fix/never-pushed\`: no upstream, 1 commit(s) not pushed"
  file_has "$pending" "Brought into the project as the branch \`fix/never-pushed\`"
  [ -f "$W/custom/requests/$TODAY-reports-pending-work.md" ]; check "pending work of reports" $?
  [ ! -e "$W/custom/requests/$TODAY-acme-pending-work.md" ]; check "no pending work of a clean project" $?
  # AC-5: the project item an idea with its Project line and its text unchanged; the process item dropped.
  req="$W/custom/requests/$TODAY-export-invoices-as-csv.md"
  [ -f "$req" ]; check "backlog request" $?
  file_has "$req" "**Project:** billing-api"
  file_has "$req" "**State:** idea"
  file_has "$req" "Imported from \`$OLD/backlog/2026-11-09-export-invoices.md\`"
  python3 -I -c 'import sys; sys.exit(open(sys.argv[2]).read() not in open(sys.argv[1]).read())' \
    "$req" "$OLD/backlog/2026-11-09-export-invoices.md"
  check "text unchanged" $?
  ! grep -rqF "session queue" "$W/custom/requests"; check "process item has no request" $?
  file_has "$plan" "Faster session queue (the older workspace's own process)"
  # AC-6: nothing of the rules imported.
  [ ! -e "$W/custom/my-rules" ] && [ ! -e "$W/custom/rules-config.json" ]; check "no rules imported" $?
  # custom/ committed by path, not pushed.
  eq "custom commit" "docs(requests): import the work of an older workspace" "$(git -C "$W/custom" log -1 --format=%s)"
  eq "custom clean" "" "$(git -C "$W/custom" status --porcelain)"
  git -C "$W/custom" log -1 --format=%b | grep -q '\[#automatic-agent-commit\]'; check "agent commit marker" $?
  imp status
  rc_is 0
  has "steps done"
  imp apply --yes
  rc_is 0
  imp answer B-1 reports
  rc_is 1
  has "apply has started"
}

test_ac7_a_dotenv_is_never_opened_nor_copied() {
  workspace
  older
  import_to_plan
  imp apply --yes
  rc_is 0
  ! grep -rqF "$ENV_VALUE" "$W/custom" "$W/projects" "$W/tmp"; check "the .env value is in no file of the workspace" $?
  [ ! -e "$W/projects/billing-api/.env" ]; check "the ignored .env not brought" $?
}

test_ac8_the_older_workspace_is_the_same_after_the_import() {
  workspace
  older
  local before
  before="$(fingerprint "$OLD")"
  import_to_plan
  imp apply --yes
  rc_is 0
  eq "older workspace unchanged" "$before" "$(fingerprint "$OLD")"
}

test_a_secret_in_a_backlog_item_keeps_only_its_path() {
  workspace
  older
  # An access key id of the AWS shape, split so that no scanner takes this file for one.
  printf '# Rotate the key\n\nUse %s%s for the export.\n' AKIA ABCDEFGHIJKLMNOP >"$OLD/backlog/rotate.md"
  printf '# Leaky item\n\nLEAKED value here.\n' >"$OLD/backlog/leaky.md"
  imp scan "$OLD"
  imp answer R-1 data
  imp answer C-1 tool
  imp questions --json
  local id
  for id in B-1 B-2 B-3 B-4; do imp answer "$id" reports; done
  imp plan
  rc_is 0
  imp apply --yes
  rc_is 0
  has "2 item(s) keep only their source path"
  local rotate="$W/custom/requests/$TODAY-rotate-the-key.md" leaky="$W/custom/requests/$TODAY-leaky-item.md"
  file_has "$rotate" "Imported from \`$OLD/backlog/rotate.md\`"
  file_has "$rotate" "looks like a secret"
  ! grep -qF AKIA "$rotate"; check "pattern hit not copied" $?
  file_has "$leaky" "looks like a secret"
  ! grep -qF LEAKED "$leaky"; check "gitleaks hit not copied" $?
  file_has "$W/custom/requests/$TODAY-export-invoices-as-csv.md" "One row per invoice."
  [ ! -e "$W/tmp/import-import-$TODAY" ]; check "the scan copies removed" $?
}

test_apply_resumes_after_a_failed_step() {
  workspace
  older
  import_to_plan
  OUT="$(cd "$W" && VALIDATE_RC=2 python3 -I -B scripts/workspace-import.py apply --yes 2>&1)"
  RC=$?
  rc_is 1
  has "failed: the secret scan of the backlog items kept"
  has "apply --yes again resumes from this step"
  [ -d "$W/projects/billing-api/.git" ]; check "steps before it done" $?
  imp status
  has "next step: the secret scan of the backlog items kept (failed:"
  imp apply --yes
  rc_is 0
  hasnt "done: bring"
  has "done: the secret scan"
  has "import applied"
}

test_a_repository_outside_the_projects_folder_becomes_a_project() {
  workspace
  older
  imp scan "$OLD"
  imp answer R-1 project
  rc_is 0
  has "questions: 2 open"
  imp questions --json
  has '"id": "P-1"'
  has '"proposal": "notes"'
  imp answer P-1 Bad_Name
  rc_is 1
  has "no kebab-case path"
  mkdir -p "$W/projects/taken"
  imp answer P-1 taken
  rc_is 1
  has "exists in this workspace"
  imp answer P-1 acme/notes
  rc_is 0
  imp answer C-1 tool
  imp answer B-1 acme/notes
  rc_is 0
  imp answer P-1 reports
  rc_is 0
  imp answer B-2 workspace
  imp plan
  rc_is 1
  has "both go to projects/reports"
  imp answer P-1 knowledge/notes
  rc_is 0
  imp questions --json
  imp answer B-1 knowledge/notes
  imp plan
  rc_is 0
  imp apply --yes
  rc_is 0
  eq "brought where answered" "$REMOTES/notes.git" "$(git -C "$W/projects/knowledge/notes" remote get-url origin)"
  file_has "$W/custom/requests/$TODAY-export-invoices-as-csv.md" "**Project:** knowledge/notes"
}

test_a_skipped_project_is_not_brought_nor_its_branches_nor_its_pending_work() {
  workspace
  older
  imp scan "$OLD"
  imp answer R-1 data
  imp answer C-1 tool
  imp skip nowhere
  rc_is 1
  has "nowhere is no project of this import"
  imp skip billing-api
  rc_is 0
  has "billing-api: skip"
  # A nested repository is skipped with its parent, unless included on its own.
  imp skip acme
  rc_is 0
  imp include acme/billing-web
  rc_is 0
  has "acme/billing-web: import"
  imp answer B-1 billing-api
  rc_is 0
  imp answer B-2 workspace
  imp plan
  rc_is 0
  local plan="$W/custom/migrations/import-$TODAY.md" r row
  file_has "$plan" "| Source | Destination | Remote | Files | .git | Status |"
  row="$(grep -F "| \`$OLD/projects/billing-api\` |" "$plan")"
  case "$row" in *"| \`projects/billing-api\` |"*"B | "*" | skip |") true ;; *) false ;; esac
  check "the plan lists billing-api, with its sizes, as skip" $?
  row="$(grep -F "| \`$OLD/projects/reports\` |" "$plan")"
  case "$row" in *"| import |") true ;; *) false ;; esac
  check "reports stays import" $?
  file_has "$plan" "| import (its parent $OLD/projects/acme is not imported) |"
  file_has "$plan" "\`$OLD/worktrees/billing-api-wt\`: a worktree of \`$OLD/projects/billing-api\`, which is not imported"
  file_has "$plan" "\`$OLD/worktrees/billing-api-spike\`: a worktree of"
  file_has "$plan" "\`$OLD/tmp/work/2026-10-01-fix-totals/billing-api\`: a work clone of \`$OLD/projects/billing-api\`"
  file_has "$plan" "Export invoices as CSV (its project billing-api is not imported)"
  imp apply --yes
  rc_is 0
  [ ! -e "$W/projects/billing-api" ]; check "the skipped project is not in projects/" $?
  [ ! -e "$W/projects/acme/.git" ]; check "the skipped parent is not a repository" $?
  eq "the included nested one is" "$W/projects/acme/billing-web" "$(git -C "$W/projects/acme/billing-web" rev-parse --show-toplevel)"
  for r in reports acme/billing-web; do
    ! git -C "$W/projects/$r" for-each-ref --format='%(refname)' | grep -qE 'billing-api-spike|fix/never-pushed|feat/wt'
    check "no branch of the skipped project's worktrees or clone in projects/$r" $?
  done
  [ ! -e "$W/custom/requests/$TODAY-billing-api-pending-work.md" ]; check "no pending-work request" $?
  [ ! -e "$W/custom/requests/$TODAY-export-invoices-as-csv.md" ]; check "its backlog item dropped" $?
  imp skip reports
  rc_is 1
  has "apply has started"
}

test_refusals() {
  workspace
  older
  imp scan "$W"
  rc_is 1
  has "this workspace, inside it, or holds it"
  imp scan "$W/projects"
  rc_is 1
  imp scan "$BASE"
  rc_is 1
  imp scan "$BASE/missing"
  rc_is 1
  has "not a folder"
  imp questions
  rc_is 1
  has "no import state: run scan"
  imp scan "$OLD"
  rc_is 0
  imp apply --yes
  rc_is 1
  has "questions are open: R-1, C-1"
  imp plan
  rc_is 1
  has "questions are open"
  imp answer R-1 maybe
  rc_is 1
  has "maybe is not an answer of R-1: one of project, data"
  imp answer R-9 data
  rc_is 1
  has "no question R-9"
  imp answer R-1 data --title "A title"
  rc_is 1
  has "only for a backlog item"
  imp answer R-1 data
  imp answer C-1 project
  imp answer B-1 nowhere
  rc_is 1
  imp answer B-1 billing-api
  imp answer B-2 workspace
  imp apply --yes
  rc_is 1
  has "no plan for the current answers"
  imp plan
  rc_is 0
  imp apply
  rc_is 1
  has "apply runs only with --yes"
  imp answer B-2 billing-api
  rc_is 0
  imp apply --yes
  rc_is 1
  has "no plan for the current answers"
  imp nope
  rc_is 2
  imp --help
  rc_is 0
  has "scan <folder>"
  [ ! -e "$W/projects/billing-api" ]; check "nothing brought by a refusal" $?
}

only=""
[ "${1:-}" != "--only" ] || only="${2:-}"
tests="$(declare -F | awk '{print $3}' | grep '^test_')"
[ -z "$only" ] || tests="$only"
for t in $tests; do
  CURRENT="$t"
  "$t"
  COUNT=$((COUNT + 1))
done
if [ "$FAILED" -eq 0 ]; then echo "ok: $COUNT tests"; else echo "failed: $FAILED checks"; exit 1; fi
