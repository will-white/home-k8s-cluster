#!/usr/bin/env bash
# SessionStart hook for Claude Code cloud sessions.
#
# A cloud session starts from a bare container: none of the validation tools
# the repo expects (task, kustomize, kubeconform, flux, flate, yamllint,
# promtool, lokitool, alloy, gitleaks, yq) are present, and get.helm.sh / ghcr blob
# downloads are blocked by the egress proxy while GitHub releases and PyPI
# are allowed. This installs the same pinned versions CI and the devcontainer
# use, into ~/.local/bin, so `task kubernetes:validate`, `task
# kubernetes:kubeconform`, `task kubernetes:rules-lint` and `flate test` work
# before the first prompt. The devcontainer image already ships everything,
# so it is a no-op outside the cloud.
#
# Idempotent: the install only re-runs when this script changes (versions are
# pinned here, with renovate comments so Renovate bumps them alongside the
# workflows and the devcontainer Dockerfile).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

BIN="${HOME}/.local/bin"
mkdir -p "${BIN}"
export PATH="${BIN}:${PATH}"

hashes="${BIN}/.session-start.sha256"
if ! sha256sum --check --status "${hashes}" 2>/dev/null; then
  rm -f "${hashes}"
  work="$(mktemp -d)"
  trap 'rm -rf "${work}"' EXIT

  fetch() { # url dest
    curl -sSfL --retry 5 --retry-delay 3 --retry-all-errors -o "$2" "$1"
  }

  # renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/(?<version>.+)$
  KUSTOMIZE_VERSION="v5.8.3"
  fetch "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" "${work}/kustomize.tgz"
  tar xzf "${work}/kustomize.tgz" -C "${BIN}" kustomize

  # renovate: datasource=github-releases depName=yannh/kubeconform
  KUBECONFORM_VERSION="v0.8.0"
  fetch "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" "${work}/kubeconform.tgz"
  tar xzf "${work}/kubeconform.tgz" -C "${BIN}" kubeconform

  # renovate: datasource=github-releases depName=fluxcd/flux2
  FLUX_VERSION="2.9.6"
  fetch "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz" "${work}/flux.tgz"
  tar xzf "${work}/flux.tgz" -C "${BIN}" flux

  # renovate: datasource=github-releases depName=home-operations/flate
  FLATE_VERSION="v0.6.5"
  fetch "https://github.com/home-operations/flate/releases/download/${FLATE_VERSION}/flate_${FLATE_VERSION#v}_linux_amd64.tar.gz" "${work}/flate.tgz"
  tar xzf "${work}/flate.tgz" -C "${BIN}" flate

  # renovate: datasource=github-releases depName=mikefarah/yq
  YQ_VERSION="v4.54.1"
  fetch "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" "${BIN}/yq"

  # renovate: datasource=github-releases depName=prometheus/prometheus
  PROMETHEUS_VERSION="v3.9.1"
  fetch "https://github.com/prometheus/prometheus/releases/download/${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION#v}.linux-amd64.tar.gz" "${work}/prometheus.tgz"
  tar xzf "${work}/prometheus.tgz" -C "${BIN}" --strip-components=1 "prometheus-${PROMETHEUS_VERSION#v}.linux-amd64/promtool"

  # renovate: datasource=github-releases depName=grafana/loki
  LOKI_VERSION="v3.7.9"
  fetch "https://github.com/grafana/loki/releases/download/${LOKI_VERSION}/lokitool-linux-amd64.zip" "${work}/lokitool.zip"
  unzip -qo "${work}/lokitool.zip" -d "${work}" && mv "${work}/lokitool-linux-amd64" "${BIN}/lokitool"

  # renovate: datasource=github-releases depName=grafana/alloy
  ALLOY_VERSION="v1.21.2"
  fetch "https://github.com/grafana/alloy/releases/download/${ALLOY_VERSION}/alloy-linux-amd64.zip" "${work}/alloy.zip"
  unzip -qo "${work}/alloy.zip" -d "${work}" && mv "${work}/alloy-linux-amd64" "${BIN}/alloy"

  # renovate: datasource=github-releases depName=go-task/task
  TASK_VERSION="v3.52.0"
  fetch "https://github.com/go-task/task/releases/download/${TASK_VERSION}/task_linux_amd64.tar.gz" "${work}/task.tgz"
  tar xzf "${work}/task.tgz" -C "${BIN}" task

  # renovate: datasource=github-releases depName=gitleaks/gitleaks
  GITLEAKS_VERSION="v8.30.1"
  fetch "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz" "${work}/gitleaks.tgz"
  tar xzf "${work}/gitleaks.tgz" -C "${BIN}" gitleaks

  chmod +x "${BIN}"/kustomize "${BIN}"/kubeconform "${BIN}"/flux "${BIN}"/flate "${BIN}"/yq "${BIN}"/promtool "${BIN}"/lokitool "${BIN}"/alloy "${BIN}"/task "${BIN}"/gitleaks

  # yamllint has no release binary; PyPI is reachable through the proxy.
  PIP_ROOT_USER_ACTION=ignore python3 -m pip install --quiet --user --disable-pip-version-check yamllint

  sha256sum .claude/hooks/session-start.sh > "${hashes}"
fi

# Every session: tools on PATH, the gitleaks pre-commit gate active, and the
# same env the devcontainer sets for task/direnv.
echo "export PATH=\"${BIN}:\${PATH}\"" >> "${CLAUDE_ENV_FILE:-/dev/null}"
git config core.hooksPath .githooks

echo "session-start: task $(task --version 2>/dev/null), $(kustomize version 2>/dev/null | head -1), kubeconform $(kubeconform -v 2>/dev/null), flux $(flux version --client 2>/dev/null | awk '{print $2}'), flate $(flate --version 2>/dev/null | awk '{print $NF}'), yamllint $(yamllint --version 2>/dev/null | awk '{print $2}')"
