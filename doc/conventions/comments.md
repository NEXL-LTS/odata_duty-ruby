---
paths: ["lib/**", "spec/**"]
---

# Let the code speak

**Prefer single-line comments.** Avoid multi-line comment blocks in source. If something needs more
than one line of explanation, rename or refactor until it doesn't — or move the explanation into a
`doc/` guide and leave a one-line pointer.

In specs, drop explanatory `#` comments entirely: the `describe`/`it` descriptions carry the
intent.

**Why:** prose next to code rots silently while the code keeps changing. The source is the best
source of truth, so keep the amount of prose that can contradict it small.

## Verify

No new comment block spans more than one line, and no spec carries a `#` comment that a
`describe`/`it` description could have said instead.
