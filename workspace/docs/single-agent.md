# Single-agent mode

Guide to working focused on one target, just you and one agent, without the workspace's instructions, hooks and skills.

- [Installing](#installing)
- [Opening a session](#opening-a-session)
- [The /single-agent command](#the-single-agent-command)
- [What still applies](#what-still-applies)
- [History](#history)
- [Taking the work to main](#taking-the-work-to-main)

## Installing

Once, in your terminal:

```bash
ln -sf "<workspace>/scripts/single-claude.sh" ~/.local/bin/single-claude
```

The link points to the workspace's own copy of the script, so an update of the workspace also updates the command.

## Opening a session

```bash
single-claude [<path>] [--commit] [--merge] [--review] [-- <claude arguments>]
```

- Target: a repository of `projects/` (at any depth), a tool of yours in `custom/tools/` (the path `tools/<name>` means the same) or a POC of `custom/pocs/`. With no path, the current folder. The workspace root, a folder of the product's `tools/` (read only), a subfolder of an item and an item the custom layer ignores are refused, with the reason.
- The command prepares the target (rewrites `SINGLE-AGENT.md` and makes sure `/SINGLE-AGENT.md` is in the target's `.gitignore`, with no commit), reserves the name `single-agent-default-<n>` and opens `claude` in the target folder.
- The session loads no `CLAUDE.md`, `AGENTS.md`, settings, hooks, skills or agents of the workspace (`--setting-sources user`); your `~/.claude` still applies. Its instructions are `SINGLE-AGENT.md`.
- In this mode the workspace's `guard-bash` hook is not loaded: nothing asks for confirmation before a commit, merge, push or destructive command. The command refuses to run inside a Claude Code session (`CLAUDECODE=1`); that is only a speed bump, which `env -u CLAUDECODE` gets around.
- Everything after `--` goes straight to `claude`, for example `-- --model sonnet`.

Options, for this session only; none pushes:

| Option | Effect |
| --- | --- |
| none | commit, branch, merge and push only when you ask, one operation per request; a failing test shows before the commit, without stopping it |
| `--commit` | a commit on its own at each step with the tests passing |
| `--merge` | a branch of its own per request and the merge back at the end; includes `--commit`; asks before going back into `main` |
| `--review` | before each commit, a review by a new subagent, without the session's context; a BLOCKER comes to you to decide |

In a POC or a tool, the commits land in a repository other sessions share (the custom layer's, or the workspace's): the session adds only the target's paths and never switches branches there.

## The /single-agent command

It exists only in the session opened by `single-claude`. Type `/single-agent`: Claude Code completes it to `/single-agent:single-agent`, the name with the plugin in front, and runs the same command.

| Use | Effect |
| --- | --- |
| `/single-agent [<path>] [options]` | rewrites and loads `SINGLE-AGENT.md`; the options given replace the session's |
| `/single-agent update <path>` | applies the template and the `.gitignore` again to that target and lists what changed; with no path, it refuses |
| `/single-agent --rename <task>` | renames the session to `single-agent-<task>` |
| `/single-agent --help` | shows the usage and the options |

`SINGLE-AGENT.md` comes from `rules/single-agent/single-agent-template.md`; editing the file in the target does not help, because every run rewrites it.

## What still applies

With no option to turn it off: data security, confirmation before a destructive action, the temperature reading before a heavy task and only the cloud and tenant of the custom layer (`custom/my-rules/company.md`). The single session completely ignores messages from `ai-workspace-*` sessions (no reply, no action, no mention to you), and the workspace's sessions send it no message and never read `SINGLE-AGENT.md`.

## History

The single session records each request in `single-agent-history.txt`, at the root of the target, in the `history.txt` format, and that file is committed with the target. To bring the entries into the workspace history, ask a workspace session; it runs:

```bash
bash scripts/single-agent.sh import-history --target <target path>
```

The new entries go into the `history.txt` of the same target, with the `REQUEST` starting with `[single-agent <date>]`. A second import brings only what is new.

## Taking the work to main

The single-agent mode never merges into `main` on its own. Open a normal session at the workspace root and ask for a clean-context review of what is on `developer` and not on `main` (a repository with no `developer`: name the branch). With zero BLOCKER and the checks passing, `main` moves only by the release, `bash scripts/aiwp-cmds.sh release <repo>`, at your request (`rules/git.md` "Gate").
