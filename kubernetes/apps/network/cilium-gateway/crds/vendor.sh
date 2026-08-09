#!/usr/bin/env bash
# Re-vendor the Gateway API standard-channel CRDs. Bump VERSION, run this from
# its own directory, and update the version references in ../kustomization.yaml
# and this directory's files in one commit.
set -euo pipefail
VERSION="v1.6.1"
cd "$(dirname "$0")/vendor"
for crd in gatewayclasses gateways httproutes grpcroutes referencegrants backendtlspolicies tlsroutes; do
  curl -fsSL -o "gateway.networking.k8s.io_${crd}.yaml" \
    "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${VERSION}/config/crd/standard/gateway.networking.k8s.io_${crd}.yaml"
done
grep -h -m1 "bundle-version" ./*.yaml | sort -u
