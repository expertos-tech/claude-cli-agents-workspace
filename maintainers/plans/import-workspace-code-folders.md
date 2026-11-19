# `/import-workspace`: every code folder found, classified and brought with a repository

Status: draft, decisions D-1..D-6 open. Source: warning W-1 of the AC-10 run of `requests/import-workspace.md`
(2026-11-19) and the owner's direction on it. Extends `import-workspace.md`; nothing of it is built yet.

## 1. What the AC-10 run showed

The run imported a real older workspace (a copy). Its repositories came whole; its code with no repository of its own
did not:

- **Detection by manifest only.** A code folder is a folder with one of 10 manifest names (`go.mod`, `package.json`...)
  or `.csproj`/`.sln`, or a folder named like a tool of this workspace. Two folders with code and no manifest were in no
  line of the plan: one of Terraform and shell scripts, one of Python scripts with their reports. Nothing said they
  were left behind.
- **A project split in its parts.** One project of the tools folder had, at its top, a compose file, a README, a
  CHANGELOG, `deploy/` and `docs/`, and two parts with a manifest each: `api/` (`go.mod`) and `web/`
  (`package.json`). The scan asked about `api/` and `web/` (the outermost folders with a manifest), never about the
  project: its top files, `deploy/` and `docs/` belonged to no question.
- **"No git" was wrong.** No folder of the tools folder had a `.git`, but the older workspace's own repository tracks
  them: 608 files of the tools folder are in its index, and the project above has 134 commits there. The folder has
  history, only not a repository of its own.
- **Nothing with no repository is brought.** The answers are `project` (listed with commands for the person: `git
  init`, a remote, a push, then `bring`) or `tool` (of the older workspace, left behind). The import itself brings
  neither.
- **Its backlog is lost (W-1).** A backlog item can be answered only with a project the import brings, or `workspace`
  (dropped). The 4 items about the project above could only be dropped, with the reason "about the older workspace
  itself", although the person had just answered `project`.

This workspace has three homes for code: `projects/<name>` (a repository of its own), `custom/pocs/<name>` and
`custom/tools/<name>` (versioned in the custom layer's repository, `scripts/init-repo.sh`).

## 2. The owner's direction

1. A missing repository never stops the import. A deterministic scan walks every folder and says, per folder, "code
   found" or "no code", from the extensions of code and of documents, not only from manifests.
2. Having no repository only stops the validation flows (the gate, the normalization). A folder with no repository
   may sit inside a repository (here, the older workspace's own): look at the root too.
3. A folder whose kind is not clear (POC, tool or project) is asked during the import, in rounds with checkboxes:
   POCs (select, confirm; the selected leave the next round), then tools (the same), then projects.
4. Everything that should have a repository and has none gets a local one, so the flows can run. No remote: no push.

## 3. Design

### 3.1 Detection: every folder ends in one bucket

- The script walks every folder of the older workspace that no repository, worktree or clone holds (the older
  workspace's own repository does not count as holding: it holds everything), skipping `node_modules`, `.venv`, `.git`
  and the closed list of build and data folders (`dist`, `build`, `.data`, `target`, `coverage`).
- A folder **has code** when it holds a manifest, or a file whose extension is in a closed list: `.go .py .ts .tsx .js
  .jsx .mjs .cjs .java .kt .cs .rb .php .rs .swift .c .h .cpp .sh .ps1 .tf .hcl .sql`, or a `Dockerfile` or compose
  file. It **has documents** when it holds `.md .docx .pdf .xlsx .pptx` and no code. Otherwise **nothing**.
- **The candidate** is the unit asked about: a folder with code or documents whose parent holds no code file of its
  own (a container, like the tools folder). A candidate keeps its subfolders as parts: in the example, one candidate
  with the parts `api/` and `web/`, its compose file, `deploy/` and `docs/` included.
- Each candidate carries its evidence: its size, its file count by extension (the top 5), its manifests, and whether
  the older workspace's repository tracks it (with its commit count).
- The plan accounts for every top folder of the older workspace in exactly one bucket: brought, a candidate (with its
  answer), the older workspace's own (`rules/`, `scripts/`...), scratch, documents only, nothing. A test fails when a
  folder with code reaches no bucket.

### 3.2 The kind: rounds with checkboxes

- A candidate the script settles is never asked: one a tool of this workspace covers stays "already here", as today.
- The rest go through three rounds, in this order: **POCs**, **tools**, **projects**. Each round shows the candidates
  still open as checkboxes; the person selects and confirms; the selected leave the next rounds.
- What no round took is **left behind**, listed in the plan with its path (D-2).
- In Claude Code, a round is `AskUserQuestion` with `multiSelect`: at most 4 options per question and 4 questions per
  call, so up to 16 candidates per call (more: the round takes several calls). Each option's description is its
  evidence in one line. With no such tool (a headless run), the skill lists them in text and takes the answer as text.
- The script takes a round in one call: `answer --kind poc C-1 C-4 C-7` records the three and keeps the rest open.

### 3.3 A repository for what has none

- **Project:** a new local repository at `projects/<name>`, branch `main`, no remote. Its files are those the older
  workspace's repository tracks in the folder plus those it neither tracks nor ignores; never a `.env`, a key, an
  ignored file or a build or data folder, and the secret scan of the import runs over them. History: D-3.
- **POC or tool:** its files, chosen the same way, go to `custom/pocs/<name>` or `custom/tools/<name>`, with the row
  of the custom layer's index (`init-repo.sh`), and enter the import's commit of `custom/`. No repository of its own:
  the custom layer's repository is its repository.
- No remote: nothing is pushed, as for every import. `/normalize-projects` already stops at stage 2 until a project has
  a remote, and says how to add one.

### 3.4 Backlog

- The backlog questions come after the rounds and accept every candidate taken as a POC, a tool or a project. An item
  about one becomes an `idea` request whose `**Project:**` names it. `workspace` keeps its meaning: about the older
  workspace itself, dropped.

### 3.5 Safety

- The older workspace stays read-only (AC-8): the files are read, never written; a history split (D-3) runs in a
  temporary clone under `tmp/`, never in the source.
- A copy with missing objects (a live snapshot): the split falls back to the files alone, and the plan says so, as
  `bring` does for refs today.

## 4. Options and recommendation

| | A: list only (today) | B: detect, ask, list | C: detect, ask, bring (recommended) |
| --- | --- | --- | --- |
| Folders with no manifest | missed | found | found |
| A project in parts | split | one candidate | one candidate |
| Kinds | project or tool | POC, tool, project, left behind | the same |
| What is brought | nothing | nothing; commands listed | everything taken, with a local repository |
| Its backlog | dropped | kept, its project not brought yet | kept, with its project |
| Effort | none | medium | high |

C is the owner's direction and closes W-1. B is the cheaper half: the person runs the listed commands.

## 5. Decisions for the owner

- **D-1, the extensions.** The closed lists of 3.1 (code, documents). Recommended: as written; a folder of documents
  only is listed, never asked.
- **D-2, what no round took.** Recommended: left behind, listed. Other: a fourth question "leave these?" before the
  plan.
- **D-3, the history of a project with no repository.** (a) One commit with its files, "import from the older
  workspace". (b) Its history split from the older workspace's repository (`git subtree split --prefix`, in a
  temporary clone), then one commit with what the files have beyond it (134 commits kept in the example).
  Recommended: (b) when the older repository tracks the folder and its objects are whole, (a) otherwise.
- **D-4, the history of a POC or tool.** Recommended: none (one commit in the custom layer). Other: as D-3, which
  needs a repository of its own and breaks the custom layer's layout.
- **D-5, where it runs.** Recommended: a new request after the `import-workspace` branch is merged, so that branch
  closes as proved (W-1 answered `request`, this plan its source).
- **D-6, the order of the rounds.** POCs, tools, projects, as the owner wrote. Recommended: keep it.

## 6. Stages and effort

1. Detection, candidates and buckets, with scenario tests (a folder with no manifest, a project in parts, a folder the
   root repository tracks): script, effort medium.
2. The rounds: `answer --kind`, the skill's checkboxes and the text fallback: script and skill, effort medium.
3. Bringing what has no repository: the file selection, the secret scan, the local repository and the split (D-3),
   the custom layer's items: script, effort high (writes, secrets).
4. Backlog to the new candidates, docs, the AC-10 run again on the copy: effort medium.
