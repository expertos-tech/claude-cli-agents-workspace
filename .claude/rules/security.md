@workspace/rules/security.md

The sections below win where they differ; its `paths:` do not limit it here.

---

## Ignore from the product rule

- Hard rules, the row of `projects/`, the read-only core and Terraform: no such thing here; its place is taken by the
  row of `developer` and `main` below.
- Hard rules, the row of a database or Grafana's data: this repository has none.
- Secrets, the bullet on automatic detection (gitleaks in a clone's pre-push hook, the gate, `guard-bash` in
  `custom/`): no product hook runs here. A work clone's hooks scan company terms, and `tests/check.sh` runs the
  product gate on `workspace/`.

## Mapping

| Product | Here |
| --- | --- |
| the human | the owner |
| the validators (the hooks, the gate, the reviews, the checks of the scripts) | the hooks of a work clone, `tests/caw-work.sh`, `tests/check.sh`, the reviews |
| `/merge` typed by the human | the push of `developer` by `/caw-merge`, which the owner types; `main`, the tag and the GitHub release each confirmed |
| the closing board of a wave, the summary of `/merge`, `/draft-request` | the closing board of a stage, the summary of `/caw-merge`, `/caw-draft-request` |
| the `deny` rules of `rules/agents/settings.json` | the `deny` rules of `.claude/settings.json`, which also cover the other secret files (`~/.ssh`, cloud credentials) |

## CAW rules

This repository is public. Everything committed, including `maintainers/`, can be read by anyone.

### Hard rules here

The closed list is the product's, with these rows over its rows of the same subject:

| Hard rule | Why |
| --- | --- |
| Deleting a remote repository, or rewriting or deleting published history (a force push of any branch; deleting `developer`, `main` or a tag on the remote; a moved tag) | Clones, releases and installations depend on it, and it cannot be undone |
| `developer` or `main` moved outside `/caw-merge` (a work branch pushes only itself) | The merge is where the owner sees what enters |
| A merge into a base without the owner's order (the push of `developer` by `/caw-merge`, which the owner types; `main`, the tag and the GitHub release each confirmed) | What enters a base, and from there a release, is the owner's decision |
| A product hard rule removed or weakened with no plan the owner decided (`product.md`) | The product's protections are code here |

### What never goes in

- Never write a company term, a customer or project name, a personal path (`/home/<user>`, `/Users/<user>`), an
  e-mail address, an internal URL, a token or any secret in this repository. `bash tests/check.sh --all` scans the
  whole repository with the owner's terms list (`--help` says where it looks); a match is reworded. A company term
  is a warning with confirmation, never a refusal: only the owner keeps one, after the warning
  (`bash tests/caw-work.sh push <work> --accept-terms`), and that answer is not asked again. A secret is a hard rule.
- Never print a matching line of the terms list into an issue, a commit, a pull request or a report: say "company term".
- Private analyses of real use (transcripts, measurements, project names, prompts) live in the git-ignored `tmp/` or in
  the owner's custom layer. What reaches the repository is the general finding.
- Examples and fixtures use invented data: `acme`, `example.com`, `billing-api`.
- A change that weakens a protection of the product (a hook, a deny rule, the gate, a file mode) needs the owner's
  explicit approval (a request or the conversation) and the review at its merge (`review.md`).
- `workspace/rules/security.md` is also code here: change it like any other file of the product, its hard rules only
  through a plan (`product.md`).
