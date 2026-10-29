<div align="center">

### My Home Kubernetes Cluster :octocat:

_... managed with Flux, Renovate, and GitHub Actions_ 🤖

</div>

> **For AI agents and developers**: [AGENTS.md](./AGENTS.md) holds policy and roles, [CLAUDE.md](./CLAUDE.md) the commands and conventions, and each `kubernetes/apps/<ns>/CLAUDE.md` the rules for that namespace.

## 🚨 Disaster recovery

Everything needed to rebuild lives in this repo **except `age.key`** — the SOPS
Age key at the repo root that decrypts the Talos PKI, the Flux deploy key, and
the Bitwarden bootstrap token. Losing it is unrecoverable, so:

- `task bootstrap:secrets-push` uploads `age.key`, `github-deploy.key`, and
  `config.yaml` to Bitwarden Secrets Manager; **run it after any rotation**.
  `task bootstrap:secrets-pull` restores them on a fresh workstation.
- Both need `BWS_ACCESS_TOKEN` exported in your shell — keep that token (and
  ideally a printed copy of `age.key`) in your personal password manager, NOT
  only on the workstation.
- All other secrets are flat values in Bitwarden SM delivered via
  ExternalSecrets — see [docs/secrets.md](./docs/secrets.md) for the naming
  schema. The NUT upsmon password (`CLUSTER_NUT_MONPWD`) is fetched from
  Bitwarden at `talhelper genconfig` time.

Docs: [docs/README.md](./docs/README.md) indexes every runbook and reference
page (network layout, secrets schema, Flux troubleshooting, Volsync restore,
BGP, shutdown, rebuild, DR).

Open work is tracked in [docs/backlog.md](./docs/backlog.md).

## 🔧 Tools

| Tool | Purpose |
|---|---|
| [Talos Linux](https://www.talos.dev/) + [talhelper](https://github.com/budimanjojo/talhelper) | Immutable node OS; `kubernetes/bootstrap/talos`; upgrades via [Tuppr](https://github.com/home-operations/tuppr) |
| [Flux](https://fluxcd.io/) | Reconciles `kubernetes/` from `main`; OCI chart sources, SOPS decryption, variable substitution |
| [Cilium](https://cilium.io/) | CNI, kube-proxy replacement, Gateway API (`network/internal` + `external` Gateways), BGP to OPNsense for `192.168.110.0/24` and L2 announcements for the LAN `/24` |
| [Rook-Ceph](https://rook.io/) / [OpenEBS](https://openebs.io/) | `ceph-block`, `ceph-filesystem`, RGW object store; `openebs-hostpath` for scratch |
| [CloudNativePG](https://cloudnative-pg.io/) | Shared Postgres for every app that supports it |
| [Volsync](https://volsync.readthedocs.io/) + Kopia | PVC backups to RGW, mirrored to Garage (`templates/volsync`) |
| [External Secrets](https://external-secrets.io/) + Bitwarden SM | Every in-cluster secret; [docs/secrets.md](./docs/secrets.md) |
| [external-dns](https://github.com/kubernetes-sigs/external-dns) + [cert-manager](https://cert-manager.io/) | Cloudflare (public, via cloudflared) and AdGuard (LAN split-horizon) records from HTTPRoutes/Services; wildcard Let's Encrypt cert on the Gateways |
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts), [Loki](https://grafana.com/oss/loki/) + [Alloy](https://grafana.com/oss/alloy-opentelemetry-collector/), [Gatus](https://gatus.io/) | Metrics, logs, alerting (Pushover), synthetic checks |
| [Kyverno](https://kyverno.io/) | Audit-mode policies for the repo's own conventions (`kubernetes/apps/kyverno`) |
| [Renovate](https://docs.renovatebot.com/) + [flate](https://github.com/home-operations/flate) | Dependency PRs with digest pinning; every PR renders the full Flux tree in CI |
| [SOPS](https://github.com/getsops/sops) + Age | The few bootstrap-time secrets that cannot come from Bitwarden |


## 💻 Nodes
| Node        | Hostname | CPU      | RAM  | Storage                              | Function | OS    |
|-------------|----------|----------|------|--------------------------------------|----------|-------|
| Lenovo Tiny | MJ0583JP | i7-6700T | 16GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Master   | Talos |
| Lenovo Tiny | MJ0581M7 | i7-6700T | 16GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Master   | Talos |
| Lenovo Tiny | MJ0583EQ | i7-6700T | 16GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Master   | Talos |
| Lenovo Tiny | MJ05AJFJ | i5-6500T | 32GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Worker   | Talos |
| Lenovo Tiny | MJ04EW44 | i5-6500T | 32GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Worker   | Talos |
| Lenovo Tiny | MJ0581RW | i5-6500T | 32GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Worker   | Talos |
| Lenovo Tiny | MJ04968E | i5-6500T | 32GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Worker   | Talos |
| Lenovo Tiny | MJ05G4UB | i5-6500T | 32GB | 250GB SSD (Talos), 500GB NVME (CEPH) | Worker   | Talos |

## ☁️ Cloud Dependencies

While most of my infrastructure and workloads are self-hosted I do rely upon the cloud for certain key parts of my setup. This saves me from having to worry about two things. (1) Dealing with chicken/egg scenarios and (2) services I critically need whether my cluster is online or not.

| Service                                                               | Use                                                               | Cost                |
|-----------------------------------------------------------------------|-------------------------------------------------------------------|---------------------|
| [Cloudflare](https://www.cloudflare.com/)                             | Domain(s), Email                                                  | ~$10/yr             |
| [Private Internet Access](https://www.privateinternetaccess.com/)     | VPN Provider                                                      | ~$40/yr             |
| [GitHub](https://github.com/)                                         | Hosting this repository and continuous integration/deployments    | Free                |
| [Bitwarden Secrets](https://bitwarden.com/products/secrets-manager/)  | External Secrets, and secret management                           | Free                |
|                                                                       |                                                                   | Total: ~50$/yr      |
