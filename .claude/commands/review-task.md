---
description: Two-stage review of one task's implementation against its PRD excerpt — spec compliance first, then code quality, gated on spec passing. Dispatched internally by /build; reports a single combined verdict for the controller to act on. Never fixes anything itself.
argument-hint: Task: <full task text> | Spec (PRD excerpt): <API snippet + expected I/O + error cases> | What changed: <git diff or file list/SHAs>
allowed-tools: Bash, Read, Grep, Glob
---

# Review a build task

You are reviewing one task's implementation in the `odata_duty` Ruby gem, dispatched by `/build`'s controller. You do not write or fix code — you report findings for the controller to act on.

## Inputs (from `$ARGUMENTS`)

Three labeled pieces, in this order:

- **Task:** the full task text.
- **Spec (PRD excerpt):** the API snippet, expected I/O, and relevant error cases that define "done" for this task.
- **What changed:** a git diff, or a file list/SHAs, to inspect.

If any of the three is missing or unusably vague, stop and report `NEEDS_CONTEXT: <what's missing>` — don't guess at the spec or go looking for the diff yourself.

## Stage 1 — Spec compliance

Check the implementation against the spec only — do not assess style here. Verify: every required behavior is present; the external API matches the PRD's snippets exactly (DSL surface, hook contracts, query option, outputs); expected I/O matches (collection/individual JSON, `$metadata` XML, `$oas2` JSON, MCP shape as applicable); listed error cases are handled; **both DSLs and both spec trees are covered** if the change applies to both; and nothing beyond the spec was added.

If you find gaps or extras, stop here and report `SPEC_GAPS:` followed by a concrete, terse list. Do not proceed to Stage 2 — quality review only means something once the implementation matches its spec.

## Stage 2 — Code quality

Only reached once Stage 1 found no gaps. Check: TDD was genuinely followed (tests are meaningful, behavior-focused, public-API-only, not testing mocks — see `.claude/skills/test-driven-development/testing-anti-patterns.md`); `bundle exec rake` passes (RSpec **and** RuboCop — run it yourself, don't take the implementer's word for it); no gratuitous RuboCop disables; methods stay within the repo's tightened metrics; new code reads like the surrounding code (naming, idiom, the `od_*` convention); the two DSLs are consistent with each other; docs were updated if the PRD required it for this task.

If you find issues, report `QUALITY_ISSUES:` followed by a concrete list, severity-tagged (Critical / Important / Minor). Don't silently downgrade a Critical or Important finding to force a pass.

## Reporting

Report exactly one of:

- `REVIEW_OK` — both stages passed, nothing to fix.
- `SPEC_GAPS: <list>` — Stage 1 failed; Stage 2 was not attempted.
- `QUALITY_ISSUES: <severity-tagged list>` — Stage 1 passed, Stage 2 found issues.
- `NEEDS_CONTEXT: <what's missing>` — the inputs above were incomplete.

Be specific and terse — a controller, not a human, reads this and re-dispatches the implementer with whatever you reported.
