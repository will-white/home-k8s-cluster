# Documentation index

Start with the root [README](../README.md) for what the cluster is and
[AGENTS.md](../AGENTS.md) + [CLAUDE.md](../CLAUDE.md) for how to work in the
repo. Domain rules live next to the manifests in
`kubernetes/apps/<ns>/CLAUDE.md`; repeatable procedures are Claude Code skills
in `.claude/skills/` (`validate-app`, `new-app`, `expose-app`,
`onboard-volsync`, `merge-renovate-prs`).

## Reference

| Page | What it covers |
|---|---|
| [network-layout.md](./network-layout.md) | Every IP and DNS path: LAN, L2 and BGP pools, Gateways, split-horizon DNS, tunnel, network-policy posture |
| [secrets.md](./secrets.md) | Bitwarden naming schema; what is still SOPS |
| [backlog.md](./backlog.md) | Open work and deliberately rejected ideas |
| [kubernetes/templates/volsync/README.md](../kubernetes/templates/volsync/README.md) | Backup template variables |
| [kubernetes/templates/network-policies/README.md](../kubernetes/templates/network-policies/README.md) | Default-deny layers |
| [kubernetes/apps/media/MEDIA_TUNING.md](../kubernetes/apps/media/MEDIA_TUNING.md) | Media stack tuning checklist |

## Runbooks: day to day

| Runbook | Use when |
|---|---|
| [add-an-app.md](./runbooks/add-an-app.md) | Onboarding a workload end to end |
| [add-a-secret.md](./runbooks/add-a-secret.md) | Creating or rotating a Bitwarden secret and wiring the `ExternalSecret` |
| [flux-troubleshooting.md](./runbooks/flux-troubleshooting.md) | Something is not reconciling |
| [volsync-restore.md](./runbooks/volsync-restore.md) | Restoring a PVC, a snapshot or a single file from Kopia |
| [cilium-bgp-opnsense.md](./runbooks/cilium-bgp-opnsense.md) | BGP peering, moving a Service between the L2 and BGP pools, rollback |

## Runbooks: incidents and maintenance

| Runbook | Use when |
|---|---|
| [full-cluster-shutdown.md](./runbooks/full-cluster-shutdown.md) | Planned power-down / bring-up, node loss, latent failures a restart exposes |
| [etcd-maintenance.md](./runbooks/etcd-maintenance.md) | etcd alerts, defrag, network-vs-disk diagnosis |
| [bare-metal-rebuild.md](./runbooks/bare-metal-rebuild.md) | Nuke and repave from blank nodes |
| [Ceph / data disaster recovery](../kubernetes/apps/rook-ceph/rook-ceph/backup/DISASTER-RECOVERY.md) | Garage → RGW → CNPG / Volsync rehydration |
| [intel-amt-vpro.md](./runbooks/intel-amt-vpro.md) | Out-of-band node management |
| [m900-bios-energy.md](./runbooks/m900-bios-energy.md) | Per-node firmware tuning |

## Conventions for new docs

- Runbooks are procedures: numbered steps, exact commands, what "done" looks
  like, and a rollback. Reference pages describe state and point at the file
  that owns it.
- Dates and PR numbers for the *why* ("#1402 deleted the public records");
  no snapshots of cluster state that go stale.
- Agent-facing rules go in the nearest `CLAUDE.md`, not here.
