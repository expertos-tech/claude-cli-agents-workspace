---
name: single-agent
description: "Single-agent mode: rewrite and load this target's SINGLE-AGENT.md, set the session options (--commit, --merge, --review), update another target, rename the session or show the help. Use only when the user asks."
argument-hint: "[<path>] [--commit] [--merge] [--review] | update <path> | --rename <task> | --help"
disable-model-invocation: true
effort: low
---

Arguments: `$ARGUMENTS`. This command exists only in a session opened by `single-claude` (`scripts/single-claude.sh`), whose first instructions name the `Workspace:` and `Target:` folders and the `Tool:` script; below, `<tool>` is that exact path (the copy `single-claude` ran, which before a merge may be a worktree), NEVER a path built from `Workspace:`. It may show as `/single-agent:single-agent`, the plugin's namespace: the same command. It authorizes only what the matching step says. Reply in the language the human writes in.

1. `--help` (alone or with anything else): reply with this help and stop, changing nothing:

   ```text
   /single-agent [<path>] [--commit] [--merge] [--review]
       rewrites the target's SINGLE-AGENT.md (default: the session folder), loads it and turns the options on in the session
   /single-agent update <path>    reapplies the template and the .gitignore on that target and lists what changed
   /single-agent --rename <task>  renames the session to single-agent-<task>
   /single-agent --help           this help

   Options (this session only; none pushes):
     --commit  commit on its own at each step with the tests passing
     --merge   one own branch per request and its merge back at the end; includes --commit; asks before going back into main
     --review  before each commit, a review by a new subagent, without the session's context; a BLOCKER goes to the human
   No option: commit, branch, merge and push only when the human asks, one operation per request.
   Target: a repository of projects/, a tool of tools/ or a POC of custom/pocs/; the workspace root is refused.
   ```

2. `--rename <task>`: run `bash <tool> rename --task "<task>"` alone in its call, with `run_in_background: true`; its end fires the hook that applies the name. Exit 2: say why in one line, the name stays. Otherwise one line: the name shows within seconds, at the latest on the next prompt.
3. `update` with no path: refuse with the usage `/single-agent update <path>` and stop. With a path: `bash <tool> update <path>`; reply with its `changed:` lists (or `unchanged:`). It does not load that file in this session, unless the path is this session's target: then go on with step 5.
4. Otherwise, the options first: `bash <tool> options <each option given>`. Exit 2 (unknown option): reply with its message, the valid list, and stop. Then `bash <tool> prepare [<path>]`, with the path given or none (the session folder). Exit 3: reply with the reason and stop.
5. Read the `SINGLE-AGENT.md` it wrote, in full, and follow it for the rest of the session, over the earlier copy. Options given in step 4 replace the session's options from now on; none given: the session keeps the ones it has (from `single-claude` or an earlier call).
6. Reply in up to three lines: the target, `SINGLE-AGENT.md` recreated and loaded, `.gitignore` changed or not (no commit), and the active options.
7. No history entry for this command.
