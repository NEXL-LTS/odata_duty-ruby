# Build plan — PRD lifecycle cleanup (delete PRDs and plans after `/build`)

PRD: [task-thrb8gev86bPsqId2v.md](task-thrb8gev86bPsqId2v.md)

## Notes on applicability

This PRD's "external API" is the **command workflow**, not the gem. It touches only
`.claude/commands/build.md`, `.claude/commands/prd.md`, and a one-time deletion of the current
`doc/prds/` contents. **No `lib/` or `spec/` changes**, so the usual repo hard rules — TDD, the
two parallel DSLs, `bundle exec rake` as the definition of done — do not apply to the deliverables
themselves. `bundle exec rake` is still run once at final review to confirm nothing regressed.

The build of *this* PRD is itself governed by the new rule it introduces: the current PRD
(`task-thrb8gev86bPsqId2v.md`) and this plan file are the only files kept during the one-time
cleanup, and they are removed by the final cleanup commit (PRD lines 70–71).

## Tasks

### Task 1 — Add the final PRD/plan deletion step to `.claude/commands/build.md`
- [x] **Status**

**Task text:** After the "5. Final review" step in `.claude/commands/build.md`, add a final step
so that once the final reviewer is satisfied, `bundle exec rake` is green, and every task is
committed, the built PRD and its `-plan.md` are removed in one separate commit
(`git rm doc/prds/<slug>.md doc/prds/<slug>-plan.md` then a commit
`Remove PRD and plan for <slug> — implemented`). The final review still runs **with** the PRD and
plan present (it checks the plan checkboxes are all ticked); deletion is the last commit on the
branch. If only one of the two files exists (e.g. a resumed build), delete what exists and don't
fail the cleanup. The closing report must mention the cleanup commit alongside the branch name and
commits. Also add a matching entry to the "Red flags — never" list: never leave the built PRD/plan
in the tree after final review passes.

**Likely files:** `.claude/commands/build.md`.

**Defining PRD excerpt:**
> Add a final step after **5. Final review**: once the final reviewer is satisfied,
> `bundle exec rake` is green, and every task is committed, delete the PRD and its plan in one
> separate commit:
> ```
> git rm doc/prds/<slug>.md doc/prds/<slug>-plan.md
> git commit  # "Remove PRD and plan for <slug> — implemented"
> ```
> - The final review still runs **with** the PRD and plan present (it checks the plan's checkboxes
>   are all ticked); deletion is the last commit on the branch.
> - If only one of the two files exists (e.g. a resumed build), delete what exists.
> - The closing report mentions the cleanup commit alongside the branch name and commits.
> - Add a matching "never" to the Red flags list: never leave the built PRD/plan in the tree after
>   final review passes.

**Dependencies:** none.

### Task 2 — Note PRD transience in `.claude/commands/prd.md`
- [ ] **Status**

**Task text:** Add one line to the Output section of `.claude/commands/prd.md` noting that PRDs
are transient: `/build` deletes the PRD (and its plan) in a final commit once implemented — git
history is the archive.

**Likely files:** `.claude/commands/prd.md`.

**Defining PRD excerpt:**
> One line in the Output section noting PRDs are transient: `/build` deletes the PRD (and its plan)
> in a final commit once implemented — git history is the archive.

**Dependencies:** none.

### Task 3 — One-time cleanup of `doc/prds/` contents
- [ ] **Status**

**Task text:** Delete every existing file under `doc/prds/` — all shipped PRDs, their `-plan.md`
files, and `README.md` — via `git rm`, **except** the currently-building PRD
(`task-thrb8gev86bPsqId2v.md`) and its plan (`task-thrb8gev86bPsqId2v-plan.md`), which stay for the
final review and are removed by the final cleanup commit. The `/prd` command recreates `doc/prds/`
when it writes a new PRD, and the workflow the README described lives in the command files.

**Likely files:** everything in `doc/prds/` except `task-thrb8gev86bPsqId2v.md` and
`task-thrb8gev86bPsqId2v-plan.md`.

**Defining PRD excerpt:**
> Delete `doc/prds/` entirely — every `*.md` including `README.md` — in a commit. The `/prd`
> command already recreates the directory when it writes a new PRD … Other PRDs present in
> `doc/prds/`: delete only the built PRD's two files, never the whole directory. … After *this*
> PRD is built, `doc/prds/` no longer exists in the tree — and by the new rule, the build of this
> PRD deletes this PRD and its own plan as its final commit.

**Dependencies:** none (independent of tasks 1–2).

### Final cleanup (executed by the process, not a task)

After final review passes, `git rm doc/prds/task-thrb8gev86bPsqId2v.md
doc/prds/task-thrb8gev86bPsqId2v-plan.md` and commit
`Remove PRD and plan for task-thrb8gev86bPsqId2v — implemented`. This empties `doc/prds/` in the
tree, satisfying PRD lines 70–71.
