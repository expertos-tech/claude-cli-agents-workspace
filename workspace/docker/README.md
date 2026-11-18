# docker/

Containerized support and validation toolbox. No host install besides Docker. Entry point: `scripts/validate.sh`.
Rules for adding or updating tools: `rules/rules.md` "Tooling".

## Tools (`compose.yaml`)

| Service | Tool | Check in validate.sh | Purpose |
| --- | --- | --- | --- |
| terraform | Terraform 1.17.1 | terraform | fmt, init without backend, validate |
| tflint | TFLint v0.65.0 | terraform | Terraform lint (`config/tflint.hcl` recommended preset; a module `.tflint.hcl` with provider rulesets takes precedence) |
| trivy | Trivy 0.76.1 | vuln, iac, secrets | dependency CVEs, IaC misconfig, secrets (with gitleaks, in `secrets`; also `trivy image`) |
| gitleaks | Gitleaks v8.30.1 | secrets | secrets in files, config `config/gitleaks.toml`; `gitleaks git` for history runs with the default rules only, never with that config (`rules/security.md` "Secrets") |
| shellcheck | ShellCheck v0.11.0 | shell | bash lint |
| hadolint | Hadolint v2.15.1 | dockerfile | Dockerfile lint |
| markdownlint | markdownlint-cli2 v0.24.0 | markdown | Markdown lint |
| mermaid | mermaid-cli 12.0.1 | mermaid | renders diagrams to prove they parse |
| infracost | Infracost 0.10.47 | cost | monthly cost from Terraform; needs `INFRACOST_API_KEY` in `custom/env/docker.env` |
| ruff | Ruff 0.17.3 | python | Python lint and format check, config `config/ruff.toml` |
| biome | Biome 2.6.4, static binary of the official image in a `scratch` image (built from `biome/`) | typescript | `biome ci` on `*.ts` and `*.tsx`, config `config/biome.json` |
| python-coverage | coverage.py 7.17.0 on `python:3.14.10-alpine` (built from `python-coverage/`) | coverage | runs the tests of each coverage target and applies the per-module gate of `rules/quality.md` |

- Images pinned by tag@digest. Trivy: never use 0.69.4–0.69.6 (GHSA-69fq-xp46-6x23).
- `ruff`, `biome` and `python-coverage` apply only to code the workspace owns: `validate.sh` ignores `projects/` for them, and `tools/` too for `python-coverage` (`rules/rules.md` "Workspace layout"), and prints `SKIP <check> (no targets)` when nothing is left.
- Ad-hoc run: `WORKSPACE_DIR="$PWD" docker compose -f docker/compose.yaml run --rm -T <service> <args>`; workspace is mounted at `/work`.
- Variables and secrets: the filled file lives in the custom layer, `custom/env/docker.env` (git-ignored there), created from `.env.example` with `/local-env docker` in a session or `bash scripts/sync-env.sh --path docker`. `scripts/validate.sh` passes it to compose with `--env-file`; without it, the defaults of `.env.example` apply (only `cost` needs a key). No `.env` is ever written in `docker/`.
- The workspace is mounted read-only in every container, which runs as root and would otherwise get past the read-only core of an installed workspace. Only `terraform` and `infracost` write, and only in the module folder `validate.sh` mounts writable on top, when it lies in `projects/`, `tmp/` or `custom/`.

## Coverage check (`python-coverage/`)

- Opt-in: every folder holding a `.coveragerc`, outside `projects/` and `tools/`, is one target; none found prints `SKIP coverage (no targets)` and exits 0, because nothing was measured.
- In each target the container runs `coverage run -m unittest discover -s tests`. A failing test fails the check, and so does any measured module below 85% lines or 85% branches. A module with no branches passes the branch part.
- Each step (tests, report) must finish within `COVERAGE_TIMEOUT_SECONDS`, whole seconds from the shell of `validate.sh`, default 600. A hung step is killed and fails the check, naming the deadline; an invalid value fails before anything runs.
- The container runs as non-root with the workspace mounted read-only and no network; data and report stay under `/tmp`. `validate.sh` rebuilds the image on change (the first build needs network).
- `run_coverage.py` is the container entry point and `check_coverage.py` the gate; their tests dogfood this check. The lock file `requirements.txt` is installed with `pip --require-hashes`; pip is removed from the image afterwards.
- The base is Alpine: musl libc, `/bin/sh` from BusyBox and no bash, so target tests can only exec what the image has. `pty.fork` plus exec works as non-root with no network; the child execs before coverage saves its data, so mark that branch `# pragma: no cover`.
- `.coveragerc` of a target (`include_namespace_packages` also measures folders without `__init__.py` that no test imports):

```ini
[run]
branch = True
source = .
omit = tests/*

[report]
include_namespace_packages = True
```

- Tests live in `<target>/tests/test_*.py` and put the target on `sys.path` themselves, so they also run with `python3 -I -B -m unittest discover -s tests` on the host (`-B`: no `__pycache__` in a read-only folder), without `PYTHONPATH`:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import my_module
```

## Sonar (`sonar/compose.yaml`, optional)

- SonarQube Community Build 26.10 + PostgreSQL 17.11 + sonar-scanner-cli 12.3. UI on `http://127.0.0.1:29000`.
- Setup: `/local-env docker/sonar` in a session (or `bash scripts/sync-env.sh --path docker/sonar`) creates `custom/env/docker-sonar.env`; set `SONAR_DB_PASSWORD` there; `bash scripts/sonar.sh up`; create a token in the UI; set `SONAR_TOKEN`. `sonar.sh` passes the file with `--env-file` and stops, naming `/local-env`, when it is missing.
- The scanner mounts the workspace read-only; its working folder (`.scannerwork`) stays in the container's `/tmp`, never in the scanned folder.
- SonarQube needs `vm.max_map_count >= 524288`; on this Linux host set it with `sysctl` on the host.
- Coverage reports and exclusions: `sonar-project.properties` in the scanned folder.
