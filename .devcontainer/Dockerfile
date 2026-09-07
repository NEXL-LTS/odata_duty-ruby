# Base Ubuntu (no Ruby baked in); we add rbenv so any Ruby installs on demand. See .devcontainer/README.md.
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ruby-build's recommended build environment, plus gnupg/curl for the apt repos, rustc for YJIT,
# jq for the Claude Code hooks in .claude/hooks (they parse their payload with it), tmux for
# detachable shells (the dev server and MCP inspector outlive a disconnect), and openssh-client
# for git over SSH, which authenticates through the agent socket the container is handed.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      autoconf bison build-essential patch rustc \
      libssl-dev libyaml-dev libreadline-dev zlib1g-dev libgmp-dev \
      libncurses-dev libffi-dev libgdbm-dev libdb-dev uuid-dev \
      curl ca-certificates gnupg git jq tmux openssh-client \
 && rm -rf /var/lib/apt/lists/*

# GitHub's host keys, system-wide. The container is handed an agent socket rather than a home
# directory of keys, so it has no known_hosts of its own and every git-over-SSH call would fail
# host verification without this. Baked at build time so it costs nothing per container start.
#
# Taken from GitHub's metadata API over TLS rather than ssh-keyscan: keyscan trusts whatever
# answers on port 22 while the image builds, so anyone in the way of that build could seed
# their own key and be trusted by every later git operation. Empty output fails the build
# rather than shipping an image that verifies nothing.
RUN curl -fsSL https://api.github.com/meta \
  | jq -r '.ssh_keys[] | "github.com \(.)"' > /etc/ssh/ssh_known_hosts \
 && test -s /etc/ssh/ssh_known_hosts

# Node.js (MCP inspector + Claude Code); NodeSource 20.x LTS since Ubuntu's package lags.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh \
 && bash /tmp/nodesource_setup.sh \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -f /tmp/nodesource_setup.sh \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI — official apt repo
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code \
 && npm cache clean --force

# bats-core — test runner for the shell hooks in .claude/hooks:
#   bats .claude/hooks/*.bats
# Pinned; bump the ARG to upgrade.
ARG BATS_VERSION=1.13.0
RUN npm install -g "bats@${BATS_VERSION}" \
 && npm cache clean --force \
 && bats --version

# agent-apropos — injects doc/conventions/ rules into Claude Code at edit time via git-tracked
# hooks in .claude/settings.json. Pinned; bump the ARG to upgrade. See .devcontainer/README.md.
ARG AGENT_APROPOS_VERSION=v0.4.0
RUN curl -fsSL "https://raw.githubusercontent.com/NEXL-LTS/agent-apropos/${AGENT_APROPOS_VERSION}/install.sh" -o /tmp/agent-apropos-install.sh \
 && AGENT_APROPOS_VERSION="${AGENT_APROPOS_VERSION}" AGENT_APROPOS_BIN_DIR=/usr/local/bin \
      sh /tmp/agent-apropos-install.sh \
 && rm -f /tmp/agent-apropos-install.sh \
 && agent-apropos --version

# Align the 'vscode' user with the host UID/GID (override via --build-arg if the host isn't 1000:1000).
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    # 1. Handle the group for USER_GID. A group already holding that GID is reused as it is:
    #    renaming it to vscode fails whenever the image already ships a vscode group, which is
    #    how a host GID of 20 (dialout) or 100 (users) aborted the build. Nothing below needs
    #    the group to be named vscode, only for the user to belong to it.
    if ! getent group "${USER_GID}" > /dev/null; then \
        if getent group vscode > /dev/null; then \
            groupmod -g "${USER_GID}" vscode; \
        else \
            groupadd -g "${USER_GID}" vscode; \
        fi; \
    fi; \
    \
    # 2. Handle the user for USER_UID
    if getent passwd "${USER_UID}" > /dev/null; then \
        existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
        if [ "${existing_user}" != "vscode" ]; then \
            usermod -l vscode "${existing_user}"; \
        fi; \
        usermod -d /home/vscode -m vscode; \
        usermod -g "${USER_GID}" vscode; \
    else \
        if id -u vscode >/dev/null 2>&1; then \
            usermod -u "${USER_UID}" -g "${USER_GID}" -d /home/vscode -m vscode; \
        else \
            useradd -m -s /bin/bash -u "${USER_UID}" -g "${USER_GID}" vscode; \
        fi; \
    fi; \
    \
    # 3. Extra groups + sudoers restricted to apt (convenience, not a hard security boundary).
    usermod -aG video vscode; \
    rm -f /etc/sudoers.d/vscode; \
    echo 'vscode ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt' >> /etc/sudoers

# System hooksPath dispatcher runs each repo's checked-in .githooks/<hook>. See .devcontainer/README.md.
COPY git-hooks-dispatcher.sh /usr/local/share/git-hooks/pre-commit
RUN chmod +x /usr/local/share/git-hooks/pre-commit \
 && git config --system core.hooksPath /usr/local/share/git-hooks

# rbenv + ruby-build for the 'vscode' user; RUBY_VERSION (keep synced with .ruby-version) is pre-built.
ENV RBENV_ROOT=/home/vscode/.rbenv
ENV PATH=${RBENV_ROOT}/shims:${RBENV_ROOT}/bin:${PATH}
ARG RUBY_VERSION=3.3.11
USER vscode
RUN git clone --depth 1 https://github.com/rbenv/rbenv.git "$RBENV_ROOT" \
 && git clone --depth 1 https://github.com/rbenv/ruby-build.git "$RBENV_ROOT/plugins/ruby-build" \
 && { \
      echo ''; \
      echo 'export RBENV_ROOT="$HOME/.rbenv"'; \
      echo 'export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:$PATH"'; \
      echo 'eval "$(rbenv init - bash)"'; \
    } >> /home/vscode/.bashrc \
 && rbenv install "$RUBY_VERSION" \
 && rbenv global "$RUBY_VERSION" \
 && gem install bundler \
 && rbenv rehash

# No ENTRYPOINT: workspace setup lives in postCreateCommand.sh / postStartCommand.sh, which
# devcontainer.json and start.sh both run. An entrypoint doing the same work would race them.
USER vscode
