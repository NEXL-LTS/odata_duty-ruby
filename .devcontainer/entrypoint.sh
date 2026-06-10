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
  if [ -x "$dir/bin/setup" ] && [ -f "$dir/Gemfile" ]; then
    echo "[entrypoint] Running bin/setup in $dir"
    run_as_user "cd '$dir' && ./bin/setup" \
      || echo "[entrypoint] bin/setup failed in $dir; continuing"
  fi
done

exec "$@"
