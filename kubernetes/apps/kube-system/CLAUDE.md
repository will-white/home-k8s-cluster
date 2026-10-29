# kube-system — domain guide (`@infra-agent`)

Loaded automatically for work under `kubernetes/apps/kube-system/`. Everything
here is cluster-critical; most of it is installed once by the Talos bootstrap
(`kubernetes/bootstrap/`) and then managed by Flux.

## Components

| App | Notes |
|---|---|
| cilium | CNI, kube-proxy replacement, Gateway API, L2 announcements and BGP. Helm values in `app/helm-values.yaml` (shared with bootstrap); `config/cilium-l2.yaml` and `config/cilium-bgp.yaml` hold the IP pools and policies |
| coredns | Cluster DNS |
| metrics-server, descheduler, reloader, spegel | Platform helpers; spegel mirrors images between nodes |
| node-feature-discovery, intel-device-plugin | Hardware labels and Intel GPU plugin consumed by Frigate / tdarr `nodeSelector`s |
| kubelet-csr-approver, node-fencer | Talos node lifecycle |

## LoadBalancer IP rules

- **Two pools, disjoint by label.** `bgp-pool` (`192.168.110.0/24`) selects
  Services labelled `lb-pool: bgp`; `l2-pool` (`192.168.5.0/24`) and the L2
  announcement policy select everything **without** that label. A Service can
  never be claimed by both.
- **New LoadBalancer Services go on BGP**: label `lb-pool: bgp` plus
  `lbipam.cilium.io/ips: <192.168.110.x>` from `cluster-settings.yaml`
  (`${EMQX_LB}`, `${POSTGRES_LB}`, ...). Add the variable there, never
  hard-code the IP in the app.
- **L2 is for devices that hard-code a LAN IP** (UniFi inform address today).
  Moving such a Service means re-pointing those devices first.
- BGP peering: ASN 64512 (cluster) ↔ 64513 (OPNsense `192.168.5.1`), fast
  timers, graceful restart. Runbook:
  [docs/runbooks/cilium-bgp-opnsense.md](../../../docs/runbooks/cilium-bgp-opnsense.md).

## Boundaries

- Cilium chart bumps roll every node's agent: read the upstream notes, check
  the Helm values diff with `flate`, and keep `updateStrategy.rollingUpdate.maxUnavailable: 1`.
- The Helm values are also used at bootstrap: a value that only works on a
  running cluster (CRDs from another chart, for example) breaks `task
  bootstrap:*`.
- Never set CPU limits; keep the Kyverno policy reports clean.

## Validate

```bash
task kubernetes:validate APP=<ns>/<app>      # wraps the checks below
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/kube-system/cilium/app | kubeconform -strict -ignore-missing-schemas -
kubectl get ciliumloadbalancerippool,ciliumbgpclusterconfig,ciliuml2announcementpolicy   # read-only
kubectl -n kube-system exec ds/cilium -- cilium bgp peers
```
