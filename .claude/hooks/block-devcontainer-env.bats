#!/usr/bin/env bats
#
# Tests for the PreToolUse hook guarding .devcontainer/.env.
#
#   bats .claude/hooks/block-devcontainer-env.bats
#
# The hook contract: read a PreToolUse payload on stdin, print a deny decision when the tool
# call would touch the secrets file, print nothing otherwise, and always exit 0 so a
# non-match is read as "no opinion" rather than a hook failure.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/block-devcontainer-env.sh"
  SECRET=".devcontainer/.env"
  GUARDED_CWD="/workspaces/odata_duty/.devcontainer"
}

# Build a PreToolUse payload: payload <tool_name> <tool_input_json> [cwd]
# cwd defaults to a project root outside the guarded directory.
payload() {
  printf '{"session_id":"test","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":%s}' \
    "${3:-/workspaces/odata_duty}" "$1" "$2"
}

assert_denied() {
  run "$HOOK" <<<"$1"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PreToolUse" ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
  # A blank reason would deny without telling the model why, so it would just try again.
  [ -n "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" ]
}

assert_allowed() {
  run "$HOOK" <<<"$1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- denied: the file named directly -----------------------------------------------------

@test "denies Read of the relative path" {
  assert_denied "$(payload Read "{\"file_path\":\"$SECRET\"}")"
}

@test "denies Read of the absolute path" {
  assert_denied "$(payload Read "{\"file_path\":\"/workspaces/odata_duty/$SECRET\"}")"
}

@test "denies Read of the ./-prefixed path" {
  assert_denied "$(payload Read "{\"file_path\":\"./$SECRET\"}")"
}

@test "denies Write clobbering the file" {
  assert_denied "$(payload Write "{\"file_path\":\"$SECRET\",\"content\":\"x\"}")"
}

@test "denies Edit of the file" {
  assert_denied "$(payload Edit "{\"file_path\":\"$SECRET\",\"old_string\":\"a\",\"new_string\":\"b\"}")"
}

@test "denies a Glob that would match the file" {
  assert_denied "$(payload Glob "{\"pattern\":\"$SECRET\"}")"
}

@test "denies an unknown MCP tool naming the file in an arbitrary field" {
  assert_denied "$(payload mcp__files__fetch "{\"target\":\"$SECRET\"}")"
}

# --- denied: reached through the shell ---------------------------------------------------

@test "denies cat" {
  assert_denied "$(payload Bash "{\"command\":\"cat $SECRET\"}")"
}

@test "denies a read piped through an encoder" {
  assert_denied "$(payload Bash "{\"command\":\"head -5 $SECRET | base64\"}")"
}

@test "denies a redirect that copies the file elsewhere" {
  assert_denied "$(payload Bash "{\"command\":\"cp $SECRET /tmp/x\"}")"
}

# --- denied: split across fields or across a cd ------------------------------------------

@test "denies cd into the directory then reading the bare filename" {
  assert_denied "$(payload Bash '{"command":"cd .devcontainer && cat .env"}')"
}

@test "denies a Grep whose pattern and path only combine to reach the file" {
  assert_denied "$(payload Grep '{"pattern":".env","path":".devcontainer"}')"
}

# --- denied: split across separate calls via the persisted cwd ----------------------------
#
# The Bash tool keeps its working directory between calls, so `cd .devcontainer` in one call
# and `sed -n 1p .env` in the next puts only one half of the path in each command. The hook
# scans the payload's cwd for exactly this.

@test "denies sed on the bare filename from a cwd inside the directory" {
  assert_denied "$(payload Bash '{"command":"sed -n 1p .env"}' "$GUARDED_CWD")"
}

@test "denies cat on the bare filename from a cwd inside the directory" {
  assert_denied "$(payload Bash '{"command":"cat .env"}' "$GUARDED_CWD")"
}

@test "denies Read of the bare filename from a cwd inside the directory" {
  assert_denied "$(payload Read '{"file_path":".env"}' "$GUARDED_CWD")"
}

@test "denies a shell variable holding the filename, from inside the directory" {
  assert_denied "$(payload Bash '{"command":"f=.env; cat \"$f\""}' "$GUARDED_CWD")"
}

@test "denies from a nested cwd below the directory" {
  assert_denied \
    "$(payload Bash '{"command":"cat ../.env"}' "$GUARDED_CWD/sub")"
}

# --- allowed: the rest of the devcontainer directory --------------------------------------

@test "allows the devcontainer config" {
  assert_allowed "$(payload Read '{"file_path":".devcontainer/devcontainer.json"}')"
}

@test "allows the devcontainer README" {
  assert_allowed "$(payload Read '{"file_path":".devcontainer/README.md"}')"
}

@test "allows the Dockerfile" {
  assert_allowed "$(payload Read '{"file_path":".devcontainer/Dockerfile"}')"
}

@test "allows the entrypoint" {
  assert_allowed "$(payload Read '{"file_path":".devcontainer/entrypoint.sh"}')"
}

@test "allows the lock file" {
  assert_allowed "$(payload Read '{"file_path":".devcontainer/devcontainer-lock.json"}')"
}

@test "allows listing the directory" {
  assert_allowed "$(payload Bash '{"command":"ls -la .devcontainer"}')"
}

# --- allowed: still able to work inside the guarded directory ------------------------------
#
# Scanning the cwd must not turn the whole directory into a no-go zone; only the pairing of
# that cwd with the filename is refused.

@test "allows editing the Dockerfile from inside the directory" {
  assert_allowed "$(payload Read '{"file_path":"Dockerfile"}' "$GUARDED_CWD")"
}

@test "allows a build command from inside the directory" {
  assert_allowed "$(payload Bash '{"command":"docker build -t x ."}' "$GUARDED_CWD")"
}

@test "allows listing from inside the directory" {
  assert_allowed "$(payload Bash '{"command":"ls -la"}' "$GUARDED_CWD")"
}

# --- allowed: near misses -----------------------------------------------------------------

@test "allows an --env-file flag pointing somewhere else" {
  assert_allowed "$(payload Bash '{"command":"docker run --env-file prod.list app"}')"
}

@test "allows a dotenv file outside the devcontainer directory" {
  assert_allowed "$(payload Read '{"file_path":"spec/fixtures/.env"}')"
}

@test "allows ordinary project work" {
  assert_allowed "$(payload Read '{"file_path":"lib/odata_duty.rb"}')"
  assert_allowed "$(payload Bash '{"command":"bundle exec rake"}')"
}

# --- allowed: authoring prose and tests that merely name the file -------------------------
#
# The hook scans paths and commands, not content bodies. Without these the hook blocks
# writing this very test file, and any doc that mentions the path.

@test "allows writing a file whose content names the path" {
  assert_allowed \
    "$(payload Write "{\"file_path\":\"doc/secrets.md\",\"content\":\"Put secrets in $SECRET\"}")"
}

@test "allows editing a file whose strings name the path" {
  assert_allowed \
    "$(payload Edit "{\"file_path\":\"README.md\",\"old_string\":\"x\",\"new_string\":\"$SECRET\"}")"
}

# --- robustness ----------------------------------------------------------------------------

@test "survives a payload with no tool_input" {
  assert_allowed '{"session_id":"test","tool_name":"Read"}'
}

@test "survives an empty payload" {
  assert_allowed '{}'
}

@test "fails closed when the payload is not valid JSON" {
  # jq exits non-zero and prints nothing, so an unguarded haystack would be empty and the
  # call would sail through.
  assert_denied "{\"cwd\":\"/x\",\"tool_input\":{\"file_path\":\"$SECRET\"}"
}

@test "fails closed when the payload is JSON but not an object" {
  # Valid JSON, but `.cwd` on a string is a jq type error.
  assert_denied "\"a note mentioning $SECRET\""
}

@test "fails closed when jq is unavailable" {
  # The hook falls back to matching the raw payload rather than letting the call through.
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for tool in bash cat grep; do
    ln -sf "$(command -v "$tool")" "$bin/$tool"
  done
  run env -i PATH="$bin" "$HOOK" <<<"$(payload Read "{\"file_path\":\"$SECRET\"}")"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"deny"'* ]]
}
