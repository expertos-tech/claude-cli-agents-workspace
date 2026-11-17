"""Tests of statusline/statusline.sh: AC-11. They need bash and jq, so the coverage container skips them."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / 'statusline' / 'statusline.sh'
HIGHLIGHT = '\033[1;97;41m'
CYAN = '\033[1;36m'
RESET = '\033[0m'
WATCHDOG_SECONDS = 10


def line(color, model, folder):
    """Returns the exact status line for a model and a folder."""
    return f'{color} {model} {RESET}  {folder}'


@unittest.skipUnless(shutil.which('bash') and shutil.which('jq'), 'statusline.sh needs bash and jq on PATH')
class StatuslineTest(unittest.TestCase):
    """AC-11: what the status line shows for each input."""

    def setUp(self):
        """Creates the fictitious home the script runs under."""
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.home = folder.name

    def run_script(self, text):
        """Runs the script with the given stdin text and the fictitious home."""
        return subprocess.run(
            ['bash', str(SCRIPT)],
            capture_output=True,
            check=False,
            env={'HOME': self.home, 'PATH': os.environ['PATH']},
            input=text,
            text=True,
            timeout=WATCHDOG_SECONDS,
        )

    def output_for(self, payload):
        """Returns the output for a valid JSON payload, failing the test on a non-zero exit."""
        result = self.run_script(json.dumps(payload))
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_ac11_fable_gets_the_highlight(self):
        """AC-11: Fable, in the name or in the id, whatever the first letter's case."""
        cases = (
            ('Fable 5', 'claude-5-1'),
            ('fable', 'claude-5-1'),
            ('Claude', 'claude-fable-5-1'),
            ('Claude', 'claude-Fable-5-1'),
        )
        for name, model_id in cases:
            with self.subTest(name=name, id=model_id):
                payload = {'model': {'display_name': name, 'id': model_id}, 'cwd': '/srv/demo'}
                self.assertEqual(self.output_for(payload), line(HIGHLIGHT, name, '/srv/demo'))

    def test_ac11_other_models_get_cyan(self):
        """AC-11: another model is cyan; only the name's first letter may vary in case."""
        for name in ('Opus 5.5', 'FABLE'):
            with self.subTest(name=name):
                payload = {'model': {'display_name': name, 'id': 'claude-opus-5-5'}, 'cwd': '/srv/demo'}
                self.assertEqual(self.output_for(payload), line(CYAN, name, '/srv/demo'))

    def test_ac11_home_becomes_a_tilde(self):
        """AC-11: the home folder and what is under it start with a tilde; other folders stay as they are."""
        cases = (
            (self.home, '~'),
            (f'{self.home}/demo', '~/demo'),
            (f'/srv{self.home}', f'/srv{self.home}'),
            ('/srv/demo', '/srv/demo'),
        )
        for folder, shown in cases:
            with self.subTest(folder=folder):
                payload = {'model': {'display_name': 'Opus'}, 'workspace': {'current_dir': folder}}
                self.assertEqual(self.output_for(payload), line(CYAN, 'Opus', shown))

    def test_ac11_missing_fields_fall_back(self):
        """AC-11: name to id to `?`; workspace folder to cwd to nothing."""
        cases = (
            ({'model': {'id': 'claude-opus-5-5'}, 'cwd': '/srv/cwd'}, 'claude-opus-5-5', '/srv/cwd'),
            ({'model': {}, 'cwd': '/srv/cwd'}, '?', '/srv/cwd'),
            ({'cwd': '/srv/cwd'}, '?', '/srv/cwd'),
            ({'model': {'id': 'x'}, 'workspace': {'current_dir': '/srv/dir'}, 'cwd': '/srv/cwd'}, 'x', '/srv/dir'),
            ({'model': {'id': 'x'}, 'workspace': {}, 'cwd': '/srv/cwd'}, 'x', '/srv/cwd'),
            ({'model': {'id': 'x'}}, 'x', ''),
            ({}, '?', ''),
        )
        for payload, model, folder in cases:
            with self.subTest(payload=payload):
                self.assertEqual(self.output_for(payload), line(CYAN, model, folder))

    def test_ac11_missing_name_falls_back_to_a_fable_id_with_the_highlight(self):
        """AC-11: the id shown as the name still earns the highlight."""
        payload = {'model': {'id': 'claude-fable-5-1'}}
        self.assertEqual(self.output_for(payload), line(HIGHLIGHT, 'claude-fable-5-1', ''))

    def test_ac11_invalid_json_exits_non_zero_with_no_output(self):
        """AC-11: invalid JSON ends the script before anything is printed."""
        result = self.run_script('{not json')

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
