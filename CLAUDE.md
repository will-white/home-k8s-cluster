# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A home Kubernetes cluster running on **Talos Linux**, managed entirely via **Flux GitOps**. Everything is declarative YAML under `kubernetes/`; Flux reconciles the live cluster from the `main` branch of the GitHub repo. There is no application source code here — the unit of work is Kubernetes manifests (HelmReleases, Kustomizations, ExternalSecrets, etc.).

**Read [AGENTS.md](./AGENTS.md) first.** It is the authoritative source for agent policy (allowed/forbidden actions, secret handling, human-approval gates) and indexes the specialist roles (`@media-agent`, `@home-agent`, `@observability-agent`, `@storage-agent`, `@db-agent`, `@infra-agent`, ...). Per-domain conventions live next to the manifests in `kubernetes/apps/<ns>/CLAUDE.md` and load automatically when you work in that tree. This file summarizes the mechanics; AGENTS.md governs the rules. Procedures (add an app, add a secret, Flux troubleshooting, restores) are indexed in [docs/README.md](./docs/README.md).

**Claude Code setup in this repo.** `.claude/settings.json` pre-approves the read-only inner loop (kustomize, kubeconform, yamllint, flux build, flate, git reads, kubectl get) and denies secret-revealing commands (`sops -d`, `bws secret get`, reading `age.key` / `kubeconfig`). `.claude/hooks/session-start.sh` installs the pinned validation tools in cloud sessions; `.claude/hooks/yamllint-on-edit.sh` lints every YAML file you edit. Skills: `/validate-app`, `/new-app`, `/expose-app`, `/onboard-volsync`, `/merge-renovate-prs`.

**Cloud sessions have no cluster credentials.** Without `KUBECONFIG` you can validate and open PRs but not reconcile, inspect or watch a rollout, so do not merge your own PR from such a session; report CI and hand the merge to the owner.

## Commands

Task runner is **Go-Task** (`Taskfile.yaml` + `.taskfiles/`). `KUBECONFIG` and `SOPS_AGE_KEY_FILE` are set automatically by Task from repo-root files.

```bash
task                              # list all tasks
task kubernetes:validate APP=media/sonarr   # ONE app: yamllint, kustomize+kubeconform, flux build, flate render — the inner loop
task kubernetes:kubeconform       # validate ALL manifests — run before proposing any change
task kubernetes:rules-lint        # promtool / lokitool / alloy validate on alert rules and the log pipeline
task kubernetes:resources         # dump nodes/ks/hr/pods/etc. cluster-wide (support snapshot)
task kubernetes:apply-ks PATH=media/sonarr   # server-side apply one app's Flux Kustomization
task kubernetes:reconcile         # force Flux to pull + reconcile from Git (owner standing-approval; monitor after)
```

`task kubernetes:validate` wraps the single-app checks below (`scripts/validate-app.sh`); run them by hand when Task is unavailable:
```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/<ns>/<app>/app \
  | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
# Dry-run the Flux Kustomization for one app:
flux build ks <app> --kustomization-file kubernetes/apps/<ns>/<app>/ks.yaml --path kubernetes/apps/<ns>/<app>/app --dry-run
yamllint kubernetes/apps/<ns>/<app>            # or lint a whole stack folder
```

Read-only cluster inspection: `kubectl -n <ns> get hr,ks,pods,pvc`. CI mirrors local validation via `.github/workflows/`: `kubeconform.yaml`, `yamllint.yaml`, `rules-lint.yaml`, `shellcheck.yaml`, `sops-check.yaml`, `gitleaks.yaml`, and `flux-diff.yaml`, whose Flux Render job templates every Kustomization and HelmRelease with flate, so a bad chart value fails the PR, not the cluster.

## Architecture / reconciliation flow

- **Entry point:** `kubernetes/flux/config/cluster.yaml` defines the `home-kubernetes` GitRepository (only `/kubernetes` is synced) and the root `cluster` Kustomization pointing at `./kubernetes/flux`. SOPS decryption and `postBuild.substituteFrom` (`cluster-settings` ConfigMap + `cluster-secrets` Secret) are configured here.
- **Fan-out:** each namespace folder under `kubernetes/apps/<ns>/` has a `kustomization.yaml` listing every app's `ks.yaml`. Each `ks.yaml` is a Flux `Kustomization` in namespace `flux-system` with `targetNamespace: <ns>`, `path: ./kubernetes/apps/<ns>/<app>/app`, `sourceRef: home-kubernetes`, and `postBuild.substitute.APP: <app>`.
- **`dependsOn`** in `ks.yaml` orders reconciliation (e.g. `cloudnative-pg-cluster`, `external-secrets-stores`). Wire these explicitly for DB / secret-store dependencies.
- **Variable substitution:** never hard-code environment values. Cluster-wide vars live in `kubernetes/flux/vars/cluster-settings.yaml` (e.g. `${NAS_IP}`, `${TIMEZONE}`, load-balancer IPs) and encrypted values in `cluster-secrets.sops.yaml` (e.g. `${SECRET_DOMAIN}`). Reference them as `${VAR}` in manifests.
- **Shared templates:** `kubernetes/templates/{gatus,volsync,network-policies}/` are consumed by many apps — a change there affects every consumer, so reconcile + smoke-test.

## Per-app layout convention

Mirror existing apps exactly:
```
kubernetes/apps/<ns>/<app>/
  ks.yaml                    # Flux Kustomization (namespace: flux-system, targetNamespace: <ns>)
  app/
    kustomization.yaml
    helmrelease.yaml         # prefer app-template (bjw-s) unless upstream chart is clearly better
    pvc.yaml                 # if stateful
    externalsecret.yaml      # if secrets needed — ExternalSecret ONLY, never a plain Secret
    gatus.yaml               # health endpoint for user-facing apps (templates/gatus, or a TCP check ConfigMap)
    resources/               # ConfigMaps, scripts, lokirule.yaml, etc.
```
Namespaces are fixed per domain (media apps → `media`; Home Assistant/IoT → `default`; MQTT broker → `database`). Before adding a namespace, confirm with the user. Search `https://kubesearch.dev` for an existing chart before writing custom manifests.

## Secrets (hard rules)

- **Never commit an unencrypted secret.** Secrets in Git are SOPS+Age encrypted (`.sops.yaml` rules: `kubernetes/**/*.sops.yaml` encrypts `data`/`stringData`; `talos/**/*.sops.yaml` encrypts fully). Age key is `age.key` at repo root.
- In-cluster secrets come from **Bitwarden Secrets Manager via ExternalSecrets** (`external-secrets-stores`), not from committed Secret manifests. The `bws` CLI may create/update Bitwarden secrets **only when explicitly requested**; never print, log, or echo raw secret values — confirm by key name and success/failure only.
- `sops --encrypt` and cluster-mutating Ceph/PVC/snapshot operations require human approval (see AGENTS.md). `age.key`, `kubeconfig`, `talosconfig`, and `*.key` files are local credentials — do not commit or leak them.

## Conventions worth knowing

- **Resources:** always set `resources.requests` and cap `limits.memory`; do **not** set CPU limits.
- **Storage:** StorageClasses are a closed set — `ceph-block`, `ceph-filesystem`, `openebs-hostpath`. Don't invent new ones. Stateful user-data apps use the shared `templates/volsync/` (Kopia → MinIO) backup pattern; Volsync Kopia movers need `moverResources` (floor: `requests memory 512Mi` / `limits 2Gi`).
- **Databases:** *arr / apps that support Postgres MUST use `cloudnative-pg-cluster` (add to `dependsOn`) rather than embedded SQLite.
- **Exposure:** no Ingress objects. app-template apps use a `route:` block (HTTPRoute) with `parentRefs` to Gateway `internal` in namespace `network` (`external` for the few public apps, which cloudflared fronts); `sectionName: https` and `timeouts.request: 0s`. Raw HTTPRoutes for charts without route support. Default-deny namespaces reach the Gateway through the `allow-from-ingress` CiliumNetworkPolicy template.
- **LoadBalancer IPs:** label `lb-pool: bgp` plus `lbipam.cilium.io/ips` from `192.168.110.0/24` (routed via BGP to OPNsense). Only Services whose off-cluster clients hard-code a LAN IP stay on the L2 `192.168.5.0/24` (UniFi). See `docs/runbooks/cilium-bgp-opnsense.md`.
- **Policies:** Kyverno (`kubernetes/apps/kyverno`) audits the rules above (no `:latest`, digests, requests + memory limit, no CPU limit). Keep `kubectl get policyreport -A` clean; nothing is enforced yet.
- **Observability:** scrape via `ServiceMonitor`/`PodMonitor` selectors; deliver Grafana dashboards as ConfigMaps labeled `grafana_dashboard: "1"` in the `observability` namespace. Alert rules are linted in CI (`task kubernetes:rules-lint`).
- Treat config files (`recyclarr.yml`, Kometa configs, Home Assistant / zigbee2mqtt YAML) as code — review their diffs like manifests.
