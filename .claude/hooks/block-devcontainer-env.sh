#!/usr/bin/env bash
# PreToolUse hook: refuse ANY tool call that touches the devcontainer env file.
#
# That file holds local secrets (gitignored; see .devcontainer/README.md). The
# permissions.deny rule in settings.json already blocks the file-reading tools in-process;
# this hook is the backstop covering Bash and every other tool, including ones that reach
# the file indirectly rather than by its full path.
#
# Reads a PreToolUse payload on stdin and emits a deny decision on a match. No output
# otherwise, which the hook runner treats as "no opinion".
set -uo pipefail

payload=$(cat)

if command -v jq >/dev/null 2>&1; then
  # Serialize the whole tool input apart from its content-bearing fields. This hook runs on
  # every tool and each names its paths differently, so there is no fixed set of path fields
  # to scan; excluding the few content fields instead keeps unknown tools covered. Dropping
  # them lets docs and tests that merely name the file be authored, and gives up nothing:
  # writing the file itself is still caught by its path, and a body cannot carry the secrets
  # unless something first read them, which this same hook refuses.
  #
  # The working directory is scanned alongside the input because it persists between Bash
  # calls: change into the directory in one call and read the bare filename in the next, and
  # neither command on its own names both halves of the path.
  haystack=$(printf '%s' "$payload" | jq -c '{
    cwd: (.cwd // ""),
    input: ((.tool_input // {}) | del(.content, .new_string, .old_string, .new_source))
  }')
else
  # No jq: match against the raw payload rather than failing open.
  haystack=$payload
fi

deny() {
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The devcontainer env file holds local secrets and is blocked by a project PreToolUse hook. Read .devcontainer/README.md for what it contains, or ask the user for the specific value you need. Do not try to route around this."}}
JSON
  exit 0
}

matches() { printf '%s' "$haystack" | grep -qF "$1"; }

# Direct reference: `cat .devcontainer/.env`, Read(/abs/path/.devcontainer/.env).
matches '.devcontainer/.env' && deny

# Split reference, where neither half names the file on its own: `cd .devcontainer && cat .env`,
# Grep(pattern='.env', path='.devcontainer'), or `sed -n 1p .env` run from a cwd left inside the
# directory by an earlier call.
matches '.devcontainer' && matches '.env' && deny

exit 0
