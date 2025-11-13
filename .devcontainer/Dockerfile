FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG ENABLE_DIND=true
ENV ENABLE_DIND=${ENABLE_DIND}

# Install common packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    build-essential \
    curl \
    direnv \
    git \
    gnupg2 \
    jq \
    procps \
    sudo \
    unzip \
    zip

# Install yq
RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Install critical CLI tools
RUN curl -L https://github.com/getsops/sops/releases/download/v3.9.1/sops-v3.9.1.linux.amd64 -o /usr/local/bin/sops && chmod +x /usr/local/bin/sops
RUN curl -L https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz | tar xz -C /tmp && mv /tmp/age/age /usr/local/bin/ && mv /tmp/age/age-keygen /usr/local/bin/ && chmod +x /usr/local/bin/age*
RUN curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz -C /usr/local/bin && chmod +x /usr/local/bin/kubeconform
RUN curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.5.0/kustomize_v5.5.0_linux_amd64.tar.gz | tar xz -C /usr/local/bin && chmod +x /usr/local/bin/kustomize
RUN curl -L https://github.com/siderolabs/talos/releases/latest/download/talosctl-linux-amd64 -o /usr/local/bin/talosctl && chmod +x /usr/local/bin/talosctl
RUN curl -L https://github.com/budimanjojo/talhelper/releases/latest/download/talhelper_linux_amd64 -o /usr/local/bin/talhelper && chmod +x /usr/local/bin/talhelper

# Install fish shell (latest version)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends software-properties-common gpg \
    && echo 'deb http://download.opensuse.org/repositories/shells:/fish:/release:/3/Debian_12/ /' | tee /etc/apt/sources.list.d/shells:fish:release:3.list \
    && curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:3/Debian_12/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/shells_fish_release_3.gpg > /dev/null \
    && apt-get update \
    && apt-get -y install --no-install-recommends fish

# The vscode user is already created in the base image.

# Create .bin directory for local tools and fish completions as root
RUN mkdir -p /home/vscode/.bin /home/vscode/.config/fish/completions \
    && chown -R vscode:vscode /home/vscode/.bin /home/vscode/.config

# Set fish as default login shell for the vscode user (use usermod; fallback to no-op)
RUN usermod -s /usr/bin/fish vscode || true

# Set environment variable for shell
ENV SHELL=/usr/bin/fish

# Switch to the vscode user for subsequent steps
USER vscode

COPY --chown=vscode:vscode setup.sh /tmp/devcontainer/setup.sh
COPY --chown=vscode:vscode completions.sh /tmp/devcontainer/completions.sh
COPY --chown=vscode:vscode fish-config.fish /tmp/devcontainer/fish-config.fish

RUN chmod +x /tmp/devcontainer/setup.sh /tmp/devcontainer/completions.sh \
    && /tmp/devcontainer/setup.sh \
    && rm -rf /tmp/devcontainer

