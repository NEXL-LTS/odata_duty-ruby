#!/usr/bin/env bash
set -e

run_as_user() {
  if [ "$(id -u)" -eq 0 ] && id -u vscode > /dev/null 2>&1; then
    su vscode -c "$1"
  else
    bash -c "$1"
  fi
}

for dir in /workspaces/*/; do
  [ -d "$dir" ] || continue

  # Ensure the Ruby pinned by .ruby-version is installed (rbenv install --skip-existing
  # is a no-op when it already exists). This is what makes a pinned version available
  # without an image rebuild — e.g. after editing .ruby-version to reproduce a
  # version-specific bug, the next container start compiles it.
  if [ -f "$dir/.ruby-version" ]; then
    echo "[entrypoint] Ensuring Ruby $(cat "$dir/.ruby-version") via rbenv in $dir"
    run_as_user "cd '$dir' && rbenv install --skip-existing && rbenv rehash" \
      || echo "[entrypoint] rbenv install failed in $dir; continuing"
  fi

  if [ -x "$dir/bin/setup" ] && [ -f "$dir/Gemfile" ]; then
    echo "[entrypoint] Running bin/setup in $dir"
    run_as_user "cd '$dir' && ./bin/setup" \
      || echo "[entrypoint] bin/setup failed in $dir; continuing"
  fi
done

exec "$@"
