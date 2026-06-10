#!/usr/bin/env bash
# Container-wide git hook dispatcher.
#
# Installed as the system-wide core.hooksPath in the Dockerfile so that every
# repository's own checked-in hook under .githooks/ runs. This keeps hook logic
# version-controlled in each repo rather than baked into the image. A repo with no
# matching .githooks/<hook> is unaffected (the hook is a no-op there).
#
# The dispatcher's filename is the hook name (e.g. pre-commit); it delegates to
# "<repo>/.githooks/<same name>" when that file is present and executable.
set -euo pipefail

hook_name="$(basename "$0")"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
repo_hook="$repo_root/.githooks/$hook_name"

[ -x "$repo_hook" ] || exit 0
exec "$repo_hook" "$@"
