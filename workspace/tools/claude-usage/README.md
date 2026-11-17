# claude-usage

- [What it is](#what-it-is)
- [How to run](#how-to-run)
- [What it reads and what it prints](#what-it-reads-and-what-it-prints)
- [How to test](#how-to-test)
- [Acceptance criteria](#acceptance-criteria)

## What it is

A single-file script, using only the Python standard library, that reads the local Claude Code session transcripts and shows how much each model was used. It counts only the sessions of this machine. The model of each response comes from the API response itself, the same data the plan limits are counted against. It helps, for example, to see when the default model changed.

## How to run

There is nothing to install. Run it from the workspace root, with Python 3.9 or newer:

```bash
# Responses and tokens per day and per model
python3 -I tools/claude-usage/claude_usage.py daily --since 2026-11-16T04:59

# One line per session, from the one that generated the most tokens to the one that generated the fewest
python3 -I tools/claude-usage/claude_usage.py sessions --since 2026-11-16 --sort tokens

# Model of the first response of each new session, per day
python3 -I tools/claude-usage/claude_usage.py default-model
```

| Option | Commands | Default |
| --- | --- | --- |
| `--since` | all three | `daily` and `sessions`: 7 days ago; `default-model`: 35 days ago |
| `--sort start\|tokens` | `sessions` | `start` (start order) |
| `--projects-dir` | all three | `~/.claude/projects` |

- `--since` takes a date (`2026-11-16`) or a date and time (`2026-11-16T04:59`), in the machine's time zone, or with `Z` or an offset. An invalid value, or a `--projects-dir` folder that does not exist, ends with exit code 2.
- The reports use the machine's time zone.
- `sessions` lists only the sessions that had a model response, and shows the model of the main conversation and the one of the subagents.
- `-I` runs Python isolated: it ignores the `PYTHON*` variables, the user `site` and the current folder, so that a stray module is not imported in place of a standard library one.

## What it reads and what it prints

It reads the `*.jsonl` files under `--projects-dir` modified since `--since`. Corrupt lines, JSON that is not an object and files that disappear during the read are skipped. Each API response is counted once, even when it appears repeated.

It prints only counts and labels: tokens, number of prompts, the first 8 characters of the session id, the project folder name, the entry point name (`entrypoint`) and the model names. It never prints the content of the messages; the prompt text is read only to know whether it exists. Everything is local: the script does not use the network.

The project folder name encodes the absolute path of the working folder, so the person's login may appear in the printed part (the `sessions` report shows the last 32 characters). Do not paste reports without looking at them first.

## How to test

```bash
cd tools/claude-usage && python3 -I -B -m unittest discover -s tests
bash scripts/validate.sh --path tools/claude-usage
```

The tests use fictitious transcripts in a temporary folder, with `HOME` pointed at it, and do not read the real `~/.claude`. The tests are optional: a tool only has to build, and `validate.sh` does not measure coverage in this folder. The suite has 62 tests, with 100% line and branch coverage.

## Acceptance criteria

The ids appear in the test names in `tests/test_claude_usage.py`.

| Id | Criterion |
| --- | --- |
| AC-1 | `daily`: responses and the four token types summed per day and model, plus each model's share of the output total |
| AC-2 | `sessions`: start, folder, entry points, prompts, output and models of the main conversation and of the subagents; `--sort start` or `tokens`; a session with only prompts is left out |
| AC-3 | `default-model`: only the first response of the main conversation of each transcript counts, on the day it happened |
| AC-4 | What a response is: counted once per pair of message id and request id, across all transcripts; a synthetic one, one without a model or without usage does not count |
| AC-5 | `--since`: a date starts at midnight of the zone; a date and time is local, unless it has an offset; default of 7 days (`daily`, `sessions`) and 35 (`default-model`); an invalid value exits with code 2 |
| AC-6 | Bad data is skipped and never breaks the run: lines that are not JSON, JSON that is not an object, fields of the wrong type, bytes outside UTF-8, files that disappear, a lone surrogate in the output |
| AC-7 | `--projects-dir`: valid in all three commands, accepts `~`, a folder that does not exist or is not a folder exits with code 2, glob characters stand only for themselves; default `~/.claude/projects` |
| AC-8 | Fixed output format, checked against golden reports of the same tree; with no data in the period, the headers remain; the command is mandatory |
