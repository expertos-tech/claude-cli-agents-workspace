# Functional request: validate what waits in qa on `developer`, without a release

**Project:** claude-cli-agents-workspace

**State:** idea. The owner will complete the design when qa is discussed (2026-11-17).

## What

A way to run the release's validation on `developer` without releasing: read every request in `qa/`, run the final
review "what enters and what leaves" on `<last tag>..developer`, and record in each qa file the status of each
acceptance criterion (proven / pending / failed), with no release clone, no version and no change to `main`.

## Where

`/merge` and `/caw-merge`: a flag such as `--qa` (recommended over a separate skill, so the review stays written once).

## Done when

To be decided with the owner.

## Effort

To be decided with the design.
