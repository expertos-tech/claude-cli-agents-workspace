"""The Docker copy of a task: the work behind aiwp-cmds.sh up, down, status, close and the merge of the gate.

A task's copy runs in its own compose project, an agent_<MMDD>-<slug> group, from the clone's compose files and an
override file written outside the clone's tracked tree: built services get the group's own image names, fixed
container, network and volume names are reset, and every published host port becomes a random free port in
61000-65535. The project's compose files never change. A group is destroyed only by its compose label and only when
its name matches GROUP_RE. Everything goes through the docker command on PATH, so the tests replace it with a fake.

Usage: python3 -I agent-copy.py up <group> <folder> <override> [--fallback <group>] [--env-file <file>]...
                                   [--custom-root <dir>] [--allow-root <dir>]... [-- <docker compose options>...]
--allow-root: a folder the copy may read besides <folder> (binds, build context, env files, secret and config files);
repeated. Without it: <folder> and AIWP_CUSTOM_DIR. What would undo the copy's isolation is refused before anything
starts; a service setting that only polices the person's compose (a key off SERVICE_KEYS, security_opt, a host
namespace...) prints one WARNING line per service and the copy starts; the override labels each service
com.aiwp.copy.safe=true, or false for a service it warned about (guard-bash then never auto-allows exec in it).
       python3 -I agent-copy.py down <group>
       python3 -I agent-copy.py destroy [--under <path>]... [<group>...]
       python3 -I agent-copy.py list [--under <path>]... [--group <group>]...
       python3 -I agent-copy.py deploy-binds <project> <checkout> <repo> <override> <workspace> [-- <options>...]
       python3 -I agent-copy.py bound-under <path>
deploy-binds (aiwp-cmds.sh deploy main): every relative bind, secret file and config file of the stack (as the compose
files wrote it: in the checkout of main, or above it through .., at any depth) is taken from the same relative path of
the repo instead (its data stays there, and the checkout can go); one that leaves the workspace is refused; under a
path either side tracks, a file that differs, or exists on one side only (tracked, or not ignored in the repo), is
refused. Prints the compose options to use, one per line; the compose files are those compose would read
(COMPOSE_FILE of the environment, of --env-file or of the checkout's .env).
bound-under: prints each container with a mount under the path (exit 0), none (exit 1).
Exit: 0 ok; 1 refused or failed; 2 usage error; 3 (list, bound-under) Docker not reachable.
"""

import filecmp
import json
import os
import random
import re
import socket
import subprocess
import sys

GROUP_RE = re.compile(r'^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$')
PROJECT_LABEL = 'com.docker.compose.project'
WORKDIR_LABEL = 'com.docker.compose.project.working_dir'
SERVICE_LABEL = 'com.docker.compose.service'
PORT_MIN, PORT_MAX = 61000, 65535
PICK_ATTEMPTS = 400
DEFAULT_FILES = ('compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml')
CUSTOM_DIR_VAR = 'AIWP_CUSTOM_DIR'
# The one network of a copy that reaches outside Docker: only the services that publish a port join it. Every other
# network of the copy is internal. Its name is <group>_edge, created by compose with the group's labels.
EDGE_KEY = 'agent-edge'
# The label the override writes on every service of a copy: "true" when up judged it safe (no WARNING), "false" when
# it warned about it. guard-bash auto-allows exec only into a container labeled "true"; the override always sets it,
# so a value from the compose files or the image never stands.
SAFE_LABEL = 'com.aiwp.copy.safe'
# An internal bridge still answers on its gateway, which is the host: the copy's internal networks have none.
ISOLATED_GATEWAY = (
    'com.docker.network.bridge.gateway_mode_ipv4',
    'com.docker.network.bridge.gateway_mode_ipv6',
)
MIN_ENGINE = 28
RUNTIME_SOCKETS = ('docker.sock', 'containerd.sock', 'podman.sock', 'crio.sock', 'dockershim.sock', 'cri-dockerd.sock')
HOST_PORT = re.compile(r':(\d+)->')


class Refused(Exception):
    """A step that cannot run, with the message for the person."""


def run(args, cwd=None, env=None, timeout=120):
    """Runs a command and returns (exit code, stdout, stderr); 127 when it is not on PATH, 124 on a timeout."""
    try:
        done = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout, check=False)
    except FileNotFoundError:
        return 127, '', f'{args[0]} not found'
    except subprocess.TimeoutExpired:
        return 124, '', f'{args[0]} timed out'
    return done.returncode, done.stdout, done.stderr


def run_live(args, cwd=None, env=None):
    """Runs a command with its output on this terminal; returns its exit code (127 when it is not on PATH)."""
    try:
        return subprocess.run(args, cwd=cwd, env=env, check=False).returncode
    except FileNotFoundError:
        return 127


def first_line(text):
    """Returns the first non-empty line of a text, or an empty string."""
    for line in (text or '').splitlines():
        if line.strip():
            return line.strip()
    return ''


def load_json(text, what):
    """Returns the JSON of a command's output, or raises Refused naming the command."""
    try:
        return json.loads(text)
    except ValueError as error:
        raise Refused(f'{what} gave no JSON: {first_line(text) or "empty output"}') from error


def valid_group(name):
    """Returns True when a name is a task's group: agent_<MMDD>-<slug>, nothing else."""
    return bool(GROUP_RE.match(name or ''))


def inside(path, folder):
    """Returns True when a path is the folder or lies under it (both normalized, never resolved)."""
    path, folder = os.path.normpath(path), os.path.normpath(folder)
    return path == folder or path.startswith(folder.rstrip(os.sep) + os.sep)


def docker_ok():
    """Returns True when the Docker daemon answers."""
    return run(['docker', 'version', '--format', '{{.Server.Version}}'], timeout=20)[0] == 0


def engine_major():
    """Returns the major version of the Docker Engine, 0 when it cannot be read."""
    code, out, _ = run(['docker', 'version', '--format', '{{.Server.Version}}'], timeout=20)
    found = re.match(r'\s*(\d+)\.', out) if code == 0 else None
    return int(found.group(1)) if found else 0


def containers(label):
    """Returns the containers that carry a label filter (key or key=value): id, project, folder, running, ports."""
    code, out, _ = run(['docker', 'ps', '-aq', '--filter', f'label={label}'])
    ids = out.split() if code == 0 else []
    if not ids:
        return []
    code, out, _ = run(['docker', 'inspect', *ids])
    if code != 0:
        return []
    found = []
    for item in load_json(out, 'docker inspect'):
        labels = (item.get('Config') or {}).get('Labels') or {}
        ports = []
        for key, binds in ((item.get('NetworkSettings') or {}).get('Ports') or {}).items():
            for bind in binds or []:
                if bind.get('HostPort'):
                    ports.append((key, int(bind['HostPort'])))
        found.append(
            {
                'id': item.get('Id', ''),
                'project': labels.get(PROJECT_LABEL, ''),
                'folder': labels.get(WORKDIR_LABEL, ''),
                'service': labels.get(SERVICE_LABEL, ''),
                'running': bool((item.get('State') or {}).get('Running')),
                'ports': sorted(set(ports)),
                'networks': sorted(((item.get('NetworkSettings') or {}).get('Networks') or {}).keys()),
            }
        )
    return found


def read_dotenv(path):
    """Reads the KEY=VALUE lines of an env file as docker compose does for its own variables (comments, export and
    quotes stripped); a missing file is empty. Never prints a value."""
    values = {}
    try:
        with open(path, encoding='utf-8') as handle:
            lines = handle.read().splitlines()
    except OSError:
        return values
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key, value = key.strip().removeprefix('export ').strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
            value = value[1:-1]
        values[key] = value
    return values


def compose_environ(folder, env_files, environ):
    """Returns the variables docker compose reads its own settings from (COMPOSE_FILE, COMPOSE_PATH_SEPARATOR): the
    --env-file files given, else the folder's .env, under the process environment, which wins."""
    merged = {}
    for path in env_files or [os.path.join(folder, '.env')]:
        merged.update(read_dotenv(path if os.path.isabs(path) else os.path.join(folder, path)))
    merged.update(environ)
    return merged


def split_compose_options(folder, options, environ, env_files=()):
    """Returns (compose files, other options) of the options given after --; the default files when none is named,
    COMPOSE_FILE read as compose reads it (compose_environ, with env_files and the --env-file options).

    The project name is this script's: -p and --project-name are refused.
    """
    files, rest, i, dotenvs = [], [], 0, list(env_files)
    while i < len(options):
        arg = options[i]
        if arg.startswith(('-p', '--project-name')):
            raise Refused('the group is the project name of a copy: drop -p/--project-name')
        if arg == '--env-file' and i + 1 < len(options):
            dotenvs.append(options[i + 1])
        elif arg.startswith('--env-file='):
            dotenvs.append(arg.split('=', 1)[1])
        if arg in ('-f', '--file'):
            if i + 1 >= len(options):
                raise Refused(f'{arg} needs a file')
            files.append(options[i + 1])
            i += 2
            continue
        if arg.startswith('--file='):
            files.append(arg.split('=', 1)[1])
        else:
            rest.append(arg)
        i += 1
    if not files:
        files = default_files(folder, compose_environ(folder, dotenvs, environ))
    return files, rest


def default_files(folder, environ):
    """Returns the compose files docker compose would read in a folder: COMPOSE_FILE, else the first default name with
    its .override file; none is a refusal (this script never looks in the folders above)."""
    if environ.get('COMPOSE_FILE'):
        separator = environ.get('COMPOSE_PATH_SEPARATOR') or os.pathsep
        return [item for item in environ['COMPOSE_FILE'].split(separator) if item]
    for name in DEFAULT_FILES:
        if os.path.isfile(os.path.join(folder, name)):
            stem, ext = os.path.splitext(name)
            extra = f'{stem}.override{ext}'
            return [name] + ([extra] if os.path.isfile(os.path.join(folder, extra)) else [])
    raise Refused(f'no compose file in {folder} (compose.yaml, docker-compose.yml...): name one with -- -f <file>')


def ports_path(override):
    """Returns the ports file next to an override file: agent-x.compose.yaml -> agent-x.ports.env."""
    suffix = '.compose.yaml'
    return (override[: -len(suffix)] if override.endswith(suffix) else override) + '.ports.env'


def read_ports_env(path):
    """Reads the KEY=VALUE lines of a ports file; a missing file is empty."""
    values = {}
    try:
        with open(path, encoding='utf-8') as handle:
            lines = handle.read().splitlines()
    except OSError:
        return values
    for line in lines:
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    return values


def variable(service, target, protocol, taken):
    """Returns the variable that carries a host port: AGENT_PORT_<SERVICE>_<TARGET>[_UDP], unique in taken."""
    name = f'AGENT_PORT_{re.sub(r"[^A-Z0-9]", "_", service.upper())}_{target}'
    if protocol and protocol != 'tcp':
        name += f'_{protocol.upper()}'
    unique, n = name, 2
    while unique in taken:
        unique, n = f'{name}_{n}', n + 1
    taken.add(unique)
    return unique


def port_entries(config):
    """Returns one entry per published port of the services: service, target, protocol, host_ip, variable."""
    entries, taken = [], set()
    for service, spec in sorted((config.get('services') or {}).items()):
        for port in spec.get('ports') or []:
            protocol = port.get('protocol') or 'tcp'
            target = int(str(port.get('target')).split('-')[0])
            entries.append(
                {
                    'service': service,
                    'target': target,
                    'protocol': protocol,
                    'host_ip': port.get('host_ip') or '',
                    'variable': variable(service, target, protocol, taken),
                }
            )
    return entries


def proc_ports():
    """Returns the (protocol, port) pairs in use on Linux: TCP in LISTEN and every bound UDP port, from /proc/net."""
    used = set()
    for name, protocol in (('tcp', 'tcp'), ('tcp6', 'tcp'), ('udp', 'udp'), ('udp6', 'udp')):
        try:
            with open(f'/proc/net/{name}', encoding='ascii') as handle:
                lines = handle.read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 3 and (protocol == 'udp' or fields[3] == '0A'):
                used.add((protocol, int(fields[1].rsplit(':', 1)[1], 16)))
    return used


def docker_ports():
    """Returns the host ports every container publishes now (a published port is not always a listening socket)."""
    code, out, _ = run(['docker', 'ps', '--format', '{{.Ports}}'])
    return {int(port) for port in HOST_PORT.findall(out)} if code == 0 else set()


def bind_free(port, protocol):
    """Returns True when a socket of the protocol can bind the port on every IPv4 and IPv6 address."""
    kind = socket.SOCK_DGRAM if protocol == 'udp' else socket.SOCK_STREAM
    for family, address in ((socket.AF_INET, '0.0.0.0'), (socket.AF_INET6, '::')):
        try:
            sock = socket.socket(family, kind)
        except OSError:
            continue
        try:
            sock.bind((address, port))
        except OSError:
            return False
        finally:
            sock.close()
    return True


def free_checker(own):
    """Returns is_free(port, protocol): not published by a container (but the group's own), not in /proc/net (Linux;
    elsewhere only the bind), and bindable. A port of the group's own containers counts as free for it."""
    published = docker_ports() - own
    listening = proc_ports()

    def is_free(port, protocol):
        """Returns True when the copy may publish the port."""
        if port in own:
            return True
        if port in published or (protocol, port) in listening:
            return False
        return bind_free(port, protocol)

    return is_free


def pick_ports(entries, previous, is_free, rng=None):
    """Returns {variable: host port} in PORT_MIN..PORT_MAX: the port of the last run when still free, else a random
    free one; no port twice."""
    rng = rng or random.SystemRandom()
    chosen, taken = {}, set()
    for entry in entries:
        old = previous.get(entry['variable'], '')
        if old.isdigit() and PORT_MIN <= int(old) <= PORT_MAX and int(old) not in taken:
            if is_free(int(old), entry['protocol']):
                chosen[entry['variable']] = int(old)
                taken.add(int(old))
                continue
        for _ in range(PICK_ATTEMPTS):
            port = rng.randint(PORT_MIN, PORT_MAX)
            if port not in taken and is_free(port, entry['protocol']):
                chosen[entry['variable']] = port
                taken.add(port)
                break
        else:
            raise Refused(f'no free port in {PORT_MIN}-{PORT_MAX} for {entry["service"]} {entry["target"]}')
    return chosen


def q(value):
    """Returns a value as a YAML double-quoted scalar (a JSON string is one)."""
    return json.dumps(str(value))


# The allowlist of a copy: what its compose files may hold. What would undo the copy's isolation (its internal networks,
# its group's labels, no gateway to the host, nothing read from outside the clone) is refused, named, before anything
# starts; what only polices the person's own services (a service key off SERVICE_KEYS, a security_opt, a host
# namespace, a deploy key off DEPLOY_KEYS, an extra host on host-gateway) is a WARNING and the copy starts.
TOP_KEYS = {'name', 'services', 'networks', 'volumes', 'secrets', 'configs'}
SERVICE_KEYS = {
    'image', 'build', 'command', 'entrypoint', 'environment', 'env_file', 'ports', 'expose', 'volumes', 'tmpfs',
    'depends_on', 'healthcheck', 'restart', 'working_dir', 'user', 'labels', 'networks', 'secrets', 'configs',
    'read_only', 'cap_drop', 'security_opt', 'init', 'stop_signal', 'stop_grace_period', 'logging', 'deploy',
    'ulimits', 'shm_size', 'profiles', 'extra_hosts', 'hostname', 'domainname', 'container_name', 'pid', 'ipc', 'uts',
    'cgroup', 'network_mode',
    # Limits, the extra groups of the container user, a terminal, the pull policy and the platform: nothing of the host.
    'cpus', 'cpu_shares', 'mem_limit', 'mem_reservation', 'memswap_limit', 'pids_limit', 'group_add', 'stdin_open',
    'tty', 'pull_policy', 'platform',
    # Names and lifecycle of the service itself: links between its own services, DNS settings, compose watch, hooks.
    'links', 'dns', 'dns_search', 'develop', 'post_start', 'pre_stop',
}  # fmt: skip
BUILD_KEYS = {
    'context', 'dockerfile', 'args', 'target', 'cache_from', 'tags', 'labels', 'pull', 'no_cache', 'platforms',
    'dockerfile_inline',
}  # fmt: skip
DEPLOY_KEYS = {'resources', 'replicas', 'restart_policy', 'update_config'}
# The modes of pid, ipc, uts and cgroup a copy may set besides service:<x> of the same files: none reaches the host.
PRIVATE_MODES = {'ipc': {'private', 'shareable'}, 'cgroup': {'private'}}
NETWORK_KEYS = {'name', 'ipam', 'internal', 'driver', 'labels', 'enable_ipv6', 'attachable'}
VOLUME_KEYS = {'name', 'driver', 'labels'}
FILE_KEYS = {'name', 'file', 'environment', 'content'}
SECURITY_OPTS = {'no-new-privileges', 'no-new-privileges:true', 'no-new-privileges=true'}
LOG_DRIVERS = {'', 'json-file', 'local', 'none'}


def extension(key):
    """Returns True for an x-* extension key, which compose itself ignores."""
    return str(key).startswith('x-')


def unknown_keys(where, spec, allowed):
    """Returns a refusal for each key of a mapping that is not allowed (x-* extensions pass)."""
    return [f'{where} sets {key}' for key in sorted(spec or {}) if key not in allowed and not extension(key)]


def socket_path(path):
    """Returns True when a path names a container runtime socket."""
    return os.path.basename(str(path or '').rstrip('/')) in RUNTIME_SOCKETS


def path_refusal(what, path, roots):
    """Returns why a host path may not be read by a copy (a runtime socket, or outside every allowed root after
    following links), or an empty string."""
    if socket_path(path):
        return f'{what} {path}: a container runtime socket, never in a copy'
    real = os.path.realpath(path)
    if any(inside(real, os.path.realpath(root)) for root in roots if root):
        return ''
    return f'{what} {path}, outside the clone'


def build_refusals(service, build, roots):
    """Returns why a service's build may not run in a copy: a key off BUILD_KEYS (network, ssh, secrets,
    additional_contexts, entitlements, privileged...), a remote context, a context or Dockerfile outside the roots."""
    if not isinstance(build, dict):
        return [f'service {service} has a build that is not a mapping']
    refusals = unknown_keys(f'service {service} build', build, BUILD_KEYS)
    context = str(build.get('context') or '')
    if '://' in context or context.startswith('git@') or not os.path.isabs(context):
        return [*refusals, f'service {service} builds from {context or "no context"}: only a folder of the clone']
    for what, path in (('a context', context), ('a Dockerfile', os.path.join(context, build.get('dockerfile') or ''))):
        why = path_refusal(f'service {service} builds from {what}', path, roots)
        if why:
            refusals.append(why)
    return refusals


def mount_refusals(service, spec, volumes, roots, remap):
    """Returns why a service's mounts may not run in a copy: a bind outside the roots (remap: where a configuration
    bind is really read from) or of a runtime socket, a volume the file does not declare, another kind of mount."""
    refusals = []
    for mount in spec.get('volumes') or []:
        kind, source = mount.get('type'), mount.get('source') or ''
        if socket_path(mount.get('target')):
            refusals.append(
                f'service {service} mounts {mount.get("target")}: a container runtime socket, never in a copy'
            )
        elif kind == 'bind':
            why = path_refusal(f'service {service} binds', remap(source), roots)
            if why:
                refusals.append(why)
        elif kind == 'volume':
            if source and source not in volumes:
                refusals.append(f'service {service} mounts the volume {source}, which the compose files do not declare')
        elif kind != 'tmpfs':
            refusals.append(f'service {service} mounts a {kind} mount')
    return refusals


def own_mode(key, value, services):
    """Returns True when a namespace or network mode keeps the service to the copy: unset, a mode of PRIVATE_MODES, or
    service:<x> of the same files."""
    value = str(value or '')
    return (
        not value
        or value in PRIVATE_MODES.get(key, ())
        or (value.startswith('service:') and value.split(':', 1)[1] in services)
    )


def option_refusals(service, spec, services):
    """Returns why a service's options would undo the copy's isolation: a network_mode that is not service:<x> of the
    files (host, bridge, none, another container: off the copy's internal networks), the volumes of a container
    outside the files (another stack's data), a log driver that sends the logs off the machine."""
    refusals = []
    if not own_mode('network_mode', spec.get('network_mode'), services):
        refusals.append(
            f'service {service} sets network_mode {spec["network_mode"]}: only service:<x> of the same files'
        )
    for item in spec.get('volumes_from') or []:
        source = str(item)
        name = source.split(':', 2)[1] if source.startswith('container:') else source.split(':', 1)[0]
        if source.startswith('container:') or name not in services:
            refusals.append(f'service {service} takes the volumes of {source}, outside the compose files')
    driver = (spec.get('logging') or {}).get('driver') or ''
    if driver not in LOG_DRIVERS:
        refusals.append(f'service {service} logs through {driver}')
    return refusals


def service_warnings(spec, services):
    """Returns (what may reach the host, what is only unusual) of a service's settings that a copy runs as they are:
    a key off SERVICE_KEYS (privileged, cap_add, devices, volumes_from, sysctls...), a security_opt other than
    no-new-privileges, a pid, ipc, uts or cgroup namespace that is not the copy's own, reserved devices; a deploy key
    off DEPLOY_KEYS, an extra host on host-gateway."""
    reach, unusual = [f'{key}' for key in sorted(spec) if key not in SERVICE_KEYS and not extension(key)], []
    reach += [f'security_opt {option}' for option in spec.get('security_opt') or [] if option not in SECURITY_OPTS]
    for key in ('pid', 'ipc', 'uts', 'cgroup'):
        if not own_mode(key, spec.get(key), services):
            reach.append(f'{key} {spec[key]}')
    deploy = spec.get('deploy') or {}
    if ((deploy.get('resources') or {}).get('reservations') or {}).get('devices'):
        reach.append('deploy reserved devices')
    unusual += [f'deploy {key}' for key in sorted(deploy) if key not in DEPLOY_KEYS and not extension(key)]
    hosts = spec.get('extra_hosts') or []
    values = hosts.values() if isinstance(hosts, dict) else hosts
    if any('host-gateway' in str(value) for value in values):
        unusual.append('an extra host on host-gateway')
    return reach, unusual


def copy_warnings(config):
    """Returns {service: its WARNING line (rules/security.md "Warnings")} for each service whose settings a copy runs
    as they are, though they are off its safe list (service_warnings): the copy starts, the person decides, and the
    override labels the service SAFE_LABEL=false, so guard-bash never auto-allows a command in it."""
    services = config.get('services') or {}
    found = {}
    for service, spec in sorted(services.items()):
        reach, unusual = service_warnings(spec, services)
        if not reach and not unusual:
            continue
        if reach:
            why = "such a container may reach the host past the copy's internal networks"
        else:
            why = (
                'compose outside a swarm ignores such a deploy key, and host-gateway reaches the host only from a '
                'service that publishes a port'
            )
        found[service] = (
            f'WARNING: service {service} sets {", ".join(reach + unusual)}, off the safe list of a copy — {why}; '
            f'guard-bash auto-allows a command only in a container up labeled {SAFE_LABEL}=true, so exec in {service} '
            'falls back to the permission mode — the copy starts; remove them from the compose files if the copy '
            'does not need them'
        )
    return found


def isolation_refusals(config, roots=(), remap=lambda path: path):
    """Returns why the copy cannot run isolated, each named, from an allowlist: only the keys of TOP_KEYS,
    BUILD_KEYS, NETWORK_KEYS, VOLUME_KEYS and FILE_KEYS (and x-* extensions), only bridge networks, local volumes with
    no options, files and binds inside the roots (the clone and the folders the caller allows; links followed), env
    files inside them, no runtime socket, and the options option_refusals allows. Nothing external. A service key off
    SERVICE_KEYS and the other settings of service_warnings are not refused: copy_warnings names them."""
    refusals = unknown_keys('the compose files', config, TOP_KEYS)
    services = config.get('services') or {}
    volumes = config.get('volumes') or {}
    for key, spec in sorted((config.get('networks') or {}).items()):
        spec = spec or {}
        refusals += unknown_keys(f'network {key}', spec, NETWORK_KEYS)
        if (spec.get('driver') or 'bridge') != 'bridge':
            refusals.append(
                f'network {key} uses the driver {spec["driver"]}: only a bridge network can be kept off the host'
            )
    if EDGE_KEY in (config.get('networks') or {}):
        refusals.append(f"network {EDGE_KEY} is the key of the copy's own edge network: rename it in the project")
    for key, spec in sorted(volumes.items()):
        spec = spec or {}
        refusals += unknown_keys(f'volume {key}', spec, VOLUME_KEYS)
        if (spec.get('driver') or 'local') != 'local':
            refusals.append(f'volume {key} uses the driver {spec["driver"]}')
    for kind in ('secrets', 'configs'):
        for key, spec in sorted((config.get(kind) or {}).items()):
            spec = spec or {}
            refusals += unknown_keys(f'{kind[:-1]} {key}', spec, FILE_KEYS)
            if spec.get('file'):
                why = path_refusal(f'{kind[:-1]} {key} reads', remap(spec['file']), roots)
                if why:
                    refusals.append(why)
    for service, spec in sorted(services.items()):
        if 'build' in spec:
            refusals += build_refusals(service, spec['build'], roots)
        for item in spec.get('env_file') or []:
            path = item.get('path') if isinstance(item, dict) else item
            why = path_refusal(f'service {service} reads the env file', str(path or ''), roots)
            if why:
                refusals.append(why)
        refusals += mount_refusals(service, spec, volumes, roots, remap)
        refusals += option_refusals(service, spec, services)
    return refusals


def custom_dir():
    """Returns the folder AIWP_CUSTOM_DIR names (real path), or '' when it is not set; a missing folder is refused."""
    value = os.environ.get(CUSTOM_DIR_VAR, '')
    if not value:
        return ''
    if not os.path.isdir(value):
        raise Refused(f'{CUSTOM_DIR_VAR} is not a folder: {value}')
    return os.path.realpath(value)


def remapped_volumes(spec, custom_root, custom):
    """Returns the bind mounts of a service whose source lies under custom_root, moved under custom."""
    moved = []
    if not (custom_root and custom):
        return moved
    for mount in spec.get('volumes') or []:
        source = mount.get('source') or ''
        if mount.get('type') == 'bind' and source and inside(source, custom_root):
            rest = os.path.relpath(os.path.normpath(source), os.path.normpath(custom_root))
            moved.append({**mount, 'source': os.path.normpath(os.path.join(custom, rest))})
    return moved


def fixed_addresses(config):
    """Returns (the fixed addresses a copy drops: the services' ipv4_address and ipv6_address, the subnets, ranges
    and gateways of the networks' ipam.config; the attention lines for each environment value or extra host of a
    service that still names one of them). A copy cannot keep them: the final stack holds the same subnet."""
    dropped = set()
    for spec in (config.get('services') or {}).values():
        for attach in (spec.get('networks') or {}).values():
            for key in ('ipv4_address', 'ipv6_address'):
                if (attach or {}).get(key):
                    dropped.add(str(attach[key]))
    for spec in (config.get('networks') or {}).values():
        for block in ((spec or {}).get('ipam') or {}).get('config') or []:
            for key in ('subnet', 'ip_range', 'gateway'):
                if (block or {}).get(key):
                    dropped.add(str(block[key]))
    notes = []
    for service, spec in sorted((config.get('services') or {}).items()):
        values = [f'{k}={v}' for k, v in sorted((spec.get('environment') or {}).items())]
        values += [f'extra host {h}' for h in spec.get('extra_hosts') or []]
        for value in values:
            for address in sorted(dropped):
                host = address.split('/', 1)[0]
                if host and host in str(value):
                    notes.append(f'{service}: {value} names {host}, a fixed address the copy does not have')
                    break
    return dropped, notes


def service_networks(spec):
    """Returns the networks a service joins: its networks, else (no network_mode) the implicit default one."""
    if spec.get('network_mode'):
        return {}
    return spec.get('networks') or {'default': None}


def edge_services(config, entries):
    """Returns the services that join <group>_edge: those that publish a port and have their own networks (not a
    network_mode)."""
    services = config.get('services') or {}
    return {e['service'] for e in entries if not (services.get(e['service']) or {}).get('network_mode')}


def network_roles(config, entries):
    """Returns {service: 'edge', 'internal' or 'shares <service>'} of a copy, as up prints it."""
    edge = edge_services(config, entries)
    roles = {}
    for service, spec in sorted((config.get('services') or {}).items()):
        mode = spec.get('network_mode') or ''
        if mode.startswith('service:'):
            roles[service] = f'shares {mode.split(":", 1)[1]}'
        elif mode:
            roles[service] = mode
        else:
            roles[service] = 'edge' if service in edge else 'internal'
    return roles


def build_override(config, group, entries, ports, custom_root='', custom='', unsafe=()):
    """Returns the text of the override file of a copy: the group's name, the image of each built service (and of a
    service that runs that image) with no extra build tag, no fixed container name, the ports moved, the port
    variables in every service, the configuration binds moved to AIWP_CUSTOM_DIR, no fixed network or volume name, and
    no fixed address (a service's ipv4_address or ipv6_address, a network's ipam.config subnet). Every network of the
    copy is internal (no way out of Docker); a service that publishes a port also joins <group>_edge (edge_services),
    the one network that is not, so the host reaches its port. Aliases and service names keep resolving. Every service
    carries SAFE_LABEL: "false" for the services in unsafe (those up warned about), "true" for the others."""
    services = config.get('services') or {}
    edge = edge_services(config, entries)
    renamed = {}
    for service, spec in services.items():
        if 'build' in spec:
            new = f'{group}-{service}'.lower()
            if spec.get('image'):
                renamed[spec['image']] = new
    variables = {'AGENT_GROUP': group, **{key: str(value) for key, value in sorted(ports.items())}}
    lines = [
        '# Written by agent-copy.py: the task copy in its own group. Never committed; the compose files do not change.',
        f'name: {q(group)}',
        'services:',
    ]
    for service, spec in sorted(services.items()):
        lines.append(f'  {q(service)}:')
        if 'build' in spec:
            lines.append(f'    image: {q(f"{group}-{service}".lower())}')
            if (spec.get('build') or {}).get('tags'):
                lines += ['    build:', '      tags: !reset []']
        elif spec.get('image') in renamed:
            lines.append(f'    image: {q(renamed[spec["image"]])}')
        if spec.get('container_name'):
            lines.append('    container_name: !reset null')
        mine = [entry for entry in entries if entry['service'] == service]
        if mine:
            lines.append('    ports: !override')
            for entry in mine:
                lines.append(f'      - target: {entry["target"]}')
                lines.append(f'        published: {q(ports[entry["variable"]])}')
                if entry['host_ip']:
                    lines.append(f'        host_ip: {q(entry["host_ip"])}')
                lines.append(f'        protocol: {q(entry["protocol"])}')
        lines.append('    environment:')
        lines += [f'      {key}: {q(value)}' for key, value in variables.items()]
        lines += ['    labels:', f'      {q(SAFE_LABEL)}: {q("false" if service in unsafe else "true")}']
        attached = {}
        for name, attach in sorted(service_networks(spec).items()):
            resets = [
                f'        {key}: !reset null' for key in ('ipv4_address', 'ipv6_address') if (attach or {}).get(key)
            ]
            if resets or service in edge:
                attached[name] = resets
        if service in edge:
            # Every network of the service is named again: an override that names one replaces the implicit default.
            attached[EDGE_KEY] = []
        if attached:
            lines.append('    networks:')
            for name, resets in attached.items():
                lines += [f'      {q(name)}:', *resets] if resets else [f'      {q(name)}: {{}}']
        moved = remapped_volumes(spec, custom_root, custom)
        if moved:
            lines.append('    volumes:')
            for mount in moved:
                lines.append('      - type: bind')
                lines.append(f'        source: {q(mount["source"])}')
                lines.append(f'        target: {q(mount["target"])}')
                if mount.get('read_only'):
                    lines.append('        read_only: true')
    declared = dict(config.get('networks') or {})
    if any('default' in service_networks(spec) for spec in services.values()):
        declared.setdefault('default', {})
    for kind in ('networks', 'volumes'):
        resets = {}
        for key, spec in sorted((declared if kind == 'networks' else config.get(kind) or {}).items()):
            spec = spec or {}
            if kind == 'networks' and key == 'edge':
                # Its default name would be the copy's <group>_edge.
                resets.setdefault(key, []).append(f'    name: {q(f"{group}_edge-net")}')
            elif spec.get('name') and spec['name'] != f'{group}_{key}':
                resets.setdefault(key, []).append('    name: !reset null')
            if kind == 'networks' and (spec.get('ipam') or {}).get('config'):
                resets.setdefault(key, []).append('    ipam: !reset {}')
            if kind == 'networks':
                resets.setdefault(key, []).append('    internal: true')
                resets[key] += ['    driver_opts:', *[f'      {option}: "isolated"' for option in ISOLATED_GATEWAY]]
        if kind == 'networks' and edge:
            resets[EDGE_KEY] = [f'    name: {q(f"{group}_edge")}', '    internal: false']
        if resets:
            lines.append(f'{kind}:')
            for key, entries_of in resets.items():
                lines.append(f'  {q(key)}:')
                lines += entries_of
    return '\n'.join(lines) + '\n'


def foreign(found, folder):
    """Returns the compose folders of a group's containers that are not the folder or under it."""
    return sorted({c['folder'] for c in found if not inside(c['folder'], folder)})


def own_ports(found):
    """Returns the host ports the group's own containers publish."""
    return {port for container in found for _, port in container['ports']}


def cmd_up(group, folder, override, fallback, env_files, custom_root, options, allow_roots=()):
    """Publishes a copy: checks the group is the folder's, writes the override and ports files, then
    docker compose up -d --build in the group, and prints each port."""
    folder = os.path.realpath(folder)
    if not os.path.isdir(folder):
        raise Refused(f'not a folder: {folder}')
    for name in (group, fallback):
        if name and not valid_group(name):
            raise Refused(f'{name} is not a copy group (agent_<MMDD>-<slug>)')
    if not docker_ok():
        raise Refused('Docker: not reachable')
    major = engine_major()
    if major < MIN_ENGINE:
        raise Refused(
            f'a copy needs Docker Engine {MIN_ENGINE} or later (its internal networks get no gateway to the host: '
            f'gateway_mode isolated); this one is {major or "unknown"}'
        )
    found = containers(f'{PROJECT_LABEL}={group}')
    if foreign(found, folder) and fallback:
        group = fallback
        found = containers(f'{PROJECT_LABEL}={group}')
    if foreign(found, folder):
        raise Refused(f'{group} belongs to another folder ({foreign(found, folder)[0]})')
    files, rest = split_compose_options(folder, options, os.environ, env_files)
    base = ['docker', 'compose', '-p', group]
    for item in files:
        base += ['-f', item]
    extra = [*rest]
    for item in env_files:
        extra += ['--env-file', item]
    code, out, err = run([*base, *extra, 'config', '--format', 'json'], cwd=folder)
    if code != 0:
        raise Refused(f'docker compose config failed: {first_line(err or out)}')
    config = load_json(out, 'docker compose config')
    custom = custom_dir()
    roots = [folder, *([custom] if custom else []), *allow_roots]

    def remap(path):
        """Returns where a bind is really read from: under custom_root, the same path of AIWP_CUSTOM_DIR."""
        if custom and custom_root and inside(path, custom_root):
            return os.path.normpath(os.path.join(custom, os.path.relpath(os.path.normpath(path), custom_root)))
        return path

    refusals = isolation_refusals(config, roots, remap)
    if refusals:
        raise Refused('; '.join(refusals))
    warnings = copy_warnings(config)
    entries = port_entries(config)
    ports = pick_ports(entries, read_ports_env(ports_path(override)), free_checker(own_ports(found)))
    text = build_override(config, group, entries, ports, custom_root, custom, set(warnings))
    os.makedirs(os.path.dirname(os.path.abspath(override)), exist_ok=True)
    with open(override, 'w', encoding='utf-8') as handle:
        handle.write(text)
    values = {'AGENT_GROUP': group, **{key: str(value) for key, value in ports.items()}}
    with open(ports_path(override), 'w', encoding='utf-8') as handle:
        handle.write(''.join(f'{key}={value}\n' for key, value in values.items()))
    env = {**os.environ, **values}
    print(f'group: {group}', flush=True)
    for line in warnings.values():
        print(line, flush=True)
    dropped, notes = fixed_addresses(config)
    if dropped:
        print(
            f'attention: the copy drops the fixed addresses {", ".join(sorted(dropped))} (the final stack holds them)'
        )
    for note in notes:
        print(f'attention: {note}')
    if run_live([*base, '-f', override, *extra, 'up', '-d', '--build'], cwd=folder, env=env) != 0:
        print(f'error: docker compose up failed for {group}; the copy is still its own group', file=sys.stderr)
        return 1
    for entry in entries:
        port = ports[entry['variable']]
        print(
            f'port: {entry["service"]} {entry["target"]}/{entry["protocol"]} -> {port} '
            f'http://localhost:{port} {entry["variable"]}'
        )
    for service, role in network_roles(config, entries).items():
        print(f'network: {service} {role}')
    print(f'published: {group} (override {override})')
    return 0


def cmd_down(group):
    """Stops a copy: docker compose down of the group (containers and networks go; volumes and images stay)."""
    if not valid_group(group):
        raise Refused(f'{group} is not a copy group (agent_<MMDD>-<slug>)')
    if not docker_ok():
        raise Refused('Docker: not reachable')
    if run_live(['docker', 'compose', '-p', group, 'down']) != 0:
        raise Refused(f'docker compose down failed for {group}')
    print(f'down: {group} (volumes and images kept)')
    return 0


def labelled(kind, group, fmt):
    """Returns the lines of docker <kind> ls for the resources that carry the group's compose label."""
    code, out, _ = run(['docker', kind, 'ls', '--filter', f'label={PROJECT_LABEL}={group}', '--format', fmt])
    if code != 0:
        raise Refused(f'docker {kind} ls failed')
    return [line for line in out.splitlines() if line.strip()]


def destroy_group(group):
    """Destroys a copy group by its compose label: containers, networks, volumes, then the images it built (a tag of
    another name keeps its image). Only a name GROUP_RE accepts. Returns True when nothing of it is left."""
    if not valid_group(group):
        print(f'refused: {group} is not a copy group (agent_<MMDD>-<slug>): never destroyed')
        return False
    ok, counts = True, {}
    for kind, listing, remove in (
        ('containers', ['docker', 'ps', '-aq', '--filter', f'label={PROJECT_LABEL}={group}'], ['docker', 'rm', '-f']),
        ('networks', None, ['docker', 'network', 'rm']),
        ('volumes', None, ['docker', 'volume', 'rm', '-f']),
    ):
        if listing:
            code, out, _ = run(listing)
            if code != 0:
                raise Refused('docker ps failed')
            items = out.split()
        else:
            items = labelled(kind[:-1], group, '{{.Name}}')
        if items and run(remove + items)[0] != 0:
            print(f'attention: could not remove the {kind} of {group}')
            ok = False
        counts[kind] = len(items)
    images = 0
    for line in labelled('image', group, '{{.ID}} {{.Repository}}:{{.Tag}}'):
        image_id, ref = line.split(' ', 1)
        repository = ref.rsplit(':', 1)[0]
        if repository == '<none>':
            target = image_id
        elif repository.startswith(f'{group}-') or repository == group:
            target = ref
        else:
            print(f"kept: {ref} (a name that is not the group's)")
            continue
        if run(['docker', 'image', 'rm', target])[0] == 0:
            images += 1
        else:
            print(f'attention: could not remove the image {target} of {group}')
            ok = False
    counts['images'] = images
    if any(counts.values()):
        summary = ', '.join(f'{value} {key}' for key, value in counts.items())
        print(f'destroyed: {group} ({summary})')
    else:
        print(f'nothing to destroy: {group}')
    return ok


def groups_under(paths):
    """Returns (copy groups, other projects) of the containers whose compose folder lies under one of the paths."""
    mine, others = set(), set()
    for container in containers(PROJECT_LABEL):
        if any(inside(container['folder'], path) for path in paths):
            (mine if valid_group(container['project']) else others).add(container['project'])
    return mine, others


def cmd_destroy(groups, under):
    """Destroys the groups named and the copy groups of the folders given; another project is never touched."""
    if not docker_ok():
        raise Refused('Docker: not reachable: nothing destroyed')
    found, others = groups_under([os.path.realpath(path) for path in under]) if under else (set(), set())
    for name in sorted(others):
        print(f'kept: {name} (not a copy group)')
    ok = True
    for group in list(dict.fromkeys([*groups, *sorted(found)])):
        ok = destroy_group(group) and ok
    return 0 if ok else 1


def listed(folder, rel, *options):
    """Returns the paths git ls-files lists in a folder at or under rel (pathspecs read literally)."""
    code, out, err = run(['git', '--literal-pathspecs', '-C', folder, 'ls-files', '-z', *options, '--', rel])
    if code != 0:
        raise Refused(f'git ls-files failed in {folder}: {first_line(err)}')
    return {item.rstrip('/') for item in out.split('\0') if item}


def tracked_differences(checkout, repo, rel):
    """Returns the files under rel that are not the same in the checkout of main and in the repo: every file main
    tracks there and every file the repo has there (tracked, or untracked and not ignored). When neither tracks
    anything under rel, it is data, not code: nothing to compare."""
    mine = listed(checkout, rel)
    theirs_tracked = listed(repo, rel)
    if not mine and not theirs_tracked:
        return []
    theirs = theirs_tracked | listed(repo, rel, '--others', '--exclude-standard')
    differ = []
    for path in sorted(mine | theirs):
        one, other = os.path.join(checkout, path), os.path.join(repo, path)
        if not (os.path.isfile(one) and os.path.isfile(other) and filecmp.cmp(one, other, shallow=False)):
            differ.append(path)
    return differ


def moved_source(source, base, repo, roots):
    """Returns (path relative to the checkout, source in the repo, refusal) of a source as the compose files wrote it
    (docker compose config --no-path-resolution): a relative one is taken from the same relative path of the repo
    (base: the folder of the first compose file, relative to the checkout), and refused when that leaves the roots (the
    workspace, its projects/); an absolute one stays: (None, None, '')."""
    if not source or os.path.isabs(source) or source.startswith('~'):
        return None, None, ''
    rel = os.path.normpath(os.path.join(base, source))
    new = os.path.normpath(os.path.join(repo, rel))
    if not any(inside(new, root) for root in roots):
        return rel, None, f'{source} leads to {new}, outside the workspace'
    return rel, new, ''


def deploy_binds(config, checkout, repo, roots, base=''):
    """Returns ({service: [moved mounts]}, {('secrets' or 'configs', name): moved file}, refusals) for a checkout of
    main, from its compose config with no path resolution: every relative bind source and secret or config file (in
    the checkout, or above it through .., at any depth) is taken from the same relative path of the repo; one that
    leaves the workspace is refused, and so are files that differ between main and the repo under a path in the
    checkout (main would run with another file). Absolute sources stay."""
    moved, files, refusals = {}, {}, []

    def check(what, rel, new, why):
        """Returns True when the source may move; else adds the refusal."""
        if why:
            refusals.append(f'{what} {why}')
            return False
        if rel.split(os.sep)[0] == '..':
            return True
        differ = tracked_differences(checkout, repo, rel)
        if differ:
            refusals.append(f'{what} {rel}, and main differs from the repo checkout in {", ".join(differ[:3])}')
        return not differ

    for service, spec in sorted((config.get('services') or {}).items()):
        for mount in spec.get('volumes') or []:
            if mount.get('type') != 'bind':
                continue
            rel, new, why = moved_source(mount.get('source') or '', base, repo, roots)
            if rel is not None and check(f'{service} binds', rel, new, why):
                moved.setdefault(service, []).append({**mount, 'source': new})
    for kind in ('secrets', 'configs'):
        for name, spec in sorted((config.get(kind) or {}).items()):
            rel, new, why = moved_source((spec or {}).get('file') or '', base, repo, roots)
            if rel is not None and check(f'{kind[:-1]} {name} reads', rel, new, why):
                files[(kind, name)] = new
    return moved, files, refusals


def binds_override(moved, files=None):
    """Returns the text of an override that mounts the moved binds, each mount whole with only its source changed
    (compose merges a service's volumes by target), and points the moved secret and config files at the repo."""
    lines = ['# Written by agent-copy.py deploy-binds: the binds of a checkout of main, mounted from the repo.']
    lines.append('services:' if moved else 'services: {}')
    for service, mounts in moved.items():
        lines += [f'  {q(service)}:', '    volumes:']
        lines += [f'      - {json.dumps(mount, sort_keys=True)}' for mount in mounts]
    for kind in ('secrets', 'configs'):
        mine = [(name, path) for (other, name), path in sorted((files or {}).items()) if other == kind]
        if mine:
            lines.append(f'{kind}:')
            for name, path in mine:
                lines += [f'  {q(name)}:', f'    file: {q(path)}']
    return '\n'.join(lines) + '\n'


def cmd_deploy_binds(project, checkout, repo, override, root, options):
    """Prints the compose options of a deploy from a checkout of main, its binds moved to the repo by an override.
    root: the workspace; a source may lead into it or into its projects/ (a link included), nowhere else."""
    checkout, repo = os.path.realpath(checkout), os.path.realpath(repo)
    roots = [os.path.realpath(root), os.path.realpath(os.path.join(root, 'projects'))]
    files, rest = split_compose_options(checkout, options, os.environ)
    args = [item for name in files for item in ('-f', name)]
    base = os.path.relpath(os.path.dirname(os.path.join(checkout, files[0])), checkout)
    code, out, err = run(
        ['docker', 'compose', '-p', project, *args, *rest, 'config', '--no-path-resolution', '--format', 'json'],
        cwd=checkout,
    )
    if code != 0:
        raise Refused(f'docker compose config failed: {first_line(err or out)}')
    config = load_json(out, 'docker compose config')
    moved, files, refusals = deploy_binds(config, checkout, repo, roots, '' if base == '.' else base)
    if refusals:
        raise Refused('main cannot be deployed from a checkout: ' + '; '.join(refusals))
    if moved or files:
        with open(override, 'w', encoding='utf-8') as handle:
            handle.write(binds_override(moved, files))
        args += ['-f', override]
    print('\n'.join([*args, *rest]))
    return 0


def cmd_bound_under(path):
    """Prints each container with a mount under the path; exit 0 when there is one, 1 none, 3 Docker not reachable."""
    if not docker_ok():
        return 3
    code, out, _ = run(['docker', 'ps', '-aq'])
    ids = out.split() if code == 0 else []
    found = 0
    if ids:
        code, out, _ = run(['docker', 'inspect', *ids])
        for item in load_json(out, 'docker inspect') if code == 0 else []:
            for mount in item.get('Mounts') or []:
                if mount.get('Source') and inside(mount['Source'], os.path.realpath(path)):
                    print(f'bound: {item.get("Name", "").lstrip("/")} {mount["Source"]}')
                    found += 1
    return 0 if found else 1


def internal_networks(names):
    """Returns {network name: True when internal} of the networks docker network inspect knows."""
    if not names:
        return {}
    code, out, _ = run(['docker', 'network', 'inspect', *sorted(names)])
    found = load_json(out, 'docker network inspect') if code == 0 and out.strip() else []
    return {item.get('Name', ''): bool(item.get('Internal')) for item in found}


def service_roles(mine, internal):
    """Returns 'service:edge,service:internal' for the containers of a group: edge when one of its networks is not
    internal, internal when all are; a container with no known network is left out."""
    roles = {}
    for c in mine:
        known = [internal[name] for name in c.get('networks') or [] if name in internal]
        if known:
            roles[c['service']] = 'internal' if all(known) else 'edge'
    return ','.join(f'{service}:{role}' for service, role in sorted(roles.items()))


def cmd_list(under, named):
    """Prints one line per copy group: name, state, ports (and the network role of each service, as
    networks=<service>:edge|internal,...). Exit 3 when Docker is not reachable."""
    if not docker_ok():
        return 3
    every = containers(PROJECT_LABEL)
    wanted = {c['project'] for c in every if valid_group(c['project'])}
    if under:
        paths = [os.path.realpath(path) for path in under]
        wanted = {
            c['project'] for c in every if valid_group(c['project']) and any(inside(c['folder'], p) for p in paths)
        }
    if under or named:
        wanted |= {name for name in named if valid_group(name)}
    for group in sorted(wanted):
        mine = [c for c in every if c['project'] == group]
        if mine:
            running = sum(c['running'] for c in mine)
            state = f'{"running" if running else "stopped"} {running}/{len(mine)}'
        else:
            state = 'down, volumes kept' if labelled('volume', group, '{{.Name}}') else 'down'
        ports = ','.join(f'{c["service"]}:{key.split("/")[0]}->{port}' for c in mine for key, port in c['ports'])
        roles = service_roles(mine, internal_networks({n for c in mine for n in c.get('networks') or []}))
        print(f'{group}\t{state}\t{ports or "-"}{" networks=" + roles if roles else ""}')
    return 0


def parse_up(argv):
    """Returns the arguments of up: group, folder, override, fallback, env files, custom root, compose options, and the
    folders --allow-root adds to what a copy may read (default: the folder and AIWP_CUSTOM_DIR)."""
    if len(argv) < 3:
        raise ValueError('up <group> <folder> <override> [options] [-- <docker compose options>...]')
    group, folder, override, rest = argv[0], argv[1], argv[2], argv[3:]
    fallback, env_files, custom_root, options, allow_roots = '', [], '', [], []
    while rest:
        arg = rest.pop(0)
        if arg == '--':
            options = rest
            break
        if arg in ('--fallback', '--env-file', '--custom-root', '--allow-root') and rest:
            value = rest.pop(0)
            if arg == '--allow-root':
                allow_roots.append(os.path.realpath(value))
            elif arg == '--fallback':
                fallback = value
            elif arg == '--env-file':
                env_files.append(value)
            else:
                custom_root = os.path.normpath(os.path.abspath(value))
            continue
        raise ValueError(f'unknown option: {arg}')
    return group, folder, override, fallback, env_files, custom_root, options, allow_roots


def parse_pairs(argv, flags):
    """Returns ({flag: [values]}, plain arguments) of an argument list with flags that take one value each."""
    found, plain = {flag: [] for flag in flags}, []
    while argv:
        arg = argv.pop(0)
        if arg in flags:
            if not argv:
                raise ValueError(f'{arg} needs a value')
            found[arg].append(argv.pop(0))
        elif arg.startswith('-'):
            raise ValueError(f'unknown option: {arg}')
        else:
            plain.append(arg)
    return found, plain


def main(argv):
    """Entry point: agent-copy.py up | down | destroy | list (see the module docstring)."""
    if not argv:
        print(__doc__.split('Usage:', 1)[1].strip(), file=sys.stderr)
        return 2
    command, rest = argv[0], list(argv[1:])
    try:
        if command == 'up':
            return cmd_up(*parse_up(rest))
        if command == 'down':
            if len(rest) != 1:
                raise ValueError('down <group>')
            return cmd_down(rest[0])
        if command == 'destroy':
            found, plain = parse_pairs(rest, ('--under',))
            if not plain and not found['--under']:
                raise ValueError('destroy [--under <path>]... [<group>...]')
            return cmd_destroy(plain, found['--under'])
        if command == 'deploy-binds':
            if len(rest) < 5 or (len(rest) > 5 and rest[5] != '--'):
                raise ValueError(
                    'deploy-binds <project> <checkout> <repo> <override> <workspace> [-- <docker compose options>...]'
                )
            return cmd_deploy_binds(*rest[:5], rest[6:])
        if command == 'bound-under':
            if len(rest) != 1:
                raise ValueError('bound-under <path>')
            return cmd_bound_under(rest[0])
        if command == 'list':
            found, plain = parse_pairs(rest, ('--under', '--group'))
            if plain:
                raise ValueError('list [--under <path>]... [--group <group>]...')
            return cmd_list(found['--under'], found['--group'])
    except ValueError as error:
        print(f'error: usage: {error}', file=sys.stderr)
        return 2
    except Refused as error:
        print(f'refused: {error}', file=sys.stderr)
        return 1
    print(f'error: unknown command: {command}', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
