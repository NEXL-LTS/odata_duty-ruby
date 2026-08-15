---
paths: ["lib/**", "spec/**"]
contents: ['#(?!\{)']
---

# Comments are a smell; the code and its specs are the documentation

**Rule:** Don't explain in a comment what a class, method, or constant does — or why. If a name
doesn't say what something is for, rename it until it does. If a behaviour, edge case, or invariant
needs stating, state it in a spec example whose description names the reason
(`it 'rejects a $top that exceeds the page size'`), not in a comment above the code. In specs, the
`describe`/`it` descriptions carry the intent; a `#` comment there is a description that wasn't
written.

The target is zero. Treat a comment as legitimate only in these cases:

- a `rubocop:disable` directive;
- **equivalent-mutant rationale** — `mutant` cannot distinguish the mutation, so no spec can either.
  `doc/conventions/mutant-ratchet.md` requires this one; keep it, and say what the equivalent
  mutation is;
- **external-dependency behaviour we rely on but don't control** (e.g. how the `mcp` gem's response
  builder compacts a nil key), where there is nothing in this repo a spec could pin.

Anything else is a rename or a spec that hasn't been written yet.

**Why:** a comment drifts from the code the moment either changes without the other, and nothing
forces them back into sync. A spec fails loudly when it goes stale; a comment just sits there and
lies. Pushing the "why" into a spec description keeps one executable source of truth for intent —
and this suite is the gem's public documentation anyway (`doc/conventions/specs.md`).

**Watch out:** some rationale is architectural and has no natural spec home — how the executor
dispatches, why a wrapper exists at all. That belongs in a `doc/` guide linked from the code, not
deleted outright and not smuggled back in as a comment block.

This rule is a graduation candidate: once the exceptions above are stable, a custom RuboCop cop
should enforce it and this prose should shrink to the carve-outs.

## Verify

No new comment in `lib/**` or `spec/**` restates what the code says. Anything removed reappears as a
better name, a spec example named after the reason, or a `doc/` guide — and every surviving comment
is a `rubocop:disable`, equivalent-mutant rationale, or third-party behaviour we can't pin with a
spec.
