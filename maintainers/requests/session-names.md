# Functional request: session names that follow the life of a request

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** a work clone of this repository; it changes the product
(`workspace/scripts/session-title.py` and its test, the rename, `workspace/rules/agents/settings.json`, the skills
`request`, `merge`, `new-request` and a new `rename-workspace`, `workspace/templates/request.md`, the scripts README,
`docs/hooks.md`, `workspace/CHANGELOG.md`). Design: `maintainers/plans/session-names.md`. Source: the owner,
2026-11-19: the older workspace named its sessions and the import brought no such rule. After
`requests/draft-prompt.md` (same files).

## 1. Objective

The list of sessions shows which session runs which request and where that request is: started, done, merged; and
which one runs the release. A session that runs no request has a numbered name. Only the life of a request and the
release rename a session; Claude Code's `/rename` stays Claude Code's.

## 3. Business rules

- BR-1: a new session (`startup`, `fork`) is named `ai-workspace-NN` at once; a session after `/clear` gets the same
  kind of name at its first prompt; `resume` and `compact` keep the name.
- BR-2: `/request <file>` names the session `rq-<two-words>` with the first of the two suggestions of the request's
  session line that no running session holds, else the second; both held: no rename, the session says so and asks
  for a new name, which becomes `rq-<name>`.
- BR-3: the `/request` skill renames the session to `rq-done-<two-words>` with the closing board; the `/merge` skill
  into `developer`, to `rq-closed-<two-words>`, with the words its request used. The board stays the last thing of
  the reply.
- BR-4: `/merge --main <project>` names the session `ai-workspace-release-<project>` when it starts and
  `ai-workspace-closed-release-<project>` when it ends. Two merges on one repository at once: `merge-queue.md`.
- BR-4a: an end name (`rq-done-`, `rq-closed-`, `ai-workspace-closed-release-`) held by a finished session still
  open: before the rename, the session asks (1) "I closed the session" (recommended) or (2) the suffix `02`; (1) with
  that session still open is asked once more, then `-02`.
- BR-4b: `/merge --hotfix` names the session as a request does, with `fix-` in place of `rq-`: `fix-<two-words>`
  when it starts, `fix-done-<two-words>` with its closing board, `fix-closed-<two-words>` at its end; the words come
  from the request the person names, else from the description.
- BR-5: a name the workspace gives is never the name of another running session.
- BR-6: `/rename` of Claude Code has no rule of the workspace; the next rename of the workspace applies over it.
- BR-7: `/rename-workspace <text>` names the session `rq-<text normalized>`, with `-02`, `-03`... when a running
  session holds it, opens nothing, and ends with the message of the plan; asked for a branch, the session opens a clone
  with the branch `<type>/<name>`, the same words as the session.
- BR-8: `/new-request` writes the session line with two suggestions; a request with no such line takes its two words
  from its file name.
- BR-9: the hook tells the model the name at each rename, and never blocks a prompt: any failure leaves the name as
  it is.

## 4. Acceptance criteria

- AC-1: Given a new session, when it starts, then its name is `ai-workspace-NN`, an `NN` no running session holds.
- AC-2: Given a named session, when the person runs `/clear` and sends a prompt, then the new session is
  `ai-workspace-NN` and does not keep the name of the one before.
- AC-3: Given a request whose first suggestion a running session holds, when `/request` runs it, then the session gets
  the second; given both held, then the name stays and the session asks for a new one.
- AC-4: Given `/request` showing its closing board, then the session is `rq-done-<two-words>` at the latest at the next
  prompt, and the board is the last thing of the reply.
- AC-5: Given `/merge` into `developer` from a session that did not run the request, when it ends, then the session is
  `rq-closed-<two-words>` with the words of that request.
- AC-6: Given `/merge --main billing-api`, then the session is `ai-workspace-release-billing-api` while it runs and
  `ai-workspace-closed-release-billing-api` at its end; given an open session already named
  `ai-workspace-closed-release-billing-api`, then the two options of BR-4a come first.
- AC-7: Given `/rename-workspace Ajuste do Login SSO` and a running session named `rq-ajuste-do-login-sso`, then the
  session is `rq-ajuste-do-login-sso-02`, nothing is opened, and the message offers the branch with that name.
- AC-8: Given a title set with `/rename` during a request, when the closing board is shown, then the session is
  `rq-done-<two-words>`.

## 7. Out of scope

- A name by activity, `-done-` checks of open work, a session board, reviewer and architect sessions.
- The parent session name in subagent labels (`workflow-agent-session-name.md`).
- The maintenance sessions at this root.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. The hook, the rename, the skills and the request's session line, with `/caw-test-install` | high | a hook of the mandatory core |

The subagents of each step run with the step's effort, passed in the call.
