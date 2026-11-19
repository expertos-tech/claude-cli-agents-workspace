# Functional request: one merge at a time

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** a work clone of this repository; it changes the product (`/merge` and its gate)
and the maintenance (`/caw-merge`). Source: the owner, 2026-11-18, from a warning of `preferred-language`: two
branches that touch the same files, merged at the same time, can conflict.

## 1. Objective

Merges run one at a time. Work in clones keeps running in parallel; only the merge (`/merge` in the product,
`/caw-merge` here) waits its turn in a queue, so two merges into the same base never run together.

## 3. Business rules

- BR-1: the queue holds only merges: `/merge` in all its forms (into `developer`, `--main`, `--hotfix`) and
  `/caw-merge` in all its forms. Nothing else waits on it.
- BR-2: one queue per base: each repo of `projects/`, and this repository for `/caw-merge` (assumed decision). Merges
  into different bases run at the same time.
- BR-3: a merge that finds another one running on its base enters the queue, says its position and which merge runs
  ahead, and starts on its own when its turn comes, in order of arrival, from the base as it is then.
- BR-4: the person can take a waiting merge out of the queue; the others keep their order.
- BR-5: a merge that ends (merged, refused, cancelled, or its session gone) frees its turn; a place held by a session
  that no longer exists never blocks the queue (assumed decision).

## 4. Acceptance criteria

- AC-1: Given a merge running on a base, when a second merge into the same base starts, then it waits, shows its
  position and the merge ahead, and starts only after the first one ends.
- AC-2: Given merges into two different bases, then both run at the same time.
- AC-3: Given a running merge whose session is killed, when another merge into that base starts, then it does not
  wait on the dead one.
- AC-4: Given three merges queued on one base, when the second one is taken out, then the third runs right after the
  first.

## 7. Out of scope

- Queuing anything but merges: stages, waves, checks, test installations.
- Solving conflicts on its own: a merge still brings its base into the branch and stops on a conflict, as today.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. Product: the queue of `/merge`, per repo, with its scenario tests | high | Concurrency in the gate |
| 2. Maintenance: `/caw-merge` waits in the same kind of queue for this repository | high | Concurrency in the merge |
| 3. Proof: two sessions merging into one base at once, headless | medium | The end-to-end check |

The subagents of each step run with the step's effort, passed in the call.

## Assumed decisions

- Open: the scope of a queue. Decided: one per base (a repo of `projects/`; this repository); merges into different
  bases run together. Reason: only a shared base can conflict.
- Open: a merge whose session died. Decided: its place is freed on its own. Reason: a crash must never block every
  later merge.
- Open: what a waiting merge does. Decided: it starts on its own when its turn comes, showing its position meanwhile.
  Reason: a queue, so the person does not type the merge again.
