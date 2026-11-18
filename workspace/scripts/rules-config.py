"""The rules configuration of a workspace: which core rules, skills and agents load, which core rule an own rule
replaces, and the own rules, skills and agents of custom/my-rules/.

custom/rules-config.json (optional; every field optional):
  {"core": {"rules": {"exclude": ["frontend.md"]}, "skills": {"exclude": ["pilot"]},
            "agents": {"exclude": ["infra-engineer"]}},
   "replace": {"review.md": "review.md"}}
custom/my-rules/ holds the own items: *.md rules (with a paths: front matter they load by path, without it in every
session), skills/<name>/ and agents/<name>.md. In .claude/ each one carries the custom- prefix, and the front matter
of an own skill or agent keeps only the keys of SKILL_KEYS and AGENT_KEYS (never hooks, a permission mode, a tool
grant or a model guard-subagent-model.py would refuse), the rest left out with a warning. An own item with the
name of a core item is refused unless a "replace" declares it (rules only). A replacement takes the place of the core
rule: copied to .claude/rules/ when the core rule loads by path, else the effective AGENTS.md points to it.
The mandatory core (rules/manifest.json) is never turned off nor replaced: the core piece stays, with a warning.
An invalid configuration never fails: what is wrong is ignored with a warning, and the rest of the core loads.
Until custom/my-rules/ exists, custom/rules/ (its former name) is read in its place, with a warning.

Commands:
  build --out <dir>     write into <dir> (empty) what setup-claude.sh syncs into .claude/: AGENTS.md (the effective
                        one: a turned-off rule is no longer named, a replaced one points to the own file),
                        rules/custom-*.md, skills/custom-<name>/, agents/custom-<name>.md, and "skip" (one
                        "<rules|skills|agents> <name>" line per core item that must not load). Warnings on stderr.
  show                  the effective rules, skills and agents with the origin of each, and the warnings.
  exclude <name> [--kind rules|skills|agents]
                        turn off a core item (a rule is <name>.md); refused for the mandatory core.
  include <name>        turn a core item back on (removes its exclude, or the replace of a rule).
  replace <rule> [--as <file>]
                        replace a core rule: copies it to custom/my-rules/<file> (default: the same name) when that
                        file does not exist yet, and declares the replace.
  add <subject>         create custom/my-rules/<slug>.md with a title, for the own rule to be written in it.
  lessons               the candidate lessons of custom/docs/lessons.md: tagged grave, or recurring (tagged so or
                        written more than once), never rare. Tags are words in square brackets on the line: weight
                        [grave] [attention] [suggestion], scope [general] [project <name>], [recurring] or [rare];
                        a line without a weight is not read.
Exit codes: 0 done (build and show always, unless the root has no rules/); 1 refused, with the reason; 2 usage.
Usage: python3 -I -B scripts/rules-config.py <command> [--root <workspace>] ...
"""

import argparse
import json
import os
import re
import shutil
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CONFIG = 'custom/rules-config.json'
OWN = 'custom/my-rules'
LEGACY = 'custom/rules'
LESSONS = 'custom/docs/lessons.md'
KINDS = ('rules', 'skills', 'agents')
ITEM_NAME = re.compile(r'[a-z0-9][a-z0-9_-]*\Z')
RULE_NAME = re.compile(r'[a-z0-9][a-z0-9._-]*\.md\Z')
WEIGHTS = ('grave', 'attention', 'suggestion')
# The front matter keys an own skill or agent keeps in .claude/: none that runs a command (hooks), grants a tool or a
# permission (allowed-tools, permissionMode, mcpServers) or changes how it runs; the rest is dropped with a warning.
SKILL_KEYS = frozenset(
    {'name', 'description', 'argument-hint', 'disable-model-invocation', 'user-invocable', 'model', 'effort', 'paths'}
)
AGENT_KEYS = frozenset({'name', 'description', 'tools', 'disallowedTools', 'model', 'effort', 'color'})
FRONT_MATTER_KEY = re.compile(r'([A-Za-z_][A-Za-z0-9_-]*)\s*:(.*)\Z')
# The models guard-subagent-model.py allows (its ALLOWED_MODEL): never Fable from an own item.
ALLOWED_MODEL = re.compile(r'(opus|sonnet|haiku|claude-(opus|sonnet|haiku)-[a-z0-9._\[\]-]+)')


class Refused(Exception):
    """An edit the configuration does not allow; the message says why."""


def is_regular(path):
    """True for a regular file that is not a link: a link could bring a file from outside into every session."""
    return os.path.isfile(path) and not os.path.islink(path)


def is_folder(path):
    """A folder that is not a link."""
    return os.path.isdir(path) and not os.path.islink(path)


def read_text(path):
    """The UTF-8 text of path."""
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def front_matter_end(lines):
    """Index of the line closing the front matter (lines[0] is ---), or None when there is none."""
    if not lines or lines[0].rstrip() != '---':
        return None
    for index in range(1, len(lines)):
        if lines[index].rstrip() == '---':
            return index
    return None


def has_paths(path):
    """True when the file opens with a front matter holding a paths: field (the same test as setup-claude.sh)."""
    try:
        lines = read_text(path).split('\n')
    except (OSError, UnicodeDecodeError):
        return False
    end = front_matter_end(lines)
    return end is not None and any(line.startswith('paths:') for line in lines[1:end])


def own_front_matter(text, name, keys):
    """(text, dropped) for an own skill or agent: its front matter keeps only the keys allowed, a model: only when
    guard-subagent-model would allow it, and name: set to name; dropped lists what was left out. (None, []) when the
    text has no front matter. A line that is neither a key nor the continuation of one is dropped too, so no YAML form
    (a quoted key, a merge key) can bring in a key that is not on the list."""
    lines = text.split('\n')
    end = front_matter_end(lines)
    if end is None:
        return None, []
    kept, dropped, keep = [], [], False
    for line in lines[1:end]:
        key = FRONT_MATTER_KEY.match(line)
        if key:
            field, value = key.group(1), key.group(2).strip().strip('\'"').strip().lower()
            keep = field in keys and field != 'name' and (field != 'model' or ALLOWED_MODEL.fullmatch(value))
            if not keep and field != 'name':
                dropped.append(field)
        elif not (line == '' or line[0] in ' -#'):
            keep = False
            dropped.append(line.strip()[:40])
        if keep:
            kept.append(line)
    return '\n'.join(['---', f'name: {name}'] + kept + lines[end:]), dropped


def slug(subject):
    """The kebab-case file stem of a subject ("SQL review" -> "sql-review")."""
    return re.sub(r'[^a-z0-9]+', '-', subject.lower()).strip('-')


class Workspace:
    """The core, the manifest, the configuration and the own items of one workspace root, resolved with warnings."""

    def __init__(self, root):
        """Reads and resolves everything under root; problems become warnings."""
        self.root = root
        self.warnings = []
        self.core = {
            'rules': self._core_rules(),
            'skills': self._core_names('rules/skills', folders=True),
            'agents': self._core_names('rules/agents', folders=False),
        }
        self.own_dir = self._own_dir()
        self.mandatory = self._manifest()
        self.config = self._config()
        self.excluded = {kind: [] for kind in KINDS}
        self.replaced = {}
        self._resolve()
        self.own_rules, self.own_skills, self.own_agents = self._own_items()

    def warn(self, text):
        """Records one warning."""
        self.warnings.append(text)

    def path(self, *parts):
        """An absolute path under the root."""
        return os.path.join(self.root, *parts)

    # The core.

    def _core_rules(self):
        """Core rule name -> True when it loads by path (paths: front matter), False when AGENTS.md says to read it."""
        folder = self.path('rules')
        names = sorted(n for n in os.listdir(folder) if n.endswith('.md') and is_regular(os.path.join(folder, n)))
        return {name: has_paths(os.path.join(folder, name)) for name in names}

    def _core_names(self, rel, folders):
        """The core skills (folders with a SKILL.md) or agents (*.md stems) of rel."""
        folder = self.path(rel)
        if not os.path.isdir(folder):
            return []
        if folders:
            return sorted(n for n in os.listdir(folder) if os.path.isfile(os.path.join(folder, n, 'SKILL.md')))
        return sorted(n[:-3] for n in os.listdir(folder) if n.endswith('.md'))

    def _manifest(self):
        """The mandatory names per kind; None when rules/manifest.json is unreadable (then nothing is configurable)."""
        try:
            data = json.loads(read_text(self.path('rules', 'manifest.json')))
            mandatory = {kind: set(data[kind]) for kind in KINDS}
            if not all(isinstance(name, str) for names in mandatory.values() for name in names):
                raise TypeError('a name is not a string')
            return mandatory
        except (OSError, ValueError, KeyError, TypeError) as error:
            name = type(error).__name__
            self.warn(f'rules/manifest.json unreadable ({name}): {CONFIG} ignored, the whole core loads')
            return None

    # The configuration.

    def _raw_config(self):
        """The parsed configuration, {} when missing, or None when it cannot be used (warned)."""
        path = self.path(CONFIG)
        if not os.path.lexists(path):
            return {}
        if not is_regular(path):
            self.warn(f'{CONFIG} is not a regular file: ignored, the whole core loads')
            return None
        try:
            data = json.loads(read_text(path))
        except UnicodeDecodeError:
            self.warn(f'{CONFIG} is not UTF-8 text: ignored, the whole core loads')
            return None
        except ValueError as error:
            line = getattr(error, 'lineno', '?')
            self.warn(f'{CONFIG} is not valid JSON (line {line}): ignored, the whole core loads')
            return None
        except OSError as error:
            self.warn(f'{CONFIG} unreadable ({type(error).__name__}): ignored, the whole core loads')
            return None
        if not isinstance(data, dict):
            self.warn(f'{CONFIG} is not a JSON object: ignored, the whole core loads')
            return None
        return data

    def _config(self):
        """The usable fields: {'exclude': {kind: [names]}, 'replace': {rule: file}}; what is malformed is warned."""
        result = {'exclude': {kind: [] for kind in KINDS}, 'replace': {}}
        data = self._raw_config()
        if not data or self.mandatory is None:
            return result
        for key in data:
            if key not in ('core', 'replace'):
                self.warn(f'{CONFIG}: unknown field "{key}" ignored')
        core = data.get('core', {})
        if not isinstance(core, dict):
            self.warn(f'{CONFIG}: "core" is not an object; ignored')
            core = {}
        for key in core:
            if key not in KINDS:
                self.warn(f'{CONFIG}: unknown field "core.{key}" ignored')
        for kind in KINDS:
            section = core.get(kind, {})
            if not isinstance(section, dict):
                self.warn(f'{CONFIG}: "core.{kind}" is not an object; ignored')
                continue
            for key in section:
                if key != 'exclude':
                    self.warn(f'{CONFIG}: unknown field "core.{kind}.{key}" ignored')
            names = section.get('exclude', [])
            if not isinstance(names, list) or not all(isinstance(n, str) for n in names):
                self.warn(f'{CONFIG}: "core.{kind}.exclude" is not a list of names; ignored')
                continue
            result['exclude'][kind] = names
        replace = data.get('replace', {})
        if not isinstance(replace, dict) or not all(isinstance(v, str) for v in replace.values()):
            self.warn(f'{CONFIG}: "replace" is not an object of file names; ignored')
        else:
            result['replace'] = replace
        return result

    def _known(self, kind, name):
        """True when name is a core item of kind."""
        return name in self.core[kind]

    def _resolve(self):
        """Applies the configuration to the core: the valid excludes and replacements, the rest warned."""
        for kind in KINDS:
            for name in self.config['exclude'][kind]:
                if not self._known(kind, name):
                    hint = f' (did you mean {name}.md?)' if kind == 'rules' and self._known(kind, f'{name}.md') else ''
                    self.warn(f'{CONFIG}: core.{kind}.exclude names "{name}", which is not in the core; ignored{hint}')
                elif name in self.mandatory[kind]:
                    self.warn(f'{CONFIG}: "{name}" is mandatory (rules/manifest.json); it stays loaded')
                elif name not in self.excluded[kind]:
                    self.excluded[kind].append(name)
        own_rel = os.path.relpath(self.own_dir, self.root)
        for rule, own in self.config['replace'].items():
            if not self._known('rules', rule):
                self.warn(f'{CONFIG}: replace names "{rule}", which is not a core rule; ignored')
            elif rule in self.mandatory['rules']:
                self.warn(f'{CONFIG}: "{rule}" is mandatory (rules/manifest.json); it is not replaced')
            elif not RULE_NAME.match(own):
                self.warn(f'{CONFIG}: replace of "{rule}": "{own}" is not a file name of {own_rel}/ ending in .md')
            elif not is_regular(os.path.join(self.own_dir, own)):
                self.warn(f'{CONFIG}: replace of "{rule}": {own_rel}/{own} is missing; the core rule applies')
            else:
                self.replaced[rule] = own
                if rule in self.excluded['rules']:
                    self.warn(f'{CONFIG}: "{rule}" is both excluded and replaced; the replacement applies')
                    self.excluded['rules'].remove(rule)

    # The own items.

    def _own_dir(self):
        """custom/my-rules/, or custom/rules/ (its former name) while only that one exists."""
        own, legacy = self.path(OWN), self.path(LEGACY)
        if is_folder(own):
            if is_folder(legacy) and os.listdir(legacy):
                self.warn(f'{LEGACY}/ is no longer read: move its files to {OWN}/')
            return own
        if is_folder(legacy):
            self.warn(f'{LEGACY}/ read in place of {OWN}/; rename it: git -C custom mv rules my-rules')
            return legacy
        return own

    def _own_items(self):
        """The own rules, skills and agents that load; the refused and skipped ones are warned."""
        rules, skills, agents = [], [], []
        own_rel = os.path.relpath(self.own_dir, self.root)
        if not is_folder(self.own_dir):
            return rules, skills, agents
        replacements = set(self.replaced.values())
        for name in sorted(os.listdir(self.own_dir)):
            path = os.path.join(self.own_dir, name)
            if not name.endswith('.md') or name in replacements:
                continue
            if not is_regular(path):
                self.warn(f'{own_rel}/{name} skipped: not a regular file')
            elif self._known('rules', name):
                self.warn(f'{own_rel}/{name} refused: a core rule has that name and no "replace" declares it')
            else:
                rules.append(name)
        skills_dir = os.path.join(self.own_dir, 'skills')
        for name in sorted(os.listdir(skills_dir)) if is_folder(skills_dir) else []:
            path = os.path.join(skills_dir, name)
            if not is_folder(path) or not ITEM_NAME.match(name):
                self.warn(f'{own_rel}/skills/{name} skipped: not a folder with a lowercase name')
            elif 'SKILL.md' not in os.listdir(path) or not is_regular(os.path.join(path, 'SKILL.md')):
                # The exact name from the listing: on a file system that ignores case, skill.md would pass an open().
                self.warn(f'{own_rel}/skills/{name} skipped: no SKILL.md')
            elif self._known('skills', name):
                self.warn(f'{own_rel}/skills/{name} refused: a core skill has that name')
            else:
                skills.append(name)
        agents_dir = os.path.join(self.own_dir, 'agents')
        for name in sorted(os.listdir(agents_dir)) if is_folder(agents_dir) else []:
            path, stem = os.path.join(agents_dir, name), name[:-3]
            if not name.endswith('.md'):
                continue
            if not is_regular(path) or not ITEM_NAME.match(stem):
                self.warn(f'{own_rel}/agents/{name} skipped: not a regular file with a lowercase name')
            elif self._known('agents', stem):
                self.warn(f'{own_rel}/agents/{name} refused: a core agent has that name')
            else:
                agents.append(stem)
        return rules, skills, agents

    # The effective AGENTS.md.

    def own_path(self, name):
        """The path of an own file, relative to the root."""
        return f'{os.path.relpath(self.own_dir, self.root)}/{name}'

    def effective_agents(self, text):
        """AGENTS.md without the turned-off rules (table rows and parenthesized references) and with each replaced
        rule pointing to its own file, plus a closing section that names the changes."""
        off = self.excluded['rules']
        lines = []
        for line in text.split('\n'):
            if line.startswith('|') and off:
                cells = line.split('|')
                items = [item.strip() for item in cells[1].split(',')]
                kept = [item for item in items if item.strip('`') not in {f'rules/{n}' for n in off}]
                if not kept:
                    continue
                if len(kept) != len(items):
                    cells[1] = ' ' + ', '.join(kept) + ' '
                    line = '|'.join(cells)
            for name in off:
                line = re.sub(r' ?\(`rules/' + re.escape(name) + r'`[^()]*\)', '', line)
            for name, own in self.replaced.items():
                line = line.replace(f'`rules/{name}`', f'`{self.own_path(own)}`')
            lines.append(line)
        result = '\n'.join(lines).rstrip('\n') + '\n'
        notes = [
            f'- Replaced: `{self.own_path(own)}` takes the place of the core `{name}`; wherever a file names the core '
            'rule, read the own one.'
            for name, own in self.replaced.items()
        ]
        off_items = [f'`{n}`' for n in off] + [f'`{n}` (skill)' for n in self.excluded['skills']]
        off_items += [f'`{n}` (agent)' for n in self.excluded['agents']]
        if off_items:
            notes.append(f'- Turned off: {", ".join(off_items)}. A mention of them in another file does not apply.')
        if notes:
            result += '\n## Workspace configuration\n\nFrom `custom/rules-config.json` (`/rules` shows it).\n\n'
            result += '\n'.join(notes) + '\n'
        return result

    # Commands.

    def build(self, out):
        """Writes what setup-claude.sh syncs into .claude/ (see the module docstring)."""
        source = self.path('AGENTS.md')
        if is_regular(source):
            write(os.path.join(out, 'AGENTS.md'), self.effective_agents(read_text(source)))
        else:
            self.warn('AGENTS.md missing: .claude/AGENTS.md not generated')
        rules = [(name, f'custom-{name}') for name in self.own_rules]
        rules += [(own, f'custom-{own}') for rule, own in self.replaced.items() if self.core['rules'][rule]]
        for name, target in rules:
            self._guarded(name, copy, os.path.join(self.own_dir, name), os.path.join(out, 'rules', target))
        for name in self.own_skills:
            self._guarded(f'skills/{name}', self._copy_skill, name, os.path.join(out, 'skills', f'custom-{name}'))
        for stem in self.own_agents:
            self._guarded(f'agents/{stem}.md', self._copy_agent, stem, os.path.join(out, 'agents', f'custom-{stem}.md'))
        skip = [f'rules {n}' for n in self.excluded['rules'] + sorted(self.replaced)]
        skip += [f'{kind} {n}' for kind in ('skills', 'agents') for n in self.excluded[kind]]
        write(os.path.join(out, 'skip'), ''.join(line + '\n' for line in skip))

    def _guarded(self, rel, action, *args):
        """Runs action(*args) for one own item; an unreadable or non-UTF-8 file skips that item only, with a warning."""
        try:
            action(*args)
        except (OSError, UnicodeDecodeError) as error:
            self.warn(f'{self.own_path(rel)} skipped: cannot be read ({type(error).__name__})')

    def _filtered(self, rel, text, name, keys):
        """The text of an own skill or agent with its front matter filtered (own_front_matter), warning what went.
        A leading byte order mark is dropped first, so it cannot hide the front matter from the filter."""
        result, dropped = own_front_matter(text.lstrip('\ufeff'), name, keys)
        if dropped:
            self.warn(f'{self.own_path(rel)}: front matter not allowed for an own item, left out: {", ".join(dropped)}')
        return result

    def _copy_agent(self, stem, target):
        """Writes an own agent to target with its front matter filtered and its name prefixed."""
        rel = f'agents/{stem}.md'
        text = self._filtered(rel, read_text(os.path.join(self.own_dir, rel)), f'custom-{stem}', AGENT_KEYS)
        if text is None:
            self.warn(f'{self.own_path(rel)} skipped: an agent needs a front matter')
        else:
            write(target, text)

    def _copy_skill(self, name, target):
        """Copies an own skill to target: regular files only, SKILL.md with its front matter filtered and its name
        prefixed. Hidden files and folders (a nested .claude/ that Claude Code could load as configuration) and a
        SKILL.md below the top are left out. A SKILL.md that opens like a front matter the filter cannot read, or a
        file that cannot be read, leaves the whole skill out (the copy is written only at the end)."""
        source = os.path.join(self.own_dir, 'skills', name)
        files_out = []
        for folder, subfolders, files in os.walk(source):
            for hidden in [d for d in subfolders if d.startswith('.')]:
                self.warn(
                    f'{self.own_path(os.path.relpath(os.path.join(folder, hidden), self.own_dir))} skipped: hidden'
                )
            subfolders[:] = [
                d for d in sorted(subfolders) if not d.startswith('.') and not os.path.islink(os.path.join(folder, d))
            ]
            for file in sorted(files):
                path = os.path.join(folder, file)
                rel = os.path.relpath(path, source)
                shown = self.own_path(f'skills/{name}/{rel}')
                if file == '.DS_Store':
                    continue
                if file.startswith('.'):
                    self.warn(f'{shown} skipped: hidden')
                elif not is_regular(path):
                    self.warn(f'{shown} skipped: not a regular file')
                elif file.lower() == 'skill.md' and rel != 'SKILL.md':
                    self.warn(f'{shown} skipped: a skill holds one SKILL.md, at its top, with that exact name')
                elif rel == 'SKILL.md':
                    text = read_text(path).lstrip('\ufeff')
                    filtered = self._filtered(f'skills/{name}/SKILL.md', text, f'custom-{name}', SKILL_KEYS)
                    if filtered is None and text.lstrip(' \t\r\n').startswith('---'):
                        self.warn(f'{shown}: its front matter cannot be read; the skill is skipped')
                        return
                    files_out.append((rel, (filtered if filtered is not None else text).encode('utf-8')))
                else:
                    with open(path, 'rb') as handle:
                        files_out.append((rel, handle.read()))
        for rel, data in files_out:
            os.makedirs(os.path.dirname(os.path.join(target, rel)), exist_ok=True)
            with open(os.path.join(target, rel), 'wb') as handle:
                handle.write(data)

    def show(self):
        """The effective rules, skills and agents, as Markdown tables, then the warnings."""
        out = ['## Core rules', '', '| Rule | State | Loads |', '| --- | --- | --- |']
        for name, by_path in self.core['rules'].items():
            out.append(f'| `{name}` | {self._state("rules", name)} | {"by path" if by_path else "on demand"} |')
        for kind in ('skills', 'agents'):
            out += ['', f'## Core {kind}', '', f'| {kind[:-1].capitalize()} | State |', '| --- | --- |']
            out += [f'| `{name}` | {self._state(kind, name)} |' for name in self.core[kind]]
        out += ['', f'## Own items ({os.path.relpath(self.own_dir, self.root)}/)', '']
        own = [f'| rule | `{n}` | `custom-{n}` | {self._own_load(n)} |' for n in self.own_rules]
        own += [f'| skill | `skills/{n}/` | `/custom-{n}` | on demand |' for n in self.own_skills]
        own += [f'| agent | `agents/{n}.md` | `custom-{n}` | on demand |' for n in self.own_agents]
        if own:
            out += ['| Kind | File | In the session | Loads |', '| --- | --- | --- | --- |'] + own
        else:
            out.append('None.')
        out += ['', '## Warnings', '']
        out += [f'- {w}' for w in self.warnings] or ['None.']
        return '\n'.join(out) + '\n'

    def _state(self, kind, name):
        """The state of a core item, as /rules shows it."""
        if self.mandatory and name in self.mandatory[kind]:
            return 'core, mandatory'
        if kind == 'rules' and name in self.replaced:
            return f'replaced by `{self.own_path(self.replaced[name])}`'
        if name in self.excluded[kind]:
            return 'turned off'
        return 'core'

    def _own_load(self, name):
        """When an own rule loads, as /rules shows it."""
        return 'by path' if has_paths(os.path.join(self.own_dir, name)) else 'every session'


def write(path, text):
    """Writes text to path, creating its folders."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


def copy(source, target):
    """Copies source to target, creating its folders."""
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(source, target)


# Edits of the configuration.


def load_for_edit(ws):
    """The configuration as an editable dict; refused when it exists and is not a valid JSON object."""
    path = ws.path(CONFIG)
    if not os.path.lexists(path):
        return {}
    if not is_regular(path):
        raise Refused(f'{CONFIG} is not a regular file')
    try:
        data = json.loads(read_text(path))
    except (ValueError, OSError) as error:
        raise Refused(f'{CONFIG} is not valid JSON ({type(error).__name__}); fix it by hand first') from error
    if not isinstance(data, dict):
        raise Refused(f'{CONFIG} is not a JSON object; fix it by hand first')
    return data


def save(ws, data):
    """Writes the configuration whole: a temporary file in the same folder, then a rename."""
    path = ws.path(CONFIG)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    handle, temp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.rules-config.')
    try:
        with os.fdopen(handle, 'w', encoding='utf-8') as out:
            out.write(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
        os.chmod(temp, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
        os.replace(temp, path)
    except BaseException:
        os.unlink(temp)
        raise


def exclude_list(data, kind):
    """The editable core.<kind>.exclude list of data, created when missing."""
    core = data.setdefault('core', {})
    if not isinstance(core, dict) or not isinstance(core.setdefault(kind, {}), dict):
        raise Refused(f'{CONFIG}: "core" or "core.{kind}" is not an object; fix it by hand first')
    names = core[kind].setdefault('exclude', [])
    if not isinstance(names, list):
        raise Refused(f'{CONFIG}: "core.{kind}.exclude" is not a list; fix it by hand first')
    return names


def replace_map(data):
    """The editable "replace" object of data, created when missing."""
    replace = data.setdefault('replace', {})
    if not isinstance(replace, dict):
        raise Refused(f'{CONFIG}: "replace" is not an object; fix it by hand first')
    return replace


def kind_of(ws, name, kind):
    """The kind of the core item name (given, or found); refused when it is in none or in two."""
    kinds = [kind] if kind else [k for k in KINDS if ws._known(k, name)]
    if kind and not ws._known(kind, name):
        kinds = []
    if not kinds:
        hint = f' (a rule is named with .md: {name}.md)' if ws._known('rules', f'{name}.md') else ''
        raise Refused(f'"{name}" is not a core {kind or "rule, skill or agent"}{hint}')
    if len(kinds) > 1:
        raise Refused(f'"{name}" is both a core {kinds[0][:-1]} and a core {kinds[1][:-1]}: add --kind')
    return kinds[0]


def check_mandatory(ws, kind, name):
    """Refuses a change to a piece of the mandatory core (or to anything without a manifest)."""
    if ws.mandatory is None:
        raise Refused('rules/manifest.json unreadable: the configuration cannot change')
    if name in ws.mandatory[kind]:
        raise Refused(f'"{name}" is mandatory (rules/manifest.json): it cannot be turned off nor replaced')


def cmd_exclude(ws, name, kind):
    """Turns a core item off; returns what changed."""
    kind = kind_of(ws, name, kind)
    check_mandatory(ws, kind, name)
    data = load_for_edit(ws)
    if kind == 'rules' and name in replace_map(data):
        raise Refused(f'"{name}" is replaced by an own rule: include it first, then exclude it')
    names = exclude_list(data, kind)
    if name in names:
        return f'{name}: already turned off'
    names.append(name)
    save(ws, data)
    return f'{name}: turned off (core.{kind}.exclude)'


def cmd_include(ws, name, kind):
    """Turns a core item back on (its exclude, or the replace of a rule); returns what changed."""
    kind = kind_of(ws, name, kind)
    data = load_for_edit(ws)
    names = exclude_list(data, kind)
    replace = replace_map(data) if kind == 'rules' else {}
    if name not in names and name not in replace:
        return f'{name}: already loaded from the core'
    message = f'{name}: loaded from the core again'
    if name in replace:
        own = replace.pop(name)
        message += f'; {ws.own_path(own)} stays: delete or rename it, or every session warns it is refused'
    while name in names:
        names.remove(name)
    save(ws, data)
    return message


def cmd_replace(ws, rule, own):
    """Declares an own rule in place of a core rule, copying the core one when the own file is new."""
    kind_of(ws, rule, 'rules')
    check_mandatory(ws, 'rules', rule)
    own = own or rule
    if not RULE_NAME.match(own):
        raise Refused(f'"{own}" is not a file name ending in .md')
    data = load_for_edit(ws)
    target = os.path.join(ws.own_dir, own)
    copied = not os.path.lexists(target)
    if copied:
        os.makedirs(ws.own_dir, exist_ok=True)
        shutil.copyfile(ws.path('rules', rule), target)
        os.chmod(target, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
    elif not is_regular(target):
        raise Refused(f'{ws.own_path(own)} is not a regular file')
    replace_map(data)[rule] = own
    names = exclude_list(data, 'rules')
    while rule in names:
        names.remove(rule)
    save(ws, data)
    start = 'copied from the core as a starting point' if copied else 'kept as it was'
    return f'{rule}: replaced by {ws.own_path(own)} ({start})'


def cmd_add(ws, subject):
    """Creates the own rule file of a subject, with its title; returns its path."""
    name = slug(subject)
    if not name:
        raise Refused('the subject gives no file name: use letters or digits')
    file = f'{name}.md'
    if ws._known('rules', file):
        raise Refused(f'{file} is a core rule: replace it (replace {file}) instead')
    target = os.path.join(ws.own_dir, file)
    if os.path.lexists(target):
        raise Refused(f'{ws.own_path(file)} already exists: adjust it instead')
    os.makedirs(ws.own_dir, exist_ok=True)
    write(target, f'# {file}\n')
    return ws.own_path(file)


TAG = re.compile(r'\[([^\[\]]+)\]')


def parse_lesson(line):
    """(weight, scope, recurrence, text) of a tagged lesson line, or None when it has no weight tag."""
    weight = scope = recurrence = None
    for tag in (t.strip().lower() for t in TAG.findall(line)):
        if tag in WEIGHTS:
            weight = tag
        elif tag == 'general' or tag.startswith('project '):
            scope = tag
        elif tag in ('recurring', 'rare'):
            recurrence = tag
    if weight is None:
        return None
    text = TAG.sub('', line)
    text = re.sub(r'^\s*[-*]\s*', '', text)
    text = re.sub(r'^\d{4}-\d{2}-\d{2}\s*[:—-]?\s*', '', text.strip())
    return weight, scope or 'general', recurrence, ' '.join(text.split())


def cmd_lessons(ws):
    """Markdown table of the candidate lessons; rare ones never, the rest when grave or recurring."""
    path = ws.path(LESSONS)
    if not is_regular(path):
        return f'No {LESSONS}: no lessons to review.\n'
    found = {}
    for number, line in enumerate(read_text(path).split('\n'), 1):
        parsed = parse_lesson(line)
        if parsed is None:
            continue
        weight, scope, recurrence, text = parsed
        key = (scope, text.lower())
        entry = found.setdefault(key, {'lines': [], 'weights': set(), 'rare': False, 'recurring': False})
        entry.update(text=text, scope=scope)
        entry['lines'].append(number)
        entry['weights'].add(weight)
        entry['rare'] |= recurrence == 'rare'
        entry['recurring'] |= recurrence == 'recurring'
    rows = []
    for entry in found.values():
        weight = next(w for w in WEIGHTS if w in entry['weights'])
        recurring = entry['recurring'] or len(entry['lines']) > 1
        if entry['rare'] or not (weight == 'grave' or recurring):
            continue
        lines = ', '.join(str(n) for n in entry['lines'])
        times = f'recurring ({len(entry["lines"])}x)' if recurring else 'once'
        rows.append(f'| {len(rows) + 1} | {weight} | {entry["scope"]} | {times} | {lines} | {entry["text"]} |')
    if not rows:
        return f'No candidate lesson in {LESSONS} (only grave or recurring ones, never rare, are proposed).\n'
    head = ['| # | Weight | Scope | Recurrence | Lines | Lesson |', '| --- | --- | --- | --- | --- | --- |']
    return '\n'.join(head + rows) + '\n'


def parse_args(argv):
    """The parsed command line."""
    parser = argparse.ArgumentParser(prog='rules-config.py', description=__doc__.split('\n', 1)[0])
    parser.add_argument('--root', help='workspace root (default: the folder above scripts/)')
    commands = parser.add_subparsers(dest='command', required=True)
    add_parser = commands.add_parser

    def command(name):
        """A subcommand that also takes --root after its name."""
        sub = add_parser(name)
        sub.add_argument('--root', dest='sub_root', help=argparse.SUPPRESS)
        return sub

    commands.add_parser = command
    build = commands.add_parser('build')
    build.add_argument('--out', required=True)
    commands.add_parser('show')
    for name in ('exclude', 'include'):
        command = commands.add_parser(name)
        command.add_argument('name')
        command.add_argument('--kind', choices=KINDS)
    replace = commands.add_parser('replace')
    replace.add_argument('rule')
    replace.add_argument('--as', dest='own')
    add = commands.add_parser('add')
    add.add_argument('subject')
    commands.add_parser('lessons')
    return parser.parse_args(argv)


def main(argv=None):
    """Runs one command; returns the exit code."""
    args = parse_args(argv)
    root = os.path.abspath(args.sub_root or args.root or ROOT)
    if not os.path.isdir(os.path.join(root, 'rules')):
        print(f'error: no rules/ folder in {root}', file=sys.stderr)
        return 2
    ws = Workspace(root)
    try:
        if args.command == 'build':
            ws.build(args.out)
            for text in ws.warnings:
                print(f'warning: {text}', file=sys.stderr)
            return 0
        if args.command == 'show':
            print(ws.show(), end='')
            return 0
        if args.command == 'lessons':
            print(cmd_lessons(ws), end='')
            return 0
        if args.command == 'exclude':
            print(cmd_exclude(ws, args.name, args.kind))
        elif args.command == 'include':
            print(cmd_include(ws, args.name, args.kind))
        elif args.command == 'replace':
            print(cmd_replace(ws, args.rule, args.own))
        else:
            print(cmd_add(ws, args.subject))
        return 0
    except Refused as error:
        print(f'refused: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
