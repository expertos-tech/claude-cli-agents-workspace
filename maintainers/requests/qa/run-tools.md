# Functional request: `/run-tools` and the single compose file of the tools

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`. Prerequisite:
the 0.1.0 publication (installer, `aiwp`, read-only core). Full design: `maintainers/plans/run-tools.md`.

## 1. Objective

Start the workspace's local tools by choice, without memorizing commands: one compose file that joins the container
tools in a single group in the container console, and a skill that shows checkboxes with the tools available on this
machine and starts the ticked ones.

## 3. Business rules

- RN-1: `workspace/tools/compose.yaml` includes (`include:`) the compose file of each container tool (`observability`,
  `login-simulator`, `safe-browsing-simulator`, `azurite-console`), in the `claude-cli-agents-tools` project. Each
  tool's compose file still starts on its own.
- RN-2: title, description and URL of each tool live in an `x-run-tools` extension of the service, in the tool's
  compose file. A new tool shows in the list just by joining the `include`.
- RN-3: configuration paths and the tools' env files come from `custom/` (`custom/config/<tool>/`,
  `custom/env/<tool>.env`), through variables with defaults. Without its configuration, a tool shows what is missing
  and does not start.
- RN-4: of the container consoles, only the machine's one shows: `container-console-docker-ce` on Linux and WSL with
  Docker Engine; `container-console-colima` on macOS with `colima`. The consoles are machine services and stay out of
  the compose group; the skill installs or starts the service.
- RN-5: `workspace/scripts/run-tools.sh` does the work: `list --json`, `up <id>...`, `down <id>...`, `status`. The
  skill only talks and calls the script.
- RN-6: before each build, the current images get the `rollback-latest` tag, as in every publish to the local Docker.
- RN-7: ticking starts a tool; unticking a tool that is up stops nothing. Stopping is an explicit request
  (`/run-tools --down`).
- RN-8: the checkboxes use `AskUserQuestion` with `multiSelect` (at most 4 options per question): one question for
  observability and consoles, another for simulators.
- RN-9: nothing writes in the installed read-only core: builds go to the outputs each tool's git ignores.
- RN-10: containers running in separate compose projects are recreated in the new project; where there is a named
  volume, the data is copied first, and deleting the old volume asks for confirmation.

## 4. Acceptance criteria

- AC-1: Given the single compose file, when `docker compose -f tools/compose.yaml up -d` runs, then every container
  tool comes up healthy and the console shows one group, `claude-cli-agents-tools`.
- AC-2: Given Linux with Docker Engine, when `run-tools.sh list --json` runs, then `container-console-docker-ce` shows
  and the Colima one does not (and the reverse on macOS with Colima; tested with simulated detection).
- AC-3: Given `login-simulator` without configuration in `custom/`, when the list shows, then it is marked
  "configuration missing" and its `up` refuses with the message of what is missing.
- AC-4: Given `/run-tools` with two tools ticked, when it ends, then both are up, the previous images carry the
  `rollback-latest` tag, and the answer is a table with tool, URL and state.
- AC-5: Given a tool that is up and not ticked, when `/run-tools` runs, then it stays up.
- AC-6: The `run-tools.sh` suite covers detection (Docker CE, Colima, none), missing configuration, busy port, rollback
  tag and `down` without deleting volumes.

## 7. Out of scope

- `tools-hub` (its own request).
- Changing tool code beyond `x-run-tools` and the configuration paths.
- Putting the consoles in containers.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Single compose file, `x-run-tools`, configuration from `custom/`, migration of running containers | high | Recreates containers and may touch data volumes |
| 2. `run-tools.sh` with its suite | medium | Clear scope, testable without a real Docker |
| 3. `/run-tools` skill, README and guide | medium | A conversation over a script already tested |

The agents of each stage run with the stage's effort, passed in the call.

## Execution — 2026-11-17, merged into developer (this merge)

- **Done:** stage 1, `tools/compose.yaml` including the four container tools in `claude-cli-agents-tools`, the
  `x-run-tools` blocks, the simulators' configuration from `custom/config/<tool>/`, Azurite's key check in the
  container, and the move of running tools into the group; stage 2, `scripts/run-tools.sh` and `run-tools.py` with the
  scenario suite and the unit tests (a7878b7); stage 3, the `/run-tools` skill, the product README, the usage guide
  and the features page (6afdfa4); the findings of the independent review (17bcacd, dc8a8c2).
- **Decisions taken while running:** each tool's network gets its own key (Compose refuses a `default` network in
  more than one included file), with its fixed name kept, so other stacks still attach; Azurite's key check moved from
  a required Compose variable into the container's entrypoint, because the group loads every tool's file and a
  missing key would have stopped all of them; the simulators mount their file with a bind that never creates a
  missing path; the logic lives in `run-tools.py`, called by `run-tools.sh`, like `guard-bash`; the console's state
  comes from `systemctl --user is-active` and `launchctl print`, not from its port; a move into the group is refused
  before any change when another stack uses one of the tool's fixed networks (Compose refuses a network another
  project created), when that network belongs to a third project, or when both the old and the group's volume exist;
  a copy that fails removes the new volume and starts the old containers again; the volume is copied with the image
  of the service that mounts it (a distroless image has no `cp`); an old volume left next to the group's is named by
  `up` and in `list --json` (`old_volumes`); `down` only stops (`docker compose stop`); `measure.py` points to
  `run-tools.sh up observability`.
- **Deviations:** none from the business rules.
- **Acceptance criteria:**
  - AC-1: proven by a real run on a copy with every name, port, network and image prefixed: the four tools in their
    old projects, moved by `run-tools.sh up`, then `docker compose -f tools/compose.yaml up -d`: five containers
    healthy in one project, no old project left. No suite runs Docker.
  - AC-2: proven (test-run-tools: docker-ce by `docker version` and by the package, Colima on macOS, none).
  - AC-3: proven (test-run-tools with a fictitious tool; the real run: a missing `custom/config` file listed and `up`
    refused).
  - AC-4: proven at script level (rollback tags before the build, the final table of the tools named); the skill's
    reply is skill text, pending a real session.
  - AC-5: proven (only the named services reach `docker compose up`; nothing else is stopped).
  - AC-6: proven (test-run-tools and test_run_tools.py: detection, missing configuration, busy port, rollback tag,
    `down` without removing a container, volume or image).
  - RN-8 (the checkboxes) is skill text, pending a real session.
- **Checks:** `tests/check.sh --base origin/developer --i18n-pending`; test-run-tools (117 checks), test_run_tools.py
  (62 tests, `run-tools.py` above 99 % of lines and branches), test-check-workspace, test_performance; the real Docker
  run on the prefixed copy (move with volume copy, both refusals, AC-1, `down`, AC-3), every test resource removed;
  `docker compose config` of the group and of each tool alone; one independent review (effort high): APPROVED_WITH_CHANGES,
  4 RECOMMENDED, fixed.
- **Left:** RN-8 and the skill's reply of AC-4 in a real session; the first `/run-tools` of an installed workspace
  moves its running tools (a stack attached to `login-simulator` must stop first); the observability smoke test fails
  its "dashboard behavior" check since 0.1.0 (`python3 -I` cannot import the sibling module), unrelated to this
  request; translations pending for the release.
