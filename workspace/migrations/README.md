# migrations

What each workspace version asks of the projects and POCs. One file per version that asks something:
`<x.y.z>.md`, named after the version that introduced it. A version that asks nothing of the projects has no file.

## How the files are used

- Every project of `projects/` and every POC of `custom/pocs/` carries a marker on line 1 of its `README.md`:
  `<!-- AI-WORKSPACE-PROJECT x.y.z -->`, the workspace version it was last normalized with. For a project, the
  marker that counts is the one committed on `developer`.
- A project is out of date only when a file here has a version above its marker and up to the workspace `VERSION`.
  A project marked `0.1.0` in a workspace on `0.3.0` whose last file here is `0.1.0.md` is up to date: a release that
  asks nothing of the projects never warns.
- `bash scripts/aiwp-project-state.sh` prints the state of each project; the `UserPromptSubmit` hook, `aiwp-cmds.sh
  open` and the gate show it, and `/normalize-projects` applies the pending files in order, then writes the marker
  of the current version.

## How a file is written

- Title `# <x.y.z>`, then what a project marked with an earlier version must change, as steps `/normalize-projects`
  can apply: what to look for (described by what it does, never by a fixed list of file names), where it goes, and
  how to check the result.
- A file is never changed after its release: a later correction is a new file for a later version.

| Version | Asks |
| --- | --- |
| [0.1.0](0.1.0.md) | The first normalization: the analysis, the custom layer, the documentation, the report and the marker |
