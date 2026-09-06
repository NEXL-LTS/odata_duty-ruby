#!/usr/bin/env bash
# devcontainer postCreateCommand — one-time provisioning of a freshly created container.
#
# Wired up in two places, both as the 'vscode' user: devcontainer.json's postCreateCommand for
# the VS Code path, and .devcontainer/start.sh for the plain-shell path. Keep it idempotent —
# start.sh reruns it whenever it starts a container it did not attach to.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The image pre-builds the Ruby that .ruby-version pins, so this is normally a no-op; it earns
# its keep when .ruby-version has moved ahead of the image's RUBY_VERSION, where bin/setup would
# otherwise fail on a shim for an uninstalled Ruby. postStartCommand.sh covers the pin moving
# after the container was created.
echo "[postCreate] Ensuring Ruby $(cat .ruby-version) via rbenv"
rbenv install --skip-existing
rbenv rehash

echo "[postCreate] Running bin/setup"
./bin/setup
