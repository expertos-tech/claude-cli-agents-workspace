# Hooks

English · [Português (Brasil)](../i18n/pt-BR/docs/hooks.md) · [Español](../i18n/es/docs/hooks.md)

## Hooks that run on your machine

The workspace runs these hooks in every session opened in a workspace (`workspace/rules/agents/settings.json`). They
are scripts in `workspace/scripts/`; each prints its full reference with `--help`. Anything they do not cover follows
the Claude Code permission mode you chose.

| Hook | When | What it does |
| --- | --- | --- |
| `guard-bash.sh` | Before every Bash command | Denies git writes in `projects/` and in the core outside the gate, Terraform changes outside `aiwp-cmds.sh apply`, `git push --no-verify`, a commit in `custom/` that carries a `.env` or a secret, `chmod`, `chown` or `git init` on core paths, and `aiwp update`, `rollback`, `repair`, `forget` and the opening inside a session (they change the rules of the open session or start `claude` inside it). Asks before deleting a database or a Docker volume, before a release, an apply or a discarded clone, and before git configuration that can run a command. It is a speed bump with your confirmation behind it, not a sandbox |
| `guard-subagent-model.sh` | Before every subagent call | Denies forks and models outside the allowed list, asks before a Fable subagent, and sets a model on a call that would inherit one |
| `setup-claude.sh` | Session start | Builds the git-ignored `.claude/` from the product rules, skills and agents plus your custom layer |
| `release-notice.sh` | Session start | Runs `aiwp check` (one answer per day, a short timeout, silent offline) and, when a newer release exists, has Claude tell you to close the session and run `aiwp update` in a terminal. It never updates anything |
| `prompt-log.py` | Session start | Records your prompts from the session transcripts in `custom/prompts/log/`, by project and week, and shows a summary of the last day. It never pushes |
| `session-title.py` | Each prompt you send | Names the session after the project on `/prompt` (`my-app-1`, `my-app-2`...), and reminds the session when a project you name is not normalized or is behind the workspace version |
| `aiwp-cmds.sh _stop-check` | When Claude ends an answer | Keeps the answer from ending with a commit that is only on your machine in a work clone |

Secret scans use gitleaks in Docker. No hook sends data anywhere: the only network calls are git's own, to your
remotes and to this repository's tags.
