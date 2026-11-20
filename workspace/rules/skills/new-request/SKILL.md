---
name: new-request
description: "Turn the user's loose ideas, or a plan of /draft-prompt, into a functional request (templates/request.md format), asking only the doubts with no best alternative and listing the rest as assumed decisions; saved to custom/requests/ for /request, with a summary on screen. Use only when the user asks."
argument-hint: "[ideas | plan | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. The user's ideas as free text, the path of a file holding them, or the path of a plan of `/draft-prompt` (`custom/plans/<file>`); a plan is never required. Empty: ask for the ideas in one line and stop.

1. Read `rules/request-writing.md` in full and follow everything below its `<!-- paste below -->` marker as this command's procedure: ideas or a file are organized first by its "Organize", and a plan follows its own final guidance ("Flow" step 1). Never implement, design how it is built, or delegate here.
2. Delivery: always save to `custom/requests/<yyyy-mm-dd>-<kebab-slug>.md` of the root checkout, never of a clone, per that file's "Delivery"; from a plan, also update its status line and its row in `custom/plans/README.md` there. The first delivery shows the summary of "Delivery", never the whole request unless the user asks for it; later changes follow that file's "Flow" step 11.
3. After each save, the first and every later change in this conversation: the one exception to the "never run commands" of `rules/request-writing.md` "Role", limited to this: commit the files of this save alone in the `custom/` repo, with a message per `rules/git.md` "Commits", scope `requests`: the request (`requests/<file>`) and, at the first save from a plan, `plans/<plan file>` and `plans/README.md`; `git -C custom add -- <those paths>`, then `git -C custom commit -F <message file> -- <those paths>`, so nothing else in the index goes in. Then `git -C custom push <remote> <branch>` of the branch checked out there. The `guard-bash` hook asks the human; a rejected or failed push is reported, never forced. No remote: commit only. This is the command's checkpoint: it opens no wave and shows no closing board (`rules/git.md` "Waves").
4. The user's replies to the questions and improvements continue this command until delivery or cancel; they are not new requests.
5. Never run the request. The summary ends with the line to run it: `➜ Run: /request <file>.md`.
6. Reply in the person's language (the Claude Code setting `language`, else the language of the conversation): the questions, the improvements and the summary are in it. The request is saved in English; a plan keeps its own language. The summary names the file once, with the language it was saved in.
