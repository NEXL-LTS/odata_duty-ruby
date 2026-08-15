#!/usr/bin/env bash
# PreToolUse hook: refuse tool calls that would read .devcontainer/.env.
#
# That file holds local secrets (it is gitignored; see .devcontainer/README.md) and should
# never reach the model's context. Reads a PreToolUse payload on stdin, inspects the path
# and command fields of the tool input, and emits a deny decision on a match. Anything else
# produces no output, which the hook runner treats as "no opinion".
set -uo pipefail

payload=$(cat)

if command -v jq >/dev/null 2>&1; then
  haystack=$(printf '%s' "$payload" | jq -r '
    [.tool_input // {} | .file_path?, .path?, .notebook_path?, .command?, .pattern?]
    | map(select(type == "string")) | join("\n")')
else
  # No jq: match against the raw payload rather than failing open.
  haystack=$payload
fi

if printf '%s' "$haystack" | grep -qF '.devcontainer/.env'; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":".devcontainer/.env holds local secrets and is blocked by a project PreToolUse hook. Read .devcontainer/README.md for what the file contains, or ask the user for the specific value you need."}}
JSON
fi

exit 0
