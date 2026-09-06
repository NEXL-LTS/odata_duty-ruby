# Dev Container

VS Code / Cursor dev container for `odata_duty`. Built on a base Ubuntu image with
**rbenv** (so any Ruby can be installed for version-specific debugging), Node.js
(for the MCP inspector), the GitHub CLI, and the Claude Code CLI.

## Getting started

1. Install the **Dev Containers** extension in VS Code (or open in Cursor).
2. Create `.devcontainer/.env` (see [Environment variables](#environment-variables)).
3. Run **Dev Containers: Reopen in Container** from the command palette.

First build takes a few minutes; subsequent opens are cached.

## Without VS Code

`.devcontainer/start.sh` gives you the same container from a plain shell. It builds and
starts `docker-compose.yml` (same `Dockerfile`, workspace mounted at `/workspace`), runs the
[lifecycle scripts](#lifecycle-scripts), and drops you into a `bash` shell as `vscode`:

```sh
.devcontainer/start.sh              # build/attach, then shell in
.devcontainer/start.sh --rebuild    # force a fresh container (needed to pick up env changes)
```

The container outlives the shell — rerun the script to get back in; the script prints the
`docker compose ... down` line that stops it. `ANTHROPIC_API_KEY`, `GH_TOKEN` and
`GITHUB_TOKEN` reach the container if they are exported in your shell or present in the
env file below (your shell wins); nothing else is forwarded.

## Environment variables

`.devcontainer/.env` is loaded into the container at start: VS Code passes it to Docker
via `--env-file`, and `start.sh` reads it into its own environment for the compose file to
forward. VS Code requires the file to exist (Docker errors if it's missing) though it may
be empty; `start.sh` treats it as optional. It is gitignored.

| Variable            | Purpose                                              |
| ------------------- | ---------------------------------------------------- |
| `ANTHROPIC_API_KEY` | Authenticates the `claude` CLI inside the container. |

Example:

```
ANTHROPIC_API_KEY=sk-ant-...
```

## Lifecycle scripts

Provisioning lives in two scripts rather than inline in `devcontainer.json`, so the VS Code
path and `start.sh` provision identically (and CI can run them against the built image):

| Script                 | When                | What                                        |
| ---------------------- | ------------------- | ------------------------------------------- |
| `postCreateCommand.sh` | on container create | ensures the pinned Ruby, runs `bin/setup`   |
| `postStartCommand.sh`  | on every start      | installs a moved `.ruby-version`, rebuilds the agent-apropos index |

`devcontainer.json` wires them to `postCreateCommand`/`postStartCommand`; `start.sh` runs the
same two inside the container as `vscode`. Both are idempotent and safe to run by hand.

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

## Ruby versions (rbenv)

The image installs Ruby via [rbenv](https://github.com/rbenv/rbenv) + `ruby-build`
rather than baking in a single fixed Ruby. The version pinned in `.ruby-version` is
pre-built into the image, and `postStartCommand.sh` installs the pinned version on container
start if it isn't there yet, so whatever `.ruby-version` pins is always present.

To reproduce a **version-specific** issue (e.g. a CI matrix failure), install and
switch to another Ruby — no rebuild needed:

```sh
rbenv install -l            # list installable versions
rbenv install 3.4.4         # build another Ruby
rbenv shell 3.4.4           # use it for this shell only
ruby -v && bundle install   # reproduce against it
```

`rbenv local <version>` writes `.ruby-version` (don't commit that if you're only
debugging); `rbenv global <version>` changes the default. The full `ruby-build`
toolchain (compilers, `libssl-dev`, `rustc` for YJIT, …) is installed, so building
arbitrary versions works offline of any prebuilt binaries.

## Conventions (agent-apropos)

[agent-apropos](https://github.com/NEXL-LTS/agent-apropos) is baked into the image at a pinned
version (`AGENT_APROPOS_VERSION` build arg in the Dockerfile). It delivers this repo's scoped
conventions to Claude Code just-in-time: rules live in `doc/conventions/` as markdown with YAML
frontmatter, and the hooks in `.claude/settings.json` inject the ones whose `paths` and/or
`contents` match. Injection happens on **writes** only — a read injects nothing, and reading a
convention doc in full marks it as already in context so no later write re-injects it. Universal
rules stay in `AGENTS.md` (`CLAUDE.md` is a symlink to it).

`postStartCommand.sh` runs `agent-apropos generate` on container start, which rebuilds the
trigger index (`.cache/agent-apropos/`, gitignored) and the skill wrappers under
`.claude/skills/`. After editing a convention doc, re-run it yourself:

```sh
agent-apropos generate   # rebuild the index + skill wrappers
agent-apropos lint       # validate frontmatter and structure
agent-apropos doctor     # check the environment and hook wiring
```

`agent-apropos generate` **owns `.claude/skills/`** — it deletes any skill directory it did not
generate. Skills must therefore be authored as `doc/conventions/workflows/<slug>.md` with
`skill: true`; never hand-write a `SKILL.md`.

`agent-apropos.yml` at the repo root points the tool at `doc/conventions` rather than its default
`docs/conventions`, matching this repo's existing `doc/` directory.

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

- rbenv + ruby-build, with the `.ruby-version` Ruby pre-built (Bundler included)
- Node.js 20 LTS + npm (from NodeSource)
- `@anthropic-ai/claude-code` (run `claude` in the integrated terminal)
- `agent-apropos` (pinned; delivers `doc/conventions/` rules to Claude Code — see above)
- GitHub CLI (`gh`)
- `tmux` (for shells and dev servers that survive a disconnect)
- VS Code extensions: Ruby LSP, RuboCop, YAML, GitLens
