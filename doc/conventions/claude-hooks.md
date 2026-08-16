---
paths: [".claude/hooks/*.sh"]
---

# A hook script and its bats suite change together

Every shell hook in `.claude/hooks/` has a paired `.bats` suite beside it —
`block-devcontainer-env.sh` is covered by `block-devcontainer-env.bats`. Editing the script
without updating the suite is unfinished work.

- **Changing what the hook matches** — a new pattern, a new field, a narrowed scan — needs a
  test for the new behaviour *and* one pinning the case it must still let through.
- **Both halves are the contract.** A guard that over-blocks is as broken as one that leaks, so
  the allow cases carry the same weight as the deny cases. The scan was narrowed once already
  because it refused to write any file that merely named the path it guards.
- Run it with `bats .claude/hooks/*.bats`; bats and jq both ship in the dev container image, and
  CI runs that same command inside the image (`.github/workflows/devcontainer.yml`).

**Why:** these hooks run on every tool call and fail quietly — a broken matcher either blocks
all work or silently stops guarding, and neither announces itself. Nothing else covers them:
`bundle exec rake` is RSpec and RuboCop only, so the bats suite is the only signal there is.

## Verify

The diff touches a `.claude/hooks/*.sh` and its paired `.bats`, and `bats .claude/hooks/*.bats`
passes.
