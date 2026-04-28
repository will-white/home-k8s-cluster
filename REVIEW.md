# Cluster Best-Practices Review

Tracking document for the cluster-wide review against Kubernetes / GitOps
best practices (not the opinions in `AGENTS.md`). Items are grouped by theme
and tagged with priority and effort. Tick items off as PRs land.

Legend:
- **P0** = do first, high impact / low effort or high risk
- **P1** = important, schedule soon
- **P2** = nice to have / long tail
- Effort: **S** ≤ 1h, **M** ≤ 1 day, **L** > 1 day

---

## 🔴 Reliability & Safety

- [ ] **P1 / M — Audit CPU requests & limits.** Set realistic requests
  everywhere; add CPU limits on bursty workloads (Frigate FFmpeg, paperless
  OCR, *arr scans, postgres). Use Goldilocks/VPA in recommend-only mode to
  derive numbers.
- [ ] **P0 / S — PodDisruptionBudgets.** Add to every Deployment with
  replicas ≥ 1. Singletons: `maxUnavailable: 0`; HA: `minAvailable: 1`.
  ingress-nginx already had it; CoreDNS PDB added 2026-04-28.
- [ ] **P1 / M — Probe audit.** Ensure every workload has liveness +
  readiness; add `startupProbe` for slow-booting apps (paperless,
  home-assistant, frigate).
- [x] **P0 / M — Default-deny NetworkPolicy templates** shipped under
  `kubernetes/templates/network-policies/`. Per-namespace adoption
  pending (see template README for rollout order).
- [x] **P0 / S — PodSecurity admission.** Workload namespaces enforce
  `baseline` with `warn`/`audit` at `restricted`; system namespaces
  enforce `privileged`.
- [x] **P1 / S — Pin every image by digest** — Renovate `pinDigests: true`
  rule added 2026-04-28; Renovate will open PRs to pin the 29
  currently-unpinned tags (44/73 already pinned). Rolling tags
  (`latest`, `stable`, `main-stable`) on flaresolverr, kopia,
  karakeep/meilisearch, sosse, litellm need explicit pinning later —
  Renovate can only update what it can resolve.
- [x] **P1 / S — `topologySpreadConstraints`** — corrected scope:
  TSC is a no-op on `replicas=1` workloads (per Kubernetes docs),
  so the original singleton list (sonarr/radarr/prowlarr/HA/frigate/
  grafana/prometheus/alertmanager/loki) cannot benefit. Audited the
  multi-replica workloads instead: ingress-nginx external+internal,
  coredns, cilium, dragonfly, rook-ceph already had TSC. Added TSC
  on EMQX core (3-replica STS, was missing). HA for the singletons
  is a separate, larger item (would require chart changes to
  support multiple replicas).

## 🔴 Secrets & Supply Chain

- [x] **P0 / S — Verify git history.** Done: no sensitive paths ever
  committed; all `kind: Secret` files are SOPS-encrypted.
- [x] **P0 / S — Gitleaks CI.** Added `.github/workflows/gitleaks.yaml`
  (PR + push + weekly full-history scan).
- [x] **P0 / S — SOPS-encryption-check workflow.** Added
  `.github/workflows/sops-check.yaml` + `scripts/sops-check.sh`.
- [ ] **P1 / S — Branch protection: require signed commits** + status
  checks (kubeconform, yamllint, kustomize-build, flux-diff, gitleaks,
  trivy).
- [ ] **P1 / M — Cosign image signing + Kyverno verify policy** for
  images we build.
- [ ] **P1 / S — Trivy scan** on PRs that change `tag:` lines, plus
  scheduled scan of currently-deployed images.
- [ ] **P2 / M — SOPS multi-recipient + rotation runbook.**

## 🔴 GitOps Structure

- [ ] **P1 / M — Shared Kustomize components.** Extract `components/arr-base/`
  for the postgres init container, exportarr sidecar, security context,
  ingress + homepage annotations, ServiceMonitor. Same for the per-app
  `ks.yaml` skeleton.
- [x] **P1 / S — `wait: true` on dependency anchors** — verified 2026-04-28.
  All anchor Kustomizations (`cloudnative-pg-cluster`, `dragonfly-cluster`,
  `emqx-cluster`, `external-secrets-stores`, `rook-ceph-cluster`) already
  have `wait: true`. Cascade behavior (downstream apps blocking on
  `dependency '…' is not ready`) is the system working as designed.
- [x] **P1 / S — HelmRelease reliability defaults** applied 2026-04-28.
  All 74 HelmReleases now have `install.remediation.retries: 3`,
  `upgrade.{cleanupOnFail: true, remediation: {strategy: rollback,
  retries: 3}}`, and `driftDetection.mode: enabled`. The 69
  `HelmRepository`-backed HRs also got `chart.spec.interval: 1h`; the
  5 OCI-backed HRs use `chartRef` so the field doesn't apply.
- [ ] **P2 / M — Switch `HelmRepository` → `OCIRepository`** where the
  publisher supports it. Audit 2026-04-28: 24 HelmRepositories,
  consumer distribution heavily skewed to bjw-s (41 HRs); other
  multi-consumer repos: grafana(3), external-dns(3), rook-ceph(2),
  prometheus-community(2), intel(2), ingress-nginx(2). Recommend a
  staged migration: low-blast-radius single-consumer repos first
  (descheduler, spegel, stakater, postfinance, piraeus, openebs,
  node-feature-discovery, metrics-server, jetstack, external-secrets,
  emqx, coredns, cloudnative-pg, cilium), then multi-consumer ones
  (each with verified OCI URL), then bjw-s last as a dedicated PR.
  Effort revised to **M**.
- [ ] **P2 / S — Audit hard-coded IPs / FQDNs** and move into
  `cluster-settings`.

## 🟡 Storage

- [ ] **P1 / M — Stop inline NFS mounts in HelmReleases.** Define one
  `csi-driver-nfs` `StorageClass` (or PV) with tuned mount options
  (`nfsvers=4.2,hard,noatime,nconnect=8`). Apps consume PVCs.
- [ ] **P1 / S — Volsync `retain` policy explicit per app** (e.g.
  hourly=24, daily=7, weekly=4, monthly=12).
- [ ] **P1 / M — Quarterly restore CronJob** into a scratch PVC, with
  alert on failure.
- [ ] **P2 / S — Ceph health knobs.** Confirm `failureDomain: host`,
  `size: 3` on production pools; PG autoscaler on; `device_health_metrics`
  pool enabled.

## 🟡 Observability

- [ ] **P0 / M — Author PrometheusRules baseline.** Flux, cert-manager,
  Ceph, Volsync, node, kube-state-metrics. Each rule needs `severity`,
  `summary`, `description`, runbook annotation.
- [ ] **P0 / S — Alertmanager receiver wired up** (Pushover/Discord/ntfy)
  with severity-based routing and inhibition rules.
- [ ] **P1 / S — Loki retention + ingestion limits explicit.**
- [ ] **P1 / S — Promtail label cardinality audit.**
- [ ] **P1 / S — Grafana dashboards as code only** (ConfigMaps with
  `grafana_dashboard: "1"`).
- [ ] **P2 / M — Platform health dashboard** combining Flux + Ceph +
  cert-manager + ingress 5xx + node pressure.

## 🟡 CI/CD

- [ ] **P0 / S — Required PR checks** in branch protection.
- [ ] **P1 / S — Renovate grouping** for `app-template`, cilium,
  cert-manager, external-secrets; pin GH Actions to SHAs; auto-merge
  patch from trusted publishers.
- [ ] **P1 / L — `actions-runner-controller` in-cluster** for proper
  `flux diff` / `kubectl auth can-i` / smoke tests.
- [ ] **P1 / M — Conftest or Kyverno policy CI.** Enforce labels, image
  registry allow-list, no `:latest`, no `hostPath`, securityContext
  baseline. Fail in PR, not at runtime.

## 🟡 Cluster Topology

- [ ] **P1 / S — Talos kubelet `kubeReserved` / `systemReserved`** tuned
  so eviction triggers correctly.
- [ ] **P1 / S — Verify SUC plans** for Kubernetes + Talos, with
  maintenance windows.
- [ ] **P0 / M — Talos etcd backups** scheduled, off-cluster (TrueNAS or
  B2), with documented restore.

## 🟡 Application-Level

- [ ] **P2 / S — Drop Sonarr `develop` branch tracking.**
- [ ] **P1 / L — SSO (Authentik / Authelia / Pocket-ID)** in front of
  internal-only UIs.
- [ ] **P2 / S — External-DNS selector audit** (annotation-only,
  internal vs external split-horizon enforced).
- [ ] **P2 / S — cert-manager**: single ClusterIssuer per provider with
  DNS-01; staging issuer pre-staged.

## 🟢 Repo Hygiene

- [ ] **P2 / S — Delete `old/`** after confirming no references.
- [ ] **P2 / S — Convert `MISSING_APPS.md` and `TODO.md` to GitHub
  Issues** with labels.
- [ ] **P2 / M — `docs/` directory** with mermaid architecture diagram,
  bootstrap runbook, restore runbook, on-call/triage flow.
- [ ] **P1 / S — `pre-commit` config** running yamllint, kustomize
  build, gitleaks, markdownlint locally.

---

## In-flight / completed

- **2026-04-28** — Renovate `pinDigests: true` enabled. Renovate will
  proactively pin any image lacking an `@sha256:` digest.
- **2026-04-28** — EMQX core (3-replica STS) gained explicit
  `topologySpreadConstraints` across `kubernetes.io/hostname` with
  `whenUnsatisfiable: DoNotSchedule`. All other multi-replica
  workloads we own already had TSC.
- **2026-04-28** — HelmRelease reliability baseline: every HR now has
  install/upgrade remediation, rollback strategy, drift detection
  enabled, and (where applicable) explicit chart polling interval.
  Drift detection immediately surfaced an obsolete
  `CephObjectStore.spec.healthCheck.bucket` field (removed in rook
  v1.19+) that had been silently dropped at apply time; fixed in
  same PR.
- **2026-04-28** — Verified `wait: true` already in place on all Flux
  dependency anchor Kustomizations.
- **2026-04-28** — Secret-leak prevention: gitleaks workflow,
  sops-check workflow + script. History audit clean.
- **2026-04-28** — Alerting baseline: Flux / cert-manager / Volsync
  PrometheusRules; Alertmanager Pushover + heartbeat receivers wired
  with file-mounted secrets and severity-based routing.
  **Action required:** add `ALERTMANAGER_PUSHOVER_USER_KEY` to the
  `alertmanager` secret in Bitwarden before merging.
- **2026-04-28** — PodSecurity admission labels on every namespace
  (workload namespaces: enforce baseline / warn+audit restricted;
  system namespaces: privileged).
- **2026-04-28** — CoreDNS PodDisruptionBudget (`minAvailable: 1`)
  enabled via chart values.
- **2026-04-28** — NetworkPolicy template library at
  `kubernetes/templates/network-policies/` (default-deny + allow-dns,
  allow-kube-apiserver, allow-from-ingress, allow-from-monitoring).
  Adoption is opt-in per namespace; suggested rollout order in the
  template README.
