# Conventions

This directory is the single source of truth for scoped guidance — the
judgment calls a linter or formatter cannot enforce. It implements the Agent
Documentation Structure Standard. Universal, always-apply rules live in the
root `AGENTS.md`; anything a tool can enforce lives in that tool.

## The four layers

| Layer | For | Trigger | Delivered by |
| --- | --- | --- | --- |
| 1 Root file | Universal rules | Always loaded | `AGENTS.md` |
| 2 Path-scoped | Guidance for a path / file type | File **path** | PreToolUse hook |
| 3 Construct-scoped | Guidance for an API / construct | Written **content** (regex), optionally AND path | PostToolUse hook |
| 4 Intent skills | Task-nature guidance | Skill match | Generated `.claude/skills/*/SKILL.md` |

## Frontmatter

```yaml
---
paths: ["src/**"]              # Layer 2: inject when editing a matching path
contents: ['\bTODO\b']        # Layer 3: inject when written code matches (PCRE2)
skill: true                    # Layer 4: generate a skill wrapper
description: "Use when ..."    # required iff skill: true; must start with "Use when"
---
```

- `paths` only → Layer 2 (fires on any edit to a matching path)
- `contents` only → Layer 3 (fires when written code matches, anywhere)
- `paths` + `contents` → **AND** (path-scoped Layer 3)
- `skill: true` is independent and may combine with either
- no frontmatter → reference-only: reachable by link, never triggered

## Writing a rule

- One concern per file; keep it short — tight rules get read, long ones get skimmed.
- State **what** the rule is, **why** it exists, and a verification criterion.
- Add an optional `## Verify` heading; `agent-apropos review` harvests it as a checklist item.

Claude Code delivers Layer 2 via PreToolUse `additionalContext`; run
`agent-apropos doctor` to verify the version. OpenCode delivers Layer 2 via
`tool.execute.before` and Layer 3 via `tool.execute.after`, injecting
context with `noReply: true` through the generated plugin. Gemini CLI and
GitHub Copilot CLI both have no pre-edit context-injection event (Gemini's
`BeforeTool` and Copilot's `preToolUse` can only override arguments or
block/allow the call), so both Layer 2 and Layer 3 deliver via their
post-edit hook instead (`AfterTool` for Gemini, `postToolUse` for Copilot)
— Layer 2 still fires, just after the edit rather than before it. Codex
CLI's own PreToolUse *can* inject context, so it delivers Layer 2 the same
way Claude Code does; its `apply_patch` tool can bundle several files'
edits into one call, which agent-apropos matches and injects per file.