#!/usr/bin/env bash
# devcontainer initializeCommand — runs on the HOST, before the container is created.
#
# Every path devcontainer.json mounts has to exist first: Docker materialises a missing bind
# source as a root-owned directory, which then takes sudo to undo and leaves the claude CLI
# looking at a directory where its config should be. start.sh does the same for the compose
# path; this is the VS Code half, and the two should stay in step.
set -euo pipefail

if [ ! -d "${HOME}/.claude" ]; then
  echo "[initialize] Creating ${HOME}/.claude — devcontainer.json mounts it into the container"
  mkdir -p "${HOME}/.claude"
fi

if [ ! -f "${HOME}/.claude.json" ]; then
  echo "[initialize] Creating ${HOME}/.claude.json — devcontainer.json mounts it into the container"
  echo '{}' > "${HOME}/.claude.json"
fi

# Docker errors out on a missing --env-file, so VS Code cannot start the container without
# this one. 0600 because it is where secrets go; it is gitignored and may stay empty.
env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env"
if [ ! -f "$env_file" ]; then
  echo "[initialize] Creating ${env_file}"
  (umask 077 && : > "$env_file")
fi
