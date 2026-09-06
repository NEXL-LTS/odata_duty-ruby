#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory (parent of this script)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Drive .devcontainer/docker-compose.yml rather than a private `docker run`, so
# this shell and VS Code's devcontainer share one definition of the environment.
#
# The project name is what separates one container from another, and compose
# would default it to the compose file's directory — `devcontainer`, which every
# repo on the machine shares. Key it to the checkout path instead: two checkouts
# of this repo each get their own container, rather than the second silently
# attaching to the first one's /workspace or recreating it out from under an
# attached shell. The directory name keeps it recognisable in `docker compose ls`
# and the digest keeps same-named checkouts apart; both differ from the name VS
# Code generates, so this container and that one never disturb each other.
checkout_slug="$(printf '%s' "$(basename "$PROJECT_ROOT")" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
checkout_digest="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)"
COMPOSE_PROJECT="odr-${checkout_slug}-${checkout_digest}"
SERVICE="app"
COMPOSE=(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_ROOT/.devcontainer/docker-compose.yml")

# Run one of the lifecycle scripts inside the container, as the user and from the directory
# devcontainer.json's postCreateCommand/postStartCommand would use for the VS Code path.
run_lifecycle_script() {
    echo -e "${GREEN}Running $1...${NC}"
    "${COMPOSE[@]}" exec -T --user vscode --workdir /workspace "$SERVICE" \
        "/workspace/.devcontainer/$1"
}

rebuild=false
for arg in "$@"; do
    case "$arg" in
        --rebuild) rebuild=true ;;
        *) echo "Usage: $(basename "$0") [--rebuild]" >&2; exit 64 ;;
    esac
done

USER_UID="$(id -u)"
USER_GID="$(id -g)"

if [ "$USER_UID" -eq 0 ] || [ "$USER_GID" -eq 0 ]; then
    echo -e "${YELLOW}Warning: running as root detected; using fallback UID/GID 1000:1000 for image build to avoid remapping the root user/group inside the image.${NC}"
    USER_UID=1000
    USER_GID=1000
fi
export USER_UID USER_GID

# The compose file forwards this shell's ssh-agent socket instead of ${HOME}/.ssh, so git in
# the container can authenticate as you without a private key ever crossing the boundary.
# Docker Desktop cannot bind-mount the host's own socket path, so it publishes a fixed one that
# proxies to whatever agent the Mac is running.
if [ "$(uname -s)" = "Darwin" ]; then
    export SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
elif [ ! -S "${SSH_AUTH_SOCK:-}" ]; then
    echo -e "${YELLOW}Warning: no ssh-agent on this host (SSH_AUTH_SOCK is unset or not a socket).${NC}"
    echo -e "${YELLOW}Everything but git-over-SSH still works. To fix: eval \"\$(ssh-agent -s)\" && ssh-add${NC}"
fi

# The compose file bind-mounts ${HOME}/.claude; ensure it exists as a directory.
if [ ! -d "${HOME}/.claude" ]; then
    echo -e "${YELLOW}Creating ${HOME}/.claude — the compose file mounts it into the container${NC}"
    mkdir -p "${HOME}/.claude"
fi

# The compose file bind-mounts ${HOME}/.claude.json; ensure it exists as a file
# so Docker does not materialise it as a root-owned directory.
if [ ! -f "${HOME}/.claude.json" ]; then
    echo -e "${YELLOW}Creating ${HOME}/.claude.json — the compose file mounts it into the container${NC}"
    echo '{}' > "${HOME}/.claude.json"
fi

# VS Code hands the gitignored secrets file to Docker with --env-file; the compose file instead
# forwards named variables from this shell, so load the file in here first. Docker's env-file
# format is plain KEY=VALUE with no quoting or expansion, so read it as such rather than sourcing
# it, and let a value already exported in this shell take precedence over the file's.
secrets_file="$SCRIPT_DIR/.env"

# The compose file masks this path with /dev/null so the file is not readable inside the
# container. Docker materialises a missing mount target as a root-owned empty file, which would
# leave you needing sudo to put a token in it later, so create it first — 0600, since this is
# where secrets go. VS Code's --env-file wants it to exist anyway.
if [ ! -f "$secrets_file" ]; then
    echo -e "${YELLOW}Creating ${secrets_file} — the compose file mounts over it${NC}"
    (umask 077 && : > "$secrets_file")
fi

# `|| [ -n "$key" ]` so a final line with no trailing newline is still read.
while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in '' | '#'*) continue ;; esac
    [ -n "${!key:-}" ] || export "$key=$value"
done < "$secrets_file"

if [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
    echo -e "${YELLOW}Warning: neither GH_TOKEN nor GITHUB_TOKEN is set (in this shell or in ${secrets_file}). GitHub access inside the container will be unauthenticated.${NC}"
fi

if [ "$rebuild" = false ] && [ -n "$("${COMPOSE[@]}" ps -q "$SERVICE" 2>/dev/null || true)" ]; then
    echo -e "${GREEN}Attaching to the running dev container...${NC}"
else
    echo -e "${GREEN}Building and starting the dev container...${NC}"
    up_args=(up --detach --build)
    # `up` recreates only when the image or service config changed, so a rebuild
    # that hits the cache would leave --rebuild's caller with the same container.
    if [ "$rebuild" = true ]; then
        up_args+=(--force-recreate)
    fi
    "${COMPOSE[@]}" "${up_args[@]}"

    # The same lifecycle scripts devcontainer.json runs for VS Code; nothing else runs them on
    # this path, so run them here, synchronously, before the shell below opens onto the
    # workspace. Claude Code and agent-apropos are baked into the image, and vscode's sudo is
    # restricted to apt, so neither script installs anything system-wide.
    run_lifecycle_script postCreateCommand.sh
fi

# postStart is due whenever the container started, which includes a start we did not do — Docker
# restarts it after a machine reboot, and the attach branch above would then skip it. Both steps
# it runs are no-ops when nothing has moved, so rerunning it on attach costs a second.
run_lifecycle_script postStartCommand.sh

# %q so the line stays copy-pasteable from a checkout path containing spaces.
printf -v stop_command '%q ' "${COMPOSE[@]}"

echo -e "${GREEN}The container outlives this shell — rerun this script to get back in.${NC}"
echo -e "${GREEN}Stop it with: ${stop_command}down${NC}"

exec "${COMPOSE[@]}" exec --user vscode --workdir /workspace "$SERVICE" bash
