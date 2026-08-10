---
description: Implement a PRD from doc/prds/ end to end — derive a task plan, then execute each task with a fresh implementer subagent followed by two-stage review (spec compliance, then code quality). Writes code and tests, and commits each task on a feature branch. Never pushes.
argument-hint: <prd name or path in doc/prds/>
allowed-tools: Agent, Bash, Read, Edit, Write, Glob, Grep, TodoWrite
---

# Build a PRD

Take the PRD identified by `$ARGUMENTS` (a filename, slug, or path under `doc/prds/`) and carry it **all the way from PRD to commit** — code, tests, and a commit per task on a feature branch — by acting as a **controller** that dispatches a fresh subagent per task and reviews each one in two stages. You **never push and never open a PR**; the work lands as commits on a local branch for the user to review.

You are the controller. You hold the plan, curate context, dispatch subagents, and gate quality. You do **not** write implementation code yourself — that is the implementer subagent's job. Your context stays clean for coordination.

## Why subagents

Each task goes to a fresh subagent whose entire context you construct: the task text, the relevant PRD excerpt, and the repo rules it must follow. It never inherits your history. This keeps each subagent focused and preserves your context for orchestration. **Fresh subagent per task + a review dispatch that runs spec compliance then code quality = high quality, fast iteration.**

## Trust the review-task dispatch

The `review-task` skill (`.claude/commands/review-task.md`) **is** the verification layer for each task — that's its whole purpose. Once it reports `REVIEW_OK`, don't re-run the full suite yourself or re-derive counts it already confirmed (an offense count, a coverage percentage, "TDD was followed") — that duplicates work the review already paid for and slows every task down without adding safety. Reserve your own independent checks for claims that are surprising, load-bearing, or trivially cheap to spot-check with a single command.

## Continuous execution

There is **no approval checkpoint**. Once invoked, derive the plan from the PRD using the codebase's own best practices (below) and **go** — execute **all** tasks without pausing to check in. Do not present the plan for sign-off, and do not emit "Should I continue?" prompts or per-task progress summaries; the user already chose to build this PRD by running the command. Stop only for: a `BLOCKED` status you cannot resolve, a genuine ambiguity in the PRD that prevents correct work, or all tasks complete.

## This repo's hard rules (every subagent must honor)

These come from `CLAUDE.md` and are non-negotiable. Bake them into every implementer and reviewer prompt:

- **Two parallel DSLs — keep both in sync.** Most features must be implemented in **both** the class-based DSL (`lib/odata_duty.rb`, `entity_type.rb`, `complex_type.rb`, `enum_type.rb`) and the builder DSL (`lib/odata_duty/schema_builder.rb` + `schema_builder/*` + `set_resolver.rb`), with matching specs under **both** `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`. If a task touches one DSL, confirm whether the other needs the same change — usually it does.
- **TDD is mandatory.** Follow the repo's own skill: `.claude/skills/test-driven-development/SKILL.md`. No production code without a failing test first. Watch the test fail for the right reason before implementing.
- **Tests use only the gem's public API** (`CLAUDE.md`) — never reach into internal classes/methods (`Executor`, `*Wrapper`, parslet, ERB, mappers). Avoid the anti-patterns in `.claude/skills/test-driven-development/testing-anti-patterns.md`.
- **Style:** two-space indent, **99-char line limit**, Ruby 3 syntax. RuboCop metrics are tight (`.rubocop.yml`: `MethodLength` 13, `Class/ModuleLength` 99, `AbcSize` 30, `CyclomaticComplexity` 7) — keep methods small rather than adding inline disables.
- **Green gate:** `bundle exec rake` runs **RSpec and RuboCop** and is the definition of done for every task. A task isn't complete until it's green.
- **Some tasks are only jointly green.** Prefer modeling jointly-green work — e.g. turning on a new lint rule before migrating the violations it flags — as a **single task**: one implementer dispatch, one `review-task` run, one commit. That way it never has to satisfy the green gate in a red intermediate state, and step 4's normal flow applies unchanged. Only split it into separate tasks if the combined diff would be too large to review as one unit; if you do, the enabling task's commit explicitly skips step 4b's `review-task` gate (its quality stage will correctly report `QUALITY_ISSUES` for the rake failure the task caused on purpose) — commit it directly with `git commit --no-verify`, quote the expected failure in the commit message so the interim state is explicit, and land the fix in the very next task. Never disable the check itself to fake a green interim state — that defeats the task either way.
- **Never silently drop a planned task.** If token or time pressure tempts you to merge or cut a task from the plan, say so explicitly in the plan file and in your final report — don't just omit the work. A dropped task produces the same clean `rake` and clean reviews as a complete one on everything that *was* built, so nothing downstream will catch it unless you flag it yourself.
- **Debug a red `rake` from live tool output, not speculation.** For a coverage failure, open `coverage/index.html` (or read the offending file/line from the console output) to see exactly which branch was missed before adding a guard — don't add defensive guards for cases you haven't confirmed are real, then chase the coverage number back down. For a RuboCop failure, run `bundle exec rubocop <path>` and read its message directly. See `doc/using_coverage.md`'s Common Error Cases for the full workflow.
- **Docs:** if the PRD's "Documentation impact" section names a `doc/` guide to add or extend, that is a task too. Bump `spec.version` in `odata_duty.gemspec` only if the user asks.
- **Keep `CLAUDE.md`'s `## Features` index current.** If this PRD adds a note-worthy, externally visible capability (a new query option, write verb, hook, output format, generator, MCP surface — anything a future session should know exists), add or update its one-line entry in the `## Features` section of `CLAUDE.md`, pointing at the `doc/` guide that documents it. The index is a pointer list, not a place for detail — one line, link to the guide. Skip purely internal refactors that change nothing a consumer can observe.

## Process

### 1. Locate and read the PRD

Resolve `$ARGUMENTS` to a file in `doc/prds/` (try exact path, then `doc/prds/<arg>.md`, then a `Glob` match; if several match or none do, ask). Read it fully. If `$ARGUMENTS` is empty, list `doc/prds/*.md` and ask which one.

### 2. Branch — never build on main

Check the current branch with `git status`. If it's `main`, create and switch to a feature branch named after the PRD (e.g. `git checkout -b prd/orderby-support`) before any code changes — do this automatically; branching off `main` is itself the safeguard, so it needs no prompt. **Never** commit implementation work directly to `main`/`master`. If the working tree has unrelated uncommitted changes, note them and continue on the new branch.

### 3. Derive the task plan — then immediately execute it

A PRD is a spec, not a task list — you must decompose it, guided by the codebase's own best practices: the **hard rules** above, the existing structure of `lib/` and the two spec trees, and how comparable features (e.g. `$search`, `$select`) are already split across the DSLs. Read the PRD's **External API**, **Behavior & expected I/O**, **Common error cases**, and **Scope** sections and produce an ordered list of small, independent, testable tasks. Good task boundaries for this repo:

- One task per coherent slice of behavior (e.g. "parse and validate the new query option", "apply it in the collection path", "surface it in `$metadata`", "surface it in `$oas2`", "expose it over MCP").
- **Split class-DSL and builder-DSL work into sibling tasks** when they're substantial, or keep them in one task when the change is small and symmetric — but the task text must always name *both* DSLs and *both* spec trees so nothing is half-done.
- **Don't over-split one small file.** If several checks/methods all land on the same small class or file (e.g. four checks on one ~70-line cop), that's usually one task, not one task per check — splitting multiplies the implement-then-review round trip for tightly coupled edits that get reviewed together anyway regardless of task boundaries. Conversely, don't merge unrelated deliverables (code with docs, or two independent files with no shared logic) into one task to save time — see "never silently drop a planned task" above.
- A final task for the documentation impact named in the PRD.

For each task, write down: the full task text, which files it likely touches (both DSLs), the exact PRD excerpt (API snippet + expected I/O) that defines "done", and how it depends on earlier tasks. Order so each task builds on green predecessors.

**Write the plan to a file.** Save the full plan next to the PRD, named after it with a `-plan.md` ending — for `doc/prds/<slug>.md` write `doc/prds/<slug>-plan.md` (e.g. `doc/prds/orderby-support.md` → `doc/prds/orderby-support-plan.md`). The file links back to its PRD at the top and lists every task in order with, for each: a title, the full task text, likely files (both DSLs + both spec trees), the defining PRD excerpt, dependencies, and a status checkbox (`- [ ]` → `- [x]`). This file is the durable plan of record — each task's checkbox is ticked as that task lands (step 4c). If a `-plan.md` already exists, overwrite it with the freshly derived plan. Commit the new plan file on its own (e.g. `Add build plan for <slug>`) before starting task work, so each task commit stays focused on code.

Then mirror the plan into a `TodoWrite` list and proceed **directly** to execution — no sign-off, no pause. (You may briefly state the plan as you start, but as a status line, not a request for approval.)

### 4. Execute each task — implement, then review

For each task in order:

**a. Dispatch the implementer subagent** (Agent tool) with the prompt in *Implementer prompt* below. Give it the full task text, the PRD excerpt, the file pointers, and the hard rules. If it returns questions before working, answer them completely and re-dispatch — don't rush it into code.

Handle its final status:
- **DONE** → go to review.
- **DONE_WITH_CONCERNS** → read the concerns. If they bear on correctness or scope, resolve them before review; if they're observations, note and proceed.
- **NEEDS_CONTEXT** → supply what's missing, re-dispatch.
- **BLOCKED** → diagnose: context problem → add context, re-dispatch; needs more reasoning → re-dispatch on a more capable model; too large → split the task; PRD itself is wrong → stop and escalate to the user. Never re-dispatch the same model on the same prompt unchanged.

**b. Review the task.** Dispatch a review subagent with the *Review-task dispatch prompt* below, giving it the full task text, the PRD excerpt, and what changed (diff or file list/SHAs). It runs the `review-task` skill — spec compliance then code quality, gated — and returns one verdict:

- **REVIEW_OK** → commit (next step).
- **SPEC_GAPS** or **QUALITY_ISSUES** → re-dispatch the **same implementer** subagent with the reported list, then dispatch a fresh review subagent to re-review. Loop until `REVIEW_OK`.
- **NEEDS_CONTEXT** → you omitted something the review dispatch needed; supply it and re-dispatch.

**c. Commit the task.** Once review-task reports `REVIEW_OK`, tick this task's checkbox in the `-plan.md` file (`- [ ]` → `- [x]`), then commit just this task's changes — including the plan-file tick — with a focused message referencing the PRD (e.g. `git add -A && git commit`). One commit per task — never bundle multiple tasks into one commit, and never leave a reviewed task uncommitted. End the commit message with a co-author trailer naming **the model actually running this build** — not a hardcoded placeholder:

```
Co-Authored-By: Claude <model name and version, e.g. "Sonnet 5" or "Opus 4.8"> <noreply@anthropic.com>
```

**d. Mark the task complete** in `TodoWrite` (its `-plan.md` checkbox was ticked and committed in step c). Next task.

### 5. Final review

After all tasks: run `bundle exec rake` yourself to confirm the whole suite + RuboCop are green (recall CI runs `rake` four times to catch flaky tests — if you suspect flakiness, run it a couple more times). Then dispatch one final reviewer over the entire diff (`git diff main...HEAD`) checking the PRD as a whole is satisfied, both DSLs are in sync, docs were updated, the `## Features` index in `CLAUDE.md` carries a one-line entry for any note-worthy capability this PRD added, every task is committed, the `-plan.md` checkboxes are all ticked, and there are no loose ends or uncommitted changes (`git status` clean). The final review runs **with** the PRD and plan still present — it verifies the plan's checkboxes are all ticked. It can lean on each task's recorded spec/quality verdicts rather than re-deriving them from scratch — its unique job is the aggregate check below, which only a full-diff view can catch.

Give the final reviewer the PRD's own section headers (**External API**, **Behavior & expected I/O**, **Scope**, **Documentation impact**) and have it confirm each one has a corresponding change in the diff, or an explicit, justified "not applicable" — checking the diff in isolation only proves what *was* built is fine, not that nothing was dropped. A task that quietly disappeared from the plan produces the same clean `rake` and clean per-task reviews as full coverage; cross-referencing against the PRD's own table of contents is the only point in the process that catches that.

### 6. Retire the PRD and plan

Once the final reviewer is satisfied, `bundle exec rake` is green, and every task is committed, remove the built PRD and its `-plan.md` in **one separate, final commit** — this is the last commit on the branch, made only after final review has passed:

```
git rm --ignore-unmatch doc/prds/<slug>.md doc/prds/<slug>-plan.md
git commit  # "Remove PRD and plan for <slug> — implemented"
```

Give this commit the same co-author trailer used for every task commit (step 4c). The `--ignore-unmatch` flag keeps this robust when only one of the two files exists (e.g. a build resumed from an older session): `git rm` removes whichever file(s) are present and won't fail the cleanup over the missing one. Report what was built, the branch name, the commits — **including this cleanup commit** — and the final `rake` result. **Do not push and do not open a PR** — leave the branch local for the user. Mention they can push/PR it themselves when ready.

## Subagent prompt templates

Construct each subagent's prompt from these. Provide full text — never tell a subagent to "go read the PRD/plan"; you curate exactly what it needs.

### Implementer prompt

> You are implementing one task in the `odata_duty` Ruby gem. Work strictly test-first per `.claude/skills/test-driven-development/SKILL.md`: write one failing test, run it, watch it fail for the right reason, then write the minimal code to pass, then refactor while green.
>
> **Task:** `<full task text>`
>
> **Definition of done (from the PRD):** `<PRD excerpt: API snippet + expected I/O + relevant error cases>`
>
> **Repo rules you must follow:** `<paste the applicable hard rules from above, in full — at minimum: both DSLs + both spec trees where applicable, public-API-only tests, style/RuboCop metrics, green bundle exec rake, debug a red rake from live tool output not speculation, and the od_* convention over new public surface. A fresh subagent has no access to this file's "above" — paste the actual text, don't just reference it.>`
> - State explicitly if only one DSL applies to this task, and why.
> - You may run a single file with `bundle exec rspec <path>` while iterating, but finish on a full green `rake`.
>
> Likely files: `<file pointers>`. Context: `<where this task fits>`.
>
> **Do not commit** — leave your changes in the working tree. The controller commits the task after `review-task` reports `REVIEW_OK`, so review fixes stay in the same single commit.
>
> If anything blocks you or the task is ambiguous, **ask before coding**. When done, report status as one of `DONE`, `DONE_WITH_CONCERNS` (list them), `NEEDS_CONTEXT` (say what), or `BLOCKED` (say why), plus a short summary of files changed and the `rake` result. Your reply is consumed by a controller, not a human — be terse and factual.

### Review-task dispatch prompt

> You are reviewing one task's implementation for the `odata_duty` Ruby gem, dispatched by this repo's `/build` controller.
>
> Invoke the `review-task` skill (Skill tool, `skill: "review-task"`) with these arguments:
>
> - **Task:** `<full task text>`
> - **Spec (PRD excerpt):** `<PRD excerpt: API snippet + expected I/O + relevant error cases>`
> - **What changed:** `<git diff or file list / SHAs>`
>
> Report back exactly what `review-task` tells you to report (`REVIEW_OK`, `SPEC_GAPS: ...`, `QUALITY_ISSUES: ...`, or `NEEDS_CONTEXT: ...`) — don't paraphrase or summarize it.

## Red flags — never

This is not a recap of the steps above — each item here is something not already stated as an imperative in its own step.

- **Push, open a PR, or commit to `main`/`master`.** Work stays as local commits on a feature branch (steps 2 and 6) — worth this repetition given the cost of getting it wrong.
- **Dispatch implementer subagents in parallel** — they conflict on files.
- **Let an implementer's self-review stand in for the `review-task` dispatch.**
- **Tell a subagent to read the PRD/plan itself** — curate the exact text it needs instead.
