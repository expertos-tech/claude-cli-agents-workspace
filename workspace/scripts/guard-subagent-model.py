"""Decision logic of scripts/guard-subagent-model.sh (PreToolUse hook, matcher Agent).

Reads the hook JSON on stdin (bytes, UTF-8), prints the decision JSON or nothing (allow silently).
Any failure prints the exception type name on stderr and exits 2, which blocks the call.
Usage: python3 -I guard-subagent-model.py <project-root>
"""

import json
import os
import re
import sys
import unicodedata

# One allowlist for the explicit model parameter and the agent frontmatter (compared after strip + lowercase).
ALLOWED_MODEL = re.compile(r'(opus|sonnet|haiku|claude-(opus|sonnet|haiku)-[a-z0-9._\[\]-]+)')
AGENT_TYPE = re.compile(r'[A-Za-z0-9._-]+')
ASK_FABLE = (
    "The subagent of type '{type}' asked for the Fable model, with effort {effort}. Confirm only if you explicitly "
    'asked for a subagent with Fable and that effort. If you did not, deny it.'
)
DENY_MODEL = 'Only opus, sonnet, haiku and claude-opus/sonnet/haiku-* ids are allowed for subagents (rules/models.md).'
DENY_TYPE = 'subagent_type has characters outside ASCII after normalization; use a registered agent name.'
DENY_FORK = (
    'A fork always inherits the main session model, which may be Fable, and ignores a model override. '
    'Use a registered agent instead.'
)


def normalize_type(subagent_type):
    """NFKC and lowercase, the normalization Claude Code applies before it compares the type with fork."""
    return unicodedata.normalize('NFKC', subagent_type).lower()


def is_fork(normalized_type):
    return re.sub(r'[\s_-]', '', normalized_type) == 'fork'


def is_allowed_model(value):
    return ALLOWED_MODEL.fullmatch(value.strip().lower()) is not None


def frontmatter_values(path):
    """Values of the model: and name: lines inside the frontmatter, as two lists (empty without frontmatter)."""
    with open(path, encoding='utf-8') as fh:
        lines = fh.read().splitlines()
    models, names = [], []
    if not lines or lines[0].strip() != '---':
        return models, names
    for line in lines[1:]:
        if line.strip() == '---':
            break
        for key, found in (('model', models), ('name', names)):
            match = re.match(key + r'\s*:\s*(.*)$', line)
            if match:
                found.append(match.group(1))
    return models, names


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
        return value[1:-1]
    return value


def has_fixed_model(root, subagent_type):
    """True only for a project agent file with exactly one model: (allowlisted) and a name: equal to the type."""
    if not subagent_type or not AGENT_TYPE.fullmatch(subagent_type):
        return False
    path = os.path.join(root, '.claude', 'agents', subagent_type + '.md')
    if not os.path.isfile(path):
        return False
    models, names = frontmatter_values(path)
    if len(models) != 1 or len(names) != 1:
        return False
    return unquote(names[0]) == subagent_type and is_allowed_model(unquote(models[0]))


def emit(decision, reason=None, updated=None):
    out = {'hookEventName': 'PreToolUse', 'permissionDecision': decision}
    if reason:
        out['permissionDecisionReason'] = reason
    if updated is not None:
        out['updatedInput'] = updated
    print(json.dumps({'hookSpecificOutput': out}))


def decide(data, root):
    tool_input = data['tool_input']
    if not isinstance(tool_input, dict):
        raise TypeError('tool_input is not an object')
    model = tool_input.get('model')
    subagent_type = tool_input.get('subagent_type')
    if model is not None and not isinstance(model, str):
        raise TypeError('model is not a string')
    if subagent_type is not None and not isinstance(subagent_type, str):
        raise TypeError('subagent_type is not a string')
    model = (model or '').strip()

    normalized = normalize_type(subagent_type) if subagent_type is not None else ''
    if is_fork(normalized):  # the person decided: forks are denied in every session, before any Fable check
        emit('deny', DENY_FORK)
    elif not normalized.isascii():
        emit('deny', DENY_TYPE)
    elif 'fable' in unicodedata.normalize('NFKC', model).lower():
        effort = tool_input.get('effort')
        effort = effort.strip()[:20] if isinstance(effort, str) and effort.strip() else 'not given'
        emit('ask', ASK_FABLE.format(type=(subagent_type or '(no type)')[:60], effort=effort))
    elif model:
        if not is_allowed_model(model):
            emit('deny', DENY_MODEL)
    elif not has_fixed_model(root, subagent_type):
        # "allow" is kept: the docs only show updatedInput combined with allow or ask.
        emit('allow', None, {**tool_input, 'model': 'opus'})


def main():
    try:
        decide(json.loads(sys.stdin.buffer.read().decode('utf-8')), sys.argv[1])
    except Exception as exc:  # noqa: BLE001 - every failure must block, whatever its type
        print(type(exc).__name__, file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
