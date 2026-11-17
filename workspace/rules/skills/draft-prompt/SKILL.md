---
name: draft-prompt
description: "Turn the user's loose ideas into a functional request prompt (templates/request.md format), asking only the doubts with no best alternative and listing the rest as assumed decisions; shown on screen and saved to custom/prompts/ for /prompt. Use only when the user asks."
argument-hint: "[ideas | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. The user's ideas as free text, or the path of a file holding them; empty: ask for the ideas in one line and stop.

1. Read `rules/prompt-project.md` in full and follow everything below its `<!-- paste below -->` marker as this command's procedure. Never implement, plan or delegate here.
2. Delivery: always save to `custom/prompts/<yyyy-mm-dd>-<kebab-slug>.md` of the root checkout, never of a clone, per that file's "Delivery", and show the same prompt on screen at the first delivery; later changes follow that file's "Flow" step 10.
3. After each save, the first and every later change in this conversation: the one exception to the "never run commands" of `rules/prompt-project.md` "Role", limited to this: commit that file alone in the `custom/` repo, with a message per `rules/git.md` "Commits", scope `prompts`: `git -C custom add -- prompts/<file>`, then `git -C custom commit -F <message file> -- prompts/<file>`, so nothing else in the index goes in. Then `git -C custom push <remote> <branch>` of the branch checked out there. The `guard-bash` hook asks the human; a rejected or failed push is reported, never forced. No remote: commit only. This is the command's checkpoint: it opens no wave and shows no closing board (`rules/git.md` "Waves").
4. The user's replies to the questions continue this command until delivery or cancel; they are not new requests.
5. Never run the prompt. End with the line to run it: `/prompt <file>.md`.
6. Reply in the language of the conversation.
