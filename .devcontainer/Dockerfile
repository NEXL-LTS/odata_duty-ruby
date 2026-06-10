# Base Ubuntu (no Ruby baked in); we add rbenv so any Ruby installs on demand. See .devcontainer/README.md.
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ruby-build's recommended build environment, plus gnupg/curl for the apt repos and rustc for YJIT.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      autoconf bison build-essential patch rustc \
      libssl-dev libyaml-dev libreadline-dev zlib1g-dev libgmp-dev \
      libncurses-dev libffi-dev libgdbm-dev libdb-dev uuid-dev \
      curl ca-certificates gnupg git \
 && rm -rf /var/lib/apt/lists/*

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

# Align the 'vscode' user with the host UID/GID (override via --build-arg if the host isn't 1000:1000).
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    # 1. Handle the group for USER_GID
    if getent group "${USER_GID}" > /dev/null; then \
        existing_group="$(getent group "${USER_GID}" | cut -d: -f1)"; \
        if [ "${existing_group}" != "vscode" ]; then \
            groupmod -n vscode "${existing_group}"; \
        fi; \
    else \
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
USER root

# Entrypoint: ensure the workspace's pinned Ruby is installed, then run bin/setup
COPY entrypoint.sh /usr/local/bin/devcontainer-entrypoint
RUN chmod +x /usr/local/bin/devcontainer-entrypoint
ENTRYPOINT ["/usr/local/bin/devcontainer-entrypoint"]

USER vscode
