# Network Policy templates

Reusable Kustomize bases for adopting a **default-deny** posture per
namespace, with the minimum allow-rules every workload needs.

## Layers

The pattern is layered — apply only what you need, in this order:

1. **`default-deny/`** — denies all ingress and egress in the target namespace.
2. **`allow-dns/`** — egress to `kube-system` CoreDNS on UDP/TCP 53.
3. **`allow-kube-apiserver/`** — egress to the Kubernetes API server.
4. **`allow-from-ingress/`** — ingress from `ingress-nginx` controllers.
5. **`allow-from-monitoring/`** — ingress from Prometheus / kube-state-metrics
   for `ServiceMonitor` scrapes (port-agnostic; rely on selectors).

Each base is namespace-scoped; consume them from a namespace's
`kustomization.yaml` like:

```yaml
resources:
  - ../../../templates/network-policies/default-deny
  - ../../../templates/network-policies/allow-dns
  - ../../../templates/network-policies/allow-kube-apiserver
  - ../../../templates/network-policies/allow-from-ingress
  - ../../../templates/network-policies/allow-from-monitoring
```

## Adoption order (suggested)

Roll out in this order to surface breakage early without taking down
critical paths:

1. `cert-manager` — small, well understood, only needs DNS + API + ACME egress.
2. `external-secrets` — needs DNS + API + Bitwarden API egress.
3. `observability` — sources of truth for what's broken; do this once
   alerting is solid.
4. `media`, `default`, `database` — broadest blast radius; do these last.
5. `network`, `kube-system`, `flux-system` — handled separately; these
   namespaces host their own controllers and need bespoke policies.

## App-specific egress

For app-specific egress (Cloudflare API, Bitwarden API, NAS NFS, MQTT
broker, etc.), add a per-app `NetworkPolicy` next to the HelmRelease;
do **not** loosen the default-deny here.

## Dependencies

- Cilium is the CNI in this cluster, so `NetworkPolicy` + `CiliumNetworkPolicy`
  both work. Prefer plain `NetworkPolicy` for portability; reach for
  `CiliumNetworkPolicy` only when you need L7 (HTTP method/path,
  Kafka, DNS FQDN) or `toFQDNs` egress rules.
