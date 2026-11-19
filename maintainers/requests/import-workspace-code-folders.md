# Functional request: `/import-workspace` brings every code folder

**Project:** claude-cli-agents-workspace

**State:** ready

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`. Design
and the owner's decisions: `maintainers/plans/import-workspace-code-folders.md`. Runs after `import-workspace` is on
`developer`; it replaces BR-7, AC-4 and the code-folder part of BR-9 of that request. Source: warning W-1 of its AC-10
run, answered `request` by the owner on 2026-11-19.

## 1. Objective

`/import-workspace` brings today only what has a git repository of its own, and finds other code only by a manifest:
folders of scripts or infrastructure are missed with no word, a project made of parts is asked about part by part,
and the backlog of a project with no repository can only be dropped. After this request every folder of the older
workspace is accounted for, the person classifies the unclear ones as POC, tool or project in rounds of checkboxes,
and each one taken is brought, with a local repository and its history when there is one.

## 3. Business rules

- BR-1: detection is deterministic, in `scripts/workspace-import.py`. It walks every folder of the older workspace
  that no repository, worktree or clone holds (the older workspace's own repository does not count as holding),
  skipping `.git`, `node_modules`, `.venv` and the build and data folders `dist`, `build`, `.data`, `target`,
  `coverage`. A folder **has code** when it holds a build or package manifest, a `Dockerfile` or compose file, or a
  file with one of the extensions `.go .py .ts .tsx .js .jsx .mjs .cjs .java .kt .cs .rb .php .rs .swift .c .h .cpp
  .sh .ps1 .tf .hcl .sql`. It **has documents only** when it holds no code and one of `.md .docx .pdf .xlsx .pptx`.
- BR-2: a **candidate** is a folder with code whose parent holds no code file of its own; its subfolders are its parts
  and come with it (its top files, `deploy/`, `docs/` included). Its evidence: size, file count by extension (the top
  5), manifests, whether the older workspace's repository tracks it and with how many commits.
- BR-3: a folder with documents only is judged by the model: the script gives it the folder's tree (paths and sizes,
  no file opened) and the model answers whether it is a project of documents or a guide (a candidate) or not (left
  behind). This is the only kind judgement the model makes alone.
- BR-4: settled without a question, as today: a candidate a tool of this workspace's `tools/` covers (already here),
  the older workspace's own folders (its instructions, its scripts), scratch. A repository outside the projects folder
  is a candidate too.
- BR-5: the rounds. The open candidates go through three rounds, in this order: POCs, tools, projects. Each round
  shows the candidates still open as checkboxes, each with its evidence in one line; the person selects and confirms;
  the selected leave the next rounds. In a session, a round is `AskUserQuestion` with `multiSelect` (at most 4 options
  a question, 4 questions a call; more candidates take several calls); with no such tool, a text list and a text
  answer. The script records a round in one call: `answer --kind <poc|tool|project> <id>...`. What no round takes is
  left behind.
- BR-6: a candidate taken as a **project** with no repository of its own becomes a new local repository at
  `projects/<kebab-name>`, branch `main`, no remote. When the older workspace's repository tracks the folder and its
  objects are whole, the history is split from it (`git subtree split --prefix`, in a temporary clone under `tmp/`),
  then one commit adds what the files have beyond it; otherwise one commit with the files, "import from the older
  workspace", and the plan says why.
- BR-7: a candidate taken as a **POC** or a **tool** goes to `custom/pocs/<kebab-name>` or `custom/tools/<kebab-name>`
  with its row in the custom layer's index (`scripts/init-repo.sh`), and never holds a repository of its own. When its
  source is a git repository, its `.git` is not brought and its history enters the custom layer's repository under
  that folder (`git subtree add`, from a temporary clone), when its objects are whole; otherwise, and for a folder
  with no repository of its own, its files enter the import's commit of `custom/`.
- BR-8: the files brought (BR-6, BR-7) are those the older workspace's repository tracks in the folder plus those it
  neither tracks nor ignores; never a `.env`, a key, a credential, an ignored file or a build or data folder of BR-1.
  The import's secret scan runs over them; a file with a secret is not brought and the plan names it.
- BR-9: the backlog questions come after the rounds and accept every candidate taken; an item about one becomes an
  `idea` request whose `**Project:**` names it.
- BR-10: the plan accounts for every top folder of the older workspace in exactly one bucket: brought (with its kind),
  the older workspace's own, scratch, left behind. Every folder left behind is listed with the reason of its
  analysis (no code; documents, judged not a project; taken by no round). The plan ends inviting final adjustments in
  the person's own words ("X is a tool", "leave Y"); the model turns each into answers through the script, writes the
  plan again, and applies only on the person's confirmation.
- BR-11: the older workspace stays read-only: no file written, nothing of it run, `.env` files never read; a split or
  a subtree runs in a temporary clone. Nothing is pushed; `custom/` is committed, not pushed, as today.

## 4. Acceptance criteria

- AC-1: Given a folder with only `.tf` and `.sh` files and no manifest, then it is a candidate with its evidence.
- AC-2: Given a folder with a compose file, a README, `deploy/` and two parts with a manifest each, then it is one
  candidate; taken as a project, `projects/<name>` holds its top files, `deploy/` and both parts.
- AC-3: Given a folder of documents only, then the model receives its tree and no file of it is opened; answered a
  project, it is a candidate; answered not, it is listed as left behind with that reason.
- AC-4: Given six open candidates, when the person takes two as POCs, then two of the other four as tools, then one of
  the last two as a project, then each is in its destination and the last one is listed as left behind; a round with
  more than four candidates spans several questions.
- AC-5: Given a project with no repository of its own that the older repository tracks with N commits, objects whole,
  then `projects/<name>` is a repository with no remote whose history holds those N commits, plus one commit when the
  files differ; given a missing object, then one commit and the plan says why.
- AC-6: Given a POC whose source is a repository with 3 commits, then `custom/pocs/<name>` holds its files and no
  `.git`, and the custom layer's history holds the 3 commits; given a tool with no repository, then its files are in
  the import's commit of `custom/`.
- AC-7: Given a `.env`, a key file, an ignored file and a `node_modules/` in a candidate, then none is brought and the
  `.env` was never opened.
- AC-8: Given a backlog item about a candidate taken as a project, then it is an `idea` request whose `**Project:**`
  names it.
- AC-9: Given the plan written, when the person says "X is a tool", then the plan is written again with X as a tool
  before any apply, and apply runs only after the person confirms.
- AC-10: Given any older workspace of the scenario tests, then every top folder is in exactly one bucket of the plan,
  and a folder with code in none fails the test.
- AC-11: Given an import run, then the older workspace is identical before and after (a snapshot of refs, configs,
  statuses, entries and hashes), and nothing was pushed.
- AC-12: Given the copy of a real older workspace of the `import-workspace` AC-10 run, then the folders it missed and
  the project it split are candidates, and that project's backlog items are `idea` requests. The proof is recorded in
  this request, with no company, project, person or path names.

## 7. Out of scope

- Analysing or changing the code brought; normalizing it (that is `/normalize-projects`).
- Creating a remote or pushing anything.
- Importing rules, skills, agents or hooks of the older workspace.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Detection, candidates, buckets and the documents question (BR-1 to BR-4, BR-10), with scenario tests (AC-1 to AC-3, AC-10) | medium | Read-only scan over a tested script |
| 2. The rounds and the final adjustments: `answer --kind`, the skill's checkboxes and text fallback (BR-5, BR-10; AC-4, AC-9) | medium | Questions and answers, no write |
| 3. Bringing what has no repository: file selection and secret scan, the local repository with its split, the custom layer's items with their subtree (BR-6 to BR-8, BR-11; AC-5 to AC-7, AC-11) | high | Git writes, history rewriting in a temporary clone, secrets |
| 4. Backlog to the new candidates, docs, the run on the copy (BR-9; AC-8, AC-12) | medium | Over tested steps |

The agents of each stage run with the stage's effort, passed in the call.
