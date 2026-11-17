"""Lists, starts and stops the workspace's local tools: the work behind scripts/run-tools.sh and /run-tools.

The container tools come from the include list of tools/compose.yaml, one compose project (the group), with the title,
description, URL and required variables of each in the x-run-tools block of its main service. The container consoles
are machine services, declared here, and only the one of this machine shows. Everything goes through the docker,
systemctl, launchctl and make commands on PATH, so the tests replace them with fakes. Nothing is written in the
workspace core: builds go to the outputs each tool's git ignores.
"""

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time

GROUP_FILE = 'tools/compose.yaml'
PROJECT_LABEL = 'com.docker.compose.project'
SERVICE_LABEL = 'com.docker.compose.service'
VOLUME_LABEL = 'com.docker.compose.volume'
WAIT_SECONDS = 300
MACHINE_WAIT_SECONDS = 15
KEEP_ROLLBACK_TAGS = 3
DOCKER_CE_UNIT = 'container-console-docker-ce.service'
COLIMA_LABEL = 'io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima'
MACHINE_TOOLS = [
    {
        'id': 'container-console-docker-ce',
        'title': 'Container console (docker-ce)',
        'description': 'Browser console to watch docker-ce and manage containers, Compose and Kubernetes',
        'url': 'http://127.0.0.1:27850/',
        'port': 27850,
        'os': 'Linux',
    },
    {
        'id': 'container-console-colima',
        'title': 'Container console (Colima)',
        'description': 'Browser console to control Colima and manage containers, Compose and Kubernetes',
        'url': 'http://127.0.0.1:17850/',
        'port': 17850,
        'os': 'Darwin',
    },
]
INCLUDE_LINE = re.compile(r"""^\s*-\s*(?:path:\s*)?["']?([a-z0-9][a-z0-9-]*)/compose\.ya?ml["']?\s*$""")
NAME_LINE = re.compile(r"""^name:\s*["']?([a-z0-9][a-z0-9_-]*)["']?\s*$""")


class Refused(Exception):
    """A tool that cannot start or stop now, with the message for the person."""


def run(args, root, check=False, timeout=None):
    """Runs a command in the workspace root and returns (exit code, stdout, stderr); 127 when it is not on PATH."""
    try:
        done = subprocess.run(args, cwd=root, capture_output=True, text=True, timeout=timeout, check=False)
    except FileNotFoundError:
        return 127, '', f'{args[0]} not found'
    except subprocess.TimeoutExpired:
        return 124, '', f'{args[0]} timed out'
    if check and done.returncode != 0:
        raise Refused(f'{" ".join(args[:3])} failed: {first_line(done.stderr or done.stdout)}')
    return done.returncode, done.stdout, done.stderr


def run_live(args, root):
    """Runs a command in the workspace root with its output on this terminal; returns its exit code."""
    try:
        return subprocess.run(args, cwd=root, check=False).returncode
    except FileNotFoundError:
        return 127


def first_line(text):
    """Returns the first non-empty line of a text, or an empty string."""
    for line in (text or '').splitlines():
        if line.strip():
            return line.strip()
    return ''


def say(text):
    """Prints a line of progress at once."""
    print(text, flush=True)


def group_layout(root):
    """Returns (group project name, tool ids) read from tools/compose.yaml."""
    path = os.path.join(root, GROUP_FILE)
    try:
        with open(path, encoding='utf-8') as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        raise Refused(f'cannot read {GROUP_FILE}: {error.strerror}') from error
    name, ids = '', []
    for line in lines:
        found = NAME_LINE.match(line)
        if found and not name:
            name = found.group(1)
        found = INCLUDE_LINE.match(line)
        if found:
            ids.append(found.group(1))
    if not name:
        raise Refused(f'{GROUP_FILE} has no name: line')
    return name, ids


def read_env_file(path):
    """Reads KEY=VALUE lines of an env file, without comments; never prints a value."""
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
        key = key.strip().removeprefix('export ').strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
            value = value[1:-1]
        values[key] = value
    return values


def env_args(root, ids):
    """Returns the --env-file arguments of every included tool that has custom/env/<tool>.env."""
    args = []
    for tool_id in ids:
        path = os.path.join(root, 'custom', 'env', f'{tool_id}.env')
        if os.path.isfile(path):
            args += ['--env-file', path]
    return args


def unquote(value):
    """Returns the text of a scalar of the YAML that docker compose config prints."""
    value = value.strip()
    if value.startswith('"'):
        try:
            return json.loads(value)
        except ValueError:
            return value.strip('"')
    if value.startswith("'") and value.endswith("'") and len(value) >= 2:
        return value[1:-1].replace("''", "'")
    return value


def extensions(yaml_text):
    """Returns {service: x-run-tools block} from the normalized YAML of docker compose config.

    Its JSON output drops the extensions of a service, so the block is read from the YAML, whose layout is fixed:
    services at two spaces, their keys at four, the keys of the block at six and list items at eight.
    """
    blocks, service, block, key, in_services = {}, None, None, None, False
    for line in yaml_text.splitlines():
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(' '))
        if indent == 0:
            in_services = line.rstrip() == 'services:'
            service = block = None
            continue
        if not in_services:
            continue
        if indent == 2:
            service, block = line.strip().rstrip(':'), None
        elif indent == 4:
            block = {} if line.strip() == 'x-run-tools:' else None
            if block is not None:
                blocks[service] = block
        elif block is not None and indent == 6:
            name, _, value = line.strip().partition(':')
            key = name.strip()
            block[key] = unquote(value) if value.strip() else []
        elif block is not None and indent >= 8 and line.strip().startswith('- ') and isinstance(block.get(key), list):
            block[key].append(unquote(line.strip()[2:]))
    return blocks


def grace_seconds(value):
    """Converts a compose duration such as 45s or 1m30s to whole seconds; 10 when it has none."""
    if not value:
        return 10
    total = 0.0
    for amount, unit in re.findall(r'([0-9.]+)(ms|h|m|s)', str(value)):
        total += float(amount) * {'h': 3600, 'm': 60, 's': 1, 'ms': 0.001}[unit]
    return max(1, int(total))


def image_name(ref):
    """Returns the repository part of an image reference: no digest and no tag (a registry port is kept)."""
    ref = ref.split('@', 1)[0]
    slash, colon = ref.rfind('/'), ref.rfind(':')
    return ref[:colon] if colon > slash else ref


def compose_tool(root, group, ids, tool_id):
    """Reads one tool's compose file alone and returns its model, with what keeps it from starting."""
    rel = f'tools/{tool_id}/compose.yaml'
    tool = {
        'id': tool_id,
        'kind': 'compose',
        'title': tool_id,
        'description': '',
        'url': '',
        'requires': [],
        'old_project': '',
        'services': [],
        'networks': [],
        'volumes': [],
        'missing': [],
    }
    base = ['docker', 'compose', *env_args(root, ids), '-f', rel, 'config']
    code, out, err = run([*base, '--format', 'json'], root)
    if code != 0:
        tool['missing'].append(f'compose error: {first_line(err or out)}')
        return tool
    config = json.loads(out)
    code, yaml_text, err = run(base, root)
    blocks = extensions(yaml_text) if code == 0 else {}
    main = next((name for name in config.get('services', {}) if name in blocks), None)
    if main:
        info = blocks[main]
        for key in ('title', 'description', 'url'):
            if isinstance(info.get(key), str) and info[key]:
                tool[key] = info[key]
        tool['requires'] = [item for item in info.get('requires') or [] if isinstance(item, str)]
    tool['old_project'] = config.get('name', '')
    for name, service in config.get('services', {}).items():
        ports = []
        for port in service.get('ports') or []:
            if port.get('published'):
                ports.append({'host_ip': port.get('host_ip') or '', 'port': int(str(port['published']).split('-')[0])})
        needed, named = [], []
        for mount in service.get('volumes') or []:
            if mount.get('type') == 'bind' and not (mount.get('bind') or {}).get('create_host_path'):
                needed.append(mount.get('source', ''))
            elif mount.get('type') == 'volume' and mount.get('source'):
                named.append(mount['source'])
        tool['services'].append(
            {
                'name': name,
                'image': service.get('image') or f'{group}-{name}',
                'build': 'build' in service,
                'ports': ports,
                'needed_files': needed,
                'named_volumes': named,
                'grace': grace_seconds(service.get('stop_grace_period')),
            }
        )
    old = tool['old_project']
    for key, network in (config.get('networks') or {}).items():
        if network.get('external'):
            continue
        real = network.get('name') or f'{old}_{key}'
        tool['networks'].append({'key': key, 'name': real, 'fixed': real != f'{old}_{key}'})
    for key, volume in (config.get('volumes') or {}).items():
        if volume.get('external'):
            continue
        real = volume.get('name') or f'{old}_{key}'
        if real == f'{old}_{key}':
            tool['volumes'].append({'key': key, 'old': real, 'new': f'{group}_{key}'})
    check_configuration(root, ids, tool)
    return tool


def check_configuration(root, ids, tool):
    """Adds to the tool's missing list each file and required variable its configuration lacks."""
    for service in tool['services']:
        for source in service['needed_files']:
            if source and not os.path.exists(source):
                shown = os.path.relpath(source, root) if source.startswith(root + os.sep) else source
                tool['missing'].append(f'configuration missing: {shown} (README of tools/{tool["id"]})')
    if tool['requires']:
        values = {}
        for tool_id in ids:
            values.update(read_env_file(os.path.join(root, 'custom', 'env', f'{tool_id}.env')))
        values.update(os.environ)
        env_rel = f'custom/env/{tool["id"]}.env'
        for name in tool['requires']:
            if not values.get(name):
                hint = (
                    ''
                    if os.path.isfile(os.path.join(root, env_rel))
                    else f'; create it with /local-env tools/{tool["id"]}'
                )
                tool['missing'].append(f'configuration missing: {name} in {env_rel}{hint}')


def containers(root):
    """Returns the inspect data of every container that carries a compose project label."""
    code, out, _ = run(['docker', 'ps', '-aq', '--filter', f'label={PROJECT_LABEL}'], root)
    ids = out.split() if code == 0 else []
    if not ids:
        return []
    code, out, _ = run(['docker', 'inspect', *ids], root)
    if code != 0:
        return []
    found = []
    for item in json.loads(out):
        labels = (item.get('Config') or {}).get('Labels') or {}
        ports = set()
        for bindings in ((item.get('NetworkSettings') or {}).get('Ports') or {}).values():
            for binding in bindings or []:
                if str(binding.get('HostPort', '')).isdigit():
                    ports.add(int(binding['HostPort']))
        found.append(
            {
                'id': item.get('Id', ''),
                'name': (item.get('Name') or '').lstrip('/'),
                'project': labels.get(PROJECT_LABEL, ''),
                'service': labels.get(SERVICE_LABEL, ''),
                'running': bool((item.get('State') or {}).get('Running')),
                'image_id': item.get('Image', ''),
                'ports': ports,
            }
        )
    return found


def port_open(port, host=''):
    """Tells whether something accepts connections on a local port."""
    target = host if host not in ('', '0.0.0.0', '::') else '127.0.0.1'
    try:
        with socket.create_connection((target, port), timeout=0.5):
            return True
    except OSError:
        return False


def add_runtime(tool, group, running):
    """Adds the state of a compose tool (up, stopped), its old project when it runs there, and busy ports."""
    names = {service['name'] for service in tool['services']}
    projects = {group, tool['old_project']}
    mine = [item for item in running if item['service'] in names and item['project'] in projects]
    tool['containers'] = mine
    up = [item for item in mine if item['running']]
    tool['state'] = 'up' if up and all(any(i['service'] == n for i in up) for n in names) else 'stopped'
    if any(item['project'] != group for item in mine if item['running']) or (
        not up and any(item['project'] != group for item in mine)
    ):
        tool['project'] = tool['old_project']
    else:
        tool['project'] = group
    owned = {port for item in mine if item['running'] for port in item['ports']}
    for service in tool['services']:
        for port in service['ports']:
            number = port['port']
            if number in owned:
                continue
            other = next((item for item in running if item['running'] and number in item['ports']), None)
            if other:
                tool['missing'].append(f'port {number} busy: container {other["name"]}')
            elif port_open(number, port['host_ip']):
                tool['missing'].append(f'port {number} busy: another process')


def uname(root):
    """Returns the kernel name (Linux, Darwin...)."""
    code, out, _ = run(['uname', '-s'], root)
    return out.strip() if code == 0 else ''


def docker_ce(root):
    """Tells whether this machine runs Docker Engine - Community (docker-ce)."""
    code, out, _ = run(['docker', 'version', '--format', '{{.Server.Platform.Name}}'], root, timeout=10)
    if code == 0 and 'Docker Engine - Community' in out:
        return True
    code, out, _ = run(['dpkg-query', '-W', '-f=${Status}', 'docker-ce'], root)
    if code == 0 and 'install ok installed' in out:
        return True
    code, _, _ = run(['rpm', '-q', 'docker-ce'], root)
    return code == 0


def has_command(name):
    """Tells whether a command is on PATH."""
    return shutil.which(name) is not None


def machine_tools(root):
    """Returns the console of this machine: docker-ce on Linux and WSL with Docker Engine, Colima on macOS."""
    system = uname(root)
    shown = []
    for spec in MACHINE_TOOLS:
        if spec['os'] != system:
            continue
        if spec['id'] == 'container-console-docker-ce' and not docker_ce(root):
            continue
        if spec['id'] == 'container-console-colima' and not has_command('colima'):
            continue
        tool = {key: spec[key] for key in ('id', 'title', 'description', 'url', 'port')}
        tool.update({'kind': 'machine', 'missing': [], 'project': ''})
        if machine_active(root, spec['id']):
            tool['state'] = 'up'
        elif os.path.isfile(machine_unit(spec['id'])):
            tool['state'] = 'stopped'
        else:
            tool['state'] = 'not installed'
            needs = [name for name in ('make', 'go', 'npm') if not has_command(name)]
            if needs:
                tool['missing'].append(f'to install it: {", ".join(needs)} on PATH (README of tools/{spec["id"]})')
        shown.append(tool)
    return shown


def machine_unit(tool_id):
    """Returns the path of the service file the console's installer writes."""
    home = os.path.expanduser('~')
    if tool_id == 'container-console-docker-ce':
        config = os.environ.get('XDG_CONFIG_HOME') or os.path.join(home, '.config')
        return os.path.join(config, 'systemd', 'user', DOCKER_CE_UNIT)
    return os.path.join(home, 'Library', 'LaunchAgents', f'{COLIMA_LABEL}.plist')


def machine_active(root, tool_id):
    """Tells whether the service of a console runs, as systemd or launchd reports it."""
    if tool_id == 'container-console-docker-ce':
        code, out, _ = run(['systemctl', '--user', 'is-active', DOCKER_CE_UNIT], root)
        return code == 0 and out.strip() == 'active'
    code, out, _ = run(['launchctl', 'print', f'gui/{os.getuid()}/{COLIMA_LABEL}'], root)
    return code == 0 and 'state = running' in out


def model(root):
    """Returns (group, include ids, tools of this machine) with their state and what is missing."""
    group, ids = group_layout(root)
    tools = []
    docker_ok = has_command('docker')
    running = containers(root) if docker_ok else []
    for tool_id in ids:
        if not docker_ok:
            tools.append(
                {
                    'id': tool_id,
                    'kind': 'compose',
                    'title': tool_id,
                    'description': '',
                    'url': '',
                    'services': [],
                    'state': 'stopped',
                    'project': group,
                    'missing': ['docker not found'],
                    'containers': [],
                }
            )
            continue
        tool = compose_tool(root, group, ids, tool_id)
        add_runtime(tool, group, running)
        tools.append(tool)
    tools += machine_tools(root)
    return group, ids, tools


def public(tool):
    """Returns the fields of a tool that list --json prints."""
    ports = {p['port'] for s in tool.get('services', []) for p in s['ports']}
    if 'port' in tool:
        ports.add(tool['port'])
    return {
        'id': tool['id'],
        'title': tool['title'],
        'description': tool.get('description', ''),
        'url': tool.get('url', ''),
        'kind': tool['kind'],
        'state': tool['state'],
        'project': tool.get('project', ''),
        'ports': sorted(ports),
        'missing': tool['missing'],
    }


def cmd_list(root, as_json):
    """Prints the tools of this machine, as JSON or as a table."""
    group, _, tools = model(root)
    if as_json:
        print(json.dumps({'group': group, 'tools': [public(tool) for tool in tools]}, indent=2))
        return 0
    print_table(tools, group)
    return 0


def print_table(tools, group):
    """Prints tool, kind, state, URL and notes as a Markdown table."""
    print('| Tool | Kind | State | URL | Notes |')
    print('| --- | --- | --- | --- | --- |')
    for tool in tools:
        notes = list(tool['missing'])
        if tool.get('project') and tool['project'] != group and tool['kind'] == 'compose':
            notes.insert(0, f'runs in the old project {tool["project"]}; up moves it to {group}')
        print(f'| {tool["id"]} | {tool["kind"]} | {tool["state"]} | {tool.get("url", "")} | {"; ".join(notes)} |')


def pick(tools, ids):
    """Returns the tools named, in order; exits 2 on a name this machine does not list."""
    by_id = {tool['id']: tool for tool in tools}
    unknown = [tool_id for tool_id in ids if tool_id not in by_id]
    if unknown:
        known = ', '.join(by_id) or 'none'
        print(f'error: not a tool of this machine: {", ".join(unknown)} (tools: {known})', file=sys.stderr)
        sys.exit(2)
    return [by_id[tool_id] for tool_id in dict.fromkeys(ids)]


def tag_rollback(root, tool, group, stamp):
    """Tags the current image of each service of a tool as <name>:rollback-latest and rollback-<stamp>."""
    for service in tool['services']:
        name = image_name(service['image'])
        image_id = next(
            (c['image_id'] for c in tool['containers'] if c['service'] == service['name'] and c['project'] == group),
            '',
        ) or next((c['image_id'] for c in tool['containers'] if c['service'] == service['name']), '')
        if not image_id:
            code, out, _ = run(['docker', 'image', 'inspect', '--format', '{{.Id}}', service['image']], root)
            image_id = out.strip() if code == 0 else ''
        if not image_id:
            say(f'first build of {service["image"]}: no checkpoint yet')
            continue
        run(['docker', 'tag', image_id, f'{name}:rollback-latest'], root, check=True)
        run(['docker', 'tag', image_id, f'{name}:rollback-{stamp}'], root, check=True)
        say(f'rollback: {name}:rollback-latest ({image_id[:19]})')
        prune_rollback(root, name)


def prune_rollback(root, name):
    """Keeps the newest rollback-<stamp> tags of an image name; removes only the tag, never an image in use."""
    code, out, _ = run(['docker', 'image', 'ls', '--format', '{{.Tag}}', name], root)
    if code != 0:
        return
    stamped = sorted((t for t in out.split() if re.fullmatch(r'rollback-[0-9]{8}-[0-9]{6}', t)), reverse=True)
    for tag in stamped[KEEP_ROLLBACK_TAGS:]:
        code, _, _ = run(['docker', 'image', 'rm', f'{name}:{tag}'], root)
        say(f'untagged: {name}:{tag}' if code == 0 else f'attention: kept {name}:{tag} (in use)')


def network_users(root, network):
    """Returns (exists, compose project label, {container id: name}) of a Docker network."""
    code, out, _ = run(['docker', 'network', 'inspect', network], root)
    if code != 0:
        return False, '', {}
    data = json.loads(out)
    item = data[0] if isinstance(data, list) and data else {}
    users = {cid: (info or {}).get('Name', cid[:12]) for cid, info in (item.get('Containers') or {}).items()}
    return True, (item.get('Labels') or {}).get(PROJECT_LABEL, ''), users


def check_move(root, tool, group):
    """Refuses to move a tool, before anything changes, when one of its fixed networks belongs to another project or
    another stack still uses it (Compose refuses a network created by another project), or when a named volume exists
    under both names (the group would start on its own volume and leave the old data behind)."""
    own = {c['id'] for c in tool['containers'] if c['project'] != group}
    if own:
        for volume in tool['volumes']:
            if run(['docker', 'volume', 'inspect', volume['old']], root)[0] == 0 and (
                run(['docker', 'volume', 'inspect', volume['new']], root)[0] == 0
            ):
                raise Refused(
                    f'both {volume["old"]} (where {tool["old_project"]} keeps its data) and {volume["new"]} (the '
                    f"group's) exist, so moving would leave that data behind; check both, delete the one you do not "
                    f'want (docker volume rm, with confirmation), then run again'
                )
    for network in tool['networks']:
        if not network['fixed']:
            continue
        exists, project, users = network_users(root, network['name'])
        if not exists or project == group:
            continue
        if project != tool['old_project']:
            raise Refused(
                f'network {network["name"]} belongs to project {project or "none"}, not to {group}; '
                f'remove it (docker network rm {network["name"]}) once nothing uses it, then run again'
            )
        others = sorted(name for cid, name in users.items() if cid not in own)
        if others:
            raise Refused(
                f'network {network["name"]} is also used by {", ".join(others)}; stop those stacks (docker compose '
                f'down in their folders), then run again: the tool moves to {group}, and they attach again at their '
                f'next up'
            )


def copy_image(tool, volume, old):
    """Returns the image that copies a volume with its cp: the one of the service that mounts the volume (it writes
    there, so it has a shell), from its old container when there is one; never another service's image, which may
    have no cp at all (a distroless one)."""
    service = next((s for s in tool['services'] if volume['key'] in s['named_volumes']), None)
    if service is None:
        raise Refused(f'no service of {tool["id"]} mounts the volume {volume["key"]}')
    image = next((c['image_id'] for c in old if c['service'] == service['name'] and c['image_id']), '')
    return image or service['image']


def move_tool(root, tool, group):
    """Brings a tool from its old compose project into the group: stops its old containers, copies each named volume
    to the group's name (the old one is kept), removes the old containers and the old project's networks. Does nothing
    for a tool already in the group. Returns the old volumes kept."""
    old = [c for c in tool['containers'] if c['project'] != group]
    running = [c['id'] for c in old if c['running']]
    if old:
        say(f'moving {tool["id"]} from project {tool["old_project"]} to {group}')
    if running:
        grace = max((s['grace'] for s in tool['services']), default=10)
        run(['docker', 'stop', '-t', str(grace), *running], root, check=True, timeout=grace + 60)
    kept = []
    for volume in tool['volumes']:
        if run(['docker', 'volume', 'inspect', volume['old']], root)[0] != 0:
            continue
        if run(['docker', 'volume', 'inspect', volume['new']], root)[0] == 0:
            continue  # already in the group; check_move refused the case where the old project still runs
        created = False
        try:
            run(
                [
                    'docker',
                    'volume',
                    'create',
                    '--label',
                    f'{PROJECT_LABEL}={group}',
                    '--label',
                    f'{VOLUME_LABEL}={volume["key"]}',
                    volume['new'],
                ],
                root,
                check=True,
            )
            created = True
            run(
                [
                    'docker',
                    'run',
                    '--rm',
                    '--network',
                    'none',
                    '--entrypoint',
                    'cp',
                    '-v',
                    f'{volume["old"]}:/from:ro',
                    '-v',
                    f'{volume["new"]}:/to',
                    copy_image(tool, volume, old),
                    '-a',
                    '/from/.',
                    '/to/',
                ],
                root,
                check=True,
                timeout=1800,
            )
        except Refused as error:
            if created:
                run(['docker', 'volume', 'rm', volume['new']], root)
            if running:
                run(['docker', 'start', *running], root)
            raise Refused(
                f'copying {volume["old"]} failed, so {tool["id"]} stays in {tool["old_project"]}: {error}'
            ) from error
        say(f'copied: {volume["old"]} -> {volume["new"]}')
        kept.append(volume['old'])
    own = {c['id'] for c in old}
    if old:
        run(['docker', 'rm', *[c['id'] for c in old]], root, check=True)
    for network in tool['networks']:
        exists, project, users = network_users(root, network['name'])
        if exists and project == tool['old_project'] and project != group and not set(users) - own:
            code, _, err = run(['docker', 'network', 'rm', network['name']], root)
            if code != 0:
                say(f'attention: network {network["name"]} kept: {first_line(err)}')
    return kept


def start_machine(root, tool):
    """Starts a console service, installing it first when it is missing; waits until its port answers."""
    tool_dir = f'tools/{tool["id"]}'
    if tool['state'] == 'up':
        return
    if tool['state'] == 'not installed':
        if tool['missing']:
            raise Refused('; '.join(tool['missing']))
        say(f'installing {tool["id"]}: make -C {tool_dir} install')
        if run_live(['make', '-C', tool_dir, 'install'], root) != 0:
            raise Refused(f'make -C {tool_dir} install failed (README of {tool_dir})')
    elif tool['id'] == 'container-console-docker-ce':
        run(['systemctl', '--user', 'start', DOCKER_CE_UNIT], root, check=True)
    else:
        uid = str(os.getuid())
        run(['launchctl', 'bootstrap', f'gui/{uid}', machine_unit(tool['id'])], root)
        run(['launchctl', 'kickstart', f'gui/{uid}/{COLIMA_LABEL}'], root, check=True)
    deadline = time.monotonic() + MACHINE_WAIT_SECONDS
    while time.monotonic() < deadline:
        if machine_active(root, tool['id']):
            return
        time.sleep(0.5)
    raise Refused(f'{tool["id"]} did not start within {MACHINE_WAIT_SECONDS} s (README of tools/{tool["id"]})')


def stop_machine(root, tool):
    """Stops a console service; an installation stays as it is."""
    if tool['state'] == 'not installed':
        return
    if tool['id'] == 'container-console-docker-ce':
        run(['systemctl', '--user', 'stop', DOCKER_CE_UNIT], root, check=True)
    else:
        run(['launchctl', 'bootout', f'gui/{os.getuid()}/{COLIMA_LABEL}'], root)


def cmd_up(root, ids):
    """Starts the tools named: refuses each one that lacks configuration or a port, tags the rollback, moves a tool
    from its old project, builds and starts the rest of the group, then prints the table of what was asked."""
    group, include, tools = model(root)
    chosen = pick(tools, ids)
    failed = False
    compose, kept = [], []
    for tool in chosen:
        if tool['kind'] == 'compose' and tool['missing']:
            for reason in tool['missing']:
                say(f'refused: {tool["id"]}: {reason}')
            failed = True
            continue
        if tool['kind'] == 'compose':
            try:
                check_move(root, tool, group)
            except Refused as error:
                say(f'refused: {tool["id"]}: {error}')
                failed = True
                continue
            compose.append(tool)
    if compose:
        stamp = time.strftime('%Y%m%d-%H%M%S')
        ready = []
        for tool in compose:
            try:
                tag_rollback(root, tool, group, stamp)
                kept += move_tool(root, tool, group)
                ready.append(tool)
            except Refused as error:
                say(f'refused: {tool["id"]}: {error}')
                failed = True
        services = [s['name'] for tool in ready for s in tool['services']]
        if services:
            args = [
                'docker',
                'compose',
                *env_args(root, include),
                '-f',
                GROUP_FILE,
                'up',
                '-d',
                '--build',
                '--wait',
                '--wait-timeout',
                str(WAIT_SECONDS),
                *services,
            ]
            say(f'starting: {", ".join(tool["id"] for tool in ready)} in {group}')
            if run_live(args, root) != 0:
                failed = True
                say(
                    'error: docker compose up failed; the images before this run are <name>:rollback-latest, and a '
                    "tool's own file still starts it alone: docker compose -f tools/<tool>/compose.yaml up -d"
                )
    for tool in chosen:
        if tool['kind'] != 'machine':
            continue
        try:
            start_machine(root, tool)
        except Refused as error:
            say(f'refused: {tool["id"]}: {error}')
            failed = True
    for name in kept:
        say(f'old volume kept: {name} (its data is in the group now; delete it only after checking, with confirmation)')
    _, _, after = model(root)
    wanted = [tool for tool in after if tool['id'] in dict.fromkeys(ids)]
    print_table(wanted, group)
    return 1 if failed else 0


def cmd_down(root, ids):
    """Stops the tools named, in the group or in their old project; never removes a container, volume or image."""
    group, include, tools = model(root)
    chosen = pick(tools, ids)
    failed = False
    services = []
    for tool in chosen:
        if tool['kind'] == 'machine':
            try:
                stop_machine(root, tool)
                say(f'stopped: {tool["id"]}')
            except Refused as error:
                say(f'error: {tool["id"]}: {error}')
                failed = True
            continue
        old = [c['id'] for c in tool.get('containers', []) if c['project'] != group and c['running']]
        if old:
            code, _, err = run(['docker', 'stop', *old], root)
            if code != 0:
                say(f'error: {tool["id"]}: {first_line(err)}')
                failed = True
        services += [s['name'] for s in tool.get('services', [])]
        say(f'stopping: {tool["id"]}')
    if services:
        args = ['docker', 'compose', *env_args(root, include), '-f', GROUP_FILE, 'stop', *services]
        if run_live(args, root) != 0:
            failed = True
    return 1 if failed else 0


def main(argv):
    """Entry point: run-tools.py <root> list [--json] | status | up <id>... | down <id>..."""
    if len(argv) < 2:
        print('usage: run-tools.py <root> <command> [args]', file=sys.stderr)
        return 2
    root, command, rest = os.path.realpath(argv[0]), argv[1], argv[2:]
    try:
        if command == 'list':
            return cmd_list(root, rest == ['--json'])
        if command == 'status':
            return cmd_list(root, False)
        if command == 'up':
            return cmd_up(root, rest)
        if command == 'down':
            return cmd_down(root, rest)
    except Refused as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    print(f'error: unknown command {command}', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
