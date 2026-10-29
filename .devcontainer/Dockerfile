# Linux dev environment for Stackbar.
# NOTE: AppKit/SwiftUI/ScreenCaptureKit do not exist on Linux. In here you can
# edit everything and build/test StackbarCore; the app itself is built on macOS.
FROM swift:6.2-noble

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg jq less make ripgrep sudo unzip vim zsh \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Non-root user (Ubuntu 24.04 ships a default 'ubuntu' user on UID 1000; replace it)
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && mkdir -p /commandhistory /workspace \
    && chown -R ${USERNAME}:${USERNAME} /commandhistory /workspace

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Claude Code (native installer -> ~/.local/bin/claude)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Pre-create the config dir so the named volume inherits correct ownership
RUN mkdir -p /home/${USERNAME}/.claude

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}" \
    CLAUDE_CONFIG_DIR="/home/${USERNAME}/.claude" \
    HISTFILE="/commandhistory/.bash_history" \
    EDITOR=vim

RUN { \
      echo 'export PROMPT_COMMAND="history -a"'; \
      echo "alias yolo='claude --dangerously-skip-permissions'"; \
    } >> /home/${USERNAME}/.bashrc

WORKDIR /workspace
