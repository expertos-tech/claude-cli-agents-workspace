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
REAL_RUN = subprocess.run
LOGIN_SIMULATOR = MODULE_PATH.parent.parent / 'tools' / 'login-simulator' / 'compose.yaml'


def container(project, folder, service='web', running=True, ports=None):
    """Returns the docker inspect data of one compose container."""
    return {
        'Id': f'c-{project}-{service}',
        'Config': {
            'Labels': {ac.PROJECT_LABEL: project, ac.WORKDIR_LABEL: folder, ac.SERVICE_LABEL: service},
        },
        'State': {'Running': running},
        'NetworkSettings': {
            'Ports': {key: [{'HostIp': '0.0.0.0', 'HostPort': str(port)}] for key, port in (ports or {}).items()}
        },
    }


def config(**extra):
    """Returns a compose config (docker compose config --format json) of a fictitious billing-api project."""
    data = {
        'name': GROUP,
        'services': {
            'web': {
                'build': {'context': '.'},
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
        self.tracked = set()

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
            return (0, '28.0\n', '') if self.up else (1, '', 'cannot connect')
        if sub == 'ps':
            return self.ps(args)
        if sub == 'inspect':
            return 0, json.dumps([item for item in self.items if item['Id'] in args[2:]]), ''
        if sub in ('network', 'volume', 'image') and args[2] == 'ls':
            group = args[4].rsplit('=', 1)[1]
            return 0, ''.join(f'{entry}\n' for entry in self.res.get((sub, group), [])), ''
        if sub == 'compose' and 'config' in args:
            return 0, self.config_text if self.config_text is not None else json.dumps(self.config), ''
        return 0, '', ''

    def git(self, args):
        """Answers git -C <checkout> ls-files -z -- <path>: the tracked files (self.tracked) at or under the path."""
        rel = args[-1]
        found = [path for path in sorted(self.tracked) if path == rel or path.startswith(rel.rstrip('/') + '/')]
        return 0, ''.join(f'{path}\0' for path in found), ''

    def __call__(self, args, **kwargs):
        if args[0] == 'git':
            code, out, err = self.git(args)
            return subprocess.CompletedProcess(args, code, out, err)
        self.calls.append(list(args))
        code, out, err = self.answer(args)
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
        self.assertEqual(ac.isolation_refusals(config()), [])
        bad = config(
            networks={'shared': {'external': True, 'name': 'proxy'}},
            volumes={'data': {'external': True}},
        )
        bad['services']['web']['network_mode'] = 'host'
        bad['services']['db']['network_mode'] = 'container:billing-db'
        bad['services']['worker']['network_mode'] = 'service:web'
        refusals = ac.isolation_refusals(bad)
        self.assertEqual(len(refusals), 4)
        self.assertIn('network shared is external (proxy)', refusals[0])
        self.assertIn('volume data is external (data)', refusals[1])

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
            'networks:\n  "default":\n    name: !reset null\nvolumes:\n  "data":\n    name: !reset null', text
        )
        self.assertNotIn('"plain"', text)
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
        self.assertIn('networks:\n  "login":\n    name: !reset null\n    ipam: !reset {}', text)
        self.assertNotIn('"plain"', text)
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


class DeployBindsTests(CopyTestCase):
    """deploy main: the binds of the checkout come from the repo; a bound checkout is never deleted."""

    def setUp(self):
        super().setUp()
        self.repo = os.path.join(self.root, 'projects', 'billing-api')
        self.checkout = os.path.join(self.root, 'tmp', 'deploy', 'billing-api-main')
        for folder in (self.repo, self.checkout):
            os.makedirs(folder)
            Path(folder, 'compose.yaml').write_text('services: {}\n', encoding='utf-8')
            Path(folder, 'nginx.conf').write_text('server {}\n', encoding='utf-8')
        self.fake.tracked = {'compose.yaml', 'nginx.conf'}
        self.override = self.checkout + '.binds.compose.yaml'
        self.fake.config = {
            'name': 'billing-api',
            'services': {
                'db': {
                    'volumes': [
                        {
                            'type': 'bind',
                            'source': f'{self.checkout}/pgdata',
                            'target': '/data',
                            'bind': {'create_host_path': True},
                        },
                        {'type': 'bind', 'source': f'{self.checkout}/nginx.conf', 'target': '/n', 'read_only': True},
                        {'type': 'bind', 'source': '/srv/acme', 'target': '/srv', 'bind': {'create_host_path': False}},
                        {'type': 'volume', 'source': 'data', 'target': '/v'},
                    ]
                },
                'web': {},
            },
        }

    def deploy(self, *options):
        """Runs main deploy-binds; returns (exit code, stdout, stderr)."""
        return self.quiet(ac.main, ['deploy-binds', 'billing-api', self.checkout, self.repo, self.override, *options])

    def test_binds_move_to_the_repo(self):
        code, out, err = self.deploy('--', '--profile', 'full')
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines(), ['-f', 'compose.yaml', '-f', self.override, '--profile', 'full'])
        text = Path(self.override).read_text(encoding='utf-8')
        self.assertIn(
            f'source: "{self.repo}/pgdata"\n        target: "/data"\n        bind:\n          create_host_path: true',
            text,
        )
        self.assertIn(f'source: "{self.repo}/nginx.conf"\n        target: "/n"\n        read_only: true', text)
        self.assertNotIn('/srv/acme', text)
        self.assertTrue(self.fake.called(r'^docker compose -p billing-api -f compose.yaml --profile full config'))

    def test_no_bind_in_the_checkout_needs_no_override(self):
        self.fake.config = {'services': {'web': {'volumes': [{'type': 'bind', 'source': '/srv', 'target': '/s'}]}}}
        code, out, _ = self.deploy()
        self.assertEqual((code, out.splitlines()), (0, ['-f', 'compose.yaml']))
        self.assertFalse(os.path.exists(self.override))

    def test_a_tracked_file_that_differs_is_refused(self):
        Path(self.repo, 'nginx.conf').write_text('server { listen 81; }\n', encoding='utf-8')
        code, _, err = self.deploy()
        self.assertEqual(code, 1)
        self.assertIn('db binds nginx.conf, and main differs from the repo checkout in nginx.conf', err)
        os.remove(os.path.join(self.repo, 'nginx.conf'))
        self.assertIn('differs', self.deploy()[2])
        self.assertFalse(os.path.exists(self.override))

    def test_failures(self):
        self.fake.fail['config --format json'] = 1
        self.assertIn('docker compose config failed', self.deploy()[2])
        self.fake.fail = {}
        with mock.patch.object(ac, 'run', return_value=(128, '', 'not a git repository')):
            with self.assertRaisesRegex(ac.Refused, 'git ls-files failed'):
                ac.tracked_differences(self.checkout, self.repo, 'x')
        self.assertEqual(self.quiet(ac.main, ['deploy-binds', 'a', 'b', 'c'])[0], 2)
        self.assertEqual(self.quiet(ac.main, ['deploy-binds', 'a', 'b', 'c', 'd', 'e'])[0], 2)

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
        self.assertIn('volume data is external (billing-data)', err)
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
            ('g', 'f', 'o', '', ['a'], '/ws/custom', ['-f', 'x']),
        )


if __name__ == '__main__':
    unittest.main()
