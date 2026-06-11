# PRDs (Product Requirement Documents)

Each file here is a Product Requirement Document describing a capability of OdataDuty's
**external API** — what a gem consumer can write and what they observe (the DSL, OData query
options, and the generated `$metadata` / `$oas2` / MCP output). A PRD captures WHAT the API
allows and WHAT it enables, not how the gem implements it internally. It's written to be
precise enough for Claude to later **build or fix** the capability.

Generate one with the `/prd` slash command (`.claude/commands/prd.md`):

```
/prd add support for the OData $orderby query option
```

PRDs follow the same purpose-first, example-driven house style as the guides in `doc/`, and
each names the guide it should extend (e.g. `doc/using_search.md`) or the new guide to add.

Once a PRD exists, implement it with the `/build` slash command (`.claude/commands/build.md`):

```
/build orderby-support
```

`/build` derives a task plan from the PRD, then implements it task by task — a fresh subagent
per task followed by two-stage review (spec compliance, then code quality) — keeping both DSLs
in sync, following TDD, and committing each task on a feature branch once `bundle exec rake` is
green. It never pushes; the work is left as local commits for you to review and push yourself.
