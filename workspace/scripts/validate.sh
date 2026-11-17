#!/usr/bin/env bash
# Runs the containerized validation checks from docker/compose.yaml and prints a concise report.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

ALL_CHECKS="secrets vuln iac shell dockerfile markdown mermaid terraform python typescript coverage"

usage() {
  cat <<'USAGE'
Usage: scripts/validate.sh [--path <dir>] [--only <list>] [--skip <list>] [--files <path-file>] [--no-cache] [--verbose] [--help]

Runs validation tools in Docker (no host install needed) and reports PASS/FAIL per check.
Exit 0 when every executed check passes, 1 otherwise, 2 on usage error.

Checks (default: all except cost):
  secrets     gitleaks: secrets in files; also fails on a .env or local.settings.json tracked by git (any depth):
              the scan skips both names (docker/config/gitleaks.toml), so a tracked one would go unseen
  vuln        trivy: HIGH/CRITICAL dependency vulnerabilities and secrets
  iac         trivy: HIGH/CRITICAL misconfigurations in Terraform, Dockerfile, Kubernetes
  shell       shellcheck: every *.sh
  dockerfile  hadolint: every Dockerfile*, except *.dockerignore; fails from warning up
  markdown    markdownlint-cli2: every *.md
  mermaid     mermaid-cli: renders every Mermaid diagram in *.md and *.mmd
  terraform   terraform fmt -check, init -backend=false, validate, tflint per root module
  python      ruff: lint and format check of every *.py
  typescript  biome ci: lint and format check of every *.ts and *.tsx
  coverage    coverage.py: runs the tests of each folder holding a .coveragerc; every module needs
              >= 85% lines and >= 85% branches. No such folder prints SKIP and exits 0. Each step
              has a deadline: COVERAGE_TIMEOUT_SECONDS, default 600
              python, typescript and coverage ignore projects/ (own tooling), coverage also tools/;
              nothing left prints SKIP, exit 0. A root scan also skips projects/ in vuln, iac, shell,
              dockerfile, markdown, terraform and the .mmd files of mermaid; mermaid still reads *.md
              there. A project is judged on its own: --path projects/<name>. The same goes
              for custom/, the repo of the custom layer: --path custom.
              Every check but mermaid on *.md skips tools/container-console-docker-ce/internal/webui/dist
  cost        infracost breakdown per root module (needs INFRACOST_API_KEY in custom/env/docker.env)

Options:
  --path <dir>    Folder to check, relative to the workspace root or absolute inside it; a folder
                  outside the workspace or a path with '..' is refused. Default: workspace root.
                  Target "." ignores the top-level tmp/ (worktrees of prompts). A worktree is checked
                  on its own: --path tmp/worktrees/<repo>/<branch> (workspace-owned checks are skipped
                  there, as under projects/).
  --only <list>   Comma-separated checks to run (e.g. terraform,shell). "all" adds cost.
  --skip <list>   Comma-separated checks to skip.
  --files <path-file>
                  File listing the files to judge, one per line, relative to the workspace root. Every
                  entry must be an existing file. shell, dockerfile, markdown, mermaid, python and
                  typescript then judge only the listed files inside the target, with the same exclusions
                  as the full scan; secrets scans a copy of the listed files inside the target (a target
                  "." leaves out the top-level tmp/), made under .history/ and removed after the scan; a path
                  in its output names the real file. Nothing to judge prints SKIP. The other checks stay on
                  the whole target. Without this flag every check scans the whole target.
  --no-cache      Run every check even when the check ledger holds a PASS for the same inputs
                  (CACHED <check>, rules/scripts.md "Check ledger"). vuln and iac expire in 24 h; cost is never recorded.
  --verbose       Print full tool output instead of the last 30 lines of failures.
  --help          Show this help.

Examples:
  scripts/validate.sh --path projects/billing
  scripts/validate.sh --only terraform,cost --path projects/billing/infra
  scripts/validate.sh --only secrets,markdown --files /tmp/changed-files.txt
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -r "$root/scripts/lib/env.sh" ] || { echo "error: scripts/lib/env.sh not found" >&2; exit 2; }
# shellcheck source=lib/env.sh
. "$root/scripts/lib/env.sh"
target="."
only=""
skip=""
verbose=0
files_list=""

while [ $# -gt 0 ]; do
  case "$1" in
    --path|--only|--skip|--files)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --path) target="$2" ;;
        --only) only="$2" ;;
        --skip) skip="$2" ;;
        --files)
          [ -n "$2" ] || { echo "error: --files needs a value" >&2; exit 2; }
          files_list="$2" ;;
      esac
      shift ;;
    --no-cache) export CHECK_LEDGER_DISABLE=1 ;;
    --verbose) verbose=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Prints absolute folder $1 relative to the workspace root ("." for the root itself); exits 2 when it lies outside.
# Compared physically: a parent that is a link gives one folder two spellings (/tmp on macOS), and a link inside the
# workspace that leads out of it is outside.
relative_to_root() {
  local real real_root
  real="$(cd "$1" 2>/dev/null && pwd -P)" || { echo "error: folder not found: $1" >&2; exit 2; }
  real_root="$(cd "$root" && pwd -P)"
  case "$real" in
    "$real_root") echo "." ;;
    "$real_root"/*) printf '%s\n' "${real#"$real_root"/}" ;;
    *) echo "error: --path is outside the workspace: $1" >&2; exit 2 ;;
  esac
}

case "$target" in
  ..|../*|*/..|*/../*) echo "error: --path must not hold '..': $target" >&2; exit 2 ;;
  /*) target="$(relative_to_root "$target")" || exit 2 ;;
esac
target="${target#./}"
target="${target%/}"
[ -n "$target" ] || target="."
# Root scan: the worktrees under the top-level tmp/ are not part of it.
root_scan=0
[ "$target" = "." ] && root_scan=1
[ -d "$root/$target" ] || { echo "error: folder not found: $target" >&2; exit 2; }

# Refuses a --files list that is not a regular file, or an entry that is not an existing file of the workspace:
# a list that names nothing real must not read as "nothing to judge".
check_files_list() {
  local p
  [ -f "$files_list" ] || { echo "error: --files is not a file: $files_list" >&2; exit 2; }
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    case "$p" in
      /*|..|../*|*/..|*/../*) echo "error: --files entry must be relative to the workspace root, without '..': $p" >&2; exit 2 ;;
    esac
    [ -f "$root/$p" ] || { echo "error: --files entry is not a file: $p" >&2; exit 2; }
  done <"$files_list"
}

[ -z "$files_list" ] || check_files_list
command -v docker >/dev/null 2>&1 || { echo "error: docker not found" >&2; exit 2; }

if [ "$only" = "all" ]; then
  checks="$ALL_CHECKS cost"
elif [ -n "$only" ]; then
  checks="$(echo "$only" | tr ',' ' ')"
else
  checks="$ALL_CHECKS"
fi
for c in $checks $(echo "$skip" | tr ',' ' '); do
  case " $ALL_CHECKS cost " in
    *" $c "*) ;;
    *) echo "error: unknown check: $c" >&2; exit 2 ;;
  esac
done

work="/work/$target"
[ "$target" = "." ] && work="/work"
logdir="$(mktemp -d)"
# Copy of the listed files the secrets check scans; removed after the scan, or here when the run stops before.
stage=""
trap 'rm -rf "$logdir" ${stage:+"$stage"}' EXIT
failed=0

# The variables of the toolbox: custom/env/docker.env, else the defaults of docker/.env.example (only cost needs a key).
compose_env="$(env_file_for_compose "$root" docker optional)" || exit 2

# Runs a compose service with the workspace mounted read-only at /work.
tool() {
  WORKSPACE_DIR="$root" docker compose --progress quiet --env-file "$compose_env" -f "$root/docker/compose.yaml" run --rm -T "$@"
}

# Runs a compose service like tool, with module folder $1 (relative to the root) mounted writable on top when it lies
# in projects/, tmp/ or custom/: terraform init and infracost write there. Elsewhere (the core) it stays read-only.
tool_in_module() {
  local d="$1"
  shift
  case "$d" in
    projects/* | tmp/* | custom/*) tool -v "$root/$d:/work/$d" "$@" ;;
    *) tool "$@" ;;
  esac
}

# Generated front-end output of the console, skipped by the checks that scan folders.
CONSOLE_DIST=tools/container-console-docker-ce/internal/webui/dist

# Prints the Trivy --skip-dirs entry for that output. Trivy matches it relative to the scanned folder.
generated_skip_dir() {
  case "$target" in
    tools/container-console-docker-ce | */tools/container-console-docker-ce) echo internal/webui/dist ;;
    tools | */tools) echo container-console-docker-ce/internal/webui/dist ;;
    *) echo "**/$CONSOLE_DIST" ;;
  esac
}

# Prints workspace-relative files under the target matching a find name pattern, skipping vendored and local folders
# (a root scan also skips the person's tmp/, projects/, custom/ and logs/, the prompt log of scripts/prompt-log.py).
files() {
  (cd "$root" && find "$target" \( -name .git -o -name node_modules -o -name .terraform -o -name refs -o -name .claude -o -name .history -o -name .data -o -path "*/$CONSOLE_DIST" -o -path "$CONSOLE_DIST" -o -path ./tmp -o -path ./projects -o -path ./custom -o -path ./logs \) -prune \
    -o -type f -name "$1" -print) | sed 's#^\./##'
}

# Prints the --files entries inside the target that match a find name pattern, skipping what files() prunes.
listed_files() {
  local p name
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    p="${p#./}"
    name="${p##*/}"
    # The pattern is a glob on purpose, as in find -name.
    # shellcheck disable=SC2254
    case "$name" in
      $1) ;;
      *) continue ;;
    esac
    case "/$p/" in
      */.git/*|*/node_modules/*|*/.terraform/*|*/refs/*|*/.claude/*|*/.history/*|*/.data/*|*/tools/container-console-docker-ce/internal/webui/dist/*) continue ;;
    esac
    if [ "$root_scan" -eq 1 ]; then
      case "$p" in tmp/*|projects/*|custom/*|logs/*) continue ;; esac
    else
      case "$p" in "$target"/*) ;; *) continue ;; esac
    fi
    printf '%s\n' "$p"
  done <"$files_list"
}

# Prints the files a lint check judges: the --files entries when given, else every matching file of the target.
judged_files() {
  if [ -n "$files_list" ]; then listed_files "$1"; else files "$1"; fi
}

# Prints the lines of stdin without what the workspace does not own: independent repos in projects/ and custom/,
# worktrees in tmp/worktrees/ and the clones of tmp/work/ configure their own lint and coverage.
only_owned() {
  grep -v -e '^projects/' -e '^custom/' -e '^tmp/worktrees/' -e '^tmp/work/' || true
}

# Prints the matching files of the target that the workspace owns.
owned_files() {
  files "$1" | only_owned
}

# Prints the matching files a lint check judges that the workspace owns.
judged_owned_files() {
  judged_files "$1" | only_owned
}

# Prints the lines of stdin; a root scan drops the top-level tmp/ only. Anchored here because
# grep --exclude-dir matches a folder name at any depth, which would also hide docs/tmp/.
without_root_tmp() {
  if [ "$root_scan" -eq 1 ]; then
    grep -v '^tmp/' || true
  else
    cat
  fi
}

# Marks a check with nothing to do as skipped in the summary.
skip_no_targets() {
  summary="SKIP $1 (no targets)"
  echo "no targets"
}

# Prints Terraform root modules (folders with a provider or backend block) outside modules/ and components/.
tf_roots() {
  files '*.tf' | grep -v -E '(^|/)(modules|components)/' | while IFS= read -r f; do
    grep -q -E '^[[:space:]]*(provider|backend)[[:space:]]+"' "$root/$f" && dirname "$f"
  done | sort -u
}

# Runs a tool once with every file listed on stdin appended as a container path.
tool_on_files() {
  local args=("$@") n=0 f
  while IFS= read -r f; do
    args+=("/work/$f")
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || { echo "no files"; return 0; }
  tool "${args[@]}"
}

# Runs a lint tool once on the files a check judges. Args: check name, find name pattern, tool and its options.
lint_files() {
  local name="$1" pattern="$2" list="$logdir/$1.list"
  shift 2
  judged_files "$pattern" >"$list.all" || return 1
  # A per-Dockerfile ignore file (Dockerfile.dockerignore) matches Dockerfile*, but it is not a Dockerfile.
  grep -v '\.dockerignore$' "$list.all" >"$list" || true
  if [ -n "$files_list" ] && [ ! -s "$list" ]; then
    skip_no_targets "$name"
    return 0
  fi
  tool_on_files "$@" <"$list"
}

# Prints the lines of stdin naming a file that holds a Mermaid diagram.
with_diagrams() {
  local f
  while IFS= read -r f; do
    if grep -qE '^```mermaid' "$root/$f" 2>/dev/null; then printf '%s\n' "$f"; fi
  done
}

# Writes to the mermaid list the files that hold diagrams: the --files entries when given, else the whole target.
mermaid_targets() {
  if [ -n "$files_list" ]; then
    listed_files '*.md' | with_diagrams
    listed_files '*.mmd'
  else
    (cd "$root" && grep -rlE --include='*.md' --exclude-dir=refs --exclude-dir=node_modules --exclude-dir=.claude --exclude-dir=.history --exclude-dir=.data '^```mermaid' "$target" 2>/dev/null) | sed 's#^\./##' | without_root_tmp
    files '*.mmd'
  fi
}

# Prints the --files entries the secrets check judges: those inside the target; a root scan leaves out the top-level
# tmp/, as gitleaks-root.toml does (its pattern cannot see the real path of a copy). The other exclusions are the
# allowlists of the gitleaks config, which match the copy too.
listed_secret_files() {
  local p
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    p="${p#./}"
    if [ "$root_scan" -eq 1 ]; then
      case "$p" in tmp/*) continue ;; esac
    else
      case "$p" in "$target"/*) ;; *) continue ;; esac
    fi
    printf '%s\n' "$p"
  done <"$files_list"
}

# Prints, relative to the workspace root, each file named .env or local.settings.json that git tracks among what the
# secrets check judges: the --files entries when given, else the whole target, in the repo that holds each one.
# gitleaks.toml allowlists both names (local files, normally git-ignored), so the scan never sees a tracked one.
# Prints nothing outside a git repo or without git.
# Prints one more pathspec for the tracked-file check of repo $1: the filled .env files when it is the custom layer
# (custom/env/<name>.env, with --path custom; the root scan leaves custom/ to that run), else the .env one again.
custom_env_glob() {
  case "$1/" in
    "$root/custom/" | "$root/custom/env/") echo ':(top,glob)env/*.env' ;;
    *) echo ':(glob)**/.env' ;;
  esac
}

tracked_local_files() {
  local p dir prefix=""
  command -v git >/dev/null 2>&1 || return 0
  if [ -n "$files_list" ]; then
    listed_secret_files | while IFS= read -r p; do
      case "$p" in custom/env/*.env) ;; *) case "${p##*/}" in .env | local.settings.json) ;; *) continue ;; esac ;; esac
      dir="$root"
      case "$p" in */*) dir="$root/${p%/*}" ;; esac
      if git -C "$dir" ls-files --error-unmatch -- "${p##*/}" >/dev/null 2>&1; then printf '%s\n' "$p"; fi
    done
    return 0
  fi
  [ "$target" = "." ] || prefix="$target/"
  { git -C "$root/$target" ls-files -z -- ':(glob)**/.env' ':(glob)**/local.settings.json' "$(custom_env_glob "$root/$target")" 2>/dev/null || true; } |
    while IFS= read -r -d '' p; do printf '%s\n' "$prefix$p"; done
  # A folder that only groups repos (a client folder of projects/): each repo inside answers for its own files.
  # The root scan leaves projects/ and tmp/ out, like its other checks.
  [ "$root_scan" -eq 0 ] || return 0
  find "$root/$target" -mindepth 2 -maxdepth 6 -name .git -not -path '*/node_modules/*' 2>/dev/null | LC_ALL=C sort |
    while IFS= read -r dir; do
      dir="${dir%/.git}"
      { git -C "$dir" ls-files -z -- ':(glob)**/.env' ':(glob)**/local.settings.json' 2>/dev/null || true; } |
        while IFS= read -r -d '' p; do printf '%s\n' "${dir#"$root"/}/$p"; done
    done
}

# Scans for secrets only the --files entries the check judges, with gitleaks config $1: copies them, keeping their
# workspace-relative paths, into a fresh folder under .history/ (git-ignored, inside the Docker mount, skipped by the
# other checks), scans that folder and prints the findings with /work/ in place of the copy's prefix.
secrets_on_listed_files() {
  local cfg="$1" list="$logdir/secrets.list" p rel rc=0
  listed_secret_files >"$list"
  if [ ! -s "$list" ]; then
    skip_no_targets secrets
    return 0
  fi
  local made_history=0
  [ -d "$root/.history" ] || made_history=1
  mkdir -p "$root/.history"
  stage="$(mktemp -d "$root/.history/validate-secrets.XXXXXX")" || { echo "cannot create the copy under .history/"; return 1; }
  while IFS= read -r p; do
    case "$p" in */*) mkdir -p "$stage/${p%/*}" ;; esac
    cp "$root/$p" "$stage/$p" || { echo "cannot copy $p for the secrets scan"; rc=1; }
  done <"$list"
  if [ "$rc" -eq 0 ]; then
    rel="${stage#"$root"/}"
    tool gitleaks dir "/work/$rel" --no-banner --redact -v --config "/work/docker/config/$cfg" </dev/null 2>&1 |
      sed "s#/work/$rel/#/work/#g" || rc=$?
  fi
  rm -rf "$stage"
  stage=""
  if [ "$made_history" -eq 1 ]; then rmdir "$root/.history" 2>/dev/null || true; fi
  return "$rc"
}

# Executes one named check and returns its tool exit code.
run_check() {
  local d f cfg skip_dirs rc=0
  case "$1" in
    secrets)
      cfg=gitleaks.toml
      [ "$root_scan" -eq 1 ] && cfg=gitleaks-root.toml
      # Found before the scan and whatever its result; printed after it, where the tail of a failure shows.
      tracked_local_files >"$logdir/secrets.tracked"
      if [ -n "$files_list" ]; then
        secrets_on_listed_files "$cfg" || rc=1
      else
        tool gitleaks dir "$work" --no-banner --redact --config "/work/docker/config/$cfg" || rc=1
      fi
      if [ -s "$logdir/secrets.tracked" ]; then
        sed 's/^/tracked by git: /' "$logdir/secrets.tracked"
        echo "a tracked .env or local.settings.json is never scanned (docker/config/gitleaks.toml allowlists both names): untrack it (git rm --cached) and rotate any key it holds"
        rc=1
      fi
      return "$rc" ;;
    vuln)
      skip_dirs="refs,.history,**/.data,**/node_modules,$(generated_skip_dir)"
      [ "$root_scan" -eq 1 ] && skip_dirs="$skip_dirs,tmp,projects,custom,logs"
      skip_files='**/.env'
      [ "$target" != custom ] || skip_files="$skip_files,env/*.env"
      tool trivy fs --quiet --scanners vuln,secret --severity HIGH,CRITICAL --exit-code 1 --skip-dirs "$skip_dirs" --skip-files "$skip_files" "$work" ;;
    iac)
      skip_dirs=".history,**/.data,**/node_modules,$(generated_skip_dir)"
      [ "$root_scan" -eq 1 ] && skip_dirs="$skip_dirs,tmp,projects,custom,logs"
      tool trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 --skip-dirs "$skip_dirs" "$work" ;;
    shell) lint_files shell '*.sh' shellcheck -x ;;
    # info findings are advice (e.g. DL3066 on the USER nonroot:nonroot of distroless): printed, not failed.
    dockerfile) lint_files dockerfile 'Dockerfile*' hadolint --failure-threshold warning ;;
    markdown) lint_files markdown '*.md' markdownlint ;;
    mermaid)
      mermaid_targets >"$logdir/mermaid.list"
      if [ ! -s "$logdir/mermaid.list" ]; then
        if [ -n "$files_list" ]; then skip_no_targets "$1"; else echo "no diagrams"; fi
        return 0
      fi
      while IFS= read -r f; do
        case "$f" in *.md) out=/tmp/out.md ;; *) out=/tmp/out.svg ;; esac
        tool mermaid -q -i "/work/$f" -o "$out" </dev/null || { echo "invalid: $f"; rc=1; }
      done <"$logdir/mermaid.list"
      return "$rc" ;;
    terraform)
      tf_roots >"$logdir/tf.list"
      if [ -z "$(files '*.tf' | head -n 1)" ]; then echo "no modules"; return 0; fi
      tool terraform -chdir="$work" fmt -check -recursive </dev/null || rc=1
      while IFS= read -r d; do
        echo "-- $d"
        tool_in_module "$d" terraform -chdir="/work/$d" init -backend=false -input=false -no-color </dev/null >/dev/null || { echo "init failed: $d"; rc=1; continue; }
        tool_in_module "$d" terraform -chdir="/work/$d" validate -no-color </dev/null || rc=1
        if [ -f "$root/$d/.tflint.hcl" ]; then
          tool --workdir "/work/$d" --entrypoint sh tflint -c 'tflint --init >/dev/null && tflint --no-color' </dev/null || rc=1
        else
          tool --workdir "/work/$d" tflint --no-color --config /work/docker/config/tflint.hcl </dev/null || rc=1
        fi
      done <"$logdir/tf.list"
      return "$rc" ;;
    cost)
      tf_roots >"$logdir/tf.list"
      [ -s "$logdir/tf.list" ] || { echo "no root modules"; return 0; }
      if [ -z "${INFRACOST_API_KEY:-}" ] && ! grep -qE '^[[:space:]]*(export[[:space:]]+)?INFRACOST_API_KEY=.+' "$compose_env"; then
        echo "INFRACOST_API_KEY is not set: fill it in custom/env/docker.env (/local-env docker)"
        return 1
      fi
      while IFS= read -r d; do
        tool_in_module "$d" infracost breakdown --path "/work/$d" --no-color </dev/null || rc=1
      done <"$logdir/tf.list"
      return "$rc" ;;
    python)
      judged_owned_files '*.py' >"$logdir/python.list"
      [ -s "$logdir/python.list" ] || { skip_no_targets "$1"; return 0; }
      tool_on_files ruff check --no-cache --config /work/docker/config/ruff.toml <"$logdir/python.list" || rc=1
      tool_on_files ruff format --check --no-cache --config /work/docker/config/ruff.toml <"$logdir/python.list" || rc=1
      return "$rc" ;;
    typescript)
      { judged_owned_files '*.ts'; judged_owned_files '*.tsx'; } >"$logdir/typescript.list"
      [ -s "$logdir/typescript.list" ] || { skip_no_targets "$1"; return 0; }
      tool_on_files --build biome ci --colors=off --config-path=/work/docker/config <"$logdir/typescript.list" ;;
    coverage)
      # tools/ has no coverage gate (rules/rules.md "Workspace layout").
      owned_files '.coveragerc' | { grep -v '^tools/' || true; } >"$logdir/coverage.list"
      [ -s "$logdir/coverage.list" ] || { skip_no_targets "$1"; return 0; }
      while IFS= read -r f; do
        d="$(dirname "$f")"
        echo "-- $d"
        tool --build --workdir "/work/$d" python-coverage </dev/null || { echo "failed: $d"; rc=1; }
      done <"$logdir/coverage.list"
      return "$rc" ;;
  esac
}

# Prints the listed files with their content hash; the state of a lint check that judges only them.
listed_state() {
  local p
  while IFS= read -r p || [ -n "$p" ]; do
    if [ -n "$p" ]; then printf '%s ' "$p"; git hash-object -- "$root/$p"; fi
  done <"$files_list"
}

# Prints the ledger key of check $1 (nothing: not cached). With --files, secrets and the lint checks depend only on
# those files.
check_key() {
  local state="$tree_state"
  [ "$1" != "cost" ] || return 0
  case "$1" in
    secrets | shell | dockerfile | markdown | mermaid | python | typescript)
      # For secrets a listed file that becomes tracked changes the result with the same content.
      if [ -n "$files_list" ]; then state="$({ listed_state; [ "$1" != secrets ] || tracked_local_files; } | ledger_hash)"; [ -s "$files_list" ] || state=""; fi ;;
  esac
  ledger_key "$1|$target" "$state"
}

# Prints the seconds a PASS of check $1 stays valid (0: no expiry): the tools' vulnerability data changes by itself.
check_ttl() {
  case "$1" in vuln | iac) echo 86400 ;; *) echo 0 ;; esac
}

LEDGER_ROOT="$root"
# shellcheck source=scripts/check-ledger.sh
. "$root/scripts/check-ledger.sh"
tree_state=""
if [ -z "${CHECK_LEDGER_DISABLE:-}" ]; then
  raw_state="$(ledger_tree_state "$root/$target" || true)"
  if [ -n "$raw_state" ]; then tree_state="$(printf '%s' "$raw_state" | ledger_hash)"; fi
fi

for c in $checks; do
  case ",$skip," in *",$c,"*) continue ;; esac
  key="$(check_key "$c")"
  if ledger_hit "$key" "$(check_ttl "$c")"; then
    echo "CACHED $c"
    continue
  fi
  summary="PASS $c"
  if run_check "$c" >"$logdir/$c.log" 2>&1; then
    echo "$summary"
    case "$summary" in PASS*) ledger_record "$key" ;; esac
    [ "$verbose" -eq 1 ] && cat "$logdir/$c.log"
  else
    echo "FAIL $c"
    failed=1
    if [ "$verbose" -eq 1 ]; then cat "$logdir/$c.log"; else tail -n 30 "$logdir/$c.log" | sed 's/^/  /'; fi
  fi
done

exit "$failed"
