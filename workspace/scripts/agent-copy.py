"""The Docker copy of a task: the work behind aiwp-cmds.sh up, down, status, close and the merge of the gate.

A task's copy runs in its own compose project, an agent_<MMDD>-<slug> group, from the clone's compose files and an
override file written outside the clone's tracked tree: built services get the group's own image names, fixed
container, network and volume names are reset, and every published host port becomes a random free port in
61000-65535. The project's compose files never change. A group is destroyed only by its compose label and only when
its name matches GROUP_RE. Everything goes through the docker command on PATH, so the tests replace it with a fake.

Usage: python3 -I agent-copy.py up <group> <folder> <override> [--fallback <group>] [--env-file <file>]...
                                   [--custom-root <dir>] [-- <docker compose options>...]
       python3 -I agent-copy.py down <group>
       python3 -I agent-copy.py destroy [--under <path>]... [<group>...]
       python3 -I agent-copy.py list [--under <path>]... [--group <group>]...
Exit: 0 ok; 1 refused or failed; 2 usage error; 3 (list) Docker not reachable.
"""

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
            }
        )
    return found


def split_compose_options(folder, options, environ):
    """Returns (compose files, other options) of the options given after --; the default files when none is named.

    The project name is this script's: -p and --project-name are refused.
    """
    files, rest, i = [], [], 0
    while i < len(options):
        arg = options[i]
        if arg in ('-p', '--project-name') or arg.startswith(('--project-name=', '-p=')):
            raise Refused('the group is the project name of a copy: drop -p/--project-name')
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
        files = default_files(folder, environ)
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


def isolation_refusals(config):
    """Returns why the copy cannot be isolated: an external network or volume, a host or container network mode."""
    refusals = []
    for kind in ('networks', 'volumes'):
        for key, spec in sorted((config.get(kind) or {}).items()):
            if (spec or {}).get('external'):
                refusals.append(
                    f'{kind[:-1]} {key} is external ({spec.get("name") or key}): shared with other stacks, a copy '
                    'cannot have its own'
                )
    for service, spec in sorted((config.get('services') or {}).items()):
        mode = spec.get('network_mode') or ''
        if mode == 'host' or mode.startswith('container:'):
            refusals.append(f'service {service} uses network_mode {mode}: its ports and names are not its own')
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


def build_override(config, group, entries, ports, custom_root='', custom=''):
    """Returns the text of the override file of a copy: the group's name, the image of each built service (and of a
    service that runs that image), no fixed container name, the ports moved, the port variables in every service,
    the configuration binds moved to AIWP_CUSTOM_DIR, no fixed network or volume name."""
    services = config.get('services') or {}
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
        moved = remapped_volumes(spec, custom_root, custom)
        if moved:
            lines.append('    volumes:')
            for mount in moved:
                lines.append('      - type: bind')
                lines.append(f'        source: {q(mount["source"])}')
                lines.append(f'        target: {q(mount["target"])}')
                if mount.get('read_only'):
                    lines.append('        read_only: true')
    for kind in ('networks', 'volumes'):
        fixed = [
            key
            for key, spec in sorted((config.get(kind) or {}).items())
            if (spec or {}).get('name') and spec['name'] != f'{group}_{key}'
        ]
        if fixed:
            lines.append(f'{kind}:')
            for key in fixed:
                lines.append(f'  {q(key)}:')
                lines.append('    name: !reset null')
    return '\n'.join(lines) + '\n'


def foreign(found, folder):
    """Returns the compose folders of a group's containers that are not the folder or under it."""
    return sorted({c['folder'] for c in found if not inside(c['folder'], folder)})


def own_ports(found):
    """Returns the host ports the group's own containers publish."""
    return {port for container in found for _, port in container['ports']}


def cmd_up(group, folder, override, fallback, env_files, custom_root, options):
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
    found = containers(f'{PROJECT_LABEL}={group}')
    if foreign(found, folder) and fallback:
        group = fallback
        found = containers(f'{PROJECT_LABEL}={group}')
    if foreign(found, folder):
        raise Refused(f'{group} belongs to another folder ({foreign(found, folder)[0]})')
    files, rest = split_compose_options(folder, options, os.environ)
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
    refusals = isolation_refusals(config)
    if refusals:
        raise Refused('; '.join(refusals))
    entries = port_entries(config)
    ports = pick_ports(entries, read_ports_env(ports_path(override)), free_checker(own_ports(found)))
    text = build_override(config, group, entries, ports, custom_root, custom_dir())
    os.makedirs(os.path.dirname(os.path.abspath(override)), exist_ok=True)
    with open(override, 'w', encoding='utf-8') as handle:
        handle.write(text)
    values = {'AGENT_GROUP': group, **{key: str(value) for key, value in ports.items()}}
    with open(ports_path(override), 'w', encoding='utf-8') as handle:
        handle.write(''.join(f'{key}={value}\n' for key, value in values.items()))
    env = {**os.environ, **values}
    print(f'group: {group}', flush=True)
    if run_live([*base, '-f', override, *extra, 'up', '-d', '--build'], cwd=folder, env=env) != 0:
        print(f'error: docker compose up failed for {group}; the copy is still its own group', file=sys.stderr)
        return 1
    for entry in entries:
        port = ports[entry['variable']]
        print(
            f'port: {entry["service"]} {entry["target"]}/{entry["protocol"]} -> {port} '
            f'http://localhost:{port} {entry["variable"]}'
        )
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


def cmd_list(under, named):
    """Prints one line per copy group: name, state, ports. Exit 3 when Docker is not reachable."""
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
        print(f'{group}\t{state}\t{ports or "-"}')
    return 0


def parse_up(argv):
    """Returns the arguments of up: group, folder, override, fallback, env files, custom root, compose options."""
    if len(argv) < 3:
        raise ValueError('up <group> <folder> <override> [options] [-- <docker compose options>...]')
    group, folder, override, rest = argv[0], argv[1], argv[2], argv[3:]
    fallback, env_files, custom_root, options = '', [], '', []
    while rest:
        arg = rest.pop(0)
        if arg == '--':
            options = rest
            break
        if arg in ('--fallback', '--env-file', '--custom-root') and rest:
            value = rest.pop(0)
            if arg == '--fallback':
                fallback = value
            elif arg == '--env-file':
                env_files.append(value)
            else:
                custom_root = os.path.normpath(os.path.abspath(value))
            continue
        raise ValueError(f'unknown option: {arg}')
    return group, folder, override, fallback, env_files, custom_root, options


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
