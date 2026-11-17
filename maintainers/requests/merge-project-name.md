# Functional request: /merge files qa items under a project the release may not name

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of `request-lifecycle.md` (2026-11-17), a RECOMMENDED finding.

## What

`workspace/rules/skills/merge/SKILL.md` step 8 files a qa item under "the top repo of the clone's source", but a project may be a plain folder of repos (`projects/acme/billing-api`, `projects/acme/billing-web`): merges write `qa/billing-api/`, `/merge --main acme` reads `qa/acme/` and validates nothing. A project at depth (`acme/billing`) also gives a release work name with a `/`, which `aiwp-cmds.sh open` refuses.

## Where

`workspace/rules/skills/merge/SKILL.md` ("Which work", steps 8 and "Release"), `workspace/rules/git.md` "Requests".

## Done when

`<project>` is defined once (the top folder of `projects/` holding the source, as `prompt-log.py` does) and used for `qa/`, `done/` and `--main`; the release work name turns `/` into `-`.

## Effort

low
