---
paths: ["doc/**", "README.md"]
---

# One guide per feature

Each consumer-facing feature has a `doc/using_<feature>.md` guide holding its full contract; the
Features list in `AGENTS.md` is only a short index that links to it. `doc/odata_crash_course.md`
and `doc/mcp_crash_course.md` are background for readers new to those protocols, not feature docs.

When a guide changes, check whether the one-line entry in `AGENTS.md` and the `README.md` examples
still describe the same behaviour.

**Why:** the index and the README are what consumers read first; a guide that drifts from them
sends people to the wrong contract, and nothing in the suite catches the mismatch.

## Verify

Feature behaviour is documented in exactly one `doc/using_*.md` guide, and the `AGENTS.md` Features
entry plus any `README.md` example agree with it.
