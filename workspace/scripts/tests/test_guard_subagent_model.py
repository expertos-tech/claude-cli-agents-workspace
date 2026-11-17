"""Unit tests of scripts/guard-subagent-model.py (the gate of docker/python-coverage runs them in-process)."""

import contextlib
import importlib.util
import io
import json
import os
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / 'guard-subagent-model.py'
SPEC = importlib.util.spec_from_file_location('guard_subagent_model', MODULE_PATH)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


def decision(tool_input, root='/nonexistent'):
    """Runs decide() and returns the decision JSON object it printed, or None when it stayed silent."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        guard.decide({'tool_input': tool_input}, root)
    text = out.getvalue()
    return json.loads(text)['hookSpecificOutput'] if text else None


class ForkAndTypeTests(unittest.TestCase):
    def test_fork_spellings_are_denied(self):
        for spelling in ('fork', 'Fork', 'FORK', 'fo-rk', 'fo_rk', 'f o r k', 'ｆｏｒｋ'):
            result = decision({'subagent_type': spelling})
            self.assertEqual(result['permissionDecision'], 'deny', spelling)
            self.assertIn('inherits', result['permissionDecisionReason'])

    def test_fork_is_checked_before_fable(self):
        result = decision({'subagent_type': 'fork', 'model': 'fable'})
        self.assertEqual(result['permissionDecision'], 'deny')
        self.assertIn('inherits', result['permissionDecisionReason'])

    def test_non_ascii_type_is_denied(self):
        for value in ('fork﻿', 'agentü', '日本'):
            self.assertEqual(decision({'subagent_type': value})['permissionDecision'], 'deny', value)

    def test_fork_like_names_are_not_forks(self):
        for value in ('forks', 'fork2', 'for'):
            self.assertEqual(decision({'subagent_type': value})['permissionDecision'], 'allow', value)


class ModelTests(unittest.TestCase):
    def test_fable_asks_with_the_type(self):
        for model in ('fable', 'FABLE', 'claude-fable-1', ' fable ', 'ｆａｂｌｅ'):
            result = decision({'subagent_type': 'Plan', 'model': model})
            self.assertEqual(result['hookEventName'], 'PreToolUse')
            self.assertEqual(result['permissionDecision'], 'ask', model)
            self.assertIn("type 'Plan' asked for the Fable model", result['permissionDecisionReason'])
            self.assertIn('with effort not given', result['permissionDecisionReason'])
            self.assertNotIn('updatedInput', result)

    def test_fable_without_type(self):
        self.assertIn('(no type)', decision({'model': 'fable'})['permissionDecisionReason'])

    def test_allowlist(self):
        for model in ('opus', 'Sonnet', ' haiku ', 'claude-opus-5-5', 'claude-haiku-4-1[1m]'):
            self.assertIsNone(decision({'subagent_type': 'Plan', 'model': model}), model)
        for model in ('inherit', 'default', 'gpt-5', 'claude-opus', 'opusplan', 'xopus'):
            result = decision({'subagent_type': 'Plan', 'model': model})
            self.assertEqual(result['permissionDecision'], 'deny', model)

    def test_no_model_gets_opus_with_input_kept(self):
        result = decision({'subagent_type': 'Plan', 'prompt': 'p'})
        self.assertEqual(result['permissionDecision'], 'allow')
        self.assertEqual(result['updatedInput'], {'subagent_type': 'Plan', 'prompt': 'p', 'model': 'opus'})
        self.assertEqual(decision({'subagent_type': 'Plan', 'model': '  '})['updatedInput']['model'], 'opus')
        self.assertEqual(decision({'prompt': 'p'})['updatedInput']['model'], 'opus')

    def test_wrong_types_raise(self):
        for bad in ({'model': 3}, {'model': []}, {'subagent_type': 0}, {'subagent_type': []}):
            with self.assertRaises(TypeError, msg=str(bad)):
                decision(bad)
        with self.assertRaises(TypeError):
            guard.decide({'tool_input': []}, '/x')
        with self.assertRaises(KeyError):
            guard.decide({}, '/x')


class AgentFileTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name
        os.makedirs(os.path.join(self.root, '.claude', 'agents'))

    def agent(self, name, text, raw=False):
        mode = 'wb' if raw else 'w'
        with open(os.path.join(self.root, '.claude', 'agents', name + '.md'), mode) as fh:
            fh.write(text)

    def fixed(self, name):
        return guard.has_fixed_model(self.root, name)

    def test_fixed_needs_one_model_and_matching_name(self):
        self.agent('good', '---\nname: good\nmodel: sonnet\n---\nbody\n')
        self.assertTrue(self.fixed('good'))
        self.assertIsNone(decision({'subagent_type': 'good'}, self.root))
        cases = {
            'noname': '---\nmodel: sonnet\n---\n',
            'other': '---\nname: x\nmodel: sonnet\n---\n',
            'twomodels': '---\nname: twomodels\nmodel: sonnet\nmodel: fable\n---\n',
            'twonames': '---\nname: twonames\nname: twonames\nmodel: sonnet\n---\n',
            'inherit': '---\nname: inherit\nmodel: inherit\n---\n',
            'afterclose': '---\nname: afterclose\n---  \nmodel: sonnet\n',
            'noopen': 'x\nname: noopen\nmodel: sonnet\n',
            'empty': '',
            'indented': '---\nname: indented\n  model: sonnet\n---\n',
        }
        for name, text in cases.items():
            self.agent(name, text)
            self.assertFalse(self.fixed(name), name)
            self.assertEqual(decision({'subagent_type': name}, self.root)['updatedInput']['model'], 'opus')

    def test_quotes_crlf_and_spaces(self):
        self.agent('q1', '---\r\nname: "q1"\r\nmodel: "Sonnet"   \r\n---\r\n')
        self.agent('q2', "---\nname : q2\nmodel   :   'haiku'\n---  \n")
        self.agent('q3', '---  \nname: q3\nmodel: "sonnet\'\n---\n')
        self.agent('q4', '---\nname: q4\nmodel: "\n---\n')
        self.assertTrue(self.fixed('q1'))
        self.assertTrue(self.fixed('q2'))
        self.assertFalse(self.fixed('q3'))
        self.assertFalse(self.fixed('q4'))

    def test_no_builtin_and_odd_types(self):
        for name in ('claude-code-guide', 'statusline-setup', 'missing'):
            self.assertFalse(self.fixed(name))
        for name in ('', None, '../x', 'a/b', 'fi xed'):
            self.assertFalse(self.fixed(name), repr(name))

    def test_invalid_utf8_raises(self):
        self.agent('bad', b'---\nname: bad\nmodel: sonnet\n---\n\xff\xfe\n', raw=True)
        with self.assertRaises(UnicodeDecodeError):
            self.fixed('bad')


class EntryPointTests(unittest.TestCase):
    def run_main(self, stdin_bytes, argv):
        out, err = io.StringIO(), io.StringIO()
        stdin = mock.Mock(buffer=io.BytesIO(stdin_bytes))
        code = 0
        with mock.patch.object(sys, 'stdin', stdin), mock.patch.object(sys, 'argv', argv):
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                try:
                    guard.main()
                except SystemExit as exit_:
                    code = exit_.code
        return code, out.getvalue(), err.getvalue()

    def test_success_prints_decision(self):
        code, out, _ = self.run_main(b'{"tool_input":{"subagent_type":"Plan","model":"gpt-5"}}', ['x', '/nonexistent'])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_failures_exit_2_naming_the_exception(self):
        for payload, name in ((b'{x', 'JSONDecodeError'), (b'{"a":1}', 'KeyError'), (b'\xff', 'UnicodeDecodeError')):
            code, out, err = self.run_main(payload, ['x', '/nonexistent'])
            self.assertEqual((code, out, err.strip()), (2, '', name))

    def test_run_as_script(self):
        stdin = mock.Mock(buffer=io.BytesIO(b'{"tool_input":{"model":"fable"}}'))
        out = io.StringIO()
        with mock.patch.object(sys, 'stdin', stdin), mock.patch.object(sys, 'argv', ['x', '/nonexistent']):
            with contextlib.redirect_stdout(out):
                runpy.run_path(str(MODULE_PATH), run_name='__main__')
        self.assertEqual(json.loads(out.getvalue())['hookSpecificOutput']['permissionDecision'], 'ask')


if __name__ == '__main__':
    unittest.main()
