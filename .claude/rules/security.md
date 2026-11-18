# security.md

This repository is public. Everything committed, including `maintainers/`, can be read by anyone.

## Hard rules

The same rule as the product (`workspace/rules/security.md` "Hard rules"): the validators (the hooks of a work clone,
`tests/caw-work.sh`, `tests/check.sh`, the reviews) protect against mistakes, not against the owner. What the owner
asks for or authorizes is the decision: a validator may warn about it once, never refuse it and never reopen it. A
hard refusal, or a BLOCKER that stops a merge, only for this closed list, mirrored from the product's:

| Hard rule | Why |
| --- | --- |
| A secret in clear (a key, a token, a password, a private key, a `.env` with values) committed, pushed or read into the session | Once it leaves the machine it must be rotated: nothing takes it back |
| Deleting a remote repository, or rewriting or deleting published history (a force push; deleting `developer`, `main` or a tag on the remote; a moved tag) | Clones, releases and installations depend on it, and it cannot be undone |
| `developer` or `main` moved outside `/caw-merge` (a work branch pushes only itself) | The merge is where the owner sees what enters |
| A merge into a base without the owner's order (the push of `developer` by `/caw-merge`, which the owner types; `main`, the tag and the GitHub release each confirmed) | What enters a base, and from there a release, is the owner's decision |
| A product hard rule removed or weakened with no plan the owner decided (`product.md`) | The product's protections are code here |
| A change that does something nobody asked for and that cannot be undone (data deleted, a remote changed) | A mistake nobody can repair after it happens |

## Warnings

Everything else is a warning in the product's format (`workspace/rules/security.md` "Warnings"), gathered and shown
once: in the closing board of a stage, in the summary of `/caw-merge`, or when a request is written
(`/caw-draft-request`). The owner decides; the work goes on.

## What never goes in

- Never write a company term, a customer or project name, a personal path (`/home/<user>`, `/Users/<user>`), an
  e-mail address, an internal URL, a token or any secret in this repository. `bash tests/check.sh --all` scans the
  whole repository with the owner's terms list (`--help` says where it looks); a match is reworded. A company term
  is a warning with confirmation, never a refusal: only the owner keeps one, after the warning, and that answer is
  not asked again. A secret is a hard rule.
- Never print a matching line of the terms list into an issue, a commit, a pull request or a report: say "company term".
- Private analyses of real use (transcripts, measurements, project names, prompts) live in the git-ignored `tmp/` or in
  the owner's custom layer. What reaches the repository is the general finding.
- `.env` files are never read or edited; `.env.example` templates are. The settings deny the rest of the secret files.
- Examples and fixtures use invented data: `acme`, `example.com`, `billing-api`.
- A change that weakens a protection of the product (a hook, a deny rule, the gate, a file mode) needs the owner's
  explicit approval (a request or the conversation) and the review at its merge (`review.md`).
- Secrets in the product follow `workspace/rules/security.md`, which is code here: change it like any other file.
