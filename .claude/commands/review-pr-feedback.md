# Review PR Feedback

Pulls down a GitHub PR's description and all review comments, walks through each piece of feedback interactively to decide what to implement, then implements the collected items directly in this repo.

> **CRITICAL: Use `AskUserQuestion` for ALL decisions throughout this process. Never assume intent — always ask.**

This is the `odata_duty` gem: a single Ruby repo (no Rails app, no monorepo subdirs). The only CI/local quality gate is `bundle exec rake` (RSpec **and** RuboCop). The same gate runs as a pre-commit hook (`.githooks/pre-commit`, enabled via `core.hooksPath`), so a commit is blocked unless the full suite is green — bypass a deliberate WIP commit with `git commit --no-verify`. Keep that in mind everywhere below.

## Usage

```
/review-pr-feedback                                     # auto-detect from current branch
/review-pr-feedback https://github.com/owner/repo/pull/123
```

## Process

### 1. Resolve the PR

**If `$ARGUMENTS` contains a URL:** extract `owner`, `repo`, and `pull_number` from it.

Example: `https://github.com/grantps/odata_duty-ruby/pull/456` → owner=`grantps`, repo=`odata_duty-ruby`, pull_number=`456`

**If `$ARGUMENTS` is empty:** detect the PR from the current branch.

1. Run `git rev-parse --abbrev-ref HEAD` to get the current branch name
2. Use `gh pr view --json number,title,url,state,headRefName,baseRefName` (or `gh pr list --head <branch>`) to find the open PR for the branch
3. If exactly one PR is found, proceed with it and tell the user which PR was detected
4. If none or multiple are found, ask the user to provide the PR URL explicitly

Prefer the `gh` CLI for all GitHub access in this repo. If GitHub MCP tools are available, they may be used instead, but `gh` is the baseline.

### 2. Fetch PR Data

Fetch in parallel:

- `gh pr view <n> --json title,body,state,author,baseRefName,headRefName,headRefOid` — PR metadata and description
- `gh api repos/{owner}/{repo}/pulls/{n}/comments` — inline review comments (with `position`, `path`, `line`)
- `gh api repos/{owner}/{repo}/pulls/{n}/reviews` — top-level review bodies and states
- `gh pr checks <n>` — CI check runs and their conclusions

Display a summary to the user:

```
PR #123: <title>
Author: <author>  |  State: <state>  |  Base: <base> ← <head>

<N> review comment threads found.
Description has feedback: <yes/no>

CI Checks:
  ✅ <check name>
  ❌ <check name> — <conclusion> (<link if available>)
  ⏳ <check name> (pending)
```

If any checks are failing, call this out prominently before moving to the triage phase.

#### CI Failure Investigation

CI for this repo is just two workflows:

- **`.github/workflows/ruby.yml`** — runs `bundle exec rake` (RSpec + RuboCop) across Ruby `3.2`, `3.3`, `3.4`, `4.0`. It runs `rake` **four times** to surface flaky tests.
- **`.github/workflows/devcontainer.yml`** — builds the dev container image and runs `bundle install` + `claude --version`.

The local equivalent of the main check is simply **`bundle exec rake`** (or `bundle exec rspec` / `bundle exec rubocop` to narrow it down). The `.githooks/pre-commit` hook runs the same `rake` before every commit, so a failing check on CI usually means the hook was bypassed (`--no-verify`) or not enabled locally (`git config core.hooksPath .githooks`).

For each failing check, investigate why it wasn't caught before or at commit time:

1. **Was `bundle exec rake` run locally?** If the failure is an RSpec or RuboCop failure, it would have been caught by running `rake`. The gap is process: `rake` wasn't run before push.
2. **Is it Ruby-version-specific?** The matrix spans 3.2–4.0. A failure on only some versions points to a version-specific API/syntax issue, not something a single local run would catch — note which versions failed.
3. **Is it flaky?** `ruby.yml` runs `rake` four times precisely because some specs are flaky. If the same check passes on other runs/PRs, treat it as flakiness rather than PR content.
4. **Is it the devcontainer build?** That failure is environment/image-specific (Dockerfile, `bin/setup`, bundler), not something a normal test run surfaces.

For each failing check, produce a **CI gap item** and add it to the feedback list with:

- **Source**: `ci-failure`
- **Check name**: the failing check
- **Gap**: what wasn't caught locally and why (didn't run `rake`, version-specific, flaky, devcontainer-only, etc.)
- **Suggested action**: one of —
  - Fix the underlying RSpec/RuboCop failure
  - Add a RuboCop rule or a regression test that would have caught it
  - Investigate and stabilize (or mark) a flaky spec
  - Fix the Ruby-version-specific incompatibility
  - No action needed (environment-only or transient)

These CI gap items are treated as first-class feedback items in the walkthrough (Step 4), appearing after any review comments. When the user reaches one, "Implement it" means acting on the suggested fix.

### 3. Collect & Organize Feedback

Build an ordered list of all feedback items from:

1. **CI gap items** — one per failing check, generated by the investigation above — **always first**
2. **PR description** — if it contains actionable feedback, requested changes, or TODOs
3. **Review comments** — each distinct inline comment thread (grouped by file+line where possible)
4. **General review comments** — top-level review body text (not inline)

For each item, record:

- **Source**: description | review | inline-comment | ci-failure
- **Author**: who left it
- **File + line** (for inline comments)
- **Body**: the comment text
- **Resolved**: whether the thread is already marked resolved

Skip already-resolved threads unless the user asks to include them.

#### Staleness check for inline comments

Two automatic exclusions happen before the walkthrough, in this order:

**Outdated comments (GitHub drift):** When the API returns an inline comment with `position: null`, the comment's source line no longer exists in the current diff. Exclude it immediately without reading the file; add to "Stale — auto-excluded" with reason "outdated — source line no longer in diff."

**Already-addressed check:** For every remaining inline comment (position is not null), **before** adding it to the walkthrough list:

1. Read the current file at the referenced path, around the referenced line (± 10 lines of context).
2. Compare what the comment requests against what the code currently does.
3. If the code already implements the suggestion (the guard is in place, the method exists, the test pattern is used, etc.), mark the item **stale** and exclude it from the walkthrough list.
4. Collect stale items separately; they appear in the final summary under "Stale — auto-excluded" with a one-line explanation per item.

Perform both checks for all inline comments **before** presenting the scope question to the user, so the count shown reflects only genuinely open items. Briefly tell the user how many items were auto-excluded as stale.

Use `AskUserQuestion` to confirm scope before walking through items:

```typescript
{
  questions: [
    {
      question: "I found <N> open feedback items. How would you like to proceed?",
      header: "Feedback scope",
      multiSelect: false,
      options: [
        {
          label: "Walk through all open items",
          description: "Review every unresolved comment one by one",
        },
        {
          label: "Walk through all items including resolved",
          description: "Include already-resolved threads for completeness",
        },
        {
          label: "Show me a summary first",
          description: "Display all items, then I'll pick which ones to discuss",
        },
      ],
    },
  ];
}
```

### 4. Walk Through Each Feedback Item

For each item, present the full context then ask what to do with it:

**Present the item:**

```
─────────────────────────────────────────
[N of M] <source>  |  <author>
File: <path>:<line>   (if inline)
─────────────────────────────────────────
<comment body>
─────────────────────────────────────────
```

**Then ask (AskUserQuestion):**

```typescript
{
  questions: [
    {
      question: "What would you like to do with this feedback?",
      header: "Feedback action",
      multiSelect: false,
      options: [
        {
          label: "Implement it",
          description: "Fix or change the code as requested",
        },
        {
          label: "Discuss first",
          description: "Talk through the feedback before deciding",
        },
        {
          label: "Skip — already handled",
          description: "This was already addressed",
        },
        {
          label: "Skip — won't fix",
          description: "Intentional decision not to act on this",
        },
        {
          label: "Defer",
          description: "Track it but don't implement now",
        },
      ],
    },
  ];
}
```

#### If "Discuss first"

Ask follow-up questions using `AskUserQuestion` to understand the feedback:

- What part is unclear?
- Does it conflict with existing constraints (the 99-char limit, tightened RuboCop metrics, public-API-only tests)?
- Is there a simpler alternative?

Continue until the user reaches a decision (implement / skip / defer).

#### If "Implement it"

Note it in the "to implement" list and continue to the next item. Do **not** implement immediately — collect ALL items marked "implement" first, then implement them together after the walkthrough.

When you do implement, follow this repo's rules:

- **Follow TDD** — write or update the failing spec first, then make it pass. Use the `test-driven-development` skill.
- **Keep both DSLs in sync** — most features must change in both the class-based DSL (`spec/odata_duty/entity_set/**`) and the builder DSL (`spec/odata_duty/schema_builder/**`). See CLAUDE.md "Two parallel DSLs."
- **Tests use only the public API** — never test internal classes/methods directly (`AGENTS.md`).
- **Respect the style budget** — two-space indent, 99-char lines, tightened RuboCop metrics (`MethodLength` 13, `ClassLength`/`ModuleLength` 99, `AbcSize` 30). Keep methods small rather than adding inline disables.
- **Always finish with `bundle exec rake`** and make it green before considering an item done.

After all items have been walked through, present the consolidated list of code changes and ask for confirmation before starting:

```typescript
{
  questions: [
    {
      question: "Ready to start implementing these <N> changes?",
      header: "Start implementation",
      multiSelect: false,
      options: [
        {
          label: "Yes — implement them now (TDD, both DSLs, then bundle exec rake)",
          description: "Make the collected changes following the repo's rules",
        },
        {
          label: "Not yet — I want to review or adjust the list first",
          description: "Pause here before starting",
        },
      ],
    },
  ];
}
```

Only begin implementing after the user confirms. Pure documentation files (`README.md`, `CLAUDE.md`, `AGENTS.md`, files under `doc/`) may be edited directly without the confirmation gate when they are the only change.

#### After deciding to implement — ask how to prevent recurrence

Once an implement decision is made, ask:

```typescript
{
  questions: [
    {
      question: "How do we prevent this from happening again?",
      header: "Prevent recurrence",
      multiSelect: false,
      options: [
        {
          label: "Document a rule",
          description: "Add a rule to CLAUDE.md, AGENTS.md, README.md, or a doc/ guide so future contributors know the pattern",
        },
        {
          label: "Add a regression test",
          description: "Add an RSpec example (via the public API) that would have caught this",
        },
        {
          label: "Add/adjust a RuboCop rule",
          description: "Tighten or add a lint rule in .rubocop.yml so rake catches it automatically",
        },
        {
          label: "One-off — nothing to prevent",
          description: "This is specific to this PR, nothing generalizable",
        },
      ],
    },
  ];
}
```

##### If "Document a rule"

Ask where it should go:

```typescript
{
  questions: [
    {
      question: "Where should this rule be documented?",
      header: "Doc location",
      multiSelect: false,
      options: [
        {
          label: "CLAUDE.md — guidance for Claude / project-wide rule",
          description: "Architecture, conventions, the od_* and two-DSL rules",
        },
        {
          label: "AGENTS.md — agent/contributor working rules",
          description: "e.g. public-API-only testing and similar working agreements",
        },
        {
          label: "README.md — user-facing project documentation",
          description: "General project guidance and usage visible to all consumers",
        },
        {
          label: "doc/<guide>.md — feature/topic guide",
          description: "A focused guide under doc/ (using_filter, using_search, mcp_crash_course, etc.)",
        },
      ],
    },
  ];
}
```

If none of the options fit, the user can type a custom file path. Draft the documentation entry, show it to the user for approval, and write it only after approval.

##### If "Add a regression test" or "Add/adjust a RuboCop rule"

Add the test or lint change to the "implement" list — it goes through the same TDD + `bundle exec rake` flow as any other code change. Remember to add specs in **both** spec trees when the behavior exists in both DSLs.

#### If "Skip — won't fix"

Ask why, to capture the learning:

```typescript
{
  questions: [
    {
      question: "Why are you skipping this?",
      header: "Skip reason",
      multiSelect: false,
      options: [
        {
          label: "Intentional design decision",
          description: "We deliberately chose a different approach",
        },
        {
          label: "Out of scope for this PR",
          description: "Valid feedback but belongs in a separate issue/PR",
        },
        {
          label: "Disagree with the feedback",
          description: "The reviewer may have misunderstood the context",
        },
        {
          label: "Other",
          description: "Something else — I'll explain",
        },
      ],
    },
  ];
}
```

Record the reason in the learnings log.

#### If "Defer"

Note it with a short description so it can be included in the final summary.

### 5. Capture Learnings

After all feedback items have been walked through, ask about implicit learnings:

```typescript
{
  questions: [
    {
      question: "Before we wrap up — any learnings from this review session worth documenting?",
      header: "Learnings",
      multiSelect: true,
      options: [
        {
          label: "Patterns the reviewer highlighted as good",
          description: "Things we should do more of",
        },
        {
          label: "Recurring feedback pattern",
          description: "This type of feedback comes up often — worth a general rule",
        },
        {
          label: "Process observation",
          description: "Something about how we work that could be improved",
        },
        {
          label: "Nothing to document",
          description: "One-off feedback, nothing generalizable",
        },
      ],
    },
  ];
}
```

For each learning identified:

1. Discuss until you fully understand the "why"
2. Use `AskUserQuestion` to propose a documentation location (CLAUDE.md, AGENTS.md, README.md, or a `doc/` guide)
3. Draft the documentation entry and show it to the user for approval
4. Write it only after approval

### 6. Final Summary

Print a structured summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PR #<N> Feedback Walkthrough — Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Implemented (<count>):
  • <brief description> [<file>:<line>]

Deferred (<count>):
  • <brief description> — reason: <reason>

Skipped (<count>):
  • <brief description> — reason: <reason>

Stale — auto-excluded (<count>):
  • <brief description> — already addressed in <file>:<line>

Learnings documented (<count>):
  • <learning> → <file>

rake status: <green / red — details>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Common Mistakes

| Mistake | Fix |
| ------- | --- |
| Asking multiple questions at once | One `AskUserQuestion` call per decision point |
| Moving to next item before resolving current | Wait for an explicit action decision before advancing |
| Implementing items one at a time as you go | Collect all "implement" items, confirm the list, then implement together |
| Changing one DSL but not the other | Most features live in both the class DSL and builder DSL — update both spec trees |
| Testing internal classes/methods | Tests use only the gem's public API (`AGENTS.md`) |
| Considering an item done without running `rake` | Finish every implement item with a green `bundle exec rake` |
| Skipping the prevent recurrence step | After every "implement" decision, ask how to prevent this from happening again |
| Skipping the learnings step | Always ask about implicit learnings even when there are no "won't fix" skips |
| Documenting without user approval | Show proposed documentation, get approval, then write |
| Treating resolved threads as unresolved | Respect resolved status unless user explicitly asks to include them |
| Skipping CI gap investigation | For every failing check, always investigate why `bundle exec rake` (or the matrix) didn't catch it locally |
| Walking CI failures after review comments | CI failures are always walked through first, before any review or description feedback |
| Skipping the staleness check for inline comments | Before adding any inline comment to the walkthrough list, read the current file at the referenced path/line and verify it's still applicable |
| Showing outdated comments (position: null) | Exclude immediately without reading the file — source line no longer exists in the diff |

## Red Flags — You're Doing It Wrong

- Moving to the next feedback item before the user gave an action decision
- Walking through review comments before all CI failure items are done
- Skipping the "prevent recurrence?" question after an implement decision
- Implementing a behavior change in only one DSL when it exists in both
- Marking an item done without a green `bundle exec rake`
- Writing documentation without showing the user the draft first
- Starting implementation without first confirming the consolidated list with the user
- Skipping the final summary
- Walking through an inline comment without first reading the current file at the referenced line to check whether it is already addressed
- Walking through an inline comment whose API `position` is `null` — those are outdated and must be excluded without reading the file

**If any of these happen: STOP, go back, handle the current item properly.**

ARGUMENTS: $ARGUMENTS
