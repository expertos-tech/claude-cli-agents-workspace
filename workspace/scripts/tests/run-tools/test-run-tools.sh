#!/usr/bin/env bash
# Tests scripts/run-tools.sh and run-tools.py in a temp workspace with fictitious tools (acme-*) and fake docker, uname,
# dpkg-query, rpm, systemctl, launchctl and make on PATH: no real Docker, service manager or tool is touched. Covers the
# console detection (Docker CE, Colima, none), missing configuration, busy port, the rollback tag, the move from an old
# compose project (volume copy, refusal when another stack uses a network, restore when the copy fails), down without
# deleting anything, and the real tools/compose.yaml.
# shellcheck disable=SC2319  # ok reads the status of the test right before it, on purpose
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
work="$(mktemp -d)"
listener=""
trap '[ -n "$listener" ] && kill "$listener" 2>/dev/null; rm -rf "$work"' EXIT

passed=0
ws=""
fx=""
out=""
rc=0

# Fails the run with the description.
fail() {
  echo "FAIL: $1" >&2
  echo "$out" >&2
  exit 1
}

# Counts one passed check, or fails with description $2 when status $1 is not 0.
ok() {
  [ "$1" -eq 0 ] || fail "$2"
  passed=$((passed + 1))
}

# Succeeds when the last output holds $1.
has() { case "$out" in *"$1"*) return 0 ;; esac; return 1; }

# Succeeds when the log of the fake commands holds a line matching the extended regex $1.
logged() { grep -Eq -- "$1" "$fx/calls.log"; }

# Prints a free local TCP port.
free_port() { python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

# The fake commands, and links to the few real ones the scripts need, so nothing else on this machine is reached.
make_bin() {
  local bin="$work/bin" sys="$work/sys" c
  mkdir -p "$bin" "$sys"
  for c in bash sh python3 cat tr touch mkdir rm basename dirname env sleep grep sed head cut mv cp chmod ln; do
    ln -sf "$(command -v "$c")" "$sys/$c"
  done
  cat >"$bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >>"$FAKE_FX/calls.log"
fx="$FAKE_FX"
cmd="$1"
shift
case "$cmd" in
  compose)
    file="" sub="" first=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --env-file) shift ;;
        -f) file="$2"; shift ;;
        *) if [ -z "$sub" ]; then sub="$1"; elif [ -z "$first" ]; then first="$1"; fi ;;
      esac
      shift
    done
    tool="$(basename "$(dirname "$file")")"
    case "$sub" in
      config)
        if [ "$first" = --format ]; then f="$fx/$tool.json"; else f="$fx/$tool.yaml"; fi
        [ -f "$f" ] || f="$fx/default.${f##*.}"
        [ -f "$f" ] || { echo "open $file: no such file or directory" >&2; exit 1; }
        sed "s/@TOOL@/$tool/g" "$f" ;;
      up) exit "${FAKE_UP_RC:-0}" ;;
      *) exit 0 ;;
    esac ;;
  ps) cat "$fx/ps" 2>/dev/null; exit 0 ;;
  inspect) cat "$fx/inspect.json" ;;
  version) [ -n "${FAKE_ENGINE:-}" ] || exit 1; echo "$FAKE_ENGINE" ;;
  image)
    case "$1" in
      inspect) ref="${!#}"; f="$fx/image-$(printf '%s' "$ref" | tr '/:' '__')"; [ -f "$f" ] || exit 1; cat "$f" ;;
      ls) cat "$fx/image-ls" 2>/dev/null; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  network)
    case "$1" in
      inspect) f="$fx/net-$2.json"; [ -f "$f" ] || exit 1; cat "$f" ;;
      rm) rm -f "$fx/net-$2.json" ;;
    esac ;;
  volume)
    case "$1" in
      inspect) [ -e "$fx/vol-$2" ] ;;
      create) touch "$fx/vol-${!#}" ;;
      rm) rm -f "$fx/vol-$2" ;;
    esac ;;
  run) exit "${FAKE_RUN_RC:-0}" ;;
  stop) exit "${FAKE_STOP_RC:-0}" ;;
  *) exit 0 ;;
esac
STUB
  cat >"$bin/uname" <<'STUB'
#!/usr/bin/env bash
echo "${FAKE_UNAME:-Linux}"
STUB
  cat >"$bin/dpkg-query" <<'STUB'
#!/usr/bin/env bash
[ -n "${FAKE_DPKG:-}" ] || exit 1
echo "install ok installed"
STUB
  cat >"$bin/rpm" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  cat >"$bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >>"$FAKE_FX/calls.log"
case "$2" in
  is-active) if [ -f "$FAKE_FX/console-active" ]; then echo active; else echo inactive; exit 3; fi ;;
  start) touch "$FAKE_FX/console-active" ;;
  stop) rm -f "$FAKE_FX/console-active" ;;
esac
STUB
  cat >"$bin/launchctl" <<'STUB'
#!/usr/bin/env bash
echo "launchctl $*" >>"$FAKE_FX/calls.log"
case "$1" in
  print) [ -f "$FAKE_FX/console-active" ] || exit 113; echo "state = running" ;;
  kickstart) touch "$FAKE_FX/console-active" ;;
  bootout) rm -f "$FAKE_FX/console-active" ;;
esac
STUB
  cat >"$bin/make" <<'STUB'
#!/usr/bin/env bash
echo "make $*" >>"$FAKE_FX/calls.log"
mkdir -p "$XDG_CONFIG_HOME/systemd/user"
touch "$XDG_CONFIG_HOME/systemd/user/container-console-docker-ce.service" "$FAKE_FX/console-active"
STUB
  printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/go"
  cp "$bin/go" "$bin/npm"
  chmod +x "$bin"/*
  export PATH="$bin:$sys"
}

# A fresh workspace with three fictitious tools: acme-web (a configuration file, a built image, a port), acme-store
# (a named volume, a pulled image, a required variable) and acme-metrics (a fixed network, a stop grace period).
fresh() {
  ws="$work/ws-$1"
  fx="$work/fx-$1"
  mkdir -p "$ws/scripts" "$ws/tools/acme-web" "$ws/tools/acme-store" "$ws/tools/acme-metrics" "$ws/custom/env" \
    "$ws/custom/config/acme-web" "$fx"
  cp "$repo/scripts/run-tools.sh" "$repo/scripts/run-tools.py" "$ws/scripts/"
  : >"$fx/calls.log"
  export FAKE_FX="$fx" HOME="$work/home-$1" XDG_CONFIG_HOME="$work/home-$1/.config"
  unset FAKE_ENGINE FAKE_DPKG FAKE_UNAME FAKE_UP_RC FAKE_RUN_RC FAKE_STOP_RC STORE_KEY
  web_port="$(free_port)"
  store_port="$(free_port)"
  metrics_port="$(free_port)"
  cat >"$ws/tools/compose.yaml" <<'YAML'
# fictitious group
name: acme-tools
include:
  - acme-web/compose.yaml
  - path: acme-store/compose.yaml
  - "acme-metrics/compose.yaml"
YAML
  printf '{}\n' >"$ws/custom/config/acme-web/users.json"
  cat >"$fx/acme-web.json" <<JSON
{"name": "acme-web", "services": {"web": {"image": "acme/web:1.0", "build": {"context": "."},
 "ports": [{"host_ip": "127.0.0.1", "target": 8080, "published": "$web_port", "protocol": "tcp"}],
 "volumes": [{"type": "bind", "source": "$ws/custom/config/acme-web/users.json", "target": "/c.json"},
             {"type": "bind", "source": "$ws/tools/acme-web/.data", "target": "/data", "bind": {"create_host_path": true}}]}},
 "networks": {"default": {"name": "acme-web_default"}}}
JSON
  cat >"$fx/acme-web.yaml" <<YAML
name: acme-web
services:
  web:
    build:
      context: .
    x-run-tools:
      description: 'Fictitious web tool: it''s a test'
      title: "Acme \"web\""
      url: http://localhost:$web_port
networks:
  default:
    name: acme-web_default
YAML
  cat >"$fx/acme-store.json" <<JSON
{"name": "acme-store", "services": {
 "store": {"image": "acme/store:2.0@sha256:abc", "ports": [{"host_ip": "127.0.0.1", "target": 10000, "published": "$store_port"}],
           "volumes": [{"type": "volume", "source": "data", "target": "/data"}]},
 "app": {"build": {"context": "."}}},
 "volumes": {"data": {"name": "acme-store_data"}}}
JSON
  cat >"$fx/acme-store.yaml" <<'YAML'
name: acme-store
services:
  app:
    build:
      context: .
    x-run-tools:
      requires:
        - STORE_KEY
      title: Acme store
      url: http://localhost:1
  store:
    image: acme/store:2.0@sha256:abc
YAML
  cat >"$fx/acme-metrics.json" <<JSON
{"name": "acme-metrics", "services": {"metrics": {"image": "acme/metrics:3.0", "stop_grace_period": "45s",
 "ports": [{"host_ip": "127.0.0.1", "target": 3000, "published": "$metrics_port"}]}},
 "networks": {"metrics": {"name": "acme-metrics"}}}
JSON
  cat >"$fx/acme-metrics.yaml" <<'YAML'
name: acme-metrics
services:
  metrics:
    image: acme/metrics:3.0
    x-run-tools:
      title: Acme metrics
      url: http://localhost:2
YAML
}

# Writes the containers docker ps and inspect report: lines "<id> <project> <service> <running> <port> <image id>".
containers() {
  local id project service running port image first=1
  : >"$fx/ps"
  printf '[' >"$fx/inspect.json"
  while read -r id project service running port image; do
    [ -n "$id" ] || continue
    echo "$id" >>"$fx/ps"
    [ "$first" -eq 1 ] || printf ',' >>"$fx/inspect.json"
    first=0
    printf '{"Id": "%s", "Name": "/%s-%s-1", "Image": "%s", "State": {"Running": %s},
      "Config": {"Labels": {"com.docker.compose.project": "%s", "com.docker.compose.service": "%s"}},
      "NetworkSettings": {"Ports": {"80/tcp": [{"HostIp": "127.0.0.1", "HostPort": "%s"}]}}}' \
      "$id" "$project" "$service" "$image" "$running" "$project" "$service" "$port" >>"$fx/inspect.json"
  done
  printf ']\n' >>"$fx/inspect.json"
}

# Writes the inspect data of a network: name, compose project label, attached "<id>:<name>" pairs.
network() {
  local name="$1" project="$2" users="" pair
  shift 2
  for pair in "$@"; do
    users="${users:+$users, }\"${pair%%:*}\": {\"Name\": \"${pair#*:}\"}"
  done
  printf '[{"Name": "%s", "Labels": {"com.docker.compose.project": "%s"}, "Containers": {%s}}]\n' \
    "$name" "$project" "$users" >"$fx/net-$name.json"
}

# Runs run-tools.sh of the temp workspace with the arguments given.
run() {
  rc=0
  out="$(bash "$ws/scripts/run-tools.sh" "$@" 2>&1)" || rc=$?
}

# Prints field $2 of tool $1 from the last list --json output.
field() {
  printf '%s' "$out" | python3 -I -c 'import json, sys
tools = {t["id"]: t for t in json.load(sys.stdin)["tools"]}
value = tools.get(sys.argv[1], {}).get(sys.argv[2], "absent")
print(json.dumps(value) if isinstance(value, list) else value)' "$1" "$2"
}

make_bin

# Usage: help, no command, unknown command, bad ids, extra arguments.
fresh usage
run --help
ok "$rc" "--help: exit 0"
has "Usage: bash scripts/run-tools.sh"; ok $? "--help: prints the usage"
run
[ "$rc" -eq 2 ]; ok $? "no command: exit 2"
run start x
[ "$rc" -eq 2 ]; ok $? "unknown command: exit 2"
run up
[ "$rc" -eq 2 ]; ok $? "up without a tool: exit 2"
run up 'Bad;id'
[ "$rc" -eq 2 ]; ok $? "a malformed id: exit 2"
run list --yaml
[ "$rc" -eq 2 ]; ok $? "list with a bad option: exit 2"
run up acme-nothing
[ "$rc" -eq 2 ]; ok $? "a tool this machine does not list: exit 2"
has "not a tool of this machine: acme-nothing"; ok $? "names the unknown tool"

# The list: titles from x-run-tools (quoted YAML scalars included), kinds, states, ports, the include forms.
fresh list
run list --json
ok "$rc" "list --json: exit 0"
[ "$(printf '%s' "$out" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["group"])')" = acme-tools ]
ok $? "list: the group name comes from tools/compose.yaml"
[ "$(field acme-web title)" = 'Acme "web"' ]; ok $? "list: a double-quoted title"
[ "$(field acme-web description)" = "Fictitious web tool: it's a test" ]; ok $? "list: a single-quoted description"
[ "$(field acme-store kind)" = compose ]; ok $? "list: a path: include line is read"
[ "$(field acme-metrics state)" = stopped ]; ok $? "list: no container: stopped"
[ "$(field acme-web missing)" = "[]" ]; ok $? "list: acme-web has its configuration"
[ "$(field acme-web ports)" = "[$web_port]" ]; ok $? "list: the published port"
run status
ok "$rc" "status: exit 0"
has "| acme-web | compose | stopped |"; ok $? "status: a Markdown table"

# Missing configuration: a file of custom/config and a required variable; up refuses those and starts the rest.
fresh config
rm "$ws/custom/config/acme-web/users.json"
printf 'STORE_KEY=\n' >"$ws/custom/env/acme-store.env"
run list --json
field acme-web missing | grep -q "configuration missing: custom/config/acme-web/users.json"
ok $? "missing file: named relative to the root"
field acme-store missing | grep -q "configuration missing: STORE_KEY in custom/env/acme-store.env"
ok $? "empty required variable: named with its env file"
run up acme-web acme-store acme-metrics
[ "$rc" -eq 1 ]; ok $? "up with refused tools: exit 1"
has "refused: acme-web: configuration missing: custom/config/acme-web/users.json"; ok $? "up: acme-web refused with the reason"
has "refused: acme-store: configuration missing: STORE_KEY"; ok $? "up: acme-store refused with the reason"
logged "compose .*up -d --build --wait --wait-timeout [0-9]+ metrics$"; ok $? "up: only the services of acme-metrics start"
! logged "compose .*up .*(web|store|app)"; ok $? "up: the refused tools never reach compose up"
logged "compose --env-file $ws/custom/env/acme-store.env -f tools/compose.yaml up"; ok $? "up: the env files of custom/env are passed"
rm "$ws/custom/env/acme-store.env"
STORE_KEY=from-env run list --json
[ "$(field acme-store missing)" = "[]" ]; ok $? "a required variable set in the environment counts"
run list --json
field acme-store missing | grep -q "create it with /local-env tools/acme-store"; ok $? "no env file: says how to create it"
printf 'STORE_KEY=s3cr3t-value\n' >"$ws/custom/env/acme-store.env"
run list --json
[ "$(field acme-store missing)" = "[]" ]; ok $? "the variable in custom/env counts"
! has "s3cr3t-value"; ok $? "list never prints a value of an env file"

# Busy port: another process, another container; the tool's own container never makes its port busy.
fresh busy
python3 -I -c 'import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen()
time.sleep(60)' "$web_port" &
listener=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do python3 -I -c 'import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1)' "$web_port" 2>/dev/null && break; sleep 0.2; done
run list --json
field acme-web missing | grep -q "port $web_port busy: another process"; ok $? "busy port: another process"
run up acme-web
[ "$rc" -eq 1 ]; ok $? "busy port: up refuses"
has "refused: acme-web: port $web_port busy"; ok $? "busy port: the reason"
kill "$listener" 2>/dev/null
wait "$listener" 2>/dev/null
listener=""
containers <<EOF
c1 billing-api api true $metrics_port sha256:other
EOF
run list --json
field acme-metrics missing | grep -q "port $metrics_port busy: container billing-api-api-1"; ok $? "busy port: another container"
containers <<EOF
c2 acme-tools metrics true $metrics_port sha256:m1
EOF
run list --json
[ "$(field acme-metrics state)" = up ]; ok $? "own container: up"
[ "$(field acme-metrics missing)" = "[]" ]; ok $? "own container: its port is not busy"
[ "$(field acme-metrics project)" = acme-tools ]; ok $? "own container: in the group"

# Rollback tag: the running image of the group, else the local image; a first build says so; old stamps pruned.
fresh rollback
containers <<EOF
c2 acme-tools metrics true $metrics_port sha256:metrics-running
EOF
printf 'sha256:web-local\n' >"$fx/image-acme_web_1.0"
printf 'rollback-20260101-000000\nrollback-20260201-000000\nrollback-20260301-000000\nrollback-20260401-000000\nrollback-latest\n1.0\n' >"$fx/image-ls"
run up acme-metrics acme-web
ok "$rc" "rollback: exit 0"
logged "^docker tag sha256:metrics-running acme/metrics:rollback-latest$"; ok $? "rollback: the running image tagged rollback-latest"
logged "^docker tag sha256:metrics-running acme/metrics:rollback-[0-9]{8}-[0-9]{6}$"; ok $? "rollback: and a stamped tag"
logged "^docker tag sha256:web-local acme/web:rollback-latest$"; ok $? "rollback: an image with no container, from the local image"
logged "^docker image rm acme/web:rollback-20260101-000000$"; ok $? "rollback: the oldest stamp pruned"
! logged "^docker image rm acme/web:rollback-20260401-000000$"; ok $? "rollback: the newest stamps kept"
first_tag="$(grep -n '^docker tag ' "$fx/calls.log" | head -n 1 | cut -d: -f1)"
up_line="$(grep -n 'compose .* up ' "$fx/calls.log" | head -n 1 | cut -d: -f1)"
[ "$first_tag" -lt "$up_line" ]; ok $? "rollback: tagged before the build"
fresh firstbuild
STORE_KEY=k run up acme-store
has "first build of acme/store:2.0@sha256:abc: no checkpoint yet"; ok $? "rollback: a first build says so"
logged "^docker tag .* acme/store:rollback-latest$" && fail "first build: no tag expected"
ok 0 "rollback: a first build tags nothing"
has "| acme-store | compose |"; ok $? "up: ends with the table of the tools named"
! has "| acme-web |"; ok $? "up: the table lists only the tools named"

# Move from an old project: stop with the grace period, copy the named volume, remove the old containers and network.
fresh move
containers <<EOF
o2 acme-store app true 1 sha256:app-old
o1 acme-store store true $store_port sha256:store-old
o3 acme-metrics metrics true $metrics_port sha256:metrics-old
EOF
network acme-metrics acme-metrics o3:acme-metrics-metrics-1
touch "$fx/vol-acme-store_data"
STORE_KEY=k run list --json
[ "$(field acme-store project)" = acme-store ]; ok $? "move: list shows the old project"
[ "$(field acme-store state)" = up ]; ok $? "move: a tool up in its old project is up"
[ "$(field acme-store missing)" = "[]" ]; ok $? "move: its own old container does not make its port busy"
STORE_KEY=k run up acme-store acme-metrics
ok "$rc" "move: exit 0"
logged "^docker stop -t 45 o3$"; ok $? "move: stopped with the stop grace period"
logged "^docker volume create --label com.docker.compose.project=acme-tools --label com.docker.compose.volume=data acme-tools_data$"
ok $? "move: the group volume created with the compose labels"
logged "^docker run --rm --network none --entrypoint cp -v acme-store_data:/from:ro -v acme-tools_data:/to sha256:store-old -a /from/. /to/$"
ok $? "move: the data copied with the old image of the service that mounts the volume (regression: not the first one)"
logged "^docker rm o2 o1$"; ok $? "move: the old containers removed"
logged "^docker network rm acme-metrics$"; ok $? "move: the old fixed network removed"
! logged "volume rm acme-store_data"; ok $? "move: the old volume is never removed"
has "old volume kept: acme-store_data"; ok $? "move: says the old volume was kept"
stop_line="$(grep -n '^docker stop .*o1' "$fx/calls.log" | head -n 1 | cut -d: -f1)"
copy_line="$(grep -n '^docker run ' "$fx/calls.log" | head -n 1 | cut -d: -f1)"
rm_line="$(grep -n '^docker rm o2 o1' "$fx/calls.log" | head -n 1 | cut -d: -f1)"
[ "$stop_line" -lt "$copy_line" ] && [ "$copy_line" -lt "$rm_line" ]; ok $? "move: stop, then copy, then remove"

# Move refused: another stack still uses the fixed network; nothing changes.
fresh shared
containers <<EOF
o3 acme-metrics metrics true $metrics_port sha256:metrics-old
EOF
network acme-metrics acme-metrics o3:acme-metrics-metrics-1 x9:billing-api-api-1
run up acme-metrics
[ "$rc" -eq 1 ]; ok $? "shared network: exit 1"
has "network acme-metrics is also used by billing-api-api-1"; ok $? "shared network: names the other stack"
! logged "^docker (stop|rm|tag|network rm)"; ok $? "shared network: nothing stopped, tagged or removed"
! logged "compose .* up "; ok $? "shared network: compose up never runs"
network acme-metrics billing-api
run up acme-metrics
has "network acme-metrics belongs to project billing-api"; ok $? "a fixed network of another project: refused"

# Move with a failed copy: the new volume removed, the old containers started again, the tool not started.
fresh copyfail
containers <<EOF
o1 acme-store store true $store_port sha256:store-old
EOF
touch "$fx/vol-acme-store_data"
STORE_KEY=k FAKE_RUN_RC=1 run up acme-store
[ "$rc" -eq 1 ]; ok $? "failed copy: exit 1"
has "copying acme-store_data failed, so acme-store stays in acme-store"; ok $? "failed copy: the reason"
logged "^docker volume rm acme-tools_data$"; ok $? "failed copy: the new volume removed"
logged "^docker start o1$"; ok $? "failed copy: the old container started again"
! logged "^docker rm o1"; ok $? "failed copy: the old container kept"
! logged "compose .* up "; ok $? "failed copy: compose up never runs"

# Move refused: the volume exists under both names (regression: it started on the group's volume, data left behind).
fresh twovolumes
containers <<EOF
o1 acme-store store true $store_port sha256:store-old
EOF
touch "$fx/vol-acme-store_data" "$fx/vol-acme-tools_data"
STORE_KEY=k run up acme-store
[ "$rc" -eq 1 ]; ok $? "two volumes: exit 1"
has "both acme-store_data (where acme-store keeps its data) and acme-tools_data"; ok $? "two volumes: names both"
! logged "^docker (stop|rm|tag|run|volume (create|rm))"; ok $? "two volumes: nothing changed"
! logged "compose .* up "; ok $? "two volumes: compose up never runs"
containers <<EOF
c1 acme-tools store false $store_port sha256:store-new
EOF
: >"$fx/calls.log"
STORE_KEY=k run up acme-store
ok "$rc" "already in the group, old volume kept: up goes on"
! logged "^docker (run|volume create)"; ok $? "already in the group: nothing copied again"

# Compose up failing: exit 1 and the way back.
fresh upfail
FAKE_UP_RC=1 run up acme-metrics
[ "$rc" -eq 1 ]; ok $? "compose up fails: exit 1"
has "rollback-latest"; ok $? "compose up fails: says where the previous images are"

# Down: compose stop only (no rm, no -v), the old project's container stopped, never a volume.
fresh down
containers <<EOF
o3 acme-metrics metrics true $metrics_port sha256:metrics-old
c1 acme-tools web true $web_port sha256:web
EOF
touch "$fx/vol-acme-store_data"
run down acme-web acme-metrics
ok "$rc" "down: exit 0"
logged "compose .*-f tools/compose.yaml stop web metrics$"; ok $? "down: compose stop of the services named"
logged "^docker stop o3$"; ok $? "down: a container of the old project stopped"
! logged "compose .* (down|rm)|volume rm|docker rm |image rm|-v"; ok $? "down: never removes a container, volume or image"
[ -e "$fx/vol-acme-store_data" ]; ok $? "down: the volume is still there"

# Console detection: Docker CE on Linux, by docker version or by the package; Colima on macOS; none.
fresh detect
FAKE_ENGINE="Docker Engine - Community" run list --json
[ "$(field container-console-docker-ce kind)" = machine ]; ok $? "Docker CE (docker version): the docker-ce console shows"
[ "$(field container-console-colima kind)" = absent ]; ok $? "Docker CE: the Colima console does not"
[ "$(field container-console-docker-ce state)" = "not installed" ]; ok $? "Docker CE: not installed"
FAKE_DPKG=1 run list --json
[ "$(field container-console-docker-ce kind)" = machine ]; ok $? "Docker CE (package): the docker-ce console shows"
FAKE_ENGINE="Docker Desktop" run list --json
[ "$(field container-console-docker-ce kind)" = absent ]; ok $? "another engine on Linux: no console"
printf '#!/usr/bin/env bash\nexit 0\n' >"$work/bin/colima"
chmod +x "$work/bin/colima"
FAKE_UNAME=Darwin FAKE_ENGINE="Docker Engine - Community" run list --json
[ "$(field container-console-colima kind)" = machine ]; ok $? "macOS with colima: the Colima console shows"
[ "$(field container-console-docker-ce kind)" = absent ]; ok $? "macOS: the docker-ce console does not"
rm "$work/bin/colima"
FAKE_UNAME=Darwin run list --json
[ "$(field container-console-colima kind)" = absent ]; ok $? "macOS without colima: no console"

# Console up and down: installed with make when missing, started with systemctl when installed, stopped on down.
fresh console
export FAKE_ENGINE="Docker Engine - Community"
run up container-console-docker-ce
ok "$rc" "console not installed: exit 0"
logged "^make -C tools/container-console-docker-ce install$"; ok $? "console not installed: make install"
has "| container-console-docker-ce | machine | up |"; ok $? "console: up in the table"
run down container-console-docker-ce
logged "^systemctl --user stop container-console-docker-ce.service$"; ok $? "console down: systemctl stop"
run up container-console-docker-ce
logged "^systemctl --user start container-console-docker-ce.service$"; ok $? "console installed: systemctl start"
unset FAKE_ENGINE

# Without docker: every container tool says so.
fresh nodocker
mv "$work/bin/docker" "$work/docker.off"
run list --json
mv "$work/docker.off" "$work/bin/docker"
ok "$rc" "no docker: list still works"
[ "$(field acme-web missing)" = '["docker not found"]' ]; ok $? "no docker: the reason"

# The real tools/compose.yaml: its group name and the four container tools, read through the fake compose.
fresh real
cp "$repo/tools/compose.yaml" "$ws/tools/compose.yaml"
printf '{"name": "@TOOL@", "services": {"main": {"image": "acme/x:1"}}}\n' >"$fx/default.json"
printf 'name: @TOOL@\nservices:\n  main:\n    x-run-tools:\n      title: T\n' >"$fx/default.yaml"
run list --json
ok "$rc" "real group file: exit 0"
[ "$(printf '%s' "$out" | python3 -I -c 'import json, sys; d = json.load(sys.stdin); print(d["group"], *[t["id"] for t in d["tools"]])')" = \
  "claude-cli-agents-tools observability login-simulator safe-browsing-simulator azurite-console" ]
ok $? "real group file: the group and its four tools"
for t in observability login-simulator safe-browsing-simulator azurite-console; do
  grep -q '^    x-run-tools:' "$repo/tools/$t/compose.yaml"; ok $? "real $t: has an x-run-tools block"
done

echo "suite ok: run-tools ($passed checks)"
