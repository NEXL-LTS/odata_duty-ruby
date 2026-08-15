---
paths: [".mutant.yml"]
---

# `.mutant.yml` is a one-way ratchet

The `matcher.ignore` list is mutation-testing debt, like `.rubocop_todo.yml`: those subjects had
surviving mutations when CI was made blocking.

- **Never add entries.** If `bundle exec mutant run --since main` reports survivors on code you
  touched, kill them with a spec — see `spec/using_mutant.md`.
- **Remove an entry** when you touch that subject and kill its survivors.
- The three `McpServerBuilder` entries are *not* debt: each has only equivalent mutants at the MCP
  SDK boundary that no public-API test can distinguish. Keep the explanatory comment with any such
  entry.

**Why:** CI fails on any surviving mutation, so the ignore list is the only escape hatch. Adding to
it converts a real coverage gap into permanent silence.

## Verify

The diff to `.mutant.yml` only removes ignore entries, or adds an equivalent-mutant entry that
carries a comment explaining why no public-API test can distinguish it.
