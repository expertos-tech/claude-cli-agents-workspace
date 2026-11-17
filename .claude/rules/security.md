# security.md

This repository is public. Everything committed, including `maintainers/`, can be read by anyone.

- Never commit a company term, a customer or project name, a personal path (`/home/<user>`, `/Users/<user>`), an
  e-mail address, an internal URL, a token or any secret. `bash tests/check.sh --all` scans the whole repository with
  the owner's terms list (`--help` says where it looks); a match is reworded, never exempted.
- Never print a matching line of the terms list into an issue, a commit, a pull request or a report: say "company term".
- Private analyses of real use (transcripts, measurements, project names, prompts) live in the git-ignored `tmp/` or in
  the owner's custom layer. What reaches the repository is the general finding.
- `.env` files are never read or edited; `.env.example` templates are. The settings deny the rest of the secret files.
- Examples and fixtures use invented data: `acme`, `example.com`, `billing-api`.
- A change that weakens a protection of the product (a hook, a deny rule, the gate, a file mode) needs the owner's
  explicit approval and an independent review (`review.md`).
- Secrets in the product follow `workspace/rules/security.md`, which is code here: change it like any other file.
