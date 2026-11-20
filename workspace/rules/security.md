---
paths:
  - "**/*.{go,py,ts,tsx,js,jsx,mjs,cjs,sh,bash,java,kt,cs,rs,rb,php,swift,sql,tf}"
  - "**/Dockerfile*"
  - "**/compose*.{yml,yaml}"
---

# security.md

## Hard rules

The validators (the hooks, the gate, the reviews, the checks of the scripts) protect against mistakes, not against the human: the human owns the machine, and a destructive program, a security test or a tool that does what the human asked is not policed. What the human asks for, in the request or in the conversation, is the decision: a validator may warn about it once, never refuse it and never reopen it later.

A hard refusal (a `deny`, a refusal of a hook or of the gate, a BLOCKER that stops a merge) exists only for this closed list. Each hook, the gate and `rules/review.md` refuse only what is here.

| Hard rule | Why |
| --- | --- |
| A secret in clear (a key, a token, a password, a private key, a `.env` with values) committed, pushed or read into the session | Once it leaves the machine it must be rotated: nothing takes it back |
| Deleting a remote repository, or rewriting or deleting published history (a force push to a shared branch; deleting `developer`, `main` or a tag on the remote) | Other clones, releases and installs depend on it, and it cannot be undone |
| A git write in `projects/` outside the gate; a write in the read-only core of an installed workspace (git, a mode change, `aiwp update` from inside a session); Terraform changing the cloud outside `aiwp-cmds.sh apply` | The gate, `aiwp update` in a terminal and the apply are where the human sees what changes in a shared base, in the rules of the sessions or in real infrastructure |
| A merge into a base without the human's order (`/merge` typed by the human) | What enters a base, and from there production, is the human's decision |
| Deleting a database or Grafana's data (`tools/observability/.data`) without the human's confirmation | Data that is not code has no copy to come back to |
| A change that does something nobody asked for and that cannot be undone (data deleted, a remote changed) | A mistake nobody can repair after it happens |

## Warnings

Everything else a validator finds is a warning, with a suggestion: a best practice, a hardening idea, a public IP in an `.env`, a company term in a public repository, an attack that needs someone writing code to escape the checks on purpose. The human decides; the work goes on. What would interrupt the work over and over (a question per command, a refusal per spelling, a review round per fix) is gathered and shown once: in the warnings board that closes a wave or a merge, before its closing board or summary (`rules/git.md` "Waves"), or when a request is written (`/new-request`). One format everywhere, numbered `W-1`, `W-2`... in its board:

```text
W-<n>  <what was seen>
     Why:      <why it may be a problem>
     Risk:     <HIGH | MEDIUM | LOW> — <impact>
     Suggest:  <what the human can do> (recommended: fix | request | accept)
```

- `HIGH`: it can reach the public or production, or lose data.
- `MEDIUM`: rework or a broken flow later.
- `LOW`: hygiene or quality.

A hook, a script or the gate prints a warning on one line, `WARNING: <what was seen> — <why it may be a problem> — <what the human can do>`; the session writes it in the format above, with its risk, when it gathers it.

## Secrets

- A leak is a secret that leaves the human's machine or lands where others read it: committed to git (any repo, any branch), or written in a versioned document, a log, a message, a report, a container image or Terraform state. A secret in the human's own local configuration (a git-ignored `.env`, `~/.config`, a keychain) is configuration, not a leak.
- Never put a secret in code, a repository, a container image, a log, a test, an example, a versioned config file or Terraform state.
- Load secrets from a managed secret store or a managed identity at runtime; environment variables only in local development. Prefer a workload or managed identity over a long-lived credential.
- Secrets are detected automatically: a clone's pre-push hook scans with gitleaks every commit that would leave the machine and refuses one that adds `.env` or `local.settings.json`; the gate scans the branch again, with `scripts/validate.sh` (check `secrets`) on its tree; in `custom/`, the `guard-bash` hook scans the files of each `git commit`.
- Filled `.env` files: the one of a core folder (`docker/`, `docker/sonar/`, `tools/<name>/`) lives in the custom layer, `custom/env/<name>.env`, git-ignored there (`env/` in `custom/.gitignore`), mode 600, created from the `.env.example` next to the tool by `/local-env`, and read by compose with `--env-file`. A project's own `.env` stays in the project, git-ignored. Never write a `.env` in the core, and never read or edit a `.env` or `custom/env/` (the `deny` rules of `rules/agents/settings.json` refuse both): only `.env.example` templates are read and edited.
- A secret scan of git history (`gitleaks git`, before importing, rewriting or publishing a history) runs through the toolbox with `--redact` and a config that holds only `[extend] useDefault = true`. Never with `docker/config/gitleaks.toml`: its path allowlist hides `.env` and `local.settings.json`, the files most likely to carry a key.

## Dependencies

- Pin exact versions, transitive ones included, through a committed lock file. Container images are pinned by tag and digest, never `latest`.
- A known high or critical vulnerability in a dependency or an image is a warning of the gate (`scripts/validate.sh`, check `vuln`): the human decides to fix it, or accepts the risk.
- Check license compatibility before adding a dependency. Never add one without a concrete benefit.

## Permissions

- Least privilege for every cloud role, service account, policy and network rule. Scope to the resource, not to the subscription.
- Never a wildcard action or resource unless the provider offers nothing narrower; document the exception in `docs/`.
- A script that runs unprompted through a native `allow` takes its scope only from the session's environment, never from an option or a variable set on the command line.

## Personal data

- Minimize: collect and keep only what the purpose requires. Define retention for every stored dataset, copies included.
- Never personal data (name, CPF, e-mail, phone, document content) in URLs, headers, file names, events, metrics or logs. Logs are structured and carry only identifiers.
- Removing personal data from telemetry or logs: inventory every field of real data at once, by key and shape, and remove all in one change.
- Masking by key words: match each word in singular and plural, in Portuguese and English, and test it as a parent key with nested values.
- An error response never reveals which security rule failed; log the reason internally.
- Logging anything taken from a request that is not authenticated yet: cap the count of items and the length of each, and never a value that may carry a credential.

## Test and example data

- Tests and evals use the data the human sends, as sent. None sent: build your own.
- Real personal data never enters a repo, even when the request asks: it stays outside every repo. A versioned fixture that needs its shape replaces each personal value with an invented one of the same type and format.
- Never a secret, token, password or key in a test, fixture, example, prompt, eval or document.
