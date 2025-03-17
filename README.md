<div align="center">

### My Home Kubernetes Cluster :octocat:

_... managed with Flux, Renovate, and GitHub Actions_ 🤖

</div>

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
| [GitHub](https://github.com/)                                         | Hosting this repository and continuous integration/deployments    | Free                |
| [Bitwarden Secrets](https://bitwarden.com/products/secrets-manager/)  | External Secrets, and secret management                           | Free                |
|                                                                       |                                                                   | Total: ~10$/yr      |
