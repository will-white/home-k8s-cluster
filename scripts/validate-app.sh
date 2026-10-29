#!/usr/bin/env bash
# Inner-loop validation for ONE app: the same checks CI runs, scoped to a
# single kubernetes/apps/<ns>/<app> folder so the result comes back in seconds.
#
#   1. yamllint          repo config, the whole app folder
#   2. kustomize build   LoadRestrictionsNone (templates live outside the app)
#   3. kubeconform       strict, same skip list and schema catalogs as CI
#   4. flux build ks     dry-run of the Flux Kustomization (substitution shape,
#                        dependsOn/targetNamespace typos). Needs a kubeconfig;
#                        skipped with a note when there is none (cloud sessions).
#   5. flate test        full Helm render of the app's HelmRelease(s) when
#                        flate is installed, so a bad chart value fails here.
#
# Usage: scripts/validate-app.sh <ns>/<app>        e.g. media/sonarr
set -o errexit
set -o nounset
set -o pipefail

APP_PATH="${1:?usage: validate-app.sh <namespace>/<app>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT}/kubernetes/apps/${APP_PATH}"

[ -d "${APP_DIR}/app" ] || { echo "no such app: ${APP_DIR}/app" >&2; exit 1; }
[ -f "${APP_DIR}/ks.yaml" ] || { echo "missing ${APP_DIR}/ks.yaml" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1 (run .claude/hooks/session-start.sh or use the devcontainer)" >&2; exit 1; }; }
need yamllint
need kustomize
need kubeconform

status=0
echo "=== yamllint ${APP_PATH} ==="
yamllint -c "${ROOT}/.yamllint.yaml" "${APP_DIR}" || status=1

echo "=== kustomize build + kubeconform ${APP_PATH}/app ==="
# Same skip list and catalogs as scripts/kubeconform.sh: the skipped kinds
# carry ${VAR} placeholders in strictly-patterned fields and only validate
# post-substitution. The pages.dev catalog is unreachable from some sandboxes
# (claude.ai cloud sessions); kubeconform treats a download failure as an
# error, so probe it once and fall back to the GitHub-hosted catalog alone.
schema_args=(-schema-location default)
if curl -sfI --max-time 5 -o /dev/null https://kubernetes-schemas.pages.dev/; then
  schema_args+=(-schema-location 'https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json')
else
  echo "note: kubernetes-schemas.pages.dev unreachable, using the datreeio CRDs-catalog only"
fi
schema_args+=(-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json')
kustomize build --load-restrictor=LoadRestrictionsNone "${APP_DIR}/app" \
  | kubeconform -strict -ignore-missing-schemas \
      -skip "Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute" \
      "${schema_args[@]}" -summary - || status=1

KS_NAME="$(awk '/^  name:/{print $NF; exit}' "${APP_DIR}/ks.yaml")"
echo "=== flux build ks ${KS_NAME} (dry-run) ==="
if command -v flux >/dev/null 2>&1 && [ -f "${KUBECONFIG:-${ROOT}/kubeconfig}" ]; then
  flux build ks "${KS_NAME}" \
    --kustomization-file "${APP_DIR}/ks.yaml" \
    --path "${APP_DIR}/app" --dry-run >/dev/null || status=1
else
  echo "skipped: flux build needs a kubeconfig (none in this session); flate below renders the same tree offline"
fi

echo "=== flate test ${APP_PATH} ==="
if ! command -v flate >/dev/null 2>&1; then
  echo "skipped: flate not installed (CI's Flux Render job runs it)"
elif ! curl -sI --max-time 5 -o /dev/null https://pkg-containers.githubusercontent.com/ 2>/dev/null; then
  # ghcr chart blobs are served from pkg-containers.githubusercontent.com; a
  # sandbox that cannot reach it (claude.ai cloud sessions) cannot render any
  # chart, so the step is skipped instead of failing on every HelmRelease.
  echo "skipped: ghcr.io chart blobs unreachable from this sandbox; CI's Flux Render job renders the tree"
else
  # Render against the whole tree so dependsOn targets resolve, but only the
  # objects that belong to this app: its HelmRelease(s) when it has any
  # (that is where chart-value mistakes surface), else its Kustomization.
  # FLATE_BASE is cleared so flate does not switch to changed-only mode.
  NS="${APP_PATH%%/*}"
  mapfile -t hrs < <(awk '/^kind: HelmRelease$/{f=1} f && /^  name:/{print $NF; f=0}' "${APP_DIR}"/app/*.yaml 2>/dev/null | sort -u)
  if [ "${#hrs[@]}" -gt 0 ]; then
    for hr in "${hrs[@]}"; do
      ( cd "${ROOT}" && FLATE_BASE="" flate test hr "${hr}" --path kubernetes -n "${NS}" --no-progress ) || status=1
    done
  else
    ( cd "${ROOT}" && FLATE_BASE="" flate test ks "${KS_NAME}" --path kubernetes --no-progress ) || status=1
  fi
fi

if [ "${status}" -ne 0 ]; then
  echo "validate-app ${APP_PATH}: FAILED" >&2
  exit 1
fi
echo "validate-app ${APP_PATH}: OK"
