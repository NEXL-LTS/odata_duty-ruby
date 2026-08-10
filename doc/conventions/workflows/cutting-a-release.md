---
skill: true
description: "Use when cutting an odata_duty release — bumping the gem version and closing out the
  changelog."
---

# Cutting a release

1. **Changelog** — `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
   Move the entries under `## [Unreleased]` into a new `## [<version>] - <YYYY-MM-DD>` section,
   grouped under `Added` / `Changed` / `Fixed` / `Removed`, and leave `## [Unreleased]` empty above
   it.
2. **Version** — bump `spec.version` in `odata_duty.gemspec`. The project follows
   [Semantic Versioning](https://semver.org/spec/v2.0.0.html): a change to the rendered `$metadata`,
   `$oas2`, MCP tool shape, or the DSL that existing consumers would have to react to is breaking.
3. **Green** — `bundle exec rake` and `bundle exec mutant run --since main`.

Entries describe what changed for a **consumer** of the gem — the DSL, the rendered documents, the
MCP tools — not the internal refactor that delivered it.

## Verify

`spec.version` and the newest `CHANGELOG.md` heading are the same version, `## [Unreleased]` is
empty, every entry is consumer-visible, and the bump matches SemVer for the changes it covers.
