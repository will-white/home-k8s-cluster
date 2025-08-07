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
    sudo \
    unzip \
    zip

# Needed for certain scripts in this repo
RUN pip install yq

# Install fish shell
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends fish

# Setup vscode user
RUN groupadd --gid 1000 vscode \
    && useradd --uid 1000 --gid 1000 -m vscode \
    && apt-get install -y sudo \
    && echo vscode ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

# Set user
USER vscode

# Set default shell
SHELL ["/usr/bin/fish", "-l", "-c"]
ENV SHELL=/usr/bin/fish
CMD ["fish"]
