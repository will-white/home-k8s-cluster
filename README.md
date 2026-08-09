<div align="center">

### My Home Kubernetes Cluster :octocat:

_... managed with Flux, Renovate, and GitHub Actions_ 🤖

</div>

> **For AI Agents and Developers**: See [AGENTS.md](./AGENTS.md) for comprehensive setup, validation, and operational instructions.

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

Runbooks:
- [Bare-metal rebuild](./docs/runbooks/bare-metal-rebuild.md) — nuke & repave from blank nodes
- [Full cluster shutdown](./docs/runbooks/full-cluster-shutdown.md) — graceful power-down/up for maintenance
- [Ceph / data restore](./kubernetes/apps/rook-ceph/rook-ceph/backup/DISASTER-RECOVERY.md) — Garage → RGW → CNPG/Volsync rehydration

## 🔧 Tools

| Tool                                             | Purpose                                                            |
|--------------------------------------------------|--------------------------------------------------------------------|
| [flux](https://toolkit.fluxcd.io/)               | Operator that manages the cluster based on this Git repository     |
| [sops](https://github.com/mozilla/sops)          | Encrypts k8s secrets                                               |


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
