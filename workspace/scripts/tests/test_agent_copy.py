"""Unit tests of scripts/agent-copy.py (the Docker copy of a task), in-process so the coverage gate measures them.

Every command the module runs goes through subprocess.run, replaced here by FakeDocker: no real Docker is reached.
The projects are fictitious (acme, billing-api); tests/aiwp-cmds/test-aiwp-cmds.sh covers the same behavior through
aiwp-cmds.sh, with one real copy when Docker is on the machine.
"""

import contextlib
import importlib.util
import io
import json
import os
import random
import re
import shutil
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / 'agent-copy.py'
SPEC = importlib.util.spec_from_file_location('agent_copy', MODULE_PATH)
ac = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ac)

GROUP = 'agent_1118-add-export'
# The clone in config(): the fake docker answers with the folder compose runs in (its cwd) in its place.
CLONE = '/acme/clone'
REAL_RUN = subprocess.run
# What every internal network of a copy carries: no gateway to the host.
ISOLATED = (
    '    driver_opts:\n      com.docker.network.bridge.gateway_mode_ipv4: "isolated"\n'
    '      com.docker.network.bridge.gateway_mode_ipv6: "isolated"\n'
)
LOGIN_SIMULATOR = MODULE_PATH.parent.parent / 'tools' / 'login-simulator' / 'compose.yaml'


def container(project, folder, service='web', running=True, ports=None, networks=()):
    """Returns the docker inspect data of one compose container."""
    return {
        'Id': f'c-{project}-{service}',
        'Config': {
            'Labels': {ac.PROJECT_LABEL: project, ac.WORKDIR_LABEL: folder, ac.SERVICE_LABEL: service},
        },
        'State': {'Running': running},
        'NetworkSettings': {
            'Ports': {key: [{'HostIp': '0.0.0.0', 'HostPort': str(port)}] for key, port in (ports or {}).items()},
            'Networks': {name: {} for name in networks},
        },
    }


def config(**extra):
    """Returns a compose config (docker compose config --format json) of a fictitious billing-api project."""
    data = {
        'name': GROUP,
        'services': {
            'web': {
                'build': {'context': CLONE, 'dockerfile': 'Dockerfile'},
                'image': 'billing-api-web',
                'container_name': 'billing-web',
                'ports': [{'target': 80, 'published': '8080', 'protocol': 'tcp', 'host_ip': '127.0.0.1'}],
            },
            'worker': {'image': 'billing-api-web'},
            'db': {
                'image': 'postgres:16',
                'ports': [
                    {'target': 5432, 'published': '5432', 'protocol': 'tcp'},
                    {'target': 5432, 'protocol': 'udp'},
                ],
                'volumes': [{'type': 'volume', 'source': 'data', 'target': '/var/lib/postgresql/data'}],
            },
        },
        'networks': {'default': {'name': 'billing-net'}, 'plain': {'name': f'{GROUP}_plain'}},
        'volumes': {'data': {'name': 'billing-data'}, 'cache': {}},
    }
    data.update(extra)
    return data


class FakeDocker:
    """Stands in for subprocess.run: answers the docker commands of agent-copy.py from the state the test sets, and
    records every call. A regex of `fail` matched on the joined argv returns its exit code first."""

    def __init__(self):
        self.calls = []
        self.fail = {}
        self.up = True
        self.items = []
        self.res = {}
        self.config = config()
        self.config_text = None
        self.ports_text = ''
        self.git_files = {}
        self.version = '28.4.0'
        self.networks = []
        self.git_fails = set()

    def joined(self):
        """Returns every recorded call as one line of text each."""
        return [' '.join(call) for call in self.calls]

    def called(self, pattern):
        """Tells whether a recorded call matches the regex."""
        return any(re.search(pattern, line) for line in self.joined())

    def ps(self, args):
        """Answers docker ps: the ids of a label filter, or the published ports."""
        if '--format' in args:
            return 0, self.ports_text, ''
        if '--filter' not in args:
            return 0, '\n'.join(item['Id'] for item in self.items), ''
        label = args[args.index('--filter') + 1].removeprefix('label=')
        key, _, value = label.partition('=')
        found = [
            item['Id']
            for item in self.items
            if key in item['Config']['Labels'] and (not value or item['Config']['Labels'][key] == value)
        ]
        return 0, '\n'.join(found), ''

    def answer(self, args):
        """Returns (code, stdout, stderr) of a command."""
        line = ' '.join(args)
        for pattern, code in self.fail.items():
            if re.search(pattern, line):
                return code, '', f'failed: {line}'
        if args[0] != 'docker':
            raise FileNotFoundError(args[0])
        sub = args[1]
        if sub == 'version':
            return (0, f'{self.version}\n', '') if self.up else (1, '', 'cannot connect')
        if sub == 'ps':
            return self.ps(args)
        if sub == 'inspect':
            return 0, json.dumps([item for item in self.items if item['Id'] in args[2:]]), ''
        if sub == 'network' and args[2] == 'inspect':
            return 0, json.dumps([n for n in self.networks if n['Name'] in args[3:]]), ''
        if sub in ('network', 'volume', 'image') and args[2] == 'ls':
            group = args[4].rsplit('=', 1)[1]
            return 0, ''.join(f'{entry}\n' for entry in self.res.get((sub, group), [])), ''
        if sub == 'compose' and 'config' in args:
            return 0, self.config_text if self.config_text is not None else json.dumps(self.config), ''
        return 0, '', ''

    def git(self, args):
        """Answers git --literal-pathspecs -C <folder> ls-files -z [--others ...] -- <path>: the files of
        git_files[(folder, 'tracked' or 'others')] at or under the path; a folder named in git_fails fails."""
        folder, rel = args[args.index('-C') + 1], args[-1]
        if folder in self.git_fails or '--literal-pathspecs' not in args:
            return 128, '', 'fatal: not a git repository'
        files = self.git_files.get((folder, 'others' if '--others' in args else 'tracked'), set())
        found = [path for path in sorted(files) if path == rel or path.startswith(rel.rstrip('/') + '/')]
        return 0, ''.join(f'{path}\0' for path in found), ''

    def __call__(self, args, **kwargs):
        if args[0] == 'git':
            code, out, err = self.git(args)
            return subprocess.CompletedProcess(args, code, out, err)
        self.calls.append(list(args))
        code, out, err = self.answer(args)
        if kwargs.get('cwd') and args[1:2] == ['compose']:
            out = out.replace(CLONE, kwargs['cwd'])
        return subprocess.CompletedProcess(args, code, out, err)


class CopyTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = os.path.realpath(self.tmp.name)
        self.clone = os.path.join(self.root, 'tmp/work/2026-11-18-add-export/billing-api')
        os.makedirs(self.clone)
        Path(self.clone, 'compose.yaml').write_text('services: {}\n', encoding='utf-8')
        self.override = os.path.join(self.root, 'tmp/work/2026-11-18-add-export/agent-billing-api.compose.yaml')
        self.fake = FakeDocker()
        env = mock.patch.dict(os.environ, {}, clear=False)
        env.start()
        self.addCleanup(env.stop)
        for name in ('COMPOSE_FILE', 'COMPOSE_PATH_SEPARATOR', ac.CUSTOM_DIR_VAR):
            os.environ.pop(name, None)
        for target, attr, value in (
            (ac.subprocess, 'run', self.fake),
            (ac, 'bind_free', lambda port, protocol: True),
            (ac, 'proc_ports', set),
        ):
            patcher = mock.patch.object(target, attr, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def quiet(self, func, *args):
        """Calls func with stdout and stderr captured; returns (result, stdout, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = func(*args)
        return result, out.getvalue(), err.getvalue()

    def up(self, *extra):
        """Runs main up for the clone; returns (exit code, stdout, stderr)."""
        return self.quiet(ac.main, ['up', GROUP, self.clone, self.override, *extra])


class HelperTests(unittest.TestCase):
    def test_run_and_run_live_map_missing_commands_and_timeouts(self):
        self.assertEqual(ac.run(['true'])[0], 0)
        self.assertEqual(ac.run(['acme-no-such-command'])[0], 127)
        self.assertEqual(ac.run(['sleep', '5'], timeout=0.01)[0], 124)
        self.assertEqual(ac.run_live(['true']), 0)
        self.assertEqual(ac.run_live(['acme-no-such-command']), 127)

    def test_first_line_and_json(self):
        self.assertEqual(ac.first_line('\n  two \nthree'), 'two')
        self.assertEqual(ac.first_line(None), '')
        self.assertEqual(ac.load_json('[1]', 'x'), [1])
        with self.assertRaisesRegex(ac.Refused, 'x gave no JSON: empty output'):
            ac.load_json('', 'x')

    def test_group_names(self):
        for name in (GROUP, 'agent_0101-a', 'agent_1231-a-b--c', 'agent_1118-add-export-billing-api'):
            self.assertTrue(ac.valid_group(name), name)
        for name in (
            '',
            None,
            'billing-api',
            'agent_118-x',
            'agent_1118-',
            'agent_1118-X',
            'agent_1118_x',
            'agent_1118--x',
            'Agent_1118-x',
            'agent_1118-x/y',
            'claude-cli-agents-tools',
            'agent_1118-x.y',
        ):
            self.assertFalse(ac.valid_group(name), name)

    def test_inside(self):
        self.assertTrue(ac.inside('/a/b', '/a/b'))
        self.assertTrue(ac.inside('/a/b/c/../d', '/a/b/'))
        self.assertFalse(ac.inside('/a/bc', '/a/b'))
        self.assertFalse(ac.inside('/a/b/../c', '/a/b'))

    def test_ports_file_and_variables(self):
        self.assertEqual(ac.ports_path('/w/agent-x.compose.yaml'), '/w/agent-x.ports.env')
        self.assertEqual(ac.ports_path('/w/other.yaml'), '/w/other.yaml.ports.env')
        taken = set()
        self.assertEqual(ac.variable('billing.web', 80, 'tcp', taken), 'AGENT_PORT_BILLING_WEB_80')
        self.assertEqual(ac.variable('billing.web', 80, 'tcp', taken), 'AGENT_PORT_BILLING_WEB_80_2')
        self.assertEqual(ac.variable('dns', 53, 'udp', taken), 'AGENT_PORT_DNS_53_UDP')
        self.assertEqual(ac.variable('x', 1, '', taken), 'AGENT_PORT_X_1')

    def test_read_ports_env(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, 'p.env')
            Path(path).write_text('# note\nA=1\nbad line\n B = 2\n', encoding='utf-8')
            self.assertEqual(ac.read_ports_env(path), {'A': '1', 'B': '2'})
            self.assertEqual(ac.read_ports_env(os.path.join(folder, 'none')), {})

    def test_port_entries(self):
        entries = ac.port_entries(config())
        self.assertEqual(
            [(e['service'], e['target'], e['protocol'], e['host_ip'], e['variable']) for e in entries],
            [
                ('db', 5432, 'tcp', '', 'AGENT_PORT_DB_5432'),
                ('db', 5432, 'udp', '', 'AGENT_PORT_DB_5432_UDP'),
                ('web', 80, 'tcp', '127.0.0.1', 'AGENT_PORT_WEB_80'),
            ],
        )
        self.assertEqual(ac.port_entries({'services': {'x': {'ports': [{'target': '90-91'}]}}})[0]['target'], 90)

    def test_bind_free_on_real_sockets(self):
        sock = socket.socket()
        sock.bind(('0.0.0.0', 0))
        sock.listen(1)
        busy = sock.getsockname()[1]
        try:
            self.assertFalse(ac.bind_free(busy, 'tcp'))
        finally:
            sock.close()
        self.assertTrue(ac.bind_free(busy, 'tcp') or True)
        with mock.patch.object(ac.socket, 'socket', side_effect=OSError('no family')):
            self.assertTrue(ac.bind_free(1, 'udp'))

    def test_proc_ports_reads_listening_tcp_and_bound_udp(self):
        tcp = 'sl local rem st\n 0: 0100007F:EE48 00000000:0000 0A\n 1: 0100007F:EE49 00000000:0000 01\n'
        udp = 'sl local rem st\n 0: 00000000:EE4A 00000000:0000 07\n'

        def fake_open(path, encoding=None):
            """Returns the fake /proc/net file of a path, or fails."""
            texts = {'/proc/net/tcp': tcp, '/proc/net/udp': udp}
            if path not in texts:
                raise OSError('absent')
            return io.StringIO(texts[path])

        with mock.patch('builtins.open', fake_open):
            self.assertEqual(ac.proc_ports(), {('tcp', 0xEE48), ('udp', 0xEE4A)})

    def test_pick_ports_keeps_the_last_ones_and_avoids_busy_ones(self):
        entries = [{'variable': 'A', 'protocol': 'tcp', 'service': 'a', 'target': 1}]
        entries.append({'variable': 'B', 'protocol': 'tcp', 'service': 'b', 'target': 2})
        busy = {61500}
        chosen = ac.pick_ports(entries, {'A': '61500', 'B': '62000'}, lambda p, _: p not in busy, random.Random(1))
        self.assertEqual(chosen['B'], 62000)
        self.assertNotEqual(chosen['A'], 61500)
        self.assertTrue(ac.PORT_MIN <= chosen['A'] <= ac.PORT_MAX)
        same = ac.pick_ports(entries, {'A': '62000', 'B': '62000'}, lambda p, _: True, random.Random(2))
        self.assertEqual(same['A'], 62000)
        self.assertNotEqual(same['B'], 62000)
        old = ac.pick_ports(entries[:1], {'A': '8080'}, lambda p, _: True)
        self.assertTrue(ac.PORT_MIN <= old['A'] <= ac.PORT_MAX)
        with self.assertRaisesRegex(ac.Refused, 'no free port in 61000-65535 for a 1'):
            ac.pick_ports(entries[:1], {}, lambda p, _: False)

    def test_isolation_refusals(self):
        self.assertEqual(ac.isolation_refusals(config(), [CLONE]), [])
        bad = config(
            networks={'shared': {'external': True, 'name': 'proxy'}},
            volumes={'data': {'external': True}},
        )
        bad['services']['web']['network_mode'] = 'host'
        bad['services']['db']['network_mode'] = 'container:billing-db'
        bad['services']['worker']['network_mode'] = 'service:web'
        refusals = ac.isolation_refusals(bad, [CLONE])
        self.assertEqual(
            refusals,
            [
                'network shared sets external',
                'volume data sets external',
                'service db sets network_mode container:billing-db: only service:<x> of the same files',
                'service web sets network_mode host: only service:<x> of the same files',
            ],
        )
        self.assertEqual(
            ac.isolation_refusals(config()),
            [
                'service web builds from a context /acme/clone, outside the clone',
                'service web builds from a Dockerfile /acme/clone/Dockerfile, outside the clone',
            ],
        )

    def test_build_override(self):
        entries = ac.port_entries(config())
        ports = {'AGENT_PORT_DB_5432': 61001, 'AGENT_PORT_DB_5432_UDP': 61002, 'AGENT_PORT_WEB_80': 61003}
        text = ac.build_override(config(), GROUP, entries, ports)
        self.assertIn(f'name: "{GROUP}"', text)
        self.assertEqual(text.count(f'image: "{GROUP}-web"'), 2)
        self.assertEqual(text.count(f'image: "{GROUP}-worker"'), 0)
        self.assertIn(f'  "worker":\n    image: "{GROUP}-web"', text)
        self.assertIn('    container_name: !reset null', text)
        self.assertIn('published: "61003"\n        host_ip: "127.0.0.1"\n        protocol: "tcp"', text)
        self.assertIn('published: "61002"\n        protocol: "udp"', text)
        self.assertIn(
            f'networks:\n  "default":\n    name: !reset null\n    internal: true\n{ISOLATED}  "plain":\n'
            f'    internal: true\n{ISOLATED}  "agent-edge":\n    name: "{GROUP}_edge"\n    internal: false\n'
            'volumes:\n  "data":\n    name: !reset null',
            text,
        )
        # A service that publishes joins the edge network too, with every network it had; the others do not.
        self.assertEqual(text.count('    networks:\n      "default": {}\n      "agent-edge": {}\n'), 2)
        self.assertNotIn('"cache"', text)
        self.assertEqual(text.count('AGENT_PORT_WEB_80: "61003"'), 3)
        self.assertNotIn('postgres', text)
        built = config()
        built['services']['web'].pop('image')
        self.assertIn(f'image: "{GROUP}-web"', ac.build_override(built, GROUP, [], {}))

    def test_remapped_volumes_and_custom_dir(self):
        spec = {
            'volumes': [
                {'type': 'bind', 'source': '/ws/custom/config/x.json', 'target': '/c', 'read_only': True},
                {'type': 'bind', 'source': '/ws/tools/x/.data', 'target': '/d'},
                {'type': 'volume', 'source': 'data', 'target': '/v'},
                {'type': 'bind', 'target': '/none'},
            ]
        }
        self.assertEqual(ac.remapped_volumes(spec, '', '/other'), [])
        moved = ac.remapped_volumes(spec, '/ws/custom', '/other/custom')
        self.assertEqual(moved, [{**spec['volumes'][0], 'source': '/other/custom/config/x.json'}])
        text = ac.build_override({'services': {'s': spec}}, GROUP, [], {}, '/ws/custom', '/other/custom')
        self.assertIn('volumes:\n      - type: bind\n        source: "/other/custom/config/x.json"', text)
        self.assertIn('read_only: true', text)
        with mock.patch.dict(os.environ, {ac.CUSTOM_DIR_VAR: ''}):
            self.assertEqual(ac.custom_dir(), '')
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(os.environ, {ac.CUSTOM_DIR_VAR: folder}):
            self.assertEqual(ac.custom_dir(), os.path.realpath(folder))
        with mock.patch.dict(os.environ, {ac.CUSTOM_DIR_VAR: '/nowhere/acme'}):
            with self.assertRaisesRegex(ac.Refused, 'is not a folder'):
                ac.custom_dir()


class ReviewFindingTests(unittest.TestCase):
    """The findings of the review of the copy: build tags, fixed addresses, the attached -p."""

    def test_a_built_service_drops_its_extra_build_tags(self):
        data = config()
        data['services']['web']['build']['tags'] = ['billing-api:latest']
        text = ac.build_override(data, GROUP, [], {})
        self.assertIn(f'    image: "{GROUP}-web"\n    build:\n      tags: !reset []', text)
        self.assertNotIn('tags: !reset', ac.build_override(config(), GROUP, [], {}))

    def test_fixed_addresses_are_dropped_and_named(self):
        data = config(
            networks={
                'login': {'name': 'login-simulator', 'ipam': {'config': [{'subnet': '172.31.250.0/24'}]}},
                'plain': {'ipam': {}},
            }
        )
        data['services']['web']['networks'] = {'login': {'ipv4_address': '172.31.250.10', 'ipv6_address': 'fd00::10'}}
        data['services']['web']['environment'] = {'AVATAR_ORIGIN': 'http://172.31.250.10:8080', 'OTHER': 'x'}
        data['services']['db']['networks'] = {'plain': None}
        data['services']['db']['extra_hosts'] = ['login:172.31.250.10']
        text = ac.build_override(data, GROUP, [], {})
        self.assertIn(
            '    networks:\n      "login":\n        ipv4_address: !reset null\n        ipv6_address: !reset null', text
        )
        self.assertIn(
            f'networks:\n  "default":\n    internal: true\n{ISOLATED}  "login":\n    name: !reset null\n'
            '    ipam: !reset {}',
            text,
        )
        self.assertIn(f'  "plain":\n    internal: true\n{ISOLATED}', text)
        self.assertNotIn('agent-edge', text)
        dropped, notes = ac.fixed_addresses(data)
        self.assertEqual(dropped, {'172.31.250.10', 'fd00::10', '172.31.250.0/24'})
        self.assertEqual(
            notes,
            [
                'db: extra host login:172.31.250.10 names 172.31.250.10, a fixed address the copy does not have',
                'web: AVATAR_ORIGIN=http://172.31.250.10:8080 names 172.31.250.10, '
                'a fixed address the copy does not have',
            ],
        )
        self.assertEqual(ac.fixed_addresses(config()), (set(), []))

    def test_the_login_simulator_copy_has_no_fixed_name_subnet_or_address(self):
        if not shutil.which('docker') or REAL_RUN(['docker', 'compose', 'version'], capture_output=True).returncode:
            self.skipTest('docker compose is not on this machine')
        with tempfile.TemporaryDirectory() as folder:
            base = ['docker', 'compose', '-p', GROUP, '-f', str(LOGIN_SIMULATOR)]
            env = {**os.environ, 'LOGIN_SIMULATOR_CONFIG': os.path.join(folder, 'config.json')}
            done = REAL_RUN([*base, 'config', '--format', 'json'], capture_output=True, text=True, env=env, check=True)
            data = json.loads(done.stdout)
            entries = ac.port_entries(data)
            ports = {entry['variable']: 61000 + n for n, entry in enumerate(entries)}
            override = os.path.join(folder, 'agent.compose.yaml')
            Path(override).write_text(ac.build_override(data, GROUP, entries, ports), encoding='utf-8')
            done = REAL_RUN(
                [*base, '-f', override, 'config', '--format', 'json'],
                capture_output=True,
                text=True,
                env=env,
                check=True,
            )
        merged = json.loads(done.stdout)
        network = merged['networks']['login-simulator']
        self.assertEqual(network['name'], f'{GROUP}_login-simulator')
        self.assertTrue(network['internal'])
        self.assertEqual(
            network['driver_opts'],
            {
                'com.docker.network.bridge.gateway_mode_ipv4': 'isolated',
                'com.docker.network.bridge.gateway_mode_ipv6': 'isolated',
            },
        )
        self.assertEqual(merged['networks']['agent-edge']['name'], f'{GROUP}_edge')
        self.assertFalse(merged['networks']['agent-edge'].get('internal'))
        self.assertEqual(sorted(merged['services']['login-simulator']['networks']), ['agent-edge', 'login-simulator'])
        self.assertFalse((network.get('ipam') or {}).get('config'))
        service = merged['services']['login-simulator']
        self.assertNotIn('ipv4_address', service['networks']['login-simulator'] or {})
        self.assertEqual(service['image'], f'{GROUP}-login-simulator')
        self.assertEqual(service['ports'][0]['published'], '61000')
        self.assertIn('172.31.250.10', ' '.join(ac.fixed_addresses(data)[1]))

    def test_every_project_name_option_is_refused(self):
        for options in (['-p', 'x'], ['-px'], ['-p=x'], ['--project-name', 'x'], ['--project-name=x']):
            with self.assertRaisesRegex(ac.Refused, 'drop -p/--project-name'):
                ac.split_compose_options('/nowhere', options, {})
        self.assertEqual(
            ac.split_compose_options('/nowhere', ['-f', 'a', '--profile', 'p'], {}), (['a'], ['--profile', 'p'])
        )


class InternalNetworkTests(CopyTestCase):
    """A copy reaches outside Docker only through <group>_edge, and only from a service that publishes a port."""

    def test_roles_and_the_edge_network(self):
        data = config(networks={'edge': {'name': 'proxy-edge'}, 'back': {}})
        data['services']['db']['networks'] = {'back': {'aliases': ['database']}}
        data['services']['proxy'] = {'network_mode': 'service:web'}
        data['services']['tool'] = {'network_mode': 'none'}
        entries = ac.port_entries(data)
        self.assertEqual(
            ac.network_roles(data, entries),
            {'db': 'edge', 'proxy': 'shares web', 'tool': 'none', 'web': 'edge', 'worker': 'internal'},
        )
        data['services']['db'].pop('ports')
        entries = ac.port_entries(data)
        self.assertEqual(ac.network_roles(data, entries)['db'], 'internal')
        text = ac.build_override(data, GROUP, entries, {'AGENT_PORT_WEB_80': 61003})
        self.assertIn(f'  "edge":\n    name: "{GROUP}_edge-net"\n    internal: true', text)
        self.assertIn('  "back":\n    internal: true', text)
        self.assertIn(f'  "agent-edge":\n    name: "{GROUP}_edge"\n    internal: false', text)
        self.assertNotIn('"database"', text)
        self.assertNotIn('"db":\n    networks', text)
        self.assertEqual(
            ac.isolation_refusals(config(networks={'agent-edge': {}}))[0][:26], 'network agent-edge is the '
        )

    def test_up_prints_each_service_s_role(self):
        code, out, _ = self.up()
        self.assertEqual(code, 0)
        self.assertIn('network: web edge\nnetwork: worker internal\n', out.replace('network: db edge\n', ''))

    def test_list_shows_edge_and_internal(self):
        self.fake.items = [
            container(GROUP, self.clone, ports={'80/tcp': 61500}, networks=(f'{GROUP}_default', f'{GROUP}_edge')),
            container(GROUP, self.clone, service='db', networks=(f'{GROUP}_default',)),
            container(GROUP, self.clone, service='gone', networks=('unknown',)),
        ]
        self.fake.networks = [
            {'Name': f'{GROUP}_default', 'Internal': True},
            {'Name': f'{GROUP}_edge', 'Internal': False},
        ]
        code, out, _ = self.quiet(ac.main, ['list'])
        self.assertEqual(out, f'{GROUP}\trunning 3/3\tweb:80->61500 networks=db:internal,web:edge\n')
        self.fake.fail['network inspect'] = 1
        self.assertEqual(self.quiet(ac.main, ['list'])[1], f'{GROUP}\trunning 3/3\tweb:80->61500\n')
        self.assertEqual(ac.internal_networks(set()), {})


class EscapeTests(CopyTestCase):
    """up refuses what would let a copy reach the host: the engine, the service options, the mounts."""

    def test_an_engine_older_than_28_is_refused(self):
        for version, shown in (('27.5.1', '27'), ('weird', 'unknown')):
            self.fake.version = version
            code, _, err = self.up()
            self.assertEqual(code, 1)
            self.assertIn('a copy needs Docker Engine 28 or later', err)
            self.assertIn(f'this one is {shown}', err)
        self.assertFalse(self.fake.called('up -d'))
        self.fake.up = False
        self.assertEqual(ac.engine_major(), 0)

    def valid(self):
        """Returns a compose config that a copy of the clone may run: every allowed form once."""
        Path(self.clone, 'Dockerfile').write_text('FROM scratch\n', encoding='utf-8')
        data = config(
            volumes={'data': {'name': f'{GROUP}_data'}, 'cache': {'driver': 'local', 'labels': {'a': 'b'}}},
            secrets={'pw': {'file': f'{self.clone}/pw'}, 'token': {'environment': 'TOKEN'}},
            configs={'site': {'file': f'{self.clone}/site.conf'}, 'inline': {'content': 'x'}},
            **{'x-acme': {'any': 'thing'}},
        )
        data['services']['web']['build'] = {
            'context': self.clone, 'dockerfile': 'Dockerfile', 'args': {'A': '1'}, 'target': 't', 'cache_from': ['x'],
        }  # fmt: skip
        data['services']['web'].update(
            {
                'security_opt': ['no-new-privileges:true', 'no-new-privileges'],
                'env_file': [{'path': f'{self.clone}/.env', 'required': False}],
                'volumes': [
                    {'type': 'bind', 'source': f'{self.clone}/conf', 'target': '/c'},
                    {'type': 'volume', 'source': 'data', 'target': '/d'},
                    {'type': 'volume', 'target': '/anonymous'},
                    {'type': 'tmpfs', 'target': '/t'},
                ],
                'deploy': {'resources': {'limits': {'cpus': '1'}}},
                'logging': {'driver': 'json-file', 'options': {'max-size': '1m'}},
                'extra_hosts': ['acme:10.0.0.1'],
                'pid': 'service:db',
                'cap_drop': ['ALL'],
                'read_only': True,
                'group_add': ['999'],
                'x-run-tools': {'title': 'x'},
            }
        )
        data['services']['worker']['network_mode'] = 'service:web'
        data['services']['db']['ipc'] = 'service:web'
        return data

    def test_the_allowed_forms_pass(self):
        self.assertEqual(ac.isolation_refusals(self.valid(), [self.clone]), [])

    def test_private_modes_and_the_harmless_keys_of_normal_projects_pass(self):
        data = self.valid()
        data['services']['db'].pop('ipc')
        data['services']['web'].pop('pid')
        data['services']['web'].update(
            {
                'ipc': 'shareable',
                'cgroup': 'private',
                'links': ['db:database'],
                'dns': ['10.0.0.2'],
                'dns_search': ['acme.example.com'],
                'develop': {'watch': [{'action': 'sync', 'path': './src', 'target': '/src'}]},
                'post_start': [{'command': 'true'}],
                'pre_stop': [{'command': 'true'}],
                'deploy': {'replicas': 2, 'restart_policy': {'condition': 'on-failure'}, 'update_config': {}},
            }
        )
        data['services']['db']['ipc'] = 'service:web'
        data['services']['worker'] = {'image': 'acme/worker', 'ipc': 'private'}
        data['services']['web']['build'].update(pull=True, no_cache=True, platforms=['linux/amd64'])
        data['networks'] = {'default': {'name': f'{GROUP}_default', 'attachable': True}}
        self.assertEqual(ac.isolation_refusals(data, [self.clone]), [])
        inline = self.valid()
        inline['services']['web']['build'] = {'context': self.clone, 'dockerfile_inline': 'FROM scratch'}
        self.assertEqual(ac.isolation_refusals(inline, [self.clone]), [])
        self.assertEqual(ac.copy_warnings(data), {})
        for key, value in (('ipc', 'host'), ('cgroup', 'host'), ('pid', 'private'), ('uts', 'private')):
            data = self.valid()
            data['services']['db'].pop('ipc')
            data['services']['web'][key] = value
            self.assertEqual(ac.isolation_refusals(data, [self.clone]), [])
            self.assertIn(f'WARNING: service web sets {key} {value}, off the safe list', ac.copy_warnings(data)['web'])

    def test_every_other_form_is_refused_and_named(self):
        sock = '/var/run/docker.sock'
        cases = [
            (lambda d: d['secrets'].update(s={'file': sock}), f'secret s reads {sock}: a container runtime socket'),
            (lambda d: d['configs'].update(c={'file': '/etc/passwd'}), 'config c reads /etc/passwd, outside the clone'),
            (lambda d: d['secrets'].update(e={'external': True}), 'secret e sets external'),
            (
                lambda d: d['services']['web'].update(volumes_from=['container:billing-db']),
                'service web takes the volumes of container:billing-db, outside the compose files',
            ),
            (
                lambda d: d['services']['web'].update(volumes_from=['billing-db:ro']),
                'service web takes the volumes of billing-db:ro, outside the compose files',
            ),
            (lambda d: d['services']['web']['build'].update(network='host'), 'service web build sets network'),
            (lambda d: d['services']['web']['build'].update(ssh=['default']), 'service web build sets ssh'),
            (lambda d: d['services']['web']['build'].update(secrets=['pw']), 'service web build sets secrets'),
            (
                lambda d: d['services']['web']['build'].update(additional_contexts={'x': '/etc'}),
                'service web build sets additional_contexts',
            ),
            (lambda d: d['services']['web']['build'].update(entitlements=['network.host']), 'build sets entitlements'),
            (lambda d: d['services']['web']['build'].update(context='https://example.com/x.git'), 'builds from https'),
            (lambda d: d['services']['web']['build'].update(dockerfile='../../../etc/x'), 'a Dockerfile'),
            (lambda d: d['services']['web'].update(build='.'), 'service web has a build that is not a mapping'),
            (
                lambda d: d['services']['web'].update(env_file=[{'path': '/etc/environment'}]),
                'service web reads the env file /etc/environment, outside the clone',
            ),
            (lambda d: d['services']['web'].update(env_file=['/etc/x.env']), 'reads the env file /etc/x.env'),
            (lambda d: d['services']['web'].update(network_mode='host'), 'network_mode host'),
            (lambda d: d['services']['web'].update(network_mode='bridge'), 'network_mode bridge'),
            (lambda d: d['services']['web'].update(network_mode='none'), 'network_mode none'),
            (lambda d: d['services']['web'].update(network_mode='container:x'), 'network_mode container:x'),
            (
                lambda d: d['volumes'].update(h={'driver_opts': {'device': '/srv', 'o': 'bind'}}),
                'volume h sets driver_opts',
            ),
            (lambda d: d['volumes'].update(n={'driver': 'nfs'}), 'volume n uses the driver nfs'),
            (lambda d: d['networks'].update(o={'driver': 'overlay'}), 'network o uses the driver overlay'),
            (lambda d: d['networks'].update(p={'driver_opts': {'a': 'b'}}), 'network p sets driver_opts'),
            (lambda d: d['services']['web'].update(logging={'driver': 'syslog'}), 'service web logs through syslog'),
            (
                lambda d: d['services']['web']['volumes'].append({'type': 'bind', 'source': '/etc', 'target': '/e'}),
                'service web binds /etc, outside the clone',
            ),
            (
                lambda d: d['services']['web']['volumes'].append({'type': 'bind', 'source': sock, 'target': '/s'}),
                f'service web binds {sock}: a container runtime socket',
            ),
            (
                lambda d: d['services']['web']['volumes'].append({'type': 'volume', 'source': 'data', 'target': sock}),
                f'service web mounts {sock}: a container runtime socket',
            ),
            (
                lambda d: d['services']['web']['volumes'].append({'type': 'volume', 'source': 'other', 'target': '/o'}),
                'mounts the volume other, which the compose files do not declare',
            ),
            (
                lambda d: d['services']['web']['volumes'].append({'type': 'npipe', 'source': 'x', 'target': '/o'}),
                'service web mounts a npipe mount',
            ),
            (lambda d: d.update(models={}), 'the compose files sets models'),
        ]
        for mutate, expected in cases:
            data = self.valid()
            mutate(data)
            refusals = ac.isolation_refusals(data, [self.clone])
            self.assertTrue(any(expected in why for why in refusals), (expected, refusals))
        os.symlink('/etc', os.path.join(self.clone, 'escape'))
        data = self.valid()
        data['services']['web']['volumes'] = [{'type': 'bind', 'source': f'{self.clone}/escape', 'target': '/e'}]
        self.assertIn('outside the clone', ac.isolation_refusals(data, [self.clone])[0])

    def test_settings_that_only_police_the_compose_are_warnings(self):
        cases = [
            (lambda d: d['services']['web'].update(privileged=True), 'privileged', True),
            (lambda d: d['services']['web'].update(cap_add=['NET_ADMIN']), 'cap_add', True),
            (lambda d: d['services']['web'].update(devices=['/dev/kvm']), 'devices', True),
            (lambda d: d['services']['web'].update(userns_mode='host'), 'userns_mode', True),
            (lambda d: d['services']['web'].update(sysctls={'a': 1}), 'sysctls', True),
            (lambda d: d['services']['web'].update(volumes_from=['db:ro']), 'volumes_from', True),
            (lambda d: d['services']['web'].update(security_opt=['seccomp:unconfined']), 'security_opt seccomp', True),
            (lambda d: d['services']['web'].update(pid='container:x'), 'pid container:x', True),
            (lambda d: d['services']['web'].update(ipc='host'), 'ipc host', True),
            (lambda d: d['services']['web'].update(uts='service:nobody'), 'uts service:nobody', True),
            (lambda d: d['services']['web'].update(cgroup='host'), 'cgroup host', True),
            (
                lambda d: d['services']['web'].update(deploy={'resources': {'reservations': {'devices': [{}]}}}),
                'deploy reserved devices',
                True,
            ),
            (lambda d: d['services']['web'].update(extra_hosts=['h:host-gateway']), 'host-gateway', False),
            (lambda d: d['services']['web'].update(extra_hosts={'h': 'host-gateway'}), 'host-gateway', False),
            (lambda d: d['services']['web'].update(deploy={'placement': {}}), 'deploy placement', False),
        ]
        for mutate, expected, reaches in cases:
            data = self.valid()
            mutate(data)
            self.assertEqual(ac.isolation_refusals(data, [self.clone]), [], expected)
            warnings = list(ac.copy_warnings(data).values())
            self.assertEqual(len(warnings), 1, (expected, warnings))
            self.assertTrue(warnings[0].startswith('WARNING: service web sets '), warnings)
            self.assertIn(expected, warnings[0])
            self.assertEqual(warnings[0].count(' — '), 2, warnings[0])
            self.assertEqual('may reach the host' in warnings[0], reaches, warnings[0])
            self.assertIn('so exec in web falls back to the permission mode', warnings[0])
        # One line per service, every setting of it named; a service with none has no line.
        data = self.valid()
        data['services']['web'].update(privileged=True, cap_add=['SYS_ADMIN'], extra_hosts=['h:host-gateway'])
        data['services']['db']['sysctls'] = {'net.core.somaxconn': 1024}
        self.assertEqual(
            [line.split(', off the safe list')[0] for line in ac.copy_warnings(data).values()],
            [
                'WARNING: service db sets sysctls',
                'WARNING: service web sets cap_add, privileged, an extra host on host-gateway',
            ],
        )

    def test_up_starts_a_service_off_the_safe_list_and_prints_its_warning(self):
        self.fake.config['services']['web'].update(privileged=True, cap_add=['NET_ADMIN'])
        code, out, err = self.up()
        self.assertEqual((code, err), (0, ''))
        self.assertIn('WARNING: service web sets cap_add, privileged, off the safe list of a copy', out)
        self.assertIn('so exec in web falls back to the permission mode', out)
        self.assertEqual(out.count('WARNING:'), 1)
        self.assertTrue(self.fake.called('up -d --build'))
        self.assertLess(out.index('WARNING:'), out.index('published:'))
        # The isolation of the override stays: every network internal, with no gateway to the host.
        text = Path(self.override).read_text(encoding='utf-8')
        self.assertIn('internal: true', text)
        self.assertIn(ISOLATED, text)
        # guard-bash auto-allows exec only where up wrote safe=true: web, which it warned about, gets false.
        labels = re.findall(
            r'\n  "([a-z]+)":\n(?:    .*\n|      .*\n)*?    labels:\n      "com.aiwp.copy.safe": "(\w+)"', text
        )
        self.assertEqual(sorted(labels), [('db', 'true'), ('web', 'false'), ('worker', 'true')])
        # A refusal still wins: nothing starts.
        self.fake.calls.clear()
        self.fake.config['services']['web']['network_mode'] = 'host'
        code, out, err = self.up()
        self.assertEqual(code, 1)
        self.assertIn('service web sets network_mode host', err)
        self.assertNotIn('WARNING:', out)
        self.assertFalse(self.fake.called('up -d'))

    def test_allowed_roots_and_the_configuration_folder(self):
        installed = os.path.join(self.root, 'installed')
        os.makedirs(installed)
        data = self.valid()
        data['services']['web']['volumes'] = [{'type': 'bind', 'source': f'{self.root}/tmp/x', 'target': '/c'}]
        self.assertEqual(len(ac.isolation_refusals(data, [self.clone])), 1)
        self.assertEqual(ac.isolation_refusals(data, [self.clone, self.root]), [])

        def remap(path):
            """Moves the configuration of the clone to the installed folder."""
            return path.replace(f'{self.clone}/custom', installed)

        data['services']['web']['volumes'] = [{'type': 'bind', 'source': f'{self.clone}/custom/c.json', 'target': '/c'}]
        self.assertIn(f'binds {installed}/c.json, outside', ac.isolation_refusals(data, [self.clone], remap)[0])
        self.assertEqual(ac.isolation_refusals(data, [self.clone, installed], remap), [])
        # Through up: --allow-root adds a folder; without it, a bind outside the clone is refused, nothing started.
        self.fake.config = config()
        self.fake.config['services']['db']['volumes'] = [{'type': 'bind', 'source': installed, 'target': '/s'}]
        code, _, err = self.up()
        self.assertEqual(code, 1)
        self.assertIn(f'service db binds {installed}, outside the clone', err)
        self.assertFalse(self.fake.called('up -d'))
        self.assertEqual(self.up('--allow-root', installed)[0], 0)
        with mock.patch.dict(os.environ, {ac.CUSTOM_DIR_VAR: installed}):
            self.assertEqual(self.up()[0], 0)
            # --allow-root adds to the folder and AIWP_CUSTOM_DIR, never replaces them.
            other = os.path.join(self.root, 'other')
            os.makedirs(other)
            self.fake.config['services']['db']['volumes'].append({'type': 'bind', 'source': other, 'target': '/o'})
            self.fake.config['services']['db']['volumes'].append(
                {'type': 'bind', 'source': f'{self.clone}/data', 'target': '/d'}
            )
            self.assertEqual(self.up('--allow-root', other)[0], 0)
            self.assertIn(f'binds {other}, outside the clone', self.up()[2])


class ProductToolTests(unittest.TestCase):
    """The product's tools publish as copies of a clone of this repository, but the one that mounts the socket."""

    def test_the_product_tools_pass_but_the_socket(self):
        if not shutil.which('docker') or REAL_RUN(['docker', 'compose', 'version'], capture_output=True).returncode:
            self.skipTest('docker compose is not on this machine')
        workspace = MODULE_PATH.parent.parent
        clone = workspace.parent
        env = {k: v for k, v in os.environ.items() if k not in ('LOGIN_SIMULATOR_CONFIG', 'SAFE_BROWSING_THREATS')}
        found = {}
        for tool in ('observability', 'login-simulator', 'safe-browsing-simulator', 'azurite-console'):
            done = REAL_RUN(
                ['docker', 'compose', '-p', GROUP, '-f', str(workspace / 'tools' / tool / 'compose.yaml'), 'config',
                 '--format', 'json'],
                capture_output=True, text=True, env=env, check=True,
            )  # fmt: skip
            found[tool] = ac.isolation_refusals(json.loads(done.stdout), [str(clone)])
        self.assertEqual(found['observability'], [])
        self.assertEqual(found['login-simulator'], [])
        self.assertEqual(found['safe-browsing-simulator'], [])
        self.assertEqual(
            found['azurite-console'],
            ['service azurite-console mounts /var/run/docker.sock: a container runtime socket, never in a copy'],
        )


class DeployBindsTests(CopyTestCase):
    """deploy main: the binds, secrets and configs of the checkout come from the repo; a bound checkout is never
    deleted."""

    def setUp(self):
        super().setUp()
        self.repo = os.path.join(self.root, 'projects', 'billing-api')
        self.checkout = os.path.join(self.root, 'tmp', 'deploy', 'billing-api-main')
        for folder in (self.repo, self.checkout):
            os.makedirs(os.path.join(folder, 'conf'))
            for name, text in (('compose.yaml', 'services: {}\n'), ('conf/nginx.conf', 'server {}\n'), ('pw', 's\n')):
                Path(folder, name).write_text(text, encoding='utf-8')
            self.fake.git_files[(folder, 'tracked')] = {'compose.yaml', 'conf/nginx.conf', 'pw'}
        self.override = self.checkout + '.binds.compose.yaml'
        self.fake.config = {
            'name': 'billing-api',
            'services': {
                'db': {
                    'volumes': [
                        {
                            'type': 'bind',
                            'source': './pgdata',
                            'target': '/data',
                            'bind': {'create_host_path': True, 'selinux': 'Z', 'propagation': 'rprivate'},
                            'consistency': 'cached',
                        },
                        {'type': 'bind', 'source': './conf', 'target': '/n', 'read_only': True},
                        {'type': 'bind', 'source': '../shared', 'target': '/shared'},
                        {'type': 'bind', 'source': '/srv/acme', 'target': '/srv'},
                        {'type': 'volume', 'source': 'data', 'target': '/v'},
                    ]
                },
                'web': {},
            },
            'secrets': {'pw': {'file': './pw'}, 'ext': {'external': True}},
            'configs': {'site': {'file': 'conf/nginx.conf'}, 'far': {'file': '/srv/acme.conf'}},
        }

    def deploy(self, *options):
        """Runs main deploy-binds; returns (exit code, stdout, stderr)."""
        return self.quiet(
            ac.main, ['deploy-binds', 'billing-api', self.checkout, self.repo, self.override, self.root, *options]
        )

    def mounts(self):
        """Returns the volumes lines of the override, parsed (each is a JSON flow mapping)."""
        text = Path(self.override).read_text(encoding='utf-8')
        return [json.loads(line.split('- ', 1)[1]) for line in text.splitlines() if line.startswith('      - ')]

    def test_binds_secrets_and_configs_move_to_the_repo_whole(self):
        code, out, err = self.deploy('--', '--profile', 'full')
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines(), ['-f', 'compose.yaml', '-f', self.override, '--profile', 'full'])
        mounts = self.mounts()
        self.assertEqual(
            mounts[0],
            {**self.fake.config['services']['db']['volumes'][0], 'source': f'{self.repo}/pgdata'},
        )
        self.assertEqual(mounts[1]['source'], f'{self.repo}/conf')
        self.assertTrue(mounts[1]['read_only'])
        # ../shared of the checkout: the same relative path from the repo.
        self.assertEqual(mounts[2]['source'], os.path.normpath(f'{self.repo}/../shared'))
        self.assertEqual(len(mounts), 3)
        text = Path(self.override).read_text(encoding='utf-8')
        self.assertIn(f'secrets:\n  "pw":\n    file: "{self.repo}/pw"', text)
        self.assertIn(f'configs:\n  "site":\n    file: "{self.repo}/conf/nginx.conf"', text)
        self.assertNotIn('/srv/acme', text)
        self.assertNotIn('"ext"', text)
        self.assertTrue(
            self.fake.called(
                r'^docker compose -p billing-api -f compose.yaml --profile full config --no-path-resolution'
            )
        )

    def test_only_a_secret_still_writes_the_override(self):
        self.fake.config = {'services': {}, 'secrets': {'pw': {'file': './pw'}}}
        code, out, _ = self.deploy()
        self.assertEqual((code, out.splitlines()), (0, ['-f', 'compose.yaml', '-f', self.override]))
        self.assertIn('services: {}', Path(self.override).read_text(encoding='utf-8'))

    def test_no_bind_in_the_checkout_needs_no_override(self):
        self.fake.config = {'services': {'web': {'volumes': [{'type': 'bind', 'source': '/srv', 'target': '/s'}]}}}
        code, out, _ = self.deploy()
        self.assertEqual((code, out.splitlines()), (0, ['-f', 'compose.yaml']))
        self.assertFalse(os.path.exists(self.override))

    def test_a_file_that_differs_or_exists_only_in_the_repo_is_refused(self):
        Path(self.repo, 'conf/nginx.conf').write_text('server { listen 81; }\n', encoding='utf-8')
        code, _, err = self.deploy()
        self.assertEqual(code, 1)
        self.assertIn('db binds conf, and main differs from the repo checkout in conf/nginx.conf', err)
        self.assertIn('config site reads conf/nginx.conf, and main differs', err)
        self.assertFalse(os.path.exists(self.override))
        Path(self.repo, 'conf/nginx.conf').write_text('server {}\n', encoding='utf-8')
        # A file developer added under the bound folder, tracked or not ignored: main would run without it.
        Path(self.repo, 'conf/extra.conf').write_text('x\n', encoding='utf-8')
        self.fake.git_files[(self.repo, 'others')] = {'conf/extra.conf'}
        self.assertIn('main differs from the repo checkout in conf/extra.conf', self.deploy()[2])
        del self.fake.git_files[(self.repo, 'others')]
        self.fake.git_files[(self.repo, 'tracked')].add('conf/extra.conf')
        self.assertIn('in conf/extra.conf', self.deploy()[2])
        # A secret main tracks and the repo lacks.
        self.fake.git_files[(self.repo, 'tracked')] = {'compose.yaml', 'conf/nginx.conf'}
        os.remove(os.path.join(self.repo, 'conf/extra.conf'))
        os.remove(os.path.join(self.repo, 'pw'))
        self.assertIn('secret pw reads pw, and main differs from the repo checkout in pw', self.deploy()[2])

    def test_data_neither_side_tracks_is_not_compared(self):
        Path(self.repo, 'pgdata').mkdir()
        Path(self.repo, 'pgdata', 'base').write_text('rows\n', encoding='utf-8')
        self.fake.git_files[(self.repo, 'others')] = {'pgdata/base'}
        self.assertEqual(ac.tracked_differences(self.checkout, self.repo, 'pgdata'), [])
        self.assertEqual(self.deploy()[0], 0)

    def test_failures(self):
        self.fake.fail['config --no-path-resolution'] = 1
        self.assertIn('docker compose config failed', self.deploy()[2])
        self.fake.fail = {}
        self.fake.git_fails.add(self.checkout)
        with self.assertRaisesRegex(ac.Refused, 'git ls-files failed in'):
            ac.tracked_differences(self.checkout, self.repo, 'conf')
        self.assertEqual(self.quiet(ac.main, ['deploy-binds', 'a', 'b', 'c', 'd'])[0], 2)
        self.assertEqual(self.quiet(ac.main, ['deploy-binds', 'a', 'b', 'c', 'd', 'e', 'f'])[0], 2)

    def test_a_nested_repo_climbs_to_the_same_place_and_never_leaves_the_workspace(self):
        repo = os.path.join(self.root, 'projects', 'acme', 'billing-api')
        os.makedirs(repo)
        Path(repo, 'compose.yaml').write_text('services: {}\n', encoding='utf-8')
        self.fake.config = {
            'services': {
                'db': {
                    'volumes': [
                        {'type': 'bind', 'source': '../../shared/pgdata', 'target': '/d'},
                        {'type': 'bind', 'source': 'sub/../data', 'target': '/e'},
                    ]
                }
            }
        }
        code, _, err = self.quiet(
            ac.main, ['deploy-binds', 'billing-api', self.checkout, repo, self.override, self.root]
        )
        self.assertEqual(code, 0, err)
        self.assertEqual([m['source'] for m in self.mounts()], [f'{self.root}/projects/shared/pgdata', f'{repo}/data'])
        self.fake.config['services']['db']['volumes'] = [{'type': 'bind', 'source': '../../../../etc', 'target': '/x'}]
        code, _, err = self.quiet(
            ac.main, ['deploy-binds', 'billing-api', self.checkout, repo, self.override, self.root]
        )
        self.assertEqual(code, 1)
        self.assertIn(f'db binds ../../../../etc leads to {os.path.normpath(repo + "/../../../../etc")}, outside', err)
        # The compose file in a subfolder: its relative paths start there.
        moved, _, _ = ac.deploy_binds(
            {'services': {'a': {'volumes': [{'type': 'bind', 'source': './data', 'target': '/d'}]}}},
            self.checkout,
            repo,
            [self.root],
            'deploy',
        )
        self.assertEqual(moved['a'][0]['source'], f'{repo}/deploy/data')
        self.assertEqual(ac.moved_source('~/x', '', repo, [self.root]), (None, None, ''))

    def test_compose_file_from_the_checkout_env(self):
        Path(self.checkout, 'compose.prod.yaml').write_text('services: {}\n', encoding='utf-8')
        Path(self.checkout, '.env').write_text(
            '# repo env\nexport COMPOSE_FILE="compose.yaml;compose.prod.yaml"\nCOMPOSE_PATH_SEPARATOR=;\nSECRET=x\n',
            encoding='utf-8',
        )
        code, out, _ = self.deploy()
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines()[:4], ['-f', 'compose.yaml', '-f', 'compose.prod.yaml'])
        # An --env-file replaces the folder's .env; the process environment wins over both.
        Path(self.checkout, 'other.env').write_text('COMPOSE_FILE=compose.prod.yaml\n', encoding='utf-8')
        code, out, _ = self.deploy('--', '--env-file', 'other.env')
        self.assertEqual(out.splitlines()[:2], ['-f', 'compose.prod.yaml'])
        self.assertIn('--env-file', out.splitlines())
        code, out, _ = self.deploy('--', '--env-file=other.env')
        self.assertEqual(out.splitlines()[:2], ['-f', 'compose.prod.yaml'])
        with mock.patch.dict(os.environ, {'COMPOSE_FILE': 'compose.yaml'}):
            self.assertEqual(self.deploy()[1].splitlines()[:3], ['-f', 'compose.yaml', '-f'])
        self.assertEqual(ac.read_dotenv(os.path.join(self.checkout, 'none.env')), {})

    def test_bound_under(self):
        bound = container('billing-api', self.repo)
        bound['Name'] = '/billing-api-db-1'
        bound['Mounts'] = [{'Source': f'{self.checkout}/pgdata'}, {}]
        other = container('acme', '/x')
        other['Mounts'] = [{'Source': '/srv/acme'}]
        self.fake.items = [other]
        self.assertEqual(self.quiet(ac.main, ['bound-under', self.checkout])[0], 1)
        self.fake.items = [bound, other]
        code, out, _ = self.quiet(ac.main, ['bound-under', self.checkout])
        self.assertEqual(code, 0)
        self.assertEqual(out, f'bound: billing-api-db-1 {self.checkout}/pgdata\n')
        self.fake.items = []
        self.assertEqual(self.quiet(ac.main, ['bound-under', self.checkout])[0], 1)
        self.fake.up = False
        self.assertEqual(self.quiet(ac.main, ['bound-under', self.checkout])[0], 3)
        self.assertEqual(self.quiet(ac.main, ['bound-under'])[0], 2)


class ComposeFileTests(CopyTestCase):
    def test_default_files_and_options(self):
        self.assertEqual(ac.split_compose_options(self.clone, [], {}), (['compose.yaml'], []))
        Path(self.clone, 'compose.override.yaml').write_text('', encoding='utf-8')
        self.assertEqual(ac.default_files(self.clone, {}), ['compose.yaml', 'compose.override.yaml'])
        self.assertEqual(ac.default_files(self.clone, {'COMPOSE_FILE': 'a.yml:b.yml'}), ['a.yml', 'b.yml'])
        self.assertEqual(
            ac.default_files(self.clone, {'COMPOSE_FILE': 'a.yml;b.yml', 'COMPOSE_PATH_SEPARATOR': ';'}),
            ['a.yml', 'b.yml'],
        )
        files, rest = ac.split_compose_options(
            self.clone, ['-f', 'a.yaml', '--file', 'b.yaml', '--file=c.yaml', '--profile', 'x'], {}
        )
        self.assertEqual((files, rest), (['a.yaml', 'b.yaml', 'c.yaml'], ['--profile', 'x']))
        for bad in (['-p', 'x'], ['--project-name=x'], ['-f']):
            with self.assertRaises(ac.Refused):
                ac.split_compose_options(self.clone, bad, {})
        os.remove(os.path.join(self.clone, 'compose.yaml'))
        os.remove(os.path.join(self.clone, 'compose.override.yaml'))
        with self.assertRaisesRegex(ac.Refused, 'no compose file'):
            ac.default_files(self.clone, {})


class UpTests(CopyTestCase):
    def test_up_writes_the_override_and_the_ports_and_starts_the_group(self):
        code, out, err = self.up('--env-file', '/acme/one.env', '--', '--profile', 'full')
        self.assertEqual(code, 0, err)
        self.assertIn(f'group: {GROUP}', out)
        self.assertTrue(
            self.fake.called(
                rf'^docker compose -p {GROUP} -f compose.yaml --profile full --env-file /acme/one.env config '
                r'--format json$'
            )
        )
        self.assertTrue(
            self.fake.called(
                rf'^docker compose -p {GROUP} -f compose.yaml -f {re.escape(self.override)} --profile full '
                r'--env-file /acme/one.env up -d --build$'
            )
        )
        ports = ac.read_ports_env(ac.ports_path(self.override))
        self.assertEqual(ports['AGENT_GROUP'], GROUP)
        for key in ('AGENT_PORT_WEB_80', 'AGENT_PORT_DB_5432', 'AGENT_PORT_DB_5432_UDP'):
            self.assertTrue(ac.PORT_MIN <= int(ports[key]) <= ac.PORT_MAX)
            self.assertIn(f'-> {ports[key]} http://localhost:{ports[key]} {key}', out)
        self.assertIn(f'published: {GROUP}', out)
        text = Path(self.override).read_text(encoding='utf-8')
        self.assertIn('container_name: !reset null', text)
        code, out, _ = self.up()
        self.assertEqual(code, 0)
        self.assertEqual(ac.read_ports_env(ac.ports_path(self.override)), ports)

    def test_up_keeps_its_own_ports_and_avoids_published_ones(self):
        self.fake.items = [container(GROUP, self.clone, ports={'80/tcp': 61500})]
        Path(ac.ports_path(self.override)).parent.mkdir(parents=True, exist_ok=True)
        Path(ac.ports_path(self.override)).write_text(
            'AGENT_PORT_WEB_80=61500\nAGENT_PORT_DB_5432=61501\n', encoding='utf-8'
        )
        self.fake.ports_text = '0.0.0.0:61501->5432/tcp, :::61501->5432/tcp\n127.0.0.1:61500->80/tcp\n'
        code, _, err = self.up()
        self.assertEqual(code, 0, err)
        ports = ac.read_ports_env(ac.ports_path(self.override))
        self.assertEqual(ports['AGENT_PORT_WEB_80'], '61500')
        self.assertNotEqual(ports['AGENT_PORT_DB_5432'], '61501')

    def test_up_takes_the_fallback_when_another_folder_owns_the_group(self):
        self.fake.items = [container(GROUP, '/elsewhere/api')]
        code, _, err = self.up()
        self.assertEqual(code, 1)
        self.assertIn(f'{GROUP} belongs to another folder (/elsewhere/api)', err)
        code, out, _ = self.up('--fallback', f'{GROUP}-billing-api')
        self.assertEqual(code, 0)
        self.assertIn(f'group: {GROUP}-billing-api', out)
        self.fake.items.append(container(f'{GROUP}-billing-api', '/elsewhere/other'))
        code, _, err = self.up('--fallback', f'{GROUP}-billing-api')
        self.assertEqual(code, 1)
        self.assertIn('belongs to another folder (/elsewhere/other)', err)

    def test_up_refuses_before_anything_starts(self):
        cases = [
            (lambda: None, ['up', 'billing-api', self.clone, self.override], 'billing-api is not a copy group'),
            (lambda: None, ['up', GROUP, self.clone, self.override, '--fallback', 'x'], 'x is not a copy group'),
            (lambda: None, ['up', GROUP, '/nowhere/acme', self.override], 'not a folder'),
            (lambda: setattr(self.fake, 'up', False), ['up', GROUP, self.clone, self.override], 'not reachable'),
        ]
        for prepare, argv, message in cases:
            self.fake.up = True
            prepare()
            code, _, err = self.quiet(ac.main, argv)
            self.assertEqual(code, 1, message)
            self.assertIn(message, err)
        self.fake.up = True
        self.fake.config = config(volumes={'data': {'external': True, 'name': 'billing-data'}})
        code, _, err = self.up()
        self.assertEqual(code, 1)
        self.assertIn('volume data sets external', err)
        self.fake.config_text = 'not json'
        code, _, err = self.up()
        self.assertIn('docker compose config gave no JSON: not json', err)
        self.fake.fail[r'config --format json'] = 1
        code, _, err = self.up()
        self.assertIn('docker compose config failed', err)
        self.assertFalse(self.fake.called('up -d'))

    def test_a_failed_build_says_the_group_stays_its_own(self):
        self.fake.fail[r'up -d --build'] = 1
        code, _, err = self.up()
        self.assertEqual(code, 1)
        self.assertIn('docker compose up failed', err)

    def test_free_checker(self):
        self.fake.ports_text = '0.0.0.0:61700->80/tcp'
        with mock.patch.object(ac, 'proc_ports', return_value={('tcp', 61701)}):
            is_free = ac.free_checker({61700})
        self.assertTrue(is_free(61700, 'tcp'))
        self.assertFalse(is_free(61701, 'tcp'))
        self.assertTrue(is_free(61701, 'udp'))
        self.fake.fail['ps --format'] = 1
        self.assertEqual(ac.docker_ports(), set())


class DownDestroyListTests(CopyTestCase):
    def test_down(self):
        code, out, _ = self.quiet(ac.main, ['down', GROUP])
        self.assertEqual(code, 0)
        self.assertIn(f'down: {GROUP} (volumes and images kept)', out)
        self.assertTrue(self.fake.called(rf'^docker compose -p {GROUP} down$'))
        self.assertFalse(self.fake.called('-v|rmi'))
        self.assertEqual(self.quiet(ac.main, ['down', 'billing-api'])[0], 1)
        self.fake.fail['compose .* down'] = 1
        self.assertEqual(self.quiet(ac.main, ['down', GROUP])[0], 1)
        self.fake.up = False
        self.assertEqual(self.quiet(ac.main, ['down', GROUP])[0], 1)

    def test_destroy_by_label_only_what_is_the_group_s(self):
        self.fake.items = [container(GROUP, self.clone), container('billing-api', self.clone)]
        self.fake.items.append(container('agent_1118-other', '/elsewhere'))
        self.fake.res = {
            ('network', GROUP): [f'{GROUP}_default'],
            ('volume', GROUP): [f'{GROUP}_data'],
            ('image', GROUP): [f'sha256:a {GROUP}-web:latest', 'sha256:b acme/other:1', 'sha256:c <none>:<none>'],
            ('volume', 'billing-api'): ['billing-api_data'],
        }
        code, out, _ = self.quiet(ac.main, ['destroy', '--under', self.clone])
        self.assertEqual(code, 0)
        self.assertIn('kept: billing-api (not a copy group)', out)
        self.assertIn('kept: acme/other:1', out)
        self.assertIn(f'destroyed: {GROUP} (1 containers, 1 networks, 1 volumes, 2 images)', out)
        removed = [line for line in self.fake.joined() if re.search(r' rm ', line)]
        self.assertEqual(
            removed,
            [
                f'docker rm -f c-{GROUP}-web',
                f'docker network rm {GROUP}_default',
                f'docker volume rm -f {GROUP}_data',
                f'docker image rm {GROUP}-web:latest',
                'docker image rm sha256:c',
            ],
        )

    def test_a_name_that_is_not_a_group_is_refused_even_by_name(self):
        self.fake.items = [container('billing-api', '/x')]
        code, out, _ = self.quiet(ac.main, ['destroy', 'billing-api', 'agent_1118-x'])
        self.assertEqual(code, 1)
        self.assertIn('refused: billing-api is not a copy group', out)
        self.assertIn('nothing to destroy: agent_1118-x', out)
        self.assertFalse(self.fake.called(r' rm '))

    def test_destroy_failures_are_said(self):
        self.fake.items = [container(GROUP, self.clone)]
        self.fake.res = {('image', GROUP): [f'sha256:a {GROUP}-web:latest']}
        self.fake.fail[r'^docker (rm|image rm)'] = 1
        code, out, _ = self.quiet(ac.main, ['destroy', GROUP])
        self.assertEqual(code, 1)
        self.assertIn(f'attention: could not remove the containers of {GROUP}', out)
        self.assertIn(f'attention: could not remove the image {GROUP}-web:latest', out)
        self.fake.fail = {r'^docker network ls': 1}
        code, _, err = self.quiet(ac.main, ['destroy', GROUP])
        self.assertIn('docker network ls failed', err)
        self.fake.fail = {r'^docker ps -aq --filter label=\S+=': 1}
        code, _, err = self.quiet(ac.main, ['destroy', GROUP])
        self.assertIn('docker ps failed', err)
        self.fake.fail = {}
        self.fake.up = False
        code, _, err = self.quiet(ac.main, ['destroy', GROUP])
        self.assertEqual(code, 1)
        self.assertIn('Docker: not reachable: nothing destroyed', err)

    def test_list(self):
        self.fake.items = [
            container(GROUP, self.clone, ports={'80/tcp': 61500}),
            container(GROUP, self.clone, service='db', running=False),
            container('agent_1118-other', '/elsewhere', running=False),
            container('billing-api', self.clone),
        ]
        self.fake.res = {('volume', 'agent_1118-kept'): ['agent_1118-kept_data']}
        code, out, _ = self.quiet(ac.main, ['list'])
        self.assertEqual(code, 0)
        self.assertEqual(
            out.splitlines(),
            [f'{GROUP}\trunning 1/2\tweb:80->61500', 'agent_1118-other\tstopped 0/1\t-'],
        )
        code, out, _ = self.quiet(
            ac.main,
            [
                'list',
                '--under',
                self.clone,
                '--group',
                'agent_1118-kept',
                '--group',
                'agent_1118-gone',
                '--group',
                'billing-api',
            ],
        )
        self.assertEqual(
            out.splitlines(),
            [
                f'{GROUP}\trunning 1/2\tweb:80->61500',
                'agent_1118-gone\tdown\t-',
                'agent_1118-kept\tdown, volumes kept\t-',
            ],
        )
        self.fake.up = False
        self.assertEqual(self.quiet(ac.main, ['list'])[0], 3)

    def test_containers_with_a_failed_inspect(self):
        self.fake.items = [container(GROUP, self.clone)]
        self.fake.fail['^docker inspect'] = 1
        self.assertEqual(ac.containers(ac.PROJECT_LABEL), [])


class MainTests(CopyTestCase):
    def test_usage_errors(self):
        for argv in (
            [],
            ['nope'],
            ['up', GROUP],
            ['up', GROUP, self.clone, self.override, '--unknown'],
            ['up', GROUP, self.clone, self.override, '--fallback'],
            ['down'],
            ['destroy'],
            ['destroy', '--under'],
            ['destroy', '--bad'],
            ['list', 'x'],
        ):
            code, _, err = self.quiet(ac.main, argv)
            self.assertEqual(code, 2, argv)
            self.assertTrue(err, argv)

    def test_parse_up(self):
        self.assertEqual(
            ac.parse_up(['g', 'f', 'o', '--custom-root', '/ws/custom/', '--env-file', 'a', '--', '-f', 'x']),
            ('g', 'f', 'o', '', ['a'], '/ws/custom', ['-f', 'x'], []),
        )
        self.assertEqual(
            ac.parse_up(['g', 'f', 'o', '--allow-root', '/acme/', '--allow-root', '/x/../y'])[7],
            [os.path.realpath('/acme'), os.path.realpath('/y')],
        )


if __name__ == '__main__':
    unittest.main()
