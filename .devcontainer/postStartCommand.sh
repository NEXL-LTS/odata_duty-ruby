#!/usr/bin/env bash
# devcontainer postStartCommand — re-sync the workspace on every container start.
#
# Wired up in two places, both as the 'vscode' user: devcontainer.json's postStartCommand for
# the VS Code path, and .devcontainer/start.sh for the plain-shell path. Runs on creation too
# (right after postCreateCommand.sh), so everything here has to be cheap and idempotent.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Editing .ruby-version and restarting is how you reproduce a version-specific bug without an
# image rebuild. Normally the pinned Ruby is already there (the image pre-builds it) and this
# is a no-op; when the pin has moved, compile it. The bundle is dealt with below, since a Ruby
# that is already installed says nothing about whether its gems are.
pinned_ruby="$(cat .ruby-version)"
if rbenv versions --bare | grep -qFx "$pinned_ruby"; then
  echo "[postStart] Ruby ${pinned_ruby} already installed"
else
  echo "[postStart] Installing Ruby ${pinned_ruby} — .ruby-version has moved past the image's"
  rbenv install --skip-existing
  rbenv rehash
fi

# Pulling a changed Gemfile, or switching to a Ruby whose gems were never installed, both leave
# the bundle incomplete while the checks above are perfectly happy. The old entrypoint ran
# bin/setup unconditionally to cover this; bundle check answers the same question in
# milliseconds, so ask it every start and only pay for setup when the answer is no.
if bundle check > /dev/null 2>&1; then
  echo "[postStart] Bundle already satisfied"
else
  echo "[postStart] Dependencies missing or changed — running bin/setup"
  ./bin/setup
fi

# Rebuilds the agent-apropos trigger index and skill wrappers from doc/conventions/. The index
# is gitignored, so without this a fresh container has none and no conventions get injected.
if command -v agent-apropos > /dev/null 2>&1; then
  echo "[postStart] Running agent-apropos generate"
  agent-apropos generate
fi
