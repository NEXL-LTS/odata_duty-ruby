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
# is a no-op; when the pin has moved, compile it and reinstall the gems against it, since the
# gems from the previous Ruby are not visible to this one.
pinned_ruby="$(cat .ruby-version)"
if rbenv versions --bare | grep -qFx "$pinned_ruby"; then
  echo "[postStart] Ruby ${pinned_ruby} already installed"
else
  echo "[postStart] Installing Ruby ${pinned_ruby} — .ruby-version has moved past the image's"
  rbenv install --skip-existing
  rbenv rehash
  ./bin/setup
fi

# Rebuilds the agent-apropos trigger index and skill wrappers from doc/conventions/. The index
# is gitignored, so without this a fresh container has none and no conventions get injected.
if command -v agent-apropos > /dev/null 2>&1; then
  echo "[postStart] Running agent-apropos generate"
  agent-apropos generate
fi
