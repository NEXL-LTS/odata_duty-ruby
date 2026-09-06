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
`docker compose ... down` line that stops it. `GH_TOKEN` and `GITHUB_TOKEN` reach the
container if they are exported in your shell or present in the env file below (your shell
wins); nothing else is forwarded.

## Environment variables

`.devcontainer/.env` is loaded into the container at start: VS Code passes it to Docker
via `--env-file`, and `start.sh` reads it into its own environment for the compose file to
forward. VS Code requires the file to exist (Docker errors if it's missing) though it may
be empty; `start.sh` creates it empty (mode 0600) when it is missing. It is gitignored.

| Variable       | Purpose                                                     |
| -------------- | ----------------------------------------------------------- |
| `GH_TOKEN`     | Authenticates `gh` and the GitHub API inside the container.  |
| `GITHUB_TOKEN` | The same; set whichever one your tooling expects.            |

Example:

```
GH_TOKEN=ghp_...
```

The `claude` CLI needs nothing here — it authenticates through the `~/.claude` and
`~/.claude.json` mounts.

The file itself is **not readable inside the container**: both paths mount `/dev/null` over
it, so it reads as empty in there. Nothing inside needs it (both readers are host-side —
Docker's `--env-file` and `start.sh`'s parse loop), and masking it keeps the file from being
grepped, echoed into a transcript, or committed by accident from in there. This hides the
*file*, not the *secrets* — what the file sets is still in the container's environment, so
`printenv` inside still shows the tokens.

## SSH and git authentication

The container never sees `~/.ssh`. `start.sh` forwards your host ssh-agent's **socket**
instead, mounted at `/ssh-agent` with `SSH_AUTH_SOCK` pointed at it, so git inside can
authenticate as you while no private key ever crosses the boundary — and nothing in
the container can export one. On macOS it uses Docker Desktop's
`/run/host-services/ssh-auth.sock` proxy automatically; the VS Code path relies on Dev
Containers' own agent forwarding, which does the same thing.

Docker can only forward an agent that already exists, so `start.sh` makes sure of one before
it starts anything. It uses the agent already in your environment when it can reach it;
otherwise it starts one on a fixed per-user socket — `$XDG_RUNTIME_DIR/odr-ssh-agent-<uid>.sock`,
falling back to `/tmp` — which later runs reuse rather than leaving a trail of agents behind.
If that agent holds no keys it runs `ssh-add` for your default key, prompting for the
passphrase if the key has one (Ctrl-C skips).

None of that is fatal. If no agent can be started, or you skip the key, it warns and carries
on — everything except git-over-SSH still works. GitHub's host keys are baked into the image at `/etc/ssh/ssh_known_hosts`, since a
container with no `~/.ssh` has no `known_hosts` of its own and would otherwise fail host
verification on every push.

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

| Port | Source                                          |
| ---- | ----------------------------------------------- |
| 9292 | `bundle exec rackup spec/config.ru`             |
| 6274 | `@modelcontextprotocol/inspector` UI            |
| 6277 | `@modelcontextprotocol/inspector` proxy         |

(The inspector's two defaults; on the `start.sh` path it is told to use a derived pair
instead — see below.)

See `Procfile` at the repo root for the commands that bind these ports.

`start.sh` has no auto-forwarding agent, so `docker-compose.yml` publishes the ports itself.
The two services need opposite treatment:

- **Rack** takes any free host port — Docker picks one per container, so checkouts never
  contend. It changes on every recreate; `docker compose -p <project> port app 9292` asks
  again.
- **The inspector** is published **1:1** on a pair derived from the checkout path — stable for
  a given clone, different between clones. It has to be 1:1, because the inspector is two
  servers (a UI, and a proxy the browser talks to *directly*) and the proxy rejects any request
  whose `Origin` does not match its own `CLIENT_PORT`. Behind a remapped port the browser
  arrives with the wrong origin and gets a `403`. Both halves are published: with only the UI
  exposed it loads and then cannot reach anything.

`start.sh` prints the lot when it hands you the shell:

```
Ports published for this container:
  Rack (spec/config.ru): http://localhost:32769
  MCP inspector: http://localhost:26022 (proxy on 26023)
    It prints a URL carrying its auth token; append
    &MCP_PROXY_FULL_ADDRESS=http://localhost:26023
```

The inspector prints its own URL with a session token embedded. That URL works as-is because
its port now matches the host's, but the UI still looks for a proxy on 6277 by default, so
append `MCP_PROXY_FULL_ADDRESS` pointing at the derived one.

All of this depends on the processes binding `0.0.0.0` rather than loopback: the `Procfile`
passes `rackup -o 0.0.0.0`, and sets `HOST` for the inspector's proxy, which otherwise binds
`127.0.0.1` (its UI already listens on all interfaces). VS Code needs neither — its forwarder
connects from inside the container.

## Running several checkouts at once

Supported, and the reason no host port above is a fixed constant. Each checkout gets its own
compose project (`odr-<dirname>-<digest of the path>`), so containers, networks and images
stay separate and a second clone never attaches to or recreates the first one's container.
Rack lands on a free port per container, and the inspector's 1:1 pair is derived from the same
path digest, so two clones get different pairs. If two ever did collide, compose refuses to
start and `start.sh` says which port is taken.

Two things are deliberately *shared* between instances, being per-user rather than
per-checkout: the ssh-agent (one agent serving every container is the point) and your
`~/.claude` / `~/.claude.json` mounts, which carry the credentials you want in all of them.
Note the consequence — every container mounts its workspace at the same `/workspace`, so
Claude Code state keyed by that path is shared across checkouts, and two instances writing
`~/.claude.json` at once can have the last writer win.

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
