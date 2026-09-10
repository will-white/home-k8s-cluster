FROM mcr.microsoft.com/devcontainers/base:bookworm@sha256:86165cfc170e9b2aa8df90b847127eea97b08eb9987021e6e6ec6c3a96545d7c

ARG ENABLE_DIND=true
ENV ENABLE_DIND=${ENABLE_DIND}

# --- Pinned tool versions (update these for upgrades) ---
# renovate: datasource=github-releases depName=getsops/sops
ARG SOPS_VERSION=v3.13.3
# renovate: datasource=github-releases depName=FiloSottile/age
ARG AGE_VERSION=v1.3.2
# renovate: datasource=github-releases depName=yannh/kubeconform
ARG KUBECONFORM_VERSION=v0.8.0
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/(?<version>.+)$
ARG KUSTOMIZE_VERSION=v5.8.1
# renovate: datasource=github-releases depName=siderolabs/talos
ARG TALOSCTL_VERSION=v1.14.0
# renovate: datasource=github-releases depName=budimanjojo/talhelper
ARG TALHELPER_VERSION=v3.1.17
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=v4.53.6
# renovate: datasource=github-releases depName=bitwarden/sdk-sm extractVersion=^bws-(?<version>.+)$
ARG BWS_VERSION=v2.1.0
# renovate: datasource=github-tags depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.37.0
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v4.2.4
# renovate: datasource=github-releases depName=helmfile/helmfile
ARG HELMFILE_VERSION=v1.7.4
# renovate: datasource=github-releases depName=stern/stern
ARG STERN_VERSION=v1.34.0
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=v2.100.0
# renovate: datasource=github-releases depName=jqlang/jq extractVersion=^jq-(?<version>.+)$
ARG JQ_VERSION=1.8.2
# renovate: datasource=github-releases depName=gitleaks/gitleaks
ARG GITLEAKS_VERSION=v8.30.1

# Install system packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    build-essential \
    curl \
    fzf \
    git \
    gnupg2 \
    moreutils \
    procps \
    shellcheck \
    sudo \
    unzip \
    yamllint \
    zip

# Install fish shell
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends software-properties-common gpg \
    && echo 'deb http://download.opensuse.org/repositories/shells:/fish:/release:/3/Debian_12/ /' | tee /etc/apt/sources.list.d/shells:fish:release:3.list \
    && curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:3/Debian_12/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/shells_fish_release_3.gpg > /dev/null \
    && apt-get update \
    && apt-get -y install --no-install-recommends fish

# Install CLI tools (single layer for efficiency)
RUN set -eux \
    # sops
    && curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64" -o /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops \
    # age
    && curl -fsSL "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz" | tar xz -C /tmp \
    && mv /tmp/age/age /tmp/age/age-keygen /usr/local/bin/ \
    && chmod +x /usr/local/bin/age /usr/local/bin/age-keygen \
    && rm -rf /tmp/age \
    # kubeconform
    && curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/kubeconform \
    # kustomize
    && curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/kustomize \
    # talosctl
    && curl -fsSL "https://github.com/siderolabs/talos/releases/download/${TALOSCTL_VERSION}/talosctl-linux-amd64" -o /usr/local/bin/talosctl \
    && chmod +x /usr/local/bin/talosctl \
    # talhelper
    && curl -fsSL "https://github.com/budimanjojo/talhelper/releases/download/${TALHELPER_VERSION}/talhelper_linux_amd64.tar.gz" | tar xz -C /usr/local/bin talhelper \
    && chmod +x /usr/local/bin/talhelper \
    # yq
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    # kubectl
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    # helm
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm \
    && chmod +x /usr/local/bin/helm \
    # helmfile
    && curl -fsSL "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_amd64.tar.gz" | tar xz -C /usr/local/bin helmfile \
    && chmod +x /usr/local/bin/helmfile \
    # stern
    && curl -fsSL "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_${STERN_VERSION#v}_linux_amd64.tar.gz" | tar xz -C /usr/local/bin stern \
    && chmod +x /usr/local/bin/stern \
    # gh (GitHub CLI)
    && curl -fsSL "https://github.com/cli/cli/releases/download/${GH_VERSION}/gh_${GH_VERSION#v}_linux_amd64.tar.gz" | tar xz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION#v}_linux_amd64/bin/gh" \
    && chmod +x /usr/local/bin/gh \
    # jq
    && curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" -o /usr/local/bin/jq \
    && chmod +x /usr/local/bin/jq \
    # gitleaks - powers the .githooks/pre-commit secret gate
    && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz" | tar xz -C /usr/local/bin gitleaks \
    && chmod +x /usr/local/bin/gitleaks \
    # bws (Bitwarden Secrets Manager)
    && curl -fsSL "https://github.com/bitwarden/sdk-sm/releases/download/bws-${BWS_VERSION}/bws-x86_64-unknown-linux-gnu-${BWS_VERSION#v}.zip" -o /tmp/bws.zip \
    && unzip -o /tmp/bws.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/bws \
    && rm -f /tmp/bws.zip

# Create directories and set fish as default shell
RUN mkdir -p /home/vscode/.bin /home/vscode/.config/fish/completions /home/vscode/.claude \
    && chown -R vscode:vscode /home/vscode/.bin /home/vscode/.config /home/vscode/.claude \
    && usermod -s /usr/bin/fish vscode || true

# fish remains the *interactive* shell (usermod above + the VS Code terminal
# profile). SHELL is what non-interactive tooling reads, and CLI agents emit bash
# syntax, so point it at bash instead.
ENV SHELL=/bin/bash

USER vscode

# Claude Code CLI — native install (no Node.js needed), lands in ~/.local/bin.
# Deliberately unpinned: the CLI self-updates at runtime, so a pinned version
# here would be stale on first launch anyway.
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && /home/vscode/.local/bin/claude --version

ENV PATH="/home/vscode/.local/bin:${PATH}"

COPY --chown=vscode:vscode setup.sh /tmp/devcontainer/setup.sh
COPY --chown=vscode:vscode fish-config.fish /tmp/devcontainer/fish-config.fish

RUN chmod +x /tmp/devcontainer/setup.sh \
    && /tmp/devcontainer/setup.sh \
    && rm -rf /tmp/devcontainer

