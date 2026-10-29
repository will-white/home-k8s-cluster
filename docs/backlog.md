# Backlog

Open items only, each still true as of 2026-10-29. Done work lives in git
history and PR descriptions, not here. Rejected ideas are at the bottom so
they are not re-proposed.

## Platform

- **SSO in front of internal UIs.** No OIDC provider exists. Pocket ID (passkeys)
  plus oauth2-proxy or Tinyauth as a Gateway ext-auth hop; the Gateway API has
  no nginx-style auth annotations, so this is the only path.
- **UniFi behind the Gateway.** The UI is HTTPS-only with a self-signed cert, so
  `unifi.<domain>` has no HTTPRoute (homepage links to the LoadBalancer Service
  on :8443). Needs a cert-manager Certificate mounted into UniFi plus a
  `BackendTLSPolicy` with the CA in a ConfigMap. UniFi also stays on L2
  (`192.168.5.25`) because adopted APs inform to that IP; moving it to the BGP
  pool means re-adopting or setting the inform host first.
- **Kyverno: graduate to Enforce.** Policies in `kubernetes/apps/kyverno` are
  Audit-only with fail-open webhooks. Once `kubectl get policyreport -A` is
  clean (burn-down: #1586 to #1590), flip `validate.failureAction` per policy
  and drop `features.forceFailurePolicyIgnore`.
- **Off-site backup target.** Kopia and CNPG land in Ceph RGW, then rclone
  mirrors to Garage. If Garage is on the same LAN, one encrypted rclone target
  in Backblaze B2 or Cloudflare R2 closes the house-level gap.
- **Inline NFS mounts → a `csi-driver-nfs` StorageClass** with tuned options
  (`nfsvers=4.2,hard,noatime,nconnect=8`). Today every media app mounts the NAS
  inline in its HelmRelease; the shared client session per node is what looped
  `TEST_STATEID` in #1591.
- **Talos kubelet `kubeReserved` / `systemReserved`** so eviction triggers
  before a node wedges.
- **SOPS multi-recipient + rotation runbook.** One Age key, no documented
  rotation.

## Storage

- **Home Assistant recorder → Postgres (CNPG).** Then `/config` is pure config
  and can move to ceph-filesystem.
- **Bazarr SQLite → Postgres.** Native support (`POSTGRES_ENABLED=true`), no
  auto-migration; fresh DB or the community script.
- **Loki chunks → Rook RGW** (`storage.type: s3`, new `loki-chunks` bucket), WAL
  on `openebs-hostpath`. Prometheus long-term to RGW only after Loki proves the
  path.
- **Frigate volume split.** One RBD PVC holds config, SQLite and recordings;
  recordings belong on ceph-filesystem, the DB on local NVMe.

## Observability

- **Alloy dashboard pin.** The four Alloy mixin dashboards in the grafana
  HelmRelease are raw URLs pinned to `v1.21.2`; Renovate cannot bump them, so
  move them with the alloy chart.
- **Probe audit.** Add `startupProbe` to slow-booting apps and check every
  workload has liveness + readiness.
- **Platform health dashboard** combining Flux, Ceph, cert-manager, Gateway 5xx
  (now from cilium-envoy access logs) and node pressure.

## CI / repo

- **Trivy** on PRs that change `tag:` lines plus a scheduled scan of running
  images; cosign verification for anything built in-house.
- **Branch protection** requiring the existing checks (Kubeconform, Flux
  Render/Diff, Rules Lint, YAML Lint, SOPS, Gitleaks).
- **`pre-commit` config** running yamllint, kustomize build and gitleaks
  locally.
- **Devcontainer tools.** `task kubernetes:rules-lint` needs `promtool`,
  `lokitool` and `alloy` on PATH; the devcontainer image does not ship them yet.

## Rejected (do not re-propose)

- **PodDisruptionBudgets on singletons.** `maxUnavailable: 0` blocks drains,
  `maxUnavailable: 1` is a no-op at `replicas: 1`. Resilience comes from node
  recovery (node-fencer, Tuppr) and RWX storage where it fits.
- **Volsync for recyclarr / kometa.** Pure caches rebuilt from Git and upstream;
  not worth the canary noise.
- **Advertising the LAN `/24` over BGP.** LAN clients ARP for on-link addresses
  and never consult the router; see `docs/runbooks/cilium-bgp-opnsense.md`.
- **CPU limits anywhere.** Repo rule, enforced by the `disallow-cpu-limits`
  Kyverno policy.
