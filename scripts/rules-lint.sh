#!/usr/bin/env bash
# Lint alerting/recording rules and the Alloy pipeline offline.
#
#   1. PrometheusRule objects  -> promtool check rules  (PromQL + rule schema)
#   2. Loki rule ConfigMaps    -> lokitool rules prepare (LogQL + rule schema)
#   3. Alloy config            -> alloy validate         (River syntax + components)
#
# Loki's ruler loads rule files from the sidecar without validating them: a
# bad LogQL expression is only visible as an error in the loki logs, and the
# alert silently never fires. lokitool has no `lint` subcommand, but every
# `rules` subcommand parses the files with Loki's own LogQL parser first and
# aborts with "unable to parse rules files" on a bad expression. `prepare`
# is the only one that needs no ruler endpoint, so that is the check; its
# own PromQL rewrite step then fails on valid LogQL pipelines, which is why
# the exit code is ignored and only the parse error is matched.
#
# Usage: scripts/rules-lint.sh [kubernetes-dir]
set -o errexit
set -o nounset
set -o pipefail

KUBERNETES_DIR="${1:-kubernetes}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 1; }; }
need yq
need promtool
need lokitool

status=0

echo "=== PrometheusRule (promtool check rules) ==="
mkdir -p "${WORK}/prom"
while IFS= read -r file; do
    out="${WORK}/prom/$(echo "${file}" | tr '/' '_')"
    # One file may hold several documents; keep only PrometheusRule specs.
    yq 'select(.kind == "PrometheusRule") | .spec' "${file}" > "${out}"
done < <(grep -rl --include='*.yaml' '^kind: PrometheusRule$' "${KUBERNETES_DIR}")
if [ -n "$(ls -A "${WORK}/prom")" ]; then
    promtool check rules "${WORK}"/prom/* || status=1
else
    echo "no PrometheusRule objects found"
fi

echo "=== Loki rules (lokitool parse) ==="
mkdir -p "${WORK}/loki"
# Loki rules are plain rule files mounted via configMapGenerator (loki_rule
# label); they all live in resources/lokirule.yaml next to the owning app.
while IFS= read -r file; do
    cp "${file}" "${WORK}/loki/$(echo "${file}" | tr '/' '_')"
done < <(find "${KUBERNETES_DIR}" -type f -name 'lokirule.yaml')
if [ -n "$(ls -A "${WORK}/loki")" ]; then
    for f in "${WORK}"/loki/*; do
        echo "Checking ${f##*/}"
        if lokitool rules prepare --no-in-place "${f}" 2>&1 >/dev/null \
            | grep -E 'unable (to )?parse rules file' ; then
            status=1
        fi
    done
else
    echo "no Loki rule files found"
fi

echo "=== Alloy config (alloy validate) ==="
ALLOY_HR="${KUBERNETES_DIR}/apps/observability/alloy/app/helmrelease.yaml"
if [ -f "${ALLOY_HR}" ]; then
    need alloy
    yq -r '.spec.values.alloy.configMap.content' "${ALLOY_HR}" > "${WORK}/config.alloy"
    alloy validate "${WORK}/config.alloy" || status=1
else
    echo "no Alloy HelmRelease at ${ALLOY_HR}, skipping"
fi

if [ "${status}" -ne 0 ]; then
    echo "rules-lint: FAILED" >&2
    exit 1
fi
echo "rules-lint: OK"
