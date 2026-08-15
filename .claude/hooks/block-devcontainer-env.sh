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
  # Serialize the whole tool input: this hook runs on every tool and each one names its
  # paths differently, so there is no fixed set of fields to inspect.
  haystack=$(printf '%s' "$payload" | jq -c '.tool_input // {}')
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

# Split reference: `cd .devcontainer && cat .env`, Grep(pattern='.env', path='.devcontainer').
matches '.devcontainer' && matches '.env' && deny

exit 0
