# Conventions

This directory is the single source of truth for scoped guidance — the
judgment calls a linter or formatter cannot enforce. It implements the Agent
Documentation Structure Standard. Universal, always-apply rules live in the
root `AGENTS.md`; anything a tool can enforce lives in that tool.

## The three layers

| Layer | For | Trigger | Delivered by |
| --- | --- | --- | --- |
| 1 Root file | Universal rules | Always loaded | `AGENTS.md` |
| 2 Scoped rules | Guidance for a path, an API / construct, or both | A **write** to a matching **path** and/or matching written **content** (regex) | Pre/PostToolUse hooks |
| 3 Intent skills | Task-nature guidance | Skill match | Generated `.claude/skills/*/SKILL.md` |

## Frontmatter

```yaml
---
paths: ["src/**"]              # inject when writing to a matching path
contents: ['\bTODO\b']        # inject when written code matches (PCRE2)
skill: true                    # Layer 3: generate a skill wrapper
description: "Use when ..."    # required iff skill: true; must start with "Use when"
---
```

- `paths` only → fires on any write to a matching path
- `contents` only → fires when written code matches, anywhere
- `paths` + `contents` → **AND**: both must match
- `skill: true` is independent and may combine with either
- no frontmatter → reference-only: reachable by link, never triggered

Rules are injected only when the agent **writes**. A read injects nothing;
it only tells agent-apropos that a convention doc is already in the model's
context, so no later write re-injects it. That needs a read that both
completed and covered the whole doc, so read tools are wired on the
post-execution event and a partial (offset/limit) read is ignored.

## Writing a rule

- One concern per file; keep it short — tight rules get read, long ones get skimmed.
- State **what** the rule is, **why** it exists, and a verification criterion.
- Add an optional `## Verify` heading; `agent-apropos review` harvests it as a checklist item.

Claude Code delivers via PreToolUse `additionalContext`; run
`agent-apropos doctor` to verify the version. OpenCode delivers via
`tool.execute.before` and `tool.execute.after`, injecting context with
`noReply: true` through the generated plugin. Gemini CLI and GitHub
Copilot CLI both have no pre-edit context-injection event (Gemini's
`BeforeTool` and Copilot's `preToolUse` can only override arguments or
block/allow the call), so they deliver via their post-edit hook instead
(`AfterTool` for Gemini, `postToolUse` for Copilot) — rules still fire,
just after the edit rather than before it. Codex CLI's own PreToolUse
*can* inject context, so it delivers the same way Claude Code does; its
`apply_patch` tool can bundle several files' edits into one call, which
agent-apropos matches and injects per file.