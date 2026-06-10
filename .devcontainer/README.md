# Dev Container

VS Code / Cursor dev container for `odata_duty`. Provides Ruby 3.3, Node.js
(for the MCP inspector), the GitHub CLI, and the Claude Code CLI.

## Getting started

1. Install the **Dev Containers** extension in VS Code (or open in Cursor).
2. Create `.devcontainer/.env` (see [Environment variables](#environment-variables)).
3. Run **Dev Containers: Reopen in Container** from the command palette.

First build takes a few minutes; subsequent opens are cached.

## Environment variables

`.devcontainer/.env` is loaded into the container at start via Docker's
`--env-file`. The file is required (Docker errors if it's missing) but may be
empty. It is gitignored.

| Variable            | Purpose                                              |
| ------------------- | ---------------------------------------------------- |
| `ANTHROPIC_API_KEY` | Authenticates the `claude` CLI inside the container. |

Example:

```
ANTHROPIC_API_KEY=sk-ant-...
```

## Ports

No ports are forwarded eagerly. When something inside the container starts
listening, VS Code auto-forwards it and picks a free host port if the
in-container port is already taken on the host.

| Port | Source                                |
| ---- | ------------------------------------- |
| 9292 | `bundle exec rackup spec/config.ru`   |
| 6274 | `@modelcontextprotocol/inspector` UI  |

See `Procfile` at the repo root for the commands that bind these ports.

## File ownership / UID mapping

The container's `vscode` user is built with UID/GID `1000:1000` by default,
which matches most Linux hosts. If `id -u` on your host returns something else,
files in the bind-mounted workspace will appear root-owned (or wrongly owned)
inside the container.

To fix, export your UID/GID before opening the container and rebuild:

```sh
export USER_UID=$(id -u)
export USER_GID=$(id -g)
```

These are read by `devcontainer.json` and passed through as build args.
macOS and Windows users on Docker Desktop don't need this — Docker Desktop
handles UID translation for bind mounts on those platforms.

## Git hooks

The container enables this repo's checked-in git hooks automatically. The Dockerfile
sets a system-wide `core.hooksPath` to a small dispatcher
(`git-hooks-dispatcher.sh`) that delegates to each repo's `.githooks/<hook>`, so the
hook logic stays version-controlled rather than baked into the image.

Active hook: **`.githooks/pre-commit`** runs `bundle exec rake` (RSpec + RuboCop — the
same check CI runs) and **blocks the commit if it fails**.

Bypass it for a deliberate work-in-progress commit with `git commit --no-verify`.

Outside the dev container, enable the same hook once with:

```sh
git config core.hooksPath .githooks
```

## What's installed

- Ruby 3.3 (matches `.ruby-version`) with Bundler
- Node.js 18 + npm (from Debian Bookworm)
- `@anthropic-ai/claude-code` (run `claude` in the integrated terminal)
- GitHub CLI (`gh`)
- VS Code extensions: Ruby LSP, RuboCop, YAML, GitLens
