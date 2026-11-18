"""Unit tests of scripts/rules-config.py (the rules configuration of custom/rules-config.json and custom/my-rules/).

Each business rule of the request "rules" (RN-1 to RN-9) has its tests; the effective AGENTS.md and the manifest are
also checked against the real core, so a later edit of AGENTS.md cannot leave a turned-off rule named.
"""

import contextlib
import importlib.util
import io
import json
import os
import re
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
PRODUCT = SCRIPTS.parent
SPEC = importlib.util.spec_from_file_location('rules_config', SCRIPTS / 'rules-config.py')
rc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rc)

SCOPED = '---\npaths:\n  - "**/*.tsx"\n---\n\n# {name}\n'


class Root:
    """A throwaway workspace root with a small core: rules, skills, agents, AGENTS.md and the real manifest."""

    def __init__(self, base):
        """Writes the small core under base."""
        self.base = Path(base)
        (self.base / 'rules' / 'agents').mkdir(parents=True)
        (self.base / 'rules' / 'manifest.json').write_text((PRODUCT / 'rules' / 'manifest.json').read_text())
        for name in ('rules.md', 'git.md', 'review.md', 'models.md'):
            self.write(f'rules/{name}', f'# {name}\n')
        for name in ('security.md', 'frontend.md', 'docs.md'):
            self.write(f'rules/{name}', SCOPED.format(name=name))
        for name in ('merge', 'commit', 'request', 'pilot'):
            self.write(f'rules/skills/{name}/SKILL.md', f'---\nname: {name}\n---\n')
        for name in ('reviewer', 'verifier', 'infra-engineer'):
            self.write(f'rules/agents/{name}.md', f'---\nname: {name}\n---\n')
        self.write(
            'AGENTS.md',
            '# AGENTS.md\n\n- Delegate (`rules/models.md`).\n- UI work (`rules/frontend.md` "Colors").\n\n'
            '| File | Read before |\n| --- | --- |\n| `rules/review.md` | a review |\n'
            '| `templates/request.md`, `rules/models.md` | a request |\n| `rules/git.md` | a commit |\n',
        )

    def write(self, rel, text):
        """Writes text to rel, creating its folders."""
        path = self.base / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def config(self, data):
        """Writes custom/rules-config.json: a dict as JSON, a string as it is."""
        self.write(rc.CONFIG, data if isinstance(data, str) else json.dumps(data))

    def read_config(self):
        """The configuration file, parsed."""
        return json.loads((self.base / rc.CONFIG).read_text())

    def ws(self):
        """A fresh Workspace of this root."""
        return rc.Workspace(str(self.base))


class Base(unittest.TestCase):
    """A fresh Root per test."""

    def setUp(self):
        """Creates the throwaway root."""
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Root(self.tmp.name)

    def tearDown(self):
        """Removes the throwaway root."""
        self.tmp.cleanup()

    def warnings(self, ws):
        """All warnings of ws as one string."""
        return '\n'.join(ws.warnings)

    def build(self):
        """Runs build into a fresh folder; returns (workspace, out path)."""
        out = Path(self.tmp.name) / 'out'
        ws = self.root.ws()
        ws.build(str(out))
        return ws, out


class ConfigurationTests(Base):
    """RN-1 and RN-7: the fields of the configuration, and validation on every path."""

    def test_missing_configuration_loads_the_whole_core(self):
        ws = self.root.ws()
        self.assertEqual(ws.excluded, {'rules': [], 'skills': [], 'agents': []})
        self.assertEqual(ws.warnings, [])

    def test_excludes_of_each_kind(self):
        self.root.config(
            {
                'core': {
                    'rules': {'exclude': ['frontend.md']},
                    'skills': {'exclude': ['pilot']},
                    'agents': {'exclude': ['infra-engineer']},
                }
            }
        )
        ws = self.root.ws()
        self.assertEqual(ws.excluded, {'rules': ['frontend.md'], 'skills': ['pilot'], 'agents': ['infra-engineer']})
        self.assertEqual(ws.warnings, [])

    def test_invalid_json_is_ignored_with_a_warning(self):
        self.root.config('{"core": ')
        ws = self.root.ws()
        self.assertEqual(ws.excluded['rules'], [])
        self.assertIn('is not valid JSON (line 1)', self.warnings(ws))

    def test_wrong_shapes_are_ignored_field_by_field(self):
        self.root.config(
            {
                'language': 'pt-BR',
                'core': {'rules': {'exclude': 'frontend.md'}, 'skills': [], 'tools': {}},
                'replace': ['x'],
            }
        )
        text = self.warnings(self.root.ws())
        for part in (
            'unknown field "language"',
            '"core.rules.exclude" is not a list',
            '"core.skills" is not an object',
            'unknown field "core.tools"',
            '"replace" is not an object',
        ):
            self.assertIn(part, text)

    def test_a_json_array_or_a_link_is_ignored(self):
        self.root.config('[]')
        self.assertIn('is not a JSON object', self.warnings(self.root.ws()))
        os.remove(self.root.base / rc.CONFIG)
        target = self.root.write('elsewhere.json', '{}')
        os.symlink(target, self.root.base / rc.CONFIG)
        self.assertIn('is not a regular file', self.warnings(self.root.ws()))

    def test_unknown_names_warn_with_a_hint(self):
        self.root.config({'core': {'rules': {'exclude': ['frontend']}, 'skills': {'exclude': ['nope']}}})
        text = self.warnings(self.root.ws())
        self.assertIn('names "frontend", which is not in the core; ignored (did you mean frontend.md?)', text)
        self.assertIn('names "nope"', text)

    def test_unreadable_manifest_ignores_the_configuration(self):
        self.root.write('rules/manifest.json', '{')
        self.root.config({'core': {'rules': {'exclude': ['frontend.md']}}})
        ws = self.root.ws()
        self.assertEqual(ws.excluded['rules'], [])
        self.assertIn('rules/manifest.json unreadable', self.warnings(ws))


class MandatoryTests(Base):
    """RN-3: the mandatory core is neither turned off nor replaced."""

    def test_mandatory_excludes_stay_with_a_warning(self):
        self.root.config(
            {
                'core': {
                    'rules': {'exclude': ['git.md', 'rules.md', 'security.md']},
                    'skills': {'exclude': ['merge', 'commit', 'request']},
                    'agents': {'exclude': ['reviewer']},
                }
            }
        )
        ws = self.root.ws()
        self.assertEqual(ws.excluded, {'rules': [], 'skills': [], 'agents': []})
        for name in ('git.md', 'rules.md', 'security.md', 'merge', 'commit', 'request', 'reviewer'):
            self.assertIn(f'"{name}" is mandatory', self.warnings(ws))

    def test_mandatory_replace_stays_with_a_warning(self):
        self.root.write('custom/my-rules/git.md', 'own')
        self.root.config({'replace': {'git.md': 'git.md'}})
        ws = self.root.ws()
        self.assertEqual(ws.replaced, {})
        self.assertIn('"git.md" is mandatory (rules/manifest.json); it is not replaced', self.warnings(ws))
        self.assertIn('custom/my-rules/git.md refused', self.warnings(ws))

    def test_manifest_matches_the_real_core(self):
        """Every piece the manifest names exists in the product, and the hooks are in the settings."""
        manifest = json.loads((PRODUCT / 'rules' / 'manifest.json').read_text())
        for name in manifest['rules']:
            self.assertTrue((PRODUCT / 'rules' / name).is_file(), name)
        for name in manifest['skills']:
            self.assertTrue((PRODUCT / 'rules' / 'skills' / name / 'SKILL.md').is_file(), name)
        for name in manifest['agents']:
            self.assertTrue((PRODUCT / 'rules' / 'agents' / f'{name}.md').is_file(), name)
        for name in manifest['scripts'] + [f for f in manifest['files'] if f != 'AGENTS.md']:
            self.assertTrue((SCRIPTS / name).is_file(), name)
        self.assertTrue((PRODUCT / 'AGENTS.md').is_file())
        settings = (PRODUCT / 'rules' / 'agents' / 'settings.json').read_text()
        for hook in manifest['hooks']:
            self.assertIn(hook if hook == 'Stop' else f'{hook}.', settings, hook)
        self.assertTrue(json.loads(settings)['permissions']['deny'])


class OwnItemTests(Base):
    """RN-2 and RN-4: the own items of custom/my-rules/, the custom- prefix, and refused core names."""

    def test_own_rules_skills_and_agents_are_built_with_the_prefix(self):
        self.root.write('custom/my-rules/company.md', '# company\n')
        self.root.write('custom/my-rules/cloud.md', SCOPED.format(name='cloud'))
        self.root.write('custom/my-rules/skills/deploy/SKILL.md', '---\nname: deploy\ndescription: d\n---\nbody\n')
        self.root.write('custom/my-rules/skills/deploy/refs/a.md', 'ref')
        self.root.write(
            'custom/my-rules/agents/sql.md', '---\nname: sql\nname: twice\nmodel: claude-haiku-5-5\n---\nbody\n'
        )
        ws, out = self.build()
        self.assertEqual(ws.warnings, [])
        self.assertEqual((out / 'rules' / 'custom-company.md').read_text(), '# company\n')
        self.assertTrue((out / 'rules' / 'custom-cloud.md').is_file())
        self.assertTrue((out / 'skills' / 'custom-deploy' / 'refs' / 'a.md').is_file())
        skill = (out / 'skills' / 'custom-deploy' / 'SKILL.md').read_text()
        self.assertEqual(skill, '---\nname: custom-deploy\ndescription: d\n---\nbody\n')
        agent = (out / 'agents' / 'custom-sql.md').read_text()
        self.assertEqual(agent, '---\nname: custom-sql\nmodel: claude-haiku-5-5\n---\nbody\n')
        self.assertEqual((out / 'skip').read_text(), '')

    def test_core_names_are_refused(self):
        self.root.write('custom/my-rules/git.md', 'own')
        self.root.write('custom/my-rules/skills/merge/SKILL.md', 'own')
        self.root.write('custom/my-rules/agents/reviewer.md', '---\nname: reviewer\n---\n')
        ws, out = self.build()
        text = self.warnings(ws)
        self.assertIn('custom/my-rules/git.md refused: a core rule has that name', text)
        self.assertIn('custom/my-rules/skills/merge refused', text)
        self.assertIn('custom/my-rules/agents/reviewer.md refused', text)
        self.assertFalse((out / 'rules').exists() or (out / 'skills').exists() or (out / 'agents').exists())

    def test_links_folders_and_bad_items_are_skipped(self):
        outside = self.root.write('outside.md', 'SECRET')
        own = self.root.base / 'custom' / 'my-rules'
        (own / 'dir.md').mkdir(parents=True)
        os.symlink(outside, own / 'link.md')
        self.root.write('custom/my-rules/skills/Bad Name/SKILL.md', 'x')
        self.root.write('custom/my-rules/skills/empty/notes.md', 'x')
        self.root.write('custom/my-rules/skills/linked/SKILL.md', 'x')
        os.symlink(outside, own / 'skills' / 'linked' / 'leak.md')
        self.root.write('custom/my-rules/agents/plain.md', 'no front matter')
        ws, out = self.build()
        text = self.warnings(ws)
        for part in (
            'custom/my-rules/dir.md skipped',
            'custom/my-rules/link.md skipped',
            'skills/Bad Name skipped',
            'skills/empty skipped: no SKILL.md',
            'skills/linked/leak.md skipped',
            'agents/plain.md skipped: an agent needs a front matter',
        ):
            self.assertIn(part, text)
        self.assertFalse((out / 'skills' / 'custom-linked' / 'leak.md').exists())
        self.assertTrue((out / 'skills' / 'custom-linked' / 'SKILL.md').is_file())

    def test_front_matter_keeps_only_the_allowed_keys(self):
        """Regression (review of stage 1): no own item brings a hook, a permission, a tool grant or Fable."""
        self.root.write(
            'custom/my-rules/skills/deploy/SKILL.md',
            '---\nname: deploy\ndescription: d\nallowed-tools: Bash(*)\nhooks:\n  PreToolUse:\n    - command: x\n'
            'model: claude-fable-5-2\n"hooks": y\n<<: *base\neffort: low\n---\nbody\n',
        )
        self.root.write(
            'custom/my-rules/agents/sql.md',
            '---\nname: sql\ntools:\n  - Read\npermissionMode: bypassPermissions\nmcpServers:\n  - evil\n'
            "model: 'opus'\n---\nbody\n",
        )
        ws, out = self.build()
        skill = (out / 'skills' / 'custom-deploy' / 'SKILL.md').read_text()
        self.assertEqual(skill, '---\nname: custom-deploy\ndescription: d\neffort: low\n---\nbody\n')
        agent = (out / 'agents' / 'custom-sql.md').read_text()
        self.assertEqual(agent, "---\nname: custom-sql\ntools:\n  - Read\nmodel: 'opus'\n---\nbody\n")
        text = self.warnings(ws)
        self.assertIn(
            'skills/deploy/SKILL.md: front matter not allowed for an own item, left out: allowed-tools, hooks, '
            'model, "hooks": y, <<: *base',
            text,
        )
        self.assertIn(
            'agents/sql.md: front matter not allowed for an own item, left out: permissionMode, mcpServers', text
        )

    def test_nested_configuration_never_reaches_claude(self):
        """Regression (review of the fix): a hidden folder (a nested .claude/skills/) or file, and a SKILL.md below
        the top, stay out of .claude/; the rest of the skill is copied."""
        self.root.write('custom/my-rules/skills/x/SKILL.md', '---\nname: x\n---\nbody\n')
        self.root.write('custom/my-rules/skills/x/ref.md', 'ref')
        self.root.write('custom/my-rules/skills/x/.claude/skills/evil/SKILL.md', '---\nhooks: x\n---\n')
        self.root.write('custom/my-rules/skills/x/.mcp.json', '{}')
        self.root.write('custom/my-rules/skills/x/sub/SKILL.md', '---\nallowed-tools: Bash(*)\n---\n')
        ws, out = self.build()
        copied = sorted(str(p.relative_to(out)) for p in out.rglob('*') if p.is_file() and 'skills' in p.parts)
        self.assertEqual(copied, ['skills/custom-x/SKILL.md', 'skills/custom-x/ref.md'])
        text = self.warnings(ws)
        self.assertIn('skills/x/.claude skipped: hidden', text)
        self.assertIn('skills/x/.mcp.json skipped: hidden', text)
        self.assertIn('skills/x/sub/SKILL.md skipped: a skill holds one SKILL.md, at its top', text)

    def test_byte_order_mark_and_unreadable_front_matter(self):
        """Regression (review of the fix): a BOM cannot hide the front matter; an unclosed one skips the skill."""
        (self.root.base / 'custom/my-rules/skills/bom').mkdir(parents=True)
        (self.root.base / 'custom/my-rules/skills/bom/SKILL.md').write_text('\ufeff---\nname: b\nhooks: x\n---\nbody\n')
        self.root.write('custom/my-rules/skills/open/SKILL.md', '\n---\nallowed-tools: Bash(*)\nbody\n')
        self.root.write('custom/my-rules/skills/plain/SKILL.md', 'no front matter\n')
        ws, out = self.build()
        bom = (out / 'skills' / 'custom-bom' / 'SKILL.md').read_text()
        self.assertEqual(bom, '---\nname: custom-bom\n---\nbody\n')
        self.assertFalse((out / 'skills' / 'custom-open').exists())
        self.assertIn('skills/open/SKILL.md: its front matter cannot be read; the skill is skipped', self.warnings(ws))
        self.assertEqual((out / 'skills' / 'custom-plain' / 'SKILL.md').read_text(), 'no front matter\n')

    def test_yaml_forms_never_bring_a_key(self):
        """Regression (review of the fix): each YAML form below leaves only name and the allowed keys."""
        forms = [
            'hooks: x\r\n',
            '{hooks: x}\n',
            'hooks : x\n',
            '? hooks\n: x\n',
            '\thooks: x\n',
            'model:\n  claude-fable-5-2\n',
            'model: >-\n  claude-fable-5-2\n',
            '"allowed-tools": Bash(*)\n',
            "'hooks': x\n",
            'Hooks: x\n',
        ]
        for form in forms:
            with self.subTest(form=form):
                result, _ = rc.own_front_matter(
                    f'---\nname: s\n{form}effort: low\n---\nbody\n', 'custom-s', rc.SKILL_KEYS
                )
                front = result.split('\n---\n')[0].split('\n')[1:]
                self.assertEqual([line.split(':')[0] for line in front if line], ['name', 'effort'], result)

    def test_an_unreadable_item_skips_only_itself(self):
        """RN-7: a non-UTF-8 agent or skill is left out with a warning; every other own item still loads."""
        self.root.write('custom/my-rules/company.md', 'c')
        (self.root.base / 'custom/my-rules/agents').mkdir(parents=True)
        (self.root.base / 'custom/my-rules/agents/latin.md').write_bytes(b'---\nname: latin\n---\ncaf\xe9\n')
        self.root.write('custom/my-rules/skills/bad/SKILL.md', 'x')
        (self.root.base / 'custom/my-rules/skills/bad/SKILL.md').write_bytes(b'caf\xe9')
        ws, out = self.build()
        text = self.warnings(ws)
        self.assertIn('custom/my-rules/agents/latin.md skipped: cannot be read (UnicodeDecodeError)', text)
        self.assertIn('custom/my-rules/skills/bad skipped: cannot be read (UnicodeDecodeError)', text)
        self.assertTrue((out / 'rules' / 'custom-company.md').is_file())
        self.assertFalse((out / 'agents').exists() or (out / 'skills').exists())

    def test_legacy_folder_is_read_until_it_moves(self):
        self.root.write('custom/rules/company.md', 'c')
        ws, out = self.build()
        self.assertTrue((out / 'rules' / 'custom-company.md').is_file())
        self.assertIn('custom/rules/ read in place of custom/my-rules/', self.warnings(ws))
        self.root.write('custom/my-rules/cloud.md', 'c')
        ws, out = self.build()
        self.assertIn('custom/rules/ is no longer read', self.warnings(ws))


class ReplaceTests(Base):
    """RN-1 and RN-4: a replacement is always declared, and takes the place of the core rule."""

    def test_replacements_by_path_and_on_demand(self):
        self.root.write('custom/my-rules/review.md', 'own review')
        self.root.write('custom/my-rules/our-docs.md', 'own docs')
        self.root.config({'replace': {'review.md': 'review.md', 'docs.md': 'our-docs.md'}})
        ws, out = self.build()
        self.assertEqual(ws.warnings, [])
        self.assertEqual(ws.replaced, {'review.md': 'review.md', 'docs.md': 'our-docs.md'})
        self.assertFalse((out / 'rules' / 'custom-review.md').exists())
        self.assertTrue((out / 'rules' / 'custom-our-docs.md').is_file())
        self.assertEqual((out / 'skip').read_text(), 'rules docs.md\nrules review.md\n')
        agents = (out / 'AGENTS.md').read_text()
        self.assertIn('| `custom/my-rules/review.md` | a review |', agents)
        self.assertIn('`custom/my-rules/review.md` takes the place of the core `review.md`', agents)

    def test_bad_replacements_keep_the_core_rule(self):
        self.root.config({'replace': {'nope.md': 'x.md', 'review.md': '../x.md', 'models.md': 'missing.md'}})
        ws = self.root.ws()
        self.assertEqual(ws.replaced, {})
        text = self.warnings(ws)
        self.assertIn('"nope.md", which is not a core rule', text)
        self.assertIn('"../x.md" is not a file name', text)
        self.assertIn('custom/my-rules/missing.md is missing; the core rule applies', text)

    def test_excluded_and_replaced_keeps_the_replacement(self):
        self.root.write('custom/my-rules/review.md', 'own')
        self.root.config({'core': {'rules': {'exclude': ['review.md']}}, 'replace': {'review.md': 'review.md'}})
        ws = self.root.ws()
        self.assertEqual(ws.excluded['rules'], [])
        self.assertIn('both excluded and replaced', self.warnings(ws))


class AgentsTests(Base):
    """RN-6: the effective AGENTS.md no longer names a turned-off rule."""

    def test_excluded_rule_leaves_rows_and_references(self):
        self.root.config(
            {'core': {'rules': {'exclude': ['frontend.md', 'models.md']}, 'skills': {'exclude': ['pilot']}}}
        )
        _, out = self.build()
        agents = (out / 'AGENTS.md').read_text()
        self.assertNotIn('rules/frontend.md', agents)
        self.assertNotIn('rules/models.md', agents)
        self.assertIn('- UI work.\n', agents)
        self.assertIn('| `templates/request.md` | a request |', agents)
        self.assertIn('| `rules/git.md` | a commit |', agents)
        self.assertIn('- Turned off: `frontend.md`, `models.md`, `pilot` (skill).', agents)

    def test_no_configuration_keeps_agents_md_as_it_is(self):
        _, out = self.build()
        self.assertEqual((out / 'AGENTS.md').read_text(), (self.root.base / 'AGENTS.md').read_text())

    def test_real_agents_md_names_no_turned_off_rule(self):
        """For every rule of the real core that can be turned off, excluding it removes every mention of it."""
        text = (PRODUCT / 'AGENTS.md').read_text()
        manifest = json.loads((PRODUCT / 'rules' / 'manifest.json').read_text())
        rules = sorted(p.name for p in (PRODUCT / 'rules').glob('*.md') if p.name not in manifest['rules'])
        self.assertTrue(rules)
        for name in rules:
            self.root.write(f'rules/{name}', f'# {name}\n')
        self.root.config({'core': {'rules': {'exclude': rules}}})
        ws = self.root.ws()
        result = ws.effective_agents(text)
        for name in rules:
            self.assertNotIn(f'rules/{name}', result, name)
        for name in manifest['rules']:
            if f'rules/{name}' in text:
                self.assertIn(f'rules/{name}', result, name)
        self.assertNotRegex(result, r'\(\s*\)')


class EditTests(Base):
    """RN-8: the edits of /rules."""

    def run_main(self, *argv):
        """Runs main() on this root; returns (exit code, stdout, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = rc.main(['--root', str(self.root.base), *argv])
        return code, out.getvalue(), err.getvalue()

    def test_exclude_and_include(self):
        self.assertEqual(self.run_main('exclude', 'frontend.md')[0], 0)
        self.assertEqual(self.run_main('exclude', 'pilot')[0], 0)
        self.assertEqual(self.run_main('exclude', 'infra-engineer')[0], 0)
        self.assertIn('already turned off', self.run_main('exclude', 'pilot')[1])
        data = self.root.read_config()
        self.assertEqual(data['core']['rules']['exclude'], ['frontend.md'])
        self.assertEqual(data['core']['skills']['exclude'], ['pilot'])
        self.assertEqual(data['core']['agents']['exclude'], ['infra-engineer'])
        self.assertEqual(self.run_main('include', 'pilot')[0], 0)
        self.assertEqual(self.root.read_config()['core']['skills']['exclude'], [])
        self.assertIn('already loaded', self.run_main('include', 'pilot')[1])

    def test_exclude_refusals(self):
        code, _, err = self.run_main('exclude', 'git.md')
        self.assertEqual(code, 1)
        self.assertIn('mandatory', err)
        self.assertIn('frontend.md', self.run_main('exclude', 'frontend')[2])
        self.root.write('rules/skills/twin/SKILL.md', 'x')
        self.root.write('rules/agents/twin.md', 'x')
        self.assertIn('add --kind', self.run_main('exclude', 'twin')[2])
        self.assertEqual(self.run_main('exclude', 'twin', '--kind', 'agents')[0], 0)
        self.root.config('{')
        self.assertIn('fix it by hand', self.run_main('exclude', 'pilot')[2])
        self.assertFalse((self.root.base / rc.CONFIG).read_text() != '{')

    def test_replace_copies_the_core_rule_once(self):
        code, out, _ = self.run_main('replace', 'review.md')
        self.assertEqual(code, 0)
        self.assertIn('copied from the core', out)
        own = self.root.base / 'custom' / 'my-rules' / 'review.md'
        self.assertEqual(own.read_text(), '# review.md\n')
        own.write_text('edited')
        self.assertIn('kept as it was', self.run_main('replace', 'review.md')[1])
        self.assertEqual(own.read_text(), 'edited')
        self.assertEqual(self.root.read_config()['replace'], {'review.md': 'review.md'})
        self.assertIn('include it first', self.run_main('exclude', 'review.md')[2])
        code, out, _ = self.run_main('include', 'review.md')
        self.assertIn('stays: delete or rename it', out)
        self.assertEqual(self.root.read_config()['replace'], {})
        self.assertEqual(self.run_main('replace', 'git.md')[0], 1)
        self.assertEqual(self.run_main('replace', 'docs.md', '--as', '../x.md')[0], 1)

    def test_add_writes_an_own_rule(self):
        """AC-7: /rules add "SQL review" creates custom/my-rules/sql-review.md."""
        code, out, _ = self.run_main('add', 'SQL review')
        self.assertEqual((code, out), (0, 'custom/my-rules/sql-review.md\n'))
        self.assertEqual((self.root.base / 'custom/my-rules/sql-review.md').read_text(), '# sql-review.md\n')
        self.assertIn('already exists', self.run_main('add', 'sql review')[2])
        self.assertIn('is a core rule', self.run_main('add', 'Review')[2])
        self.assertIn('no file name', self.run_main('add', '!!')[2])

    def test_show_lists_origins_and_warnings(self):
        self.root.write('custom/my-rules/company.md', 'c')
        self.root.write('custom/my-rules/review.md', 'own')
        self.root.config(
            {'core': {'rules': {'exclude': ['frontend.md', 'git.md']}}, 'replace': {'review.md': 'review.md'}}
        )
        code, out, _ = self.run_main('show')
        self.assertEqual(code, 0)
        for row in (
            '| `git.md` | core, mandatory | on demand |',
            '| `frontend.md` | turned off | by path |',
            '| `review.md` | replaced by `custom/my-rules/review.md` | on demand |',
            '| `docs.md` | core | by path |',
            '| `pilot` | core |',
            '| rule | `company.md` | `custom-company.md` | every session |',
            '- custom/rules-config.json: "git.md" is mandatory',
        ):
            self.assertIn(row, out)

    def test_build_prints_warnings_and_a_bad_root_is_a_usage_error(self):
        self.root.config('{')
        code, _, err = self.run_main('build', '--out', str(Path(self.tmp.name) / 'out'))
        self.assertEqual(code, 0)
        self.assertIn('warning: custom/rules-config.json is not valid JSON', err)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(rc.main(['--root', str(Path(self.tmp.name) / 'nothing'), 'show']), 2)


class LessonTests(Base):
    """RN-9: /rules lessons shows only grave lessons and recurring ones, never rare ones."""

    def test_candidates(self):
        """AC-1a: one grave general, one suggestion seen twice, one rare: the first two only."""
        self.root.write(
            rc.LESSONS,
            '# Lessons\n\n'
            '- 2026-11-01 [grave] [general] A hook was bypassed by a pipe.\n'
            '- 2026-11-02 [suggestion] [project billing-api] Run the migrations before the tests.\n'
            '- 2026-11-03 [attention] [general] [rare] A one-off flaky network.\n'
            '- 2026-11-04 [suggestion] [project billing-api] run the migrations before the tests.\n'
            '- 2026-11-05 [attention] [general] Seen once only.\n'
            '- 2026-11-06 untagged line\n',
        )
        table = rc.cmd_lessons(self.root.ws())
        rows = [line for line in table.split('\n') if re.match(r'\| \d', line)]
        self.assertEqual(len(rows), 2, table)
        self.assertIn('| 1 | grave | general | once | 3 | A hook was bypassed by a pipe. |', rows[0])
        self.assertIn('| 2 | suggestion | project billing-api | recurring (2x) | 4, 6 |', rows[1])
        self.assertNotIn('flaky', table)

    def test_recurring_tag_and_rare_grave(self):
        self.root.write(
            rc.LESSONS,
            '- [attention] [recurring] Tagged recurring.\n- [grave] [rare] Grave but rare.\n',
        )
        table = rc.cmd_lessons(self.root.ws())
        self.assertIn('Tagged recurring.', table)
        self.assertNotIn('Grave but rare', table)

    def test_no_file_and_no_candidate(self):
        self.assertIn('No custom/docs/lessons.md', rc.cmd_lessons(self.root.ws()))
        self.root.write(rc.LESSONS, '- [suggestion] once\n')
        self.assertIn('No candidate lesson', rc.cmd_lessons(self.root.ws()))


if __name__ == '__main__':
    unittest.main()
