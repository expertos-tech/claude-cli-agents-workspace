# Functional request: install.sh --developer

**Project:** claude-cli-agents-workspace

**State:** done in a session. Size: adjustment. Created 2026-11-20 from the owner's words.

## Requested

The owner asked to adjust the installer so that it downloads from the branch `developer` when it receives
`--developer` as a parameter.

## Execution — 2026-11-20, merged into developer

- **Done:** `install.sh` reads its arguments in order (04f8dfe): `--developer` and one workspace folder, in either
  order, also under `curl ... | bash -s -- --developer <folder>`; `--help` prints as soon as it comes; any other option
  and a second folder exit 2. `--developer` checks out `origin/developer` instead of the newest release tag, wins over
  `AIWP_REF`, refuses a remote with no branch `developer` (exit 1, nothing linked), and prints a `note:` line that the
  installation is not a release and how it updates. `--help` gains the option and an example that takes the
  installer from `developer`. Three scenarios in `workspace/scripts/tests/aiwp/test-aiwp.sh`, which fail with the old
  installer. `docs/getting-started.md` gains a note for testers (945e793). The two changelogs (07dfa19).
- **Decisions:** the update behavior was read in `workspace/scripts/aiwp.sh` and proven by a scenario before it was
  written: `aiwp update` never follows `developer`, it moves the installation only to a release tag newer than its
  `workspace/VERSION`; a new run of the installer with `--developer` follows `developer`, without it goes back to the
  newest release. A repeated `--developer` is accepted. The note line comes only with `--developer`, not with
  `AIWP_REF=developer`.
- **Deviations:** `install.sh <folder> --help` used to be a usage error; it now prints the help.
- **Done when:** `bash install.sh <folder> --developer` installs the commit of `developer`: proven by the scenarios and
  by a run on the snapshot repository of the test installation, with a `developer` branch added (rc 0, the checkout
  equal to that branch, the workspace created).
- **Checks:** the `aiwp` suite (46 run, 0 failed, 44 s under its 60 s budget); `bash -n install.sh`; shellcheck of
  `install.sh` and the test file through `validate.sh`; `bash tests/test-install.sh` from the clone: every check PASS;
  `bash tests/check.sh --base origin/developer --i18n-pending` passed (repo-terms skipped: no terms list).
- **Warnings:** none.
- **Left:** the `pt-BR` and `es` translations of `docs/getting-started.md`, pending until the release.
