---
description: Implement a PRD from doc/prds/ end to end — derive a task plan, then execute each task with a fresh implementer subagent followed by two-stage review (spec compliance, then code quality). Writes code and tests, and commits each task on a feature branch. Never pushes.
argument-hint: <prd name or path in doc/prds/>
allowed-tools: Agent, Bash, Read, Edit, Write, Glob, Grep, TodoWrite
---

# Build a PRD

Take the PRD identified by `$ARGUMENTS` (a filename, slug, or path under `doc/prds/`) and carry it **all the way from PRD to commit** — code, tests, and a commit per task on a feature branch — by acting as a **controller** that dispatches a fresh subagent per task and reviews each one in two stages. You **never push and never open a PR**; the work lands as commits on a local branch for the user to review.

You are the controller. You hold the plan, curate context, dispatch subagents, and gate quality. You do **not** write implementation code yourself — that is the implementer subagent's job. Your context stays clean for coordination.

## Why subagents

Each task goes to a fresh subagent whose entire context you construct: the task text, the relevant PRD excerpt, and the repo rules it must follow. It never inherits your history. This keeps each subagent focused and preserves your context for orchestration. **Fresh subagent per task + two-stage review (spec, then quality) = high quality, fast iteration.**

## Continuous execution

There is **no approval checkpoint**. Once invoked, derive the plan from the PRD using the codebase's own best practices (below) and **go** — execute **all** tasks without pausing to check in. Do not present the plan for sign-off, and do not emit "Should I continue?" prompts or per-task progress summaries; the user already chose to build this PRD by running the command. Stop only for: a `BLOCKED` status you cannot resolve, a genuine ambiguity in the PRD that prevents correct work, or all tasks complete.

## This repo's hard rules (every subagent must honor)

These come from `CLAUDE.md` and are non-negotiable. Bake them into every implementer and reviewer prompt:

- **Two parallel DSLs — keep both in sync.** Most features must be implemented in **both** the class-based DSL (`lib/odata_duty.rb`, `entity_type.rb`, `complex_type.rb`, `enum_type.rb`) and the builder DSL (`lib/odata_duty/schema_builder.rb` + `schema_builder/*` + `set_resolver.rb`), with matching specs under **both** `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`. If a task touches one DSL, confirm whether the other needs the same change — usually it does.
- **TDD is mandatory.** Follow the repo's own skill: `.claude/skills/test-driven-development/SKILL.md`. No production code without a failing test first. Watch the test fail for the right reason before implementing.
- **Tests use only the gem's public API** (`AGENTS.md`) — never reach into internal classes/methods (`Executor`, `*Wrapper`, parslet, ERB, mappers). Avoid the anti-patterns in `.claude/skills/test-driven-development/testing-anti-patterns.md`.
- **Style:** two-space indent, **99-char line limit**, Ruby 3 syntax. RuboCop metrics are tight (`.rubocop.yml`: `MethodLength` 13, `Class/ModuleLength` 99, `AbcSize` 30, `CyclomaticComplexity` 7) — keep methods small rather than adding inline disables.
- **Green gate:** `bundle exec rake` runs **RSpec and RuboCop** and is the definition of done for every task. A task isn't complete until it's green.
- **Docs:** if the PRD's "Documentation impact" section names a `doc/` guide to add or extend, that is a task too. Bump `spec.version` in `odata_duty.gemspec` only if the user asks.

## Process

### 1. Locate and read the PRD

Resolve `$ARGUMENTS` to a file in `doc/prds/` (try exact path, then `doc/prds/<arg>.md`, then a `Glob` match; if several match or none do, ask). Read it fully. If `$ARGUMENTS` is empty, list `doc/prds/*.md` and ask which one.

### 2. Branch — never build on main

Check the current branch with `git status`. If it's `main`, create and switch to a feature branch named after the PRD (e.g. `git checkout -b prd/orderby-support`) before any code changes — do this automatically; branching off `main` is itself the safeguard, so it needs no prompt. **Never** commit implementation work directly to `main`/`master`. If the working tree has unrelated uncommitted changes, note them and continue on the new branch.

### 3. Derive the task plan — then immediately execute it

A PRD is a spec, not a task list — you must decompose it, guided by the codebase's own best practices: the **hard rules** above, the existing structure of `lib/` and the two spec trees, and how comparable features (e.g. `$search`, `$select`) are already split across the DSLs. Read the PRD's **External API**, **Behavior & expected I/O**, **Common error cases**, and **Scope** sections and produce an ordered list of small, independent, testable tasks. Good task boundaries for this repo:

- One task per coherent slice of behavior (e.g. "parse and validate the new query option", "apply it in the collection path", "surface it in `$metadata`", "surface it in `$oas2`", "expose it over MCP").
- **Split class-DSL and builder-DSL work into sibling tasks** when they're substantial, or keep them in one task when the change is small and symmetric — but the task text must always name *both* DSLs and *both* spec trees so nothing is half-done.
- A final task for the documentation impact named in the PRD.

For each task, write down: the full task text, which files it likely touches (both DSLs), the exact PRD excerpt (API snippet + expected I/O) that defines "done", and how it depends on earlier tasks. Order so each task builds on green predecessors.

**Write the plan to a file.** Save the full plan next to the PRD, named after it with a `-plan.md` ending — for `doc/prds/<slug>.md` write `doc/prds/<slug>-plan.md` (e.g. `doc/prds/orderby-support.md` → `doc/prds/orderby-support-plan.md`). The file links back to its PRD at the top and lists every task in order with, for each: a title, the full task text, likely files (both DSLs + both spec trees), the defining PRD excerpt, dependencies, and a status checkbox (`- [ ]` → `- [x]`). This file is the durable plan of record — each task's checkbox is ticked as that task lands (step 4d). If a `-plan.md` already exists, overwrite it with the freshly derived plan. Commit the new plan file on its own (e.g. `Add build plan for <slug>`) before starting task work, so each task commit stays focused on code.

Then mirror the plan into a `TodoWrite` list and proceed **directly** to execution — no sign-off, no pause. (You may briefly state the plan as you start, but as a status line, not a request for approval.)

### 4. Execute each task — implement, then two-stage review

For each task in order:

**a. Dispatch the implementer subagent** (Agent tool) with the prompt in *Implementer prompt* below. Give it the full task text, the PRD excerpt, the file pointers, and the hard rules. If it returns questions before working, answer them completely and re-dispatch — don't rush it into code.

Handle its final status:
- **DONE** → go to spec review.
- **DONE_WITH_CONCERNS** → read the concerns. If they bear on correctness or scope, resolve them before review; if they're observations, note and proceed.
- **NEEDS_CONTEXT** → supply what's missing, re-dispatch.
- **BLOCKED** → diagnose: context problem → add context, re-dispatch; needs more reasoning → re-dispatch on a more capable model; too large → split the task; PRD itself is wrong → stop and escalate to the user. Never re-dispatch the same model on the same prompt unchanged.

**b. Spec-compliance review first.** Dispatch a reviewer subagent with the *Spec-compliance reviewer prompt*. It checks the code against the PRD excerpt: every required behavior present, nothing extra, **both DSLs and both spec trees covered**, expected I/O matches. If it finds gaps, the **same implementer** subagent fixes them and you re-review. Loop until ✅. Do not start quality review until spec review is ✅.

**c. Code-quality review second.** Dispatch a reviewer subagent with the *Code-quality reviewer prompt*. It checks TDD was followed (tests written first and meaningful, public-API-only, no mock-behavior tests), RuboCop is clean without gratuitous disables, methods stay within the metrics, names read like the surrounding code, and `bundle exec rake` is green. Implementer fixes, you re-review, loop until ✅.

**d. Commit the task.** Once both reviews are ✅ and `bundle exec rake` is green, tick this task's checkbox in the `-plan.md` file (`- [ ]` → `- [x]`), then commit just this task's changes — including the plan-file tick — with a focused message referencing the PRD (e.g. `git add -A && git commit`). One commit per task — never bundle multiple tasks into one commit, and never leave a reviewed task uncommitted. End the commit message with the required co-author trailer:

```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

**e. Mark the task complete** in `TodoWrite` (its `-plan.md` checkbox was ticked and committed in step d). Next task.

### 5. Final review

After all tasks: run `bundle exec rake` yourself to confirm the whole suite + RuboCop are green (recall CI runs `rake` four times to catch flaky tests — if you suspect flakiness, run it a couple more times). Then dispatch one final reviewer over the entire diff (`git diff main...HEAD`) checking the PRD as a whole is satisfied, both DSLs are in sync, docs were updated, every task is committed, the `-plan.md` checkboxes are all ticked, and there are no loose ends or uncommitted changes (`git status` clean). Report what was built, the branch name, the commits, and the final `rake` result. **Do not push and do not open a PR** — leave the branch local for the user. Mention they can push/PR it themselves when ready.

## Subagent prompt templates

Construct each subagent's prompt from these. Provide full text — never tell a subagent to "go read the PRD/plan"; you curate exactly what it needs.

### Implementer prompt

> You are implementing one task in the `odata_duty` Ruby gem. Work strictly test-first per `.claude/skills/test-driven-development/SKILL.md`: write one failing test, run it, watch it fail for the right reason, then write the minimal code to pass, then refactor while green.
>
> **Task:** `<full task text>`
>
> **Definition of done (from the PRD):** `<PRD excerpt: API snippet + expected I/O + relevant error cases>`
>
> **Repo rules you must follow:**
> - Implement in **both** DSLs where applicable — class-based (`lib/odata_duty.rb`, `entity_type.rb`, `complex_type.rb`, `enum_type.rb`) and builder (`lib/odata_duty/schema_builder.rb`, `schema_builder/*`, `set_resolver.rb`) — with specs under **both** `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`. State explicitly if only one DSL applies and why.
> - Tests use the gem's **public API only** — never internal classes. Avoid the anti-patterns in `.claude/skills/test-driven-development/testing-anti-patterns.md`.
> - 99-char lines, two-space indent, Ruby 3. Keep methods within RuboCop metrics (MethodLength 13, AbcSize 30, etc.) — small methods over inline disables.
> - Run `bundle exec rake` (RSpec + RuboCop) until green. You may run a single file with `bundle exec rspec <path>` while iterating, but finish on a full green `rake`.
> - Prefer extending the `od_*` convention over adding new public surface.
>
> Likely files: `<file pointers>`. Context: `<where this task fits>`.
>
> **Do not commit** — leave your changes in the working tree. The controller commits the task after both reviews pass, so review fixes stay in the same single commit.
>
> If anything blocks you or the task is ambiguous, **ask before coding**. When done, report status as one of `DONE`, `DONE_WITH_CONCERNS` (list them), `NEEDS_CONTEXT` (say what), or `BLOCKED` (say why), plus a short summary of files changed and the `rake` result. Your reply is consumed by a controller, not a human — be terse and factual.

### Spec-compliance reviewer prompt

> Review whether an implementation matches its spec. Do **not** assess style here — only spec compliance.
>
> **The spec (PRD excerpt):** `<PRD excerpt>`
>
> **What changed:** `<git diff or file list / SHAs>`
>
> Verify: every required behavior is present; the external API matches the PRD's snippets exactly (DSL surface, hook contracts, query option, outputs); expected I/O matches (collection/individual JSON, `$metadata` XML, `$oas2` JSON, MCP shape as applicable); listed error cases are handled; **both DSLs and both spec trees are covered** if the change applies to both; and nothing beyond the spec was added. Report `SPEC_OK`, or list concrete gaps and extras. Be specific and terse — a controller reads this.

### Code-quality reviewer prompt

> Review code quality of this change in the `odata_duty` gem. Assume spec compliance is already confirmed.
>
> **What changed:** `<git diff / SHAs>`
>
> Check: TDD was genuinely followed (tests are meaningful, behavior-focused, public-API-only, not testing mocks); `bundle exec rake` passes (RSpec **and** RuboCop); no gratuitous RuboCop disables; methods stay within metrics; new code reads like the surrounding code (naming, idiom, `od_*` convention); the two DSLs are consistent with each other; docs updated if the PRD required it. Report `QUALITY_OK`, or list concrete issues by severity (Critical / Important / Minor). Terse — a controller reads this.

## Red flags — never

- Implement or commit on `main`/`master` (always branch first, automatically).
- Pause to ask the user to approve or sign off on the plan (derive it and go).
- Write implementation code yourself as the controller (dispatch a subagent).
- Skip either review, or start quality review before spec review is ✅.
- Move to the next task while a review has open issues, or skip the re-review after a fix.
- Dispatch implementer subagents in parallel (they conflict on files).
- Tell a subagent to read the PRD/plan instead of providing the text it needs.
- Let an implementer's self-review stand in for the two review stages.
- Mark a task done while `bundle exec rake` is red.
- Commit a task before both reviews are ✅, or bundle multiple tasks into one commit.
- **Push, open a PR, or commit to `main`** — work stays as local commits on the feature branch.
