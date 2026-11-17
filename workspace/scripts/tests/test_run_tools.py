"""Unit tests of scripts/run-tools.py (the work behind /run-tools), in-process so the coverage gate measures them.

Every command the module runs goes through subprocess.run, replaced here by FakeCommands: no docker, systemctl,
launchctl or make is reached. The tools are fictitious (acme-*); tests/run-tools/test-run-tools.sh covers the same
behavior end to end through run-tools.sh.
"""

import contextlib
import importlib.util
import io
import json
import os
import re
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / 'run-tools.py'
SPEC = importlib.util.spec_from_file_location('run_tools', MODULE_PATH)
rt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rt)

GROUP = 'acme-tools'
WEB_PORT, STORE_PORT, METRICS_PORT = 18081, 18082, 18083
GROUP_YAML = """# fictitious group
name: acme-tools
name: ignored-second-name
include:
  - acme-web/compose.yaml
  - path: acme-store/compose.yaml
  - "acme-metrics/compose.yaml"
  - not-a-compose-line
"""
WEB_YAML = """name: acme-web
services:
  web:
    build:
      context: .
    x-run-tools:
      description: 'Fictitious web tool: it''s a test'
      title: "Acme \\"web\\""
      url: http://localhost:18081
networks:
  default:
    name: acme-web_default
"""
STORE_YAML = """name: acme-store
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
"""
METRICS_YAML = """name: acme-metrics
services:
  metrics:
    image: acme/metrics:3.0
    x-run-tools:
      title: Acme metrics
      url: http://localhost:2
"""


def container(cid, project, service, running=True, port=None, image='sha256:img'):
    """Returns the docker inspect data of one compose container."""
    ports = {'80/tcp': [{'HostIp': '127.0.0.1', 'HostPort': str(port)}]} if port else {}
    return {
        'Id': cid,
        'Name': f'/{project}-{service}-1',
        'Image': image,
        'State': {'Running': running},
        'Config': {'Labels': {rt.PROJECT_LABEL: project, rt.SERVICE_LABEL: service}},
        'NetworkSettings': {'Ports': ports},
    }


class FakeCommands:
    """Stands in for subprocess.run: answers docker, uname, dpkg-query, rpm, systemctl, launchctl and make from the
    state the test sets, and records every call. A regex of `fail` matched on the joined argv returns its (code,
    stderr) before anything else."""

    def __init__(self, root):
        self.root = root
        self.calls = []
        self.fail = {}
        self.uname, self.engine, self.dpkg, self.rpm = 'Linux', '', False, False
        self.active, self.activate_on_start = False, True
        self.containers = []
        self.networks, self.volumes, self.images = {}, set(), {}
        self.image_ls = ''
        self.config_json = {
            'acme-web': {
                'name': 'acme-web',
                'services': {
                    'web': {
                        'image': 'acme/web:1.0',
                        'build': {'context': '.'},
                        'ports': [{'host_ip': '127.0.0.1', 'target': 8080, 'published': str(WEB_PORT)}],
                        'volumes': [
                            {'type': 'bind', 'source': f'{root}/custom/config/acme-web/users.json', 'target': '/c'},
                            {
                                'type': 'bind',
                                'source': f'{root}/tools/acme-web/.data',
                                'target': '/data',
                                'bind': {'create_host_path': True},
                            },
                        ],
                    }
                },
                'networks': {'default': {'name': 'acme-web_default'}},
            },
            'acme-store': {
                'name': 'acme-store',
                'services': {
                    'store': {
                        'image': 'acme/store:2.0@sha256:abc',
                        'ports': [{'host_ip': '127.0.0.1', 'target': 10000, 'published': STORE_PORT}],
                        'volumes': [{'type': 'volume', 'source': 'data', 'target': '/data'}],
                    },
                    'app': {'build': {'context': '.'}},
                },
                'volumes': {'data': {'name': 'acme-store_data'}},
            },
            'acme-metrics': {
                'name': 'acme-metrics',
                'services': {
                    'metrics': {
                        'image': 'acme/metrics:3.0',
                        'stop_grace_period': '45s',
                        'ports': [{'host_ip': '127.0.0.1', 'target': 3000, 'published': METRICS_PORT}],
                    }
                },
                'networks': {'metrics': {'name': 'acme-metrics'}},
            },
        }
        self.config_yaml = {'acme-web': WEB_YAML, 'acme-store': STORE_YAML, 'acme-metrics': METRICS_YAML}

    def joined(self):
        """Returns every recorded call as one line of text each."""
        return [' '.join(call) for call in self.calls]

    def called(self, pattern):
        """Tells whether a recorded call matches the regex."""
        return any(re.search(pattern, line) for line in self.joined())

    def compose(self, args):
        """Answers docker compose config (JSON or YAML of the tool of -f) and up/stop."""
        file = args[args.index('-f') + 1]
        tool = os.path.basename(os.path.dirname(file))
        if 'config' in args:
            if '--format' in args:
                data = self.config_json.get(tool)
                if data is None:
                    return 1, '', f'open {file}: no such file or directory\n'
                return 0, json.dumps(data), ''
            text = self.config_yaml.get(tool)
            return (1, '', 'bad yaml') if text is None else (0, text, '')
        return 0, '', ''

    def docker(self, args):
        """Answers the docker subcommands run-tools.py runs."""
        sub = args[1]
        if sub == 'compose':
            return self.compose(args)
        if sub == 'ps':
            return 0, '\n'.join(item['Id'] for item in self.containers), ''
        if sub == 'inspect':
            return 0, json.dumps(self.containers), ''
        if sub == 'version':
            return (0, self.engine + '\n', '') if self.engine else (1, '', 'no server')
        if sub == 'image':
            if args[2] == 'inspect':
                ref = args[-1]
                return (0, self.images[ref] + '\n', '') if ref in self.images else (1, '', 'no such image')
            if args[2] == 'ls':
                return 0, self.image_ls, ''
            return 0, '', ''
        if sub == 'network':
            name = args[3]
            if args[2] == 'inspect':
                return (0, json.dumps([self.networks[name]]), '') if name in self.networks else (1, '', 'no network')
            self.networks.pop(name, None)
            return 0, '', ''
        if sub == 'volume':
            if args[2] == 'inspect':
                return (0, '[]', '') if args[3] in self.volumes else (1, '', 'no volume')
            if args[2] == 'create':
                self.volumes.add(args[-1])
            if args[2] == 'rm':
                self.volumes.discard(args[3])
            return 0, '', ''
        return 0, '', ''

    def answer(self, args):
        """Returns (code, stdout, stderr) of a command."""
        line = ' '.join(args)
        for pattern, (code, err) in self.fail.items():
            if re.search(pattern, line):
                return code, '', err
        cmd = args[0]
        if cmd == 'docker':
            return self.docker(args)
        if cmd == 'uname':
            return 0, self.uname + '\n', ''
        if cmd == 'dpkg-query':
            return (0, 'install ok installed', '') if self.dpkg else (1, '', '')
        if cmd == 'rpm':
            return (0 if self.rpm else 1), '', ''
        if cmd == 'systemctl':
            if args[2] == 'is-active':
                return (0, 'active\n', '') if self.active else (3, 'inactive\n', '')
            self.active = self.activate_on_start if args[2] == 'start' else False
            return 0, '', ''
        if cmd == 'launchctl':
            if args[1] == 'print':
                return (0, 'state = running\n', '') if self.active else (113, '', 'not found')
            if args[1] == 'kickstart':
                self.active = self.activate_on_start
            if args[1] == 'bootout':
                self.active = False
            return 0, '', ''
        if cmd == 'make':
            self.active = True
            return 0, '', ''
        raise FileNotFoundError(cmd)

    def __call__(self, args, **kwargs):
        self.calls.append(list(args))
        code, out, err = self.answer(args)
        return subprocess.CompletedProcess(args, code, out, err)


class RunToolsTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.realpath(self.tmp.name)
        for folder in (
            'tools/acme-web',
            'tools/acme-store',
            'tools/acme-metrics',
            'custom/env',
            'custom/config/acme-web',
        ):
            os.makedirs(os.path.join(self.root, folder))
        self.write('tools/compose.yaml', GROUP_YAML)
        self.write('custom/config/acme-web/users.json', '{}\n')
        self.home = os.path.join(self.root, 'home')
        env = mock.patch.dict(os.environ, {'HOME': self.home, 'XDG_CONFIG_HOME': os.path.join(self.home, '.config')})
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop('STORE_KEY', None)
        self.fake = FakeCommands(self.root)
        self.commands = {'docker', 'make', 'go', 'npm'}
        for target, attr, value in (
            (rt.subprocess, 'run', self.fake),
            (rt.shutil, 'which', lambda name: f'/usr/bin/{name}' if name in self.commands else None),
            (rt, 'port_open', lambda port, host='': False),
            (rt.time, 'sleep', lambda seconds: None),
        ):
            patcher = mock.patch.object(target, attr, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)

    def write(self, relative, text):
        """Writes a file of the temp workspace, creating its folder."""
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(text)
        return path

    def quiet(self, func, *args):
        """Calls func with stdout and stderr captured; returns (result, stdout, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = func(*args)
        return result, out.getvalue(), err.getvalue()

    def tools(self):
        """Returns {id: tool} of the model of the temp workspace."""
        _, _, tools = rt.model(self.root)
        return {tool['id']: tool for tool in tools}

    def docker_ce_machine(self):
        """Makes the fake machine a Linux one with Docker Engine - Community."""
        self.fake.engine = 'Docker Engine - Community'

    def install_unit(self, tool_id):
        """Writes the service file of a console, as its installer would."""
        path = rt.machine_unit(tool_id)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Path(path).touch()


class RunTests(unittest.TestCase):
    def test_run_returns_the_code_and_output(self):
        done = subprocess.CompletedProcess(['x'], 0, 'out', 'err')
        with mock.patch.object(rt.subprocess, 'run', return_value=done) as call:
            self.assertEqual(rt.run(['x'], '/w', timeout=3), (0, 'out', 'err'))
        self.assertEqual(call.call_args.kwargs['cwd'], '/w')
        self.assertEqual(call.call_args.kwargs['timeout'], 3)

    def test_run_maps_a_missing_command_and_a_timeout(self):
        with mock.patch.object(rt.subprocess, 'run', side_effect=FileNotFoundError):
            self.assertEqual(rt.run(['acme'], '/w'), (127, '', 'acme not found'))
        with mock.patch.object(rt.subprocess, 'run', side_effect=subprocess.TimeoutExpired('acme', 1)):
            self.assertEqual(rt.run(['acme'], '/w'), (124, '', 'acme timed out'))

    def test_run_with_check_raises_on_failure(self):
        failed = subprocess.CompletedProcess(['docker'], 1, 'from stdout\n', '\n  first error\nsecond\n')
        with mock.patch.object(rt.subprocess, 'run', return_value=failed):
            with self.assertRaisesRegex(rt.Refused, r'^docker tag a failed: first error$'):
                rt.run(['docker', 'tag', 'a', 'b'], '/w', check=True)
        failed = subprocess.CompletedProcess(['docker'], 1, 'from stdout\n', '')
        with mock.patch.object(rt.subprocess, 'run', return_value=failed):
            with self.assertRaisesRegex(rt.Refused, 'failed: from stdout'):
                rt.run(['docker'], '/w', check=True)
            self.assertEqual(rt.run(['docker'], '/w')[0], 1)

    def test_run_live_returns_the_exit_code(self):
        with mock.patch.object(rt.subprocess, 'run', return_value=subprocess.CompletedProcess(['x'], 3)):
            self.assertEqual(rt.run_live(['x'], '/w'), 3)
        with mock.patch.object(rt.subprocess, 'run', side_effect=FileNotFoundError):
            self.assertEqual(rt.run_live(['x'], '/w'), 127)

    def test_first_line_and_say(self):
        self.assertEqual(rt.first_line(None), '')
        self.assertEqual(rt.first_line('\n \n  a  \nb'), 'a')
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rt.say('hello')
        self.assertEqual(out.getvalue(), 'hello\n')

    def test_port_open_on_a_real_local_socket(self):
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen()
            port = server.getsockname()[1]
            self.assertTrue(rt.port_open(port))
            self.assertTrue(rt.port_open(port, '0.0.0.0'))
            self.assertTrue(rt.port_open(port, '127.0.0.1'))
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            closed = probe.getsockname()[1]
        self.assertFalse(rt.port_open(closed, '::'))


class ParsingTests(RunToolsTestCase):
    def test_group_layout_reads_the_name_and_every_include_form(self):
        self.write('tools/compose.yaml', GROUP_YAML + "  - 'acme-extra/compose.yml'\n")
        self.assertEqual(rt.group_layout(self.root), (GROUP, ['acme-web', 'acme-store', 'acme-metrics', 'acme-extra']))

    def test_group_layout_refuses_a_missing_file_or_name(self):
        os.remove(os.path.join(self.root, 'tools/compose.yaml'))
        with self.assertRaisesRegex(rt.Refused, 'cannot read tools/compose.yaml'):
            rt.group_layout(self.root)
        self.write('tools/compose.yaml', 'include:\n  - acme-web/compose.yaml\n')
        with self.assertRaisesRegex(rt.Refused, 'has no name: line'):
            rt.group_layout(self.root)

    def test_read_env_file(self):
        path = self.write(
            'custom/env/acme.env',
            '# comment\n\nexport A=1\nB = "two words"\nC=\'single\'\nD="\nE=x=y\nnot a pair\n',
        )
        self.assertEqual(rt.read_env_file(path), {'A': '1', 'B': 'two words', 'C': 'single', 'D': '"', 'E': 'x=y'})
        self.assertEqual(rt.read_env_file(os.path.join(self.root, 'missing.env')), {})

    def test_env_args_only_for_existing_files(self):
        path = self.write('custom/env/acme-store.env', 'STORE_KEY=k\n')
        self.assertEqual(rt.env_args(self.root, ['acme-web', 'acme-store']), ['--env-file', path])

    def test_unquote(self):
        self.assertEqual(rt.unquote(' "Acme \\"web\\"" '), 'Acme "web"')
        self.assertEqual(rt.unquote('"broken'), 'broken')
        self.assertEqual(rt.unquote("'it''s'"), "it's")
        self.assertEqual(rt.unquote("'"), "'")
        self.assertEqual(rt.unquote('plain'), 'plain')

    def test_extensions_reads_only_the_blocks_of_services(self):
        text = (
            'name: x\nx-top:\n  a:\n    x-run-tools:\n      title: no\n\nservices:\n  one:\n    image: i\n'
            '    x-run-tools:\n      title: One\n      requires:\n        - A\n        - "B"\n      url: u\n'
            '        - stray\n    ports:\n      - 1\n        - 2\n  two:\n    image: j\nvolumes:\n  data: {}\n'
        )
        self.assertEqual(rt.extensions(text), {'one': {'title': 'One', 'requires': ['A', 'B'], 'url': 'u'}})

    def test_grace_seconds(self):
        self.assertEqual(rt.grace_seconds(None), 10)
        self.assertEqual(rt.grace_seconds('45s'), 45)
        self.assertEqual(rt.grace_seconds('1m30s'), 90)
        self.assertEqual(rt.grace_seconds('1h'), 3600)
        self.assertEqual(rt.grace_seconds('500ms'), 1)

    def test_image_name(self):
        self.assertEqual(rt.image_name('acme/store:2.0@sha256:abc'), 'acme/store')
        self.assertEqual(rt.image_name('registry.example.com:5000/acme/web'), 'registry.example.com:5000/acme/web')
        self.assertEqual(rt.image_name('registry.example.com:5000/acme/web:1.0'), 'registry.example.com:5000/acme/web')
        self.assertEqual(rt.image_name('acme-tools-app'), 'acme-tools-app')


class ComposeToolTests(RunToolsTestCase):
    def compose(self, tool_id):
        """Returns compose_tool of one tool of the temp workspace."""
        return rt.compose_tool(self.root, GROUP, ['acme-web', 'acme-store', 'acme-metrics'], tool_id)

    def test_a_tool_with_its_configuration(self):
        web = self.compose('acme-web')
        self.assertEqual((web['title'], web['description']), ('Acme "web"', "Fictitious web tool: it's a test"))
        self.assertEqual(web['url'], 'http://localhost:18081')
        self.assertEqual(web['missing'], [])
        service = web['services'][0]
        self.assertEqual(service['ports'], [{'host_ip': '127.0.0.1', 'port': WEB_PORT}])
        self.assertEqual(service['needed_files'], [f'{self.root}/custom/config/acme-web/users.json'])
        self.assertTrue(service['build'])
        self.assertEqual(web['networks'], [{'key': 'default', 'name': 'acme-web_default', 'fixed': False}])

    def test_named_volumes_default_images_and_fixed_networks(self):
        store = self.compose('acme-store')
        self.assertEqual(store['requires'], ['STORE_KEY'])
        by_name = {s['name']: s for s in store['services']}
        self.assertEqual(by_name['app']['image'], 'acme-tools-app')
        self.assertEqual(by_name['store']['named_volumes'], ['data'])
        self.assertEqual(store['volumes'], [{'key': 'data', 'old': 'acme-store_data', 'new': 'acme-tools_data'}])
        metrics = self.compose('acme-metrics')
        self.assertEqual(metrics['services'][0]['grace'], 45)
        self.assertEqual(metrics['networks'], [{'key': 'metrics', 'name': 'acme-metrics', 'fixed': True}])

    def test_external_and_explicitly_named_resources_are_left_alone(self):
        data = self.fake.config_json['acme-metrics']
        data['networks'] = {'ext': {'external': True}, 'plain': {}}
        data['volumes'] = {'ext': {'external': True}, 'shared': {'name': 'acme-shared'}, 'own': {}}
        data['services']['metrics']['ports'] = [{'target': 1}, {'published': '9000-9001'}]
        metrics = self.compose('acme-metrics')
        self.assertEqual(metrics['networks'], [{'key': 'plain', 'name': 'acme-metrics_plain', 'fixed': False}])
        self.assertEqual(metrics['volumes'], [{'key': 'own', 'old': 'acme-metrics_own', 'new': 'acme-tools_own'}])
        self.assertEqual(metrics['services'][0]['ports'], [{'host_ip': '', 'port': 9000}])

    def test_a_compose_error_or_an_unreadable_yaml(self):
        self.fake.config_json['acme-web'] = None
        web = self.compose('acme-web')
        self.assertEqual(web['missing'], ['compose error: open tools/acme-web/compose.yaml: no such file or directory'])
        self.fake.config_yaml['acme-metrics'] = None
        metrics = self.compose('acme-metrics')
        self.assertEqual((metrics['title'], metrics['url']), ('acme-metrics', ''))

    def test_an_empty_title_keeps_the_id(self):
        self.fake.config_yaml['acme-metrics'] = METRICS_YAML.replace('title: Acme metrics', "title: ''")
        self.assertEqual(self.compose('acme-metrics')['title'], 'acme-metrics')

    def test_missing_files_and_variables(self):
        os.remove(os.path.join(self.root, 'custom/config/acme-web/users.json'))
        self.assertEqual(
            self.compose('acme-web')['missing'],
            ['configuration missing: custom/config/acme-web/users.json (README of tools/acme-web)'],
        )
        tool = {'id': 'acme-x', 'requires': [], 'missing': []}
        tool['services'] = [{'needed_files': ['', '/nowhere/acme.json']}]
        rt.check_configuration(self.root, [], tool)
        self.assertEqual(tool['missing'], ['configuration missing: /nowhere/acme.json (README of tools/acme-x)'])
        store = self.compose('acme-store')
        self.assertIn('create it with /local-env tools/acme-store', store['missing'][0])
        self.write('custom/env/acme-store.env', 'STORE_KEY=\n')
        self.assertEqual(
            self.compose('acme-store')['missing'], ['configuration missing: STORE_KEY in custom/env/acme-store.env']
        )
        os.remove(os.path.join(self.root, 'custom/env/acme-store.env'))
        self.write('custom/env/acme-web.env', 'STORE_KEY=from-another-file\n')
        self.assertEqual(self.compose('acme-store')['missing'], [])
        os.remove(os.path.join(self.root, 'custom/env/acme-web.env'))
        with mock.patch.dict(os.environ, {'STORE_KEY': 'from-env'}):
            self.assertEqual(self.compose('acme-store')['missing'], [])


class RuntimeTests(RunToolsTestCase):
    def test_containers(self):
        self.assertEqual(rt.containers(self.root), [])
        self.fake.fail['docker ps'] = (1, 'no daemon')
        self.assertEqual(rt.containers(self.root), [])
        del self.fake.fail['docker ps']
        item = container('c1', GROUP, 'web', port=WEB_PORT)
        item['NetworkSettings']['Ports']['81/tcp'] = None
        item['NetworkSettings']['Ports']['82/tcp'] = [{'HostPort': ''}]
        self.fake.containers = [item, {'Id': 'c2'}]
        found = rt.containers(self.root)
        self.assertEqual(found[0]['ports'], {WEB_PORT})
        self.assertEqual(
            (found[0]['name'], found[0]['project'], found[0]['running']), ('acme-tools-web-1', GROUP, True)
        )
        self.assertEqual((found[1]['name'], found[1]['ports'], found[1]['running']), ('', set(), False))
        self.fake.fail['docker inspect'] = (1, 'gone')
        self.assertEqual(rt.containers(self.root), [])

    def test_states_and_busy_ports(self):
        self.write('custom/env/acme-store.env', 'STORE_KEY=k\n')
        self.fake.containers = [
            container('x1', 'billing-api', 'api', port=METRICS_PORT),
            container('c1', GROUP, 'web', port=WEB_PORT),
            container('o1', 'acme-store', 'store', running=False, port=STORE_PORT),
        ]
        tools = self.tools()
        self.assertEqual((tools['acme-web']['state'], tools['acme-web']['missing']), ('up', []))
        self.assertEqual(tools['acme-metrics']['missing'], [f'port {METRICS_PORT} busy: container billing-api-api-1'])
        self.assertEqual((tools['acme-store']['state'], tools['acme-store']['project']), ('stopped', 'acme-store'))
        with mock.patch.object(rt, 'port_open', return_value=True):
            tools = self.tools()
        self.assertEqual(tools['acme-store']['missing'], [f'port {STORE_PORT} busy: another process'])
        self.assertEqual(tools['acme-web']['missing'], [])

    def test_a_tool_up_in_its_old_project(self):
        self.fake.containers = [container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT)]
        metrics = self.tools()['acme-metrics']
        self.assertEqual((metrics['state'], metrics['project'], metrics['missing']), ('up', 'acme-metrics', []))

    def test_without_docker_every_compose_tool_says_so(self):
        self.commands.discard('docker')
        tools = self.tools()
        self.assertEqual(tools['acme-web']['missing'], ['docker not found'])
        self.assertFalse(self.fake.called('^docker (compose|ps|inspect)'))


class MachineTests(RunToolsTestCase):
    def test_docker_ce_detection(self):
        self.assertFalse(rt.docker_ce(self.root))
        self.fake.rpm = True
        self.assertTrue(rt.docker_ce(self.root))
        self.fake.rpm, self.fake.dpkg = False, True
        self.assertTrue(rt.docker_ce(self.root))
        self.fake.dpkg, self.fake.engine = False, 'Docker Desktop'
        self.assertFalse(rt.docker_ce(self.root))
        self.docker_ce_machine()
        self.assertTrue(rt.docker_ce(self.root))

    def test_uname_failure_shows_no_console(self):
        self.fake.fail['^uname'] = (1, 'no uname')
        self.assertEqual(rt.uname(self.root), '')
        self.assertEqual(rt.machine_tools(self.root), [])

    def test_docker_ce_console_states(self):
        self.docker_ce_machine()
        self.commands.discard('go')
        self.commands.discard('npm')
        tool = rt.machine_tools(self.root)[0]
        self.assertEqual((tool['id'], tool['state']), ('container-console-docker-ce', 'not installed'))
        self.assertEqual(
            tool['missing'], ['to install it: go, npm on PATH (README of tools/container-console-docker-ce)']
        )
        self.commands.update({'go', 'npm'})
        self.assertEqual(rt.machine_tools(self.root)[0]['missing'], [])
        self.install_unit('container-console-docker-ce')
        self.assertEqual(rt.machine_tools(self.root)[0]['state'], 'stopped')
        self.fake.active = True
        self.assertEqual(rt.machine_tools(self.root)[0]['state'], 'up')

    def test_docker_ce_on_linux_without_it(self):
        self.fake.engine = 'Docker Desktop'
        self.assertEqual(rt.machine_tools(self.root), [])

    def test_colima_console_on_macos(self):
        self.fake.uname = 'Darwin'
        self.docker_ce_machine()
        self.assertEqual(rt.machine_tools(self.root), [])
        self.commands.add('colima')
        tool = rt.machine_tools(self.root)[0]
        self.assertEqual((tool['id'], tool['state']), ('container-console-colima', 'not installed'))
        self.fake.active = True
        with mock.patch.object(rt.os, 'getuid', return_value=501):
            self.assertEqual(rt.machine_tools(self.root)[0]['state'], 'up')
        self.assertTrue(self.fake.called(f'^launchctl print gui/501/{re.escape(rt.COLIMA_LABEL)}$'))

    def test_machine_unit_paths(self):
        self.assertEqual(
            rt.machine_unit('container-console-docker-ce'),
            os.path.join(self.home, '.config', 'systemd', 'user', rt.DOCKER_CE_UNIT),
        )
        with mock.patch.dict(os.environ, {'XDG_CONFIG_HOME': ''}):
            self.assertTrue(
                rt.machine_unit('container-console-docker-ce').startswith(os.path.join(self.home, '.config'))
            )
        self.assertEqual(
            rt.machine_unit('container-console-colima'),
            os.path.join(self.home, 'Library', 'LaunchAgents', f'{rt.COLIMA_LABEL}.plist'),
        )

    def machine(self, tool_id, state, missing=()):
        """Returns a console tool in the state given."""
        return {'id': tool_id, 'kind': 'machine', 'state': state, 'missing': list(missing)}

    def test_start_machine(self):
        rt.start_machine(self.root, self.machine('container-console-docker-ce', 'up'))
        self.assertEqual(self.fake.calls, [])
        with self.assertRaisesRegex(rt.Refused, 'to install it: make'):
            rt.start_machine(
                self.root, self.machine('container-console-docker-ce', 'not installed', ['to install it: make'])
            )
        self.quiet(rt.start_machine, self.root, self.machine('container-console-docker-ce', 'not installed'))
        self.assertTrue(self.fake.called('^make -C tools/container-console-docker-ce install$'))
        self.fake.active = False
        rt.start_machine(self.root, self.machine('container-console-docker-ce', 'stopped'))
        self.assertTrue(self.fake.called(f'^systemctl --user start {rt.DOCKER_CE_UNIT}$'))
        self.fake.active = False
        with mock.patch.object(rt.os, 'getuid', return_value=501):
            rt.start_machine(self.root, self.machine('container-console-colima', 'stopped'))
        self.assertTrue(self.fake.called('^launchctl bootstrap gui/501 .*LaunchAgents'))
        self.assertTrue(self.fake.called(f'^launchctl kickstart gui/501/{re.escape(rt.COLIMA_LABEL)}$'))

    def test_start_machine_failures(self):
        self.fake.fail['^make'] = (2, 'no go')
        with self.assertRaisesRegex(rt.Refused, r'make -C tools/container-console-docker-ce install failed'):
            self.quiet(rt.start_machine, self.root, self.machine('container-console-docker-ce', 'not installed'))
        self.fake.activate_on_start = False
        with mock.patch.object(rt, 'machine_active', side_effect=[False, True]) as active:
            rt.start_machine(self.root, self.machine('container-console-docker-ce', 'stopped'))
        self.assertEqual(active.call_count, 2)
        with mock.patch.object(rt.time, 'monotonic', side_effect=[0, 0, 100]):
            with self.assertRaisesRegex(rt.Refused, 'did not start within 15 s'):
                rt.start_machine(self.root, self.machine('container-console-docker-ce', 'stopped'))

    def test_stop_machine(self):
        rt.stop_machine(self.root, self.machine('container-console-docker-ce', 'not installed'))
        self.assertEqual(self.fake.calls, [])
        rt.stop_machine(self.root, self.machine('container-console-docker-ce', 'up'))
        self.assertTrue(self.fake.called(f'^systemctl --user stop {rt.DOCKER_CE_UNIT}$'))
        rt.stop_machine(self.root, self.machine('container-console-colima', 'up'))
        self.assertTrue(self.fake.called('^launchctl bootout gui/'))


class ListTests(RunToolsTestCase):
    def test_list_json(self):
        self.docker_ce_machine()
        code, out, _ = self.quiet(rt.cmd_list, self.root, True)
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual(data['group'], GROUP)
        tools = {tool['id']: tool for tool in data['tools']}
        self.assertEqual(tools['acme-web']['ports'], [WEB_PORT])
        self.assertEqual(tools['container-console-docker-ce']['ports'], [27850])
        self.assertEqual(tools['container-console-docker-ce']['kind'], 'machine')

    def test_list_table_notes_an_old_project(self):
        self.fake.containers = [container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT)]
        code, out, _ = self.quiet(rt.cmd_list, self.root, False)
        self.assertEqual(code, 0)
        self.assertIn('| Tool | Kind | State | URL | Notes |', out)
        self.assertIn('| acme-metrics | compose | up | http://localhost:2 | runs in the old project acme-metrics', out)
        self.assertIn('| acme-web | compose | stopped |', out)

    def test_list_names_an_old_volume_only_once_the_tool_is_in_the_group(self):
        """Next to the group's volume, the old one is data the group does not use (old_volumes); alone, it is the only
        copy, not moved yet (unmoved_volumes, regression: it was offered as kept); while the tool still runs in its
        old project it is the live volume, in neither list."""
        self.fake.volumes = {'acme-store_data'}
        _, out, _ = self.quiet(rt.cmd_list, self.root, True)
        tools = {tool['id']: tool for tool in json.loads(out)['tools']}
        self.assertEqual(tools['acme-store']['old_volumes'], [])
        self.assertEqual(tools['acme-store']['unmoved_volumes'], ['acme-store_data'])
        _, out, _ = self.quiet(rt.cmd_list, self.root, False)
        self.assertIn('volume acme-store_data not moved yet: up copies it', out)
        self.assertNotIn('old volume kept', out)
        self.fake.volumes = {'acme-store_data', 'acme-tools_data'}
        _, out, _ = self.quiet(rt.cmd_list, self.root, True)
        tools = {tool['id']: tool for tool in json.loads(out)['tools']}
        self.assertEqual(tools['acme-store']['old_volumes'], ['acme-store_data'])
        self.assertEqual(tools['acme-store']['unmoved_volumes'], [])
        _, out, _ = self.quiet(rt.cmd_list, self.root, False)
        self.assertIn('old volume kept: acme-store_data', out)
        self.fake.containers = [container('o1', 'acme-store', 'store', port=STORE_PORT)]
        _, out, _ = self.quiet(rt.cmd_list, self.root, True)
        tools = {tool['id']: tool for tool in json.loads(out)['tools']}
        self.assertEqual(tools['acme-store']['old_volumes'], [])
        self.assertEqual(tools['acme-store']['unmoved_volumes'], [])

    def test_pick(self):
        tools = [{'id': 'a'}, {'id': 'b'}]
        self.assertEqual(rt.pick(tools, ['b', 'a', 'b']), [{'id': 'b'}, {'id': 'a'}])
        for known, expected in ((tools, 'tools: a, b'), ([], 'tools: none')):
            err = io.StringIO()
            with contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as stop:
                rt.pick(known, ['acme-nothing'])
            self.assertEqual(stop.exception.code, 2)
            self.assertIn(f'not a tool of this machine: acme-nothing ({expected})', err.getvalue())


class RollbackTests(RunToolsTestCase):
    def tool(self, containers):
        """Returns a tool with two services (web and app) and the containers given."""
        return {
            'id': 'acme-web',
            'services': [{'name': 'web', 'image': 'acme/web:1.0'}, {'name': 'app', 'image': 'acme-tools-app'}],
            'containers': containers,
        }

    def test_tag_rollback_prefers_the_group_container(self):
        old = {'service': 'web', 'project': 'acme-web', 'image_id': 'sha256:old'}
        mine = {'service': 'web', 'project': GROUP, 'image_id': 'sha256:new'}
        self.fake.images['acme-tools-app'] = 'sha256:app-local'
        _, out, _ = self.quiet(rt.tag_rollback, self.root, self.tool([old, mine]), GROUP, '20260101-000000')
        self.assertTrue(self.fake.called('^docker tag sha256:new acme/web:rollback-latest$'))
        self.assertTrue(self.fake.called('^docker tag sha256:new acme/web:rollback-20260101-000000$'))
        self.assertTrue(self.fake.called('^docker tag sha256:app-local acme-tools-app:rollback-latest$'))
        self.assertIn('rollback: acme/web:rollback-latest (sha256:new)', out)

    def test_tag_rollback_from_an_old_container_or_a_first_build(self):
        old = {'service': 'web', 'project': 'acme-web', 'image_id': 'sha256:old'}
        _, out, _ = self.quiet(rt.tag_rollback, self.root, self.tool([old]), GROUP, '20260101-000000')
        self.assertTrue(self.fake.called('^docker tag sha256:old acme/web:rollback-latest$'))
        self.assertIn('first build of acme-tools-app: no checkpoint yet', out)
        self.assertFalse(self.fake.called('acme-tools-app:rollback'))

    def test_tag_failure_raises(self):
        self.fake.fail['^docker tag'] = (1, 'no such image')
        old = {'service': 'web', 'project': GROUP, 'image_id': 'sha256:old'}
        with self.assertRaisesRegex(rt.Refused, 'docker tag sha256:old failed: no such image'):
            rt.tag_rollback(self.root, self.tool([old]), GROUP, '20260101-000000')

    def test_prune_rollback(self):
        self.fake.image_ls = '\n'.join(
            [f'rollback-2026010{n}-000000' for n in range(1, 6)] + ['rollback-latest', '1.0', 'rollback-x']
        )
        self.fake.fail['image rm acme/web:rollback-20260102'] = (1, 'in use')
        _, out, _ = self.quiet(rt.prune_rollback, self.root, 'acme/web')
        self.assertIn('untagged: acme/web:rollback-20260101-000000', out)
        self.assertIn('attention: kept acme/web:rollback-20260102-000000 (in use)', out)
        self.assertFalse(self.fake.called('rm acme/web:rollback-2026010[345]'))
        self.fake.fail['image ls'] = (1, 'down')
        self.fake.calls.clear()
        rt.prune_rollback(self.root, 'acme/web')
        self.assertFalse(self.fake.called('image rm'))


class MoveTests(RunToolsTestCase):
    def setUp(self):
        super().setUp()
        self.write('custom/env/acme-store.env', 'STORE_KEY=k\n')

    def test_network_users(self):
        self.assertEqual(rt.network_users(self.root, 'acme-none'), (False, '', {}))
        self.fake.networks['acme-n'] = {'Containers': {'abcdef1234567890': None, 'c2': {'Name': 'acme-2'}}}
        self.assertEqual(
            rt.network_users(self.root, 'acme-n'), (True, '', {'abcdef1234567890': 'abcdef123456', 'c2': 'acme-2'})
        )
        with mock.patch.object(rt, 'run', return_value=(0, '[]', '')):
            self.assertEqual(rt.network_users(self.root, 'acme-n'), (True, '', {}))

    def network(self, name, project, *users):
        """Declares a Docker network with its compose project label and the (id, name) pairs attached to it."""
        self.fake.networks[name] = {
            'Name': name,
            'Labels': {rt.PROJECT_LABEL: project} if project else {},
            'Containers': {cid: {'Name': user} for cid, user in users},
        }

    def test_check_move_refuses_a_volume_under_both_names(self):
        self.fake.containers = [container('o1', 'acme-store', 'store', port=STORE_PORT)]
        self.fake.volumes = {'acme-store_data', 'acme-tools_data'}
        store = self.tools()['acme-store']
        with self.assertRaisesRegex(rt.Refused, 'both acme-store_data .* and acme-tools_data'):
            rt.check_move(self.root, store, GROUP)
        self.fake.volumes = {'acme-store_data'}
        rt.check_move(self.root, store, GROUP)

    def test_check_move_networks(self):
        self.fake.containers = [container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT)]
        metrics = self.tools()['acme-metrics']
        rt.check_move(self.root, metrics, GROUP)
        self.network('acme-metrics', GROUP)
        rt.check_move(self.root, metrics, GROUP)
        self.network('acme-metrics', 'acme-metrics', ('o3', 'acme-metrics-metrics-1'))
        rt.check_move(self.root, metrics, GROUP)
        self.network('acme-metrics', 'acme-metrics', ('o3', 'm'), ('x9', 'billing-api-api-1'))
        with self.assertRaisesRegex(rt.Refused, 'network acme-metrics is also used by billing-api-api-1'):
            rt.check_move(self.root, metrics, GROUP)
        self.network('acme-metrics', 'billing-api')
        with self.assertRaisesRegex(rt.Refused, 'belongs to project billing-api, not to acme-tools'):
            rt.check_move(self.root, metrics, GROUP)
        self.network('acme-metrics', '')
        with self.assertRaisesRegex(rt.Refused, 'belongs to project none'):
            rt.check_move(self.root, metrics, GROUP)
        web = self.tools()['acme-web']
        self.fake.calls.clear()
        rt.check_move(self.root, web, GROUP)
        self.assertFalse(self.fake.called('network inspect'))

    def test_copy_image(self):
        tool = {
            'id': 'acme-store',
            'services': [{'name': 'store', 'image': 'acme/store:2.0', 'named_volumes': ['data']}],
        }
        volume = {'key': 'data'}
        old = [{'service': 'store', 'image_id': ''}, {'service': 'store', 'image_id': 'sha256:old'}]
        self.assertEqual(rt.copy_image(tool, volume, old), 'sha256:old')
        self.assertEqual(rt.copy_image(tool, volume, []), 'acme/store:2.0')
        with self.assertRaisesRegex(rt.Refused, 'no service of acme-store mounts the volume logs'):
            rt.copy_image(tool, {'key': 'logs'}, old)

    def test_move_tool_in_the_group_does_nothing(self):
        self.fake.containers = [container('c1', GROUP, 'metrics', port=METRICS_PORT)]
        self.network('acme-metrics', GROUP)
        self.assertEqual(rt.move_tool(self.root, self.tools()['acme-metrics'], GROUP), [])
        self.assertFalse(self.fake.called('^docker (stop|rm|run|network rm)'))

    def test_move_tool_copies_the_volume_and_removes_the_old_project(self):
        self.fake.containers = [
            container('o2', 'acme-store', 'app', port=1, image='sha256:app-old'),
            container('o1', 'acme-store', 'store', running=False, port=STORE_PORT, image='sha256:store-old'),
        ]
        self.fake.volumes = {'acme-store_data'}
        store = self.tools()['acme-store']
        store['networks'] = [{'key': 'n', 'name': 'acme-store-net', 'fixed': True}]
        self.network('acme-store-net', 'acme-store', ('o1', 'x'))
        kept, out, _ = self.quiet(rt.move_tool, self.root, store, GROUP)
        self.assertEqual(kept, [('acme-store_data', 'its data is in the group now')])
        self.assertIn('moving acme-store from project acme-store to acme-tools', out)
        self.assertIn('copied: acme-store_data -> acme-tools_data', out)
        self.assertTrue(self.fake.called('^docker stop -t 10 o2$'))
        self.assertTrue(
            self.fake.called(
                '^docker run --rm --network none --entrypoint cp -v acme-store_data:/from:ro -v acme-tools_data:/to '
                'sha256:store-old -a /from/. /to/$'
            )
        )
        self.assertTrue(self.fake.called('^docker rm o2 o1$'))
        self.assertTrue(self.fake.called('^docker network rm acme-store-net$'))

    def test_move_tool_skips_volumes_absent_or_already_moved(self):
        """No old volume: nothing kept; both volumes: nothing copied, the old one named as left behind."""
        self.fake.containers = [container('o1', 'acme-store', 'store', running=False, port=STORE_PORT)]
        store = self.tools()['acme-store']
        self.assertEqual(self.quiet(rt.move_tool, self.root, store, GROUP)[0], [])
        self.fake.volumes = {'acme-store_data', 'acme-tools_data'}
        self.assertEqual(
            self.quiet(rt.move_tool, self.root, store, GROUP)[0],
            [('acme-store_data', 'not copied: the group already has acme-tools_data; check both')],
        )
        self.assertFalse(self.fake.called('^docker (stop|run|volume create)'))

    def test_a_failed_copy_restores_the_old_project(self):
        self.fake.containers = [container('o1', 'acme-store', 'store', port=STORE_PORT, image='sha256:store-old')]
        self.fake.volumes = {'acme-store_data'}
        self.fake.fail['^docker run'] = (1, 'cp: not found')
        store = self.tools()['acme-store']
        with self.assertRaisesRegex(rt.Refused, 'copying acme-store_data failed, so acme-store stays in acme-store'):
            self.quiet(rt.move_tool, self.root, store, GROUP)
        self.assertTrue(self.fake.called('^docker volume rm acme-tools_data$'))
        self.assertTrue(self.fake.called('^docker start o1$'))
        self.assertFalse(self.fake.called('^docker rm '))

    def test_a_failed_volume_create_removes_nothing(self):
        self.fake.containers = [container('o1', 'acme-store', 'store', running=False, port=STORE_PORT)]
        self.fake.volumes = {'acme-store_data'}
        self.fake.fail['^docker volume create'] = (1, 'disk full')
        store = self.tools()['acme-store']
        with self.assertRaisesRegex(rt.Refused, 'disk full'):
            self.quiet(rt.move_tool, self.root, store, GROUP)
        self.assertFalse(self.fake.called('^docker (volume rm|start)'))

    def test_a_network_that_cannot_be_removed_is_kept(self):
        self.fake.containers = [container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT)]
        self.network('acme-metrics', 'acme-metrics', ('o3', 'm'))
        self.fake.fail['^docker network rm'] = (1, 'error: network has active endpoints\nmore')
        _, out, _ = self.quiet(rt.move_tool, self.root, self.tools()['acme-metrics'], GROUP)
        self.assertTrue(self.fake.called('^docker stop -t 45 o3$'))
        self.assertIn('attention: network acme-metrics kept: error: network has active endpoints', out)
        self.network('acme-metrics', 'acme-metrics', ('o3', 'm'), ('x9', 'other'))
        self.fake.calls.clear()
        self.quiet(rt.move_tool, self.root, self.tools()['acme-metrics'], GROUP)
        self.assertFalse(self.fake.called('network rm'))


class UpDownTests(RunToolsTestCase):
    def test_up_refuses_tools_without_configuration_and_starts_the_rest(self):
        os.remove(os.path.join(self.root, 'custom/config/acme-web/users.json'))
        code, out, _ = self.quiet(rt.cmd_up, self.root, ['acme-web', 'acme-store', 'acme-metrics'])
        self.assertEqual(code, 1)
        self.assertIn('refused: acme-web: configuration missing: custom/config/acme-web/users.json', out)
        self.assertIn('refused: acme-store: configuration missing: STORE_KEY', out)
        self.assertTrue(
            self.fake.called(r'compose -f tools/compose.yaml up -d --build --wait --wait-timeout 300 metrics$')
        )
        self.assertIn('starting: acme-metrics in acme-tools', out)
        self.assertIn('| acme-metrics | compose |', out)

    def test_up_moves_a_tool_and_keeps_the_old_volume(self):
        self.write('custom/env/acme-store.env', 'STORE_KEY=k\n')
        self.fake.containers = [
            container('o1', 'acme-store', 'store', port=STORE_PORT, image='sha256:store-old'),
            container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT, image='sha256:metrics-old'),
        ]
        self.fake.volumes = {'acme-store_data'}
        code, out, _ = self.quiet(rt.cmd_up, self.root, ['acme-store', 'acme-metrics'])
        self.assertEqual(code, 0)
        self.assertTrue(self.fake.called(r'^docker tag sha256:metrics-old acme/metrics:rollback-\d{8}-\d{6}$'))
        self.assertTrue(self.fake.called('--env-file .*acme-store.env -f tools/compose.yaml up .* store app metrics$'))
        self.assertIn('old volume kept: acme-store_data', out)
        self.assertNotIn('| acme-web |', out)

    def test_up_refused_by_a_shared_network_or_a_failed_move(self):
        self.fake.containers = [container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT)]
        self.network = MoveTests.network.__get__(self)
        self.network('acme-metrics', 'acme-metrics', ('o3', 'm'), ('x9', 'billing-api-api-1'))
        code, out, _ = self.quiet(rt.cmd_up, self.root, ['acme-metrics'])
        self.assertEqual(code, 1)
        self.assertIn('refused: acme-metrics: network acme-metrics is also used by billing-api-api-1', out)
        self.assertFalse(self.fake.called(' up '))
        self.network('acme-metrics', 'acme-metrics', ('o3', 'm'))
        self.fake.fail['^docker stop'] = (1, 'cannot stop')
        code, out, _ = self.quiet(rt.cmd_up, self.root, ['acme-metrics'])
        self.assertEqual(code, 1)
        self.assertIn('refused: acme-metrics: docker stop -t failed: cannot stop', out)
        self.assertFalse(self.fake.called(' up '))

    def test_up_when_compose_up_fails(self):
        self.fake.fail[' up -d '] = (1, '')
        code, out, _ = self.quiet(rt.cmd_up, self.root, ['acme-metrics'])
        self.assertEqual(code, 1)
        self.assertIn('error: docker compose up failed', out)
        self.assertIn('rollback-latest', out)

    def test_up_of_a_console(self):
        self.docker_ce_machine()
        code, out, _ = self.quiet(rt.cmd_up, self.root, ['container-console-docker-ce'])
        self.assertEqual(code, 0)
        self.assertTrue(self.fake.called('^make -C tools/container-console-docker-ce install$'))
        self.assertIn('| container-console-docker-ce | machine | up |', out)
        self.assertFalse(self.fake.called(' up -d '))
        self.fake.active = False
        self.fake.fail['^make'] = (2, '')
        code, out, _ = self.quiet(rt.cmd_up, self.root, ['container-console-docker-ce'])
        self.assertEqual(code, 1)
        self.assertIn('refused: container-console-docker-ce: make -C', out)

    def test_down(self):
        self.docker_ce_machine()
        self.install_unit('container-console-docker-ce')
        self.fake.containers = [
            container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT),
            container('c1', GROUP, 'web', port=WEB_PORT),
        ]
        code, out, _ = self.quiet(rt.cmd_down, self.root, ['acme-web', 'acme-metrics', 'container-console-docker-ce'])
        self.assertEqual(code, 0)
        self.assertTrue(self.fake.called('^docker stop o3$'))
        self.assertTrue(self.fake.called('compose -f tools/compose.yaml stop web metrics$'))
        self.assertIn('stopped: container-console-docker-ce', out)
        self.assertFalse(self.fake.called(r'compose .* (down|rm)|volume rm|^docker rm |image rm'))

    def test_down_failures(self):
        self.docker_ce_machine()
        self.install_unit('container-console-docker-ce')
        self.fake.containers = [container('o3', 'acme-metrics', 'metrics', port=METRICS_PORT)]
        self.fake.fail['^docker stop o3'] = (1, 'cannot stop o3\n')
        self.fake.fail['^systemctl --user stop'] = (5, 'unit busy')
        self.fake.fail[' stop metrics$'] = (1, '')
        code, out, _ = self.quiet(rt.cmd_down, self.root, ['acme-metrics', 'container-console-docker-ce'])
        self.assertEqual(code, 1)
        self.assertIn('error: acme-metrics: cannot stop o3', out)
        self.assertIn('error: container-console-docker-ce: systemctl --user stop failed: unit busy', out)

    def test_down_of_a_console_alone(self):
        self.docker_ce_machine()
        code, _, _ = self.quiet(rt.cmd_down, self.root, ['container-console-docker-ce'])
        self.assertEqual(code, 0)
        self.assertFalse(self.fake.called(' stop '))


class MainTests(RunToolsTestCase):
    def test_usage_and_unknown_command(self):
        code, _, err = self.quiet(rt.main, [self.root])
        self.assertEqual(code, 2)
        self.assertIn('usage: run-tools.py', err)
        code, _, err = self.quiet(rt.main, [self.root, 'start'])
        self.assertEqual(code, 2)
        self.assertIn('error: unknown command start', err)

    def test_commands(self):
        code, out, _ = self.quiet(rt.main, [self.root, 'list', '--json'])
        self.assertEqual((code, json.loads(out)['group']), (0, GROUP))
        code, out, _ = self.quiet(rt.main, [self.root, 'list'])
        self.assertEqual(code, 0)
        self.assertIn('| Tool |', out)
        self.assertEqual(self.quiet(rt.main, [self.root, 'status'])[0], 0)
        self.assertEqual(self.quiet(rt.main, [self.root, 'up', 'acme-metrics'])[0], 0)
        self.assertEqual(self.quiet(rt.main, [self.root, 'down', 'acme-metrics'])[0], 0)

    def test_a_refusal_exits_1(self):
        os.remove(os.path.join(self.root, 'tools/compose.yaml'))
        code, _, err = self.quiet(rt.main, [self.root, 'status'])
        self.assertEqual(code, 1)
        self.assertIn('error: cannot read tools/compose.yaml', err)


if __name__ == '__main__':
    unittest.main()
