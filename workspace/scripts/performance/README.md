# performance

Measures how the workspace behaves in real sessions: how much of Claude's work goes to the workspace process, how much to validation and the gate, how many questions reach you, how much context each session loads and how long it takes to the first edit.

## How to run

It needs the observability stack up. Without it the script refuses, with the command that starts it:

```bash
docker compose -f tools/observability/compose.yaml up -d
python3 -I -B scripts/performance/measure.py --name after-the-gate
```

- Writes `custom/performance/<yyyy-mm-dd>-<name>.md` (default name: `measurement`). Without `custom/`, pass `--out <folder>`.
- The period starts where the previous measurement ended. `--since <date>` picks another start; `--all` measures everything the transcripts still keep.
- The report compares with the previous measurement and lays out the last five side by side (`--compare <n>` changes the number).
- **Per project:** lines delivered per hour of agent work, in code and in documentation, with the total of the period and the previous rate of each project. The hours come from the turns of the sessions, each request counted for the project its tools touched most (`projects/<project>`, a clone in `tmp/work/`); the lines come from the agent commits (`[#automatic-agent-commit]`) of the repositories in `projects/`, without generated files (lock, build, images, fonts). With less than half an hour on a project, the rate is left blank. Without `git` on the machine, the section says so and the rest of the report comes out the same.
- The numbers of each report go inside it, in a `performance-data` comment, and the next measurement compares from there.

## What it reads

- The transcripts of the sessions opened at the workspace root (`~/.claude/projects/<root>/*.jsonl`), main session only; subagents are left out.
- Only aggregates leave the script: no prompt text, no file content.
- The transcript format is internal to Claude Code and may change between versions. Transcripts are deleted after `cleanupPeriodDays` (30 days by default): measure before that.
- The classification of each tool call is heuristic (`classify` and `SCRIPT_CATEGORY` in `measure.py`). When a workspace script changes name or role, update it there.

## How to test

```bash
cd scripts && python3 -I -B -m unittest discover -s tests -p 'test_performance.py'
```
