ARG VARIANT=dev-3.3-bookworm
FROM mcr.microsoft.com/devcontainers/ruby:${VARIANT}

# Node.js — used by the MCP inspector in Procfile and required by Claude Code.
# Bookworm ships Node 18 LTS, which satisfies Claude Code's Node 18+ requirement.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nodejs npm \
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

# Align the 'vscode' user with the host UID/GID so bind-mounted files stay
# owned correctly. Override at build time with --build-arg if the host isn't 1000:1000.
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
    # 3. Extra groups + sudoers
    # Restrict sudo to apt only. Blocks "sudo bash" / "sudo su" while still
    # allowing package management. Convenience restriction, not a hard
    # security boundary against a determined local user.
    usermod -aG video vscode; \
    rm -f /etc/sudoers.d/vscode; \
    echo 'vscode ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt' >> /etc/sudoers

# Git hooks: enable each repo's checked-in hooks (e.g. .githooks/pre-commit, which
# runs `bundle exec rake` and blocks the commit on failure). A system-wide hooksPath
# points git at a dispatcher that delegates to the in-repo hook, so the logic stays
# version-controlled and repos without one are unaffected. Use --system so the config
# applies to the 'vscode' user too; per-repo config still takes precedence over it.
COPY git-hooks-dispatcher.sh /usr/local/share/git-hooks/pre-commit
RUN chmod +x /usr/local/share/git-hooks/pre-commit \
 && git config --system core.hooksPath /usr/local/share/git-hooks

# Entrypoint: run bin/setup against any mounted workspace before handing off
COPY entrypoint.sh /usr/local/bin/devcontainer-entrypoint
RUN chmod +x /usr/local/bin/devcontainer-entrypoint
ENTRYPOINT ["/usr/local/bin/devcontainer-entrypoint"]

USER vscode
