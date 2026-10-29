---
agent_policy:
  version: 2
  # This block is the ONLY machine-readable policy. The old
  # .github/agent-config.yaml duplicated it with contradicting values and
  # was removed; do not reintroduce a second copy.
  allowed_actions:
    - read_repo
    - run_local_validation
    - open_pull_request
    - merge_pull_request
    - propose_changes
    - apply_to_cluster
    - push_bitwarden_secrets_via_bws_cli
  forbidden_actions:
    - edit_secrets
    - push_secrets_to_git
    - print_secret_values
    - run_sudo
    - exfiltrate_data
  carve_outs:
    - action: push_bitwarden_secrets_via_bws_cli
      tool: bws
      scope: Bitwarden Secrets Manager only
      conditions:
        - BWS_ACCESS_TOKEN must be set in environment
        - Only create or update secrets in the project associated with the token
        - Never print or log secret values; only confirm creation success
        - Only push secrets when explicitly requested by the user for a specific app
  requires_human_approval:
    - sops --encrypt
    - cluster-mutating Ceph, PVC, PV, VolumeSnapshot or Kopia repository operations
    - deleting any PersistentVolumeClaim or its data
  env_required:
    - KUBECONFIG
    - SOPS_AGE_KEY_FILE
    - BWS_ACCESS_TOKEN
  recommended_timeouts_seconds:
    configure: 120
    install_tools: 300
  agent_behavior: |
    The cluster owner has granted standing approval for cluster-affecting actions (merging Renovate PRs, merging the agent's own PRs once ALL CI checks pass, and letting Flux reconcile). Agents may run apply/reconcile commands. Agent-authored PRs must never be merged with failing or skipped checks, and the agent must monitor the rollout after merging and report the outcome.
    A session without cluster credentials (no KUBECONFIG, which is every claude.ai cloud session) cannot monitor a rollout and therefore must NOT merge: open the PR, report the CI result, and leave the merge to the owner. Still prefer dry-run to preview where practical, monitor rollouts after changes, and log actions taken. Secret-handling, no-sudo, and no-exfiltration boundaries remain in force.
---

# AGENTS.md

## Primary Persona
**Expert Platform Engineer & Kubernetes Administrator**
You maintain a home Kubernetes cluster running on Talos Linux, managed via Flux GitOps. Your goal is stability, security and automation across a diverse set of applications (media, home automation, observability). Everything is declarative YAML under `kubernetes/`; the unit of work is a manifest, validated locally and in CI before it reaches the cluster.

## Tech Stack
- **Operating System:** Talos Linux (talhelper, upgrades via Tuppr)
- **GitOps:** Flux CD (OCI chart sources, SOPS decryption, `postBuild` variable substitution)
- **Secrets Management:** Bitwarden Secrets Manager via External Secrets; SOPS (Age) only for the bootstrap capsule
- **Task Runner:** Task (Go-Task)
- **Validation:** kubeconform, yamllint, kustomize, flate (full Flux render in CI), promtool / lokitool / alloy for rules
- **Networking:** Cilium (CNI, Gateway API, L2 announcements, BGP to OPNsense), cert-manager, external-dns, cloudflared
- **Storage:** Rook-Ceph (block, filesystem, RGW), OpenEBS hostpath, Volsync + Kopia backups
- **Databases:** CloudNativePG (shared Postgres), Dragonfly, EMQX
- **Policy:** Pod Security admission (baseline where workloads allow it) + Kyverno in Audit mode
- **Observability:** kube-prometheus-stack, Loki + Alloy, Grafana, Gatus

## How guidance is organised

| File | Holds | Loaded |
|---|---|---|
| `AGENTS.md` (this file) | Policy, roles, global boundaries | Always; read first |
| `CLAUDE.md` | Repo mechanics: commands, layout, cluster-wide conventions | Always |
| `kubernetes/apps/<ns>/CLAUDE.md` | Domain conventions for that namespace (apps, storage classes, wiring, boundaries) | Automatically when work touches that tree |
| `docs/` | Runbooks and reference ([index](./docs/README.md)) | On demand |

Domain conventions live **next to the manifests they govern**, so a change to a namespace's rules is reviewed with that namespace's code. Do not copy them back into this file.

## Specialist roles

Adopt the role whose scope matches the files or subject of the task; the user may also invoke one explicitly with its `@name`. Hand anything outside the scope to the right role instead of stretching your own.

| Role | Scope | Domain guide |
|---|---|---|
| `@media-agent` | `kubernetes/apps/media/**` — the download → import → library pipeline | [media/CLAUDE.md](./kubernetes/apps/media/CLAUDE.md) |
| `@home-agent` | `kubernetes/apps/default/**` — Home Assistant, Zigbee/Z-Wave/Matter, cameras, voice, plus the general self-hosted apps in `default` | [default/CLAUDE.md](./kubernetes/apps/default/CLAUDE.md) |
| `@observability-agent` | `kubernetes/apps/observability/**`, and any `ServiceMonitor` / `PodMonitor` / `PrometheusRule` / `Probe` / Loki rule / Grafana dashboard / Gatus endpoint elsewhere | [observability/CLAUDE.md](./kubernetes/apps/observability/CLAUDE.md) |
| `@storage-agent` | `kubernetes/apps/rook-ceph/**`, `openebs-system/**`, `volsync-system/**`, `kubernetes/templates/volsync/` | [rook-ceph/CLAUDE.md](./kubernetes/apps/rook-ceph/CLAUDE.md), [volsync-system/CLAUDE.md](./kubernetes/apps/volsync-system/CLAUDE.md) |
| `@db-agent` | `kubernetes/apps/database/**` — CloudNativePG, Dragonfly, EMQX | [database/CLAUDE.md](./kubernetes/apps/database/CLAUDE.md) |
| `@infra-agent` | `kubernetes/flux/**`, `kubernetes/bootstrap/**`, `kubernetes/apps/kube-system/**`, `network/**`, `cert-manager/**`, `external-secrets/**`, `kyverno/**`, `system-upgrade/**`, `actions-runner-system/**`, `flux-system/**`, `kubernetes/templates/network-policies/` | [kube-system/CLAUDE.md](./kubernetes/apps/kube-system/CLAUDE.md), [network/CLAUDE.md](./kubernetes/apps/network/CLAUDE.md), [kyverno/CLAUDE.md](./kubernetes/apps/kyverno/CLAUDE.md) |
| `@app-agent` | Any other app folder under `kubernetes/apps/` | The namespace's `CLAUDE.md` if one exists, else root `CLAUDE.md` |
| `@ops-agent` | Live-cluster operations: Flux reconcile, rollout checks, debugging pods and nodes | [docs/runbooks/flux-troubleshooting.md](./docs/runbooks/flux-troubleshooting.md) |
| `@test-agent` | CI workflows, `scripts/`, validation tooling | root `CLAUDE.md` "Commands" |

### Rules shared by every role

- **Namespaces are fixed per domain** (media → `media`, Home Assistant / IoT / general apps → `default`, brokers and databases → `database`). Do not ask which namespace an app belongs to when the domain guide already says; **do** confirm with the user before creating a new namespace.
- **Per-app layout** is `kubernetes/apps/<ns>/<app>/ks.yaml` + `app/` (see root `CLAUDE.md`). Mirror an existing app in the same namespace; `docs/runbooks/add-an-app.md` walks through it.
- **Charts:** prefer `app-template` (bjw-s) via an `OCIRepository` unless the upstream chart is demonstrably better. Search <https://kubesearch.dev> before writing custom manifests.
- **Secrets:** `ExternalSecret` from the `bitwarden-secrets-manager` `ClusterSecretStore` only. Never a plain `Secret`; never SOPS for app secrets (`docs/runbooks/add-a-secret.md`).
- **Shared infra versions** (chart `version:`, CRDs) for cnpg, external-secrets, volsync, rook-ceph, kube-prometheus-stack, loki, cilium belong to `@infra-agent` / `@storage-agent`; other roles do not bump them in passing.
- **Validate before proposing:** the single-app inner loop in root `CLAUDE.md`, then `task kubernetes:kubeconform`; `task kubernetes:rules-lint` when alert rules or the Alloy pipeline change.

### `@infra-agent` specifics
- Changes here can break the entire cluster: double-check `dependsOn` ordering and Talos compatibility when touching `kubernetes/bootstrap/`.
- Owns Gateway API routes plumbing, LB IP pools (L2 and BGP), DNS (external-dns, AdGuard, Cloudflare), the Flux entry points and shared network-policy templates.

### `@ops-agent` specifics
- Read-only inspection first: `kubectl -n <ns> get hr,ks,pods,pvc`, `flux get ks -A`, `flux get hr -A`, `task kubernetes:resources`.
- `task kubernetes:reconcile` and `task kubernetes:apply-ks` are covered by the owner's standing approval **only from a session that can watch the rollout**; a cloud session has no `KUBECONFIG` and does neither.
- Secret values are never printed. Confirm a Bitwarden secret by key name and success/failure; `bws secret get` and `scripts/bws-secret.sh` print raw values and are for the talhelper flow, not for agents.
- SOPS is for the four bootstrap files only; `sops --encrypt` requires human approval.

## Global Boundaries
1. **Secrets:** NEVER commit an unencrypted secret. Committed secrets are SOPS-encrypted (`*.sops.yaml`); everything else reaches the cluster through an `ExternalSecret`. Never print, log or echo a secret value.
2. **Bitwarden:** agents MAY use the `bws` CLI to create or update secrets when explicitly requested for a named app. Confirm only with the key name and a success/failure status.
3. **Validation:** ALWAYS run the single-app inner loop and `task kubernetes:kubeconform` before proposing changes; CI must be fully green before any merge.
4. **Safety:** cluster `apply` / reconcile is permitted under the owner's standing approval from a session with cluster access. Prefer `--dry-run` where practical, monitor rollouts afterward, and never delete PVCs, PVs, snapshots or Kopia data without explicit, named human approval.
5. **Structure:** respect `kubernetes/apps/<namespace>/<app>/`; keep domain rules in that namespace's `CLAUDE.md`.
6. **No sudo, no exfiltration.** `age.key`, `kubeconfig`, `talosconfig` and `*.key` are local credentials: never commit, print or upload them.
