#!/usr/bin/env bash
# Print the value of a Bitwarden Secrets Manager secret by key name.
# Token resolution order:
#   1. $BWS_ACCESS_TOKEN from the environment
#   2. the SOPS-encrypted ESO machine-account token committed in the repo
#      (requires age.key / $SOPS_AGE_KEY_FILE)
# Used by the talos taskfiles to inject ${nut_monpwd} into `talhelper
# genconfig` without a committed talenv file — Bitwarden is the single
# canonical store for that password (TrueNAS and the other NUT secondaries
# use the same one). Prints the raw value to stdout; callers capture it.
set -euo pipefail
KEY="${1:?usage: bws-secret.sh <SECRET_KEY>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOKEN_FILE="$ROOT/kubernetes/apps/external-secrets/external-secrets/stores/bitwarden-secrets/bitwarden-access-token.sops.yaml"

TOKEN="${BWS_ACCESS_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$ROOT/age.key}"
  TOKEN="$(sops -d --extract '["stringData"]["token"]' "$TOKEN_FILE")"
fi

ID="$(BWS_ACCESS_TOKEN="$TOKEN" bws secret list --output json | jq -r --arg k "$KEY" '.[] | select(.key==$k) | .id' | head -1)"
if [ -z "$ID" ]; then
  echo "ERROR: secret '$KEY' not found in Bitwarden SM (does it exist, and can the machine account read it?)" >&2
  exit 1
fi
BWS_ACCESS_TOKEN="$TOKEN" bws secret get "$ID" --output json | jq -r '.value'
