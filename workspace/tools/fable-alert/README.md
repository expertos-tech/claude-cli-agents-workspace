# fable-alert

Visual alert for Claude Code: while Fable is active, the terminal background turns dark red and a "FABLE ACTIVE" band appears above the prompt. It also ships the status line that shows the model, the settings snippet and `ptyrun.py`, which records what Claude Code draws when it opens.

- [What it is](#what-it-is)
- [How it works](#how-it-works)
- [Layout](#layout)
- [How to install](#how-to-install)
- [How to run](#how-to-run)
- [How to test](#how-to-test)
- [Acceptance criteria](#acceptance-criteria)
- [Customization](#customization)
- [Uninstall](#uninstall)
- [Limitations](#limitations)
- [Design notes](#design-notes)

## What it is

A Claude Code mod (folder `plugin/`) plus three supporting pieces. The mod exists because `/model` saves the chosen model as the default of every new session. After one `/model fable`, every following session can open on Fable with no warning on screen, and its weekly quota runs out in a few days.

There is no marketplace install.

## How it works

Code in `plugin/hooks/register.tsx`.

1. Two seconds after the session opens (`FIRST_CHECK_MS`), the mod starts asking for the active model every second.
2. If the model name contains `fable` (any case), it writes the OSC 11 sequence to the terminal, which switches the background to `#420c0c`, and only then sets the `isFable` atom, which draws the band. The band changes the layout and forces the prompt to redraw over anything the write may have disturbed.
3. When the model is no longer Fable, it writes OSC 111, which restores the terminal's own background, and hides the band. Outside Fable, the mod only writes to undo a tint that is still recorded.
4. The `isFable` atom, held by the host, is the only record of "background painted": the band and the tint both come from it and never drift apart, and it survives a reload of the mod.
5. When the session exits with Fable active, it restores the background before closing. On `/clear` or `/resume` the process keeps running, with another session id and no new `session.start`: the mod restores the background, keeps watching and paints again on the next tick if the model is still Fable. If the session ends while the tint is being written, the mod undoes the write, as long as the process is still alive when it finishes.
6. The band does not appear while a survey takes the space above the prompt.

The command that writes the tint runs in a child process with no terminal of its own. So the script walks up to 8 ancestors, finds the first one with a terminal (`ps -o tty=`) and writes the sequence straight to `/dev/<tty>`.

The status line (`statusline/statusline.sh`) shows the model and the session folder, with `~` in place of the home folder. A model whose name or id contains `Fable` or `fable` appears in white on red; the others in cyan. It needs `bash` and `jq`.

## Layout

| Path | What it is |
| --- | --- |
| `plugin/` | The mod: `.claude-plugin/plugin.json`, `hooks/register.tsx`, `types/index.d.ts` and `tests/fable-alert.test.tsx` |
| `statusline/statusline.sh` | Status line with the active model |
| `settings-snippet.json` | Snippets of `~/.claude/settings.json`: `statusLine` and `env.CLAUDE_CODE_PLUGIN_DIRS` |
| `tools/ptyrun.py` | Opens Claude Code in a fake terminal, records what it draws and reports the background color writes |
| `tests/` | Python tests of `ptyrun.py`, of the terminal script and of the status line |
| `.coveragerc` | Target of the `coverage` check of `scripts/validate.sh` |

## How to install

Requires Claude Code 2.1.309 or newer, the minimum for mods; the tests here ran on 2.1.314.

Run from the workspace root. What runs is the installed copy: changing the tool has no effect until you copy it again. Installed from a folder, the mod joins a session when it opens and, after that, the session reloads it by itself when a file of the installed copy changes.

```bash
mkdir -p ~/.claude/mods/fable-alert && cp -R tools/fable-alert/plugin/. ~/.claude/mods/fable-alert/
```

Status line (needs `jq`):

```bash
cp tools/fable-alert/statusline/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Settings. The command makes a backup and merges the snippet into the current settings, without deleting what exists; if `env.CLAUDE_CODE_PLUGIN_DIRS` already has a value, the snippet's one replaces it.

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json.bak tools/fable-alert/settings-snippet.json > ~/.claude/settings.json
```

The mod joins the sessions opened after this setup.

## How to run

There is nothing to run: once installed, the mod acts in every new session. To see what Claude Code draws when it opens, use `ptyrun.py` in a folder outside the workspace (see the warning in [How to test](#how-to-test)):

```bash
python3 -I <workspace-root>/tools/fable-alert/tools/ptyrun.py open-default.bin 6
python3 -I <workspace-root>/tools/fable-alert/tools/ptyrun.py open-fable.bin 7 --model fable
```

The first argument is the output file; the second, the recording seconds; the rest goes to `claude`. The fake terminal is 120 x 40, and the session ends with `SIGTERM`. The report lists each background color write (`set (OSC 11)` or `reset (OSC 111)`) and marks `SPLITS A CHARACTER` if one of them cut a UTF-8 character in half, which is what breaks a line. Opening Claude without sending a message makes no request to the model.

## How to test

Automated tests, from the workspace root. `claude plugin validate` and `claude plugin test` write `tsconfig.json` and `.claude-plugin/types/` inside the plugin folder, which is read-only in an installed workspace, so they run on a copy in `tmp/`:

```bash
rm -rf tmp/fable-alert-plugin && cp -R tools/fable-alert/plugin tmp/fable-alert-plugin && chmod -R u+w tmp/fable-alert-plugin
claude plugin validate tmp/fable-alert-plugin
claude plugin test tmp/fable-alert-plugin
(cd tools/fable-alert && python3 -I -B -m unittest discover -s tests)
bash scripts/validate.sh --path tools/fable-alert
```

- `claude plugin test` runs the 37 tests of `plugin/tests/fable-alert.test.tsx`.
- The Python tests cover `ptyrun.py` (with a fake `claude`), the script that walks up the process tree (with a fake `ps`) and the status line. The 6 status line tests (AC-11) need `bash` and `jq`: in the container of the `coverage` check they are skipped, and they run on the host.
- The tests are optional: a tool only has to build, and `scripts/validate.sh` does not measure coverage in this folder.

**Coverage of the mod.** `claude plugin test` has no coverage option, so the 85% of `rules/quality.md` is not measured for the mod. Instead, the header of `plugin/tests/fable-alert.test.tsx` maps each branch of `register.tsx` to a test, and a mutation check caught 22 of 22 branch flips and 13 of 13 extra mutants, with no surviving guard. This is an accepted gap, since it is a local tool. `ptyrun.py` has 98.9% line and 95.4% branch coverage.

**Coverage of the status line.** The `coverage` check does not measure bash, and the 6 AC-11 tests are skipped in its container. A regression in the status line does not fail `validate.sh`: run the command on the host (`python3 -I -B -m unittest discover -s tests`). Also an accepted gap.

**Check on the real engine** (Claude Code 2.1.314, opening with no prompt): a temporary copy of the mod, with the regular expression changed to react to Opus, with no Fable involved, gave exactly 1 OSC 11 write in about 8 seconds of observation, 1 OSC 111 on exit, no split character and the band present. Limits: a model switch in the middle of a session and `/resume` are proven by the tests only, not on the real engine.

**Visual test**, outside the workspace:

1. Open `claude` in a folder outside the workspace. Inside it, `rules/agents/settings.json` sets `availableModels` without Fable.
2. Without sending a message, run `/model fable`: the background turns dark red and the band appears within one second.
3. Switch back to the model that was your default before, which is not necessarily Opus, with `/model <model>`. `/model` saves the choice as the default of new sessions: forgetting this step leaves every new session on Fable.

## Acceptance criteria

The ids appear in the test names.

| Id | Criterion |
| --- | --- |
| AC-1 | A model with `fable` in its name, in any case: the tint is written once and the band appears |
| AC-2 | Another model: nothing is written and the band does not appear |
| AC-3 | Switching between Fable and another model changes the tint and the band within one second, including a band already drawn |
| AC-4 | Leaving the session stops the watch; on Fable it restores the tint, on another model it writes nothing; a tick in flight does nothing |
| AC-5 | `/clear` restores the tint, keeps watching and paints again if the model is still Fable |
| AC-6 | Nothing is read or written before `FIRST_CHECK_MS` |
| AC-7 | A failure to read the model, write the tint or restore it (on exit or on `/clear`) does not break the session; the next tick tries again, except the reset that failed |
| AC-8 | A survey hides the band, even on Fable |
| AC-9 | Races: overlapping ticks do not write twice; the session ending while the model is read, the tint is written or the reset is written does not leave the wrong tint; a failing undo is contained |
| AC-10 | Terminal script: walks up to 8 ancestors, skips `??` and an empty terminal, stops at pid 1 or with no parent, tries the next one if the write fails; exits with 0 when it writes and 1 with no terminal |
| AC-11 | Status line: Fable highlight (`Fable` or `fable` in the name or the id), cyan for the others, `~` in place of the home folder, missing fields with a fallback value, invalid JSON exits with an error and no output |
| AC-12 | `ptyrun.py` records what `claude` draws, passes the arguments on, ends with `SIGTERM`, answers the terminal queries and reports each background color write |
| AC-13 | `splits_utf8` points at the write that falls in the middle of a UTF-8 character |
| AC-14 | `ptyrun.py` with invalid arguments or environment (time, `claude` not in `PATH`, output folder missing or without permission) exits with a message, no traceback and no hang |
| AC-15 | `/resume` keeps the watch, like `/clear` |
| AC-16 | The atom is the only record of a painted tint: band and tint do not drift apart after `/clear`, session end, an undo in the middle of the write, a tick and the end at the same time or state left by a reload; on Fable, the host clearing the state only makes the mod paint again |
| AC-17 | A write whose process exits with a non-zero code (no terminal): the band appears and the write is not repeated every second |
| AC-18 | A failure to read the state at session end counts as a painted tint: the mod tries to restore the tint, and the exit goes on |

## Customization

At the top of `plugin/hooks/register.tsx`: `TINT` (background color) and `FIRST_CHECK_MS` (wait before the first check). The band text is at the end of the file. The tests have these values written by hand: when you change `TINT` or `FIRST_CHECK_MS`, also change `SET_TINT` and `FIRST_CHECK_MS` in `plugin/tests/fable-alert.test.tsx`; when you change the "FABLE ACTIVE" title, change what the test looks for. Then run the tests and copy the mod again to `~/.claude/mods/fable-alert/`.

## Uninstall

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq 'del(.env.CLAUDE_CODE_PLUGIN_DIRS, .statusLine)' ~/.claude/settings.json.bak > ~/.claude/settings.json
rm -r ~/.claude/mods/fable-alert ~/.claude/statusline.sh
```

If a hang leaves the terminal with the red background:

```bash
printf '\033]111\007'
```

## Limitations

- The Claude Code mods API is in early access and may change between versions.
- The terminal must accept OSC 11 and OSC 111. Tested on Ghostty 1.3.1.
- With no terminal found in the 8 ancestors, the background does not change, the band appears anyway and the write is not repeated (AC-17).
- A tint reset that fails, on exit, on `/clear` or on `/resume`, is not repeated: the red background may stay until the recovery command above (AC-7).
- If the process closes right after a write in flight, the tint may stay until the same command. The window is short, and AC-9 only proves the case with the process alive. The session end does not wait for that write on purpose: a stuck call must not hold Claude's exit.
- If the host clears the state with the tint painted and the model is no longer Fable, the mod does not know it painted, and the tint stays until the same command.
- The terminal script uses `ps -o tty=`, available on macOS and other Unix systems.
- The status line is outside the automatic coverage of `validate.sh` (see [How to test](#how-to-test)).
- The `.bin` files of `ptyrun.py` hold everything drawn on the screen. This folder's `.gitignore` ignores them; do not share them.

## Design notes

- **No write at session open.** Writing to the terminal while the session draws its first screen can land in the middle of a prompt line and cut a character in half. So outside Fable the mod only writes to undo a tint that is still recorded, waits for the initial drawing to finish and redraws the prompt after each write. `ptyrun.py` confirms this on openings with Opus and with Fable.
- **The timer stops at session end**, except on `/clear` or `/resume`, and a write in flight at the end is undone, so leaving with Fable active does not leave the terminal red.
- **`/resume` keeps the alert alive**: the session end does not stop the timers on `/clear` or `/resume`, since no new session restarts them.
- **One record for band and tint.** The tint state lives only in the host's atom, never in a variable of the mod, so the band and the tint cannot diverge.
