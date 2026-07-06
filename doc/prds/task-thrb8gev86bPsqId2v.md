# PRD lifecycle cleanup — delete PRDs and plans after `/build`

## Summary

Make `doc/prds/` transient: delete its current contents (all PRDs, plans, and the README) now,
and change the `/build` command so that after an implementation is complete it deletes the built
PRD and its `-plan.md` in a separate, final commit. Git history becomes the PRD archive.

## Goal / Problem

**Current behavior:** `/build` leaves the PRD and its plan file in the tree after the work lands,
so `doc/prds/` accumulates documents for already-shipped capabilities (24 files today). These
duplicate what the `doc/` guides and the specs (the repo's public documentation) already cover,
and they go stale.

**Expected behavior:** `doc/prds/` only ever contains in-flight work. Once `/build` finishes a
PRD, the PRD and plan are removed in their own commit on the feature branch; anyone needing them
later finds them in git history.

## What it enables

- As a maintainer, I can treat anything in `doc/prds/` as *not yet built* — the directory is a
  work queue, not an archive.
- As a reviewer of a `/build` branch, I still see the PRD and ticked plan throughout the branch's
  task commits, and one final commit that retires them.
- Scope limit: `/build` deletes only the files for the PRD it built — other in-flight PRDs in the
  directory are untouched.

## Changes (the "external API" here is the command workflow)

### 1. One-time cleanup (part of implementing this PRD)

Delete `doc/prds/` entirely — every `*.md` including `README.md` — in a commit. The `/prd`
command already recreates the directory when it writes a new PRD, and the workflow the README
described lives in `.claude/commands/prd.md` and `.claude/commands/build.md`.

### 2. `.claude/commands/build.md`

Add a final step after **5. Final review**: once the final reviewer is satisfied,
`bundle exec rake` is green, and every task is committed, delete the PRD and its plan in one
separate commit:

```
git rm doc/prds/<slug>.md doc/prds/<slug>-plan.md
git commit  # "Remove PRD and plan for <slug> — implemented"
```

- The final review still runs **with** the PRD and plan present (it checks the plan's checkboxes
  are all ticked); deletion is the last commit on the branch.
- If only one of the two files exists (e.g. a resumed build), delete what exists.
- The closing report mentions the cleanup commit alongside the branch name and commits.
- Add a matching "never" to the Red flags list: never leave the built PRD/plan in the tree after
  final review passes.

### 3. `.claude/commands/prd.md`

One line in the Output section noting PRDs are transient: `/build` deletes the PRD (and its plan)
in a final commit once implemented — git history is the archive.

## Behavior & expected I/O

A `/build orderby-support` branch ends like:

```
Add build plan for orderby-support
<one commit per task…>
Remove PRD and plan for orderby-support — implemented
```

After *this* PRD is built, `doc/prds/` no longer exists in the tree — and by the new rule, the
build of this PRD deletes this PRD and its own plan as its final commit.

## Common error cases

- Plan file missing (build resumed from an older session): `git rm` only the file(s) present;
  don't fail the cleanup.
- Other PRDs present in `doc/prds/`: delete only the built PRD's two files, never the whole
  directory.

## Scope

- **In:** `.claude/commands/build.md`, `.claude/commands/prd.md`, one-time deletion of
  `doc/prds/` contents.
- **Out:** `lib/`, `spec/`, `doc/` guides, gemspec version (no `lib/` change, so no version
  bump), and every other part of the `/build` flow (branching, TDD, two-stage review,
  commit-per-task are unchanged).

## Documentation impact

None of the `doc/` guides. `doc/prds/README.md` is deleted; the command files themselves are the
workflow documentation.