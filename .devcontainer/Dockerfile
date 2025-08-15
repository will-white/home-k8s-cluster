FROM mcr.microsoft.com/devcontainers/base:debian

# Install common packages
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    build-essential \
    curl \
    git \
    gnupg2 \
    jq \
    procps \
    python3-venv \
    sudo \
    unzip \
    zip

# Install yq
RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Install fish shell
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends fish

# The vscode user is already created in the base image, so this is not needed.

# Set user
USER vscode

# Set default shell
SHELL ["/usr/bin/fish", "-l", "-c"]
ENV SHELL=/usr/bin/fish
CMD ["fish"]

