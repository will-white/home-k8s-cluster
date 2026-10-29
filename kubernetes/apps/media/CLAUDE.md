# media — domain guide (`@media-agent`)

Loaded automatically for work under `kubernetes/apps/media/`. Policy and the
shared rules live in [AGENTS.md](../../../AGENTS.md); mechanics in the root
[CLAUDE.md](../../../CLAUDE.md). Hand off anything outside this folder.

## Domain

The full pipeline: indexer → request → grab → download → unpack → import →
library → notify.

| Stage | Apps |
|---|---|
| Indexers / requests | prowlarr, flaresolverr, autobrr, omegabrr, seerr |
| Managers (*arr) | sonarr, radarr, bazarr, recyclarr |
| Download / post-process | qbittorrent (gluetun VPN sidecar), unpackerr, cleanuparr, tdarr |
| Libraries / readers | komga, komf, kavita, suwayomi |
| Metadata / curation | kometa |

Operational tuning (indexers, qBittorrent, release profiles, Bazarr scores)
is in [MEDIA_TUNING.md](./MEDIA_TUNING.md); treat it as the checklist after
any pipeline change.

## Conventions

- **Namespace** is always `media`. Register every app's `ks.yaml` in
  [kustomization.yaml](./kustomization.yaml).
- **Postgres is mandatory** for every app that supports it (sonarr, radarr,
  prowlarr, bazarr when migrated, seerr): `dependsOn: cloudnative-pg-cluster`,
  an `init-db` initContainer from `ghcr.io/home-operations/postgres-init` fed
  by `INIT_POSTGRES_*` keys in the app's `ExternalSecret`, host
  `postgres16-rw.database.svc.cluster.local`. No embedded SQLite where
  Postgres is an option.
- **Media library** is the NAS over NFS, mounted inline:
  `server: ${NAS_IP}`, `path: /mnt/main/media`. Keep the same mount path across
  apps so hardlinks and *arr path mappings keep working. qBittorrent's
  in-progress downloads use a dedicated dataset (#1593).
- **Config PVCs**: `ceph-filesystem` RWX for the *arrs (their configs are
  read by sidecars and scripts), `ceph-block` RWO otherwise. Backed up with the
  shared Volsync template (`../../../../templates/volsync`) unless the data is a
  pure cache (recyclarr, kometa are deliberately not backed up).
- **Secrets**: `ExternalSecret` only, keys named per
  [docs/secrets.md](../../../docs/secrets.md) (`SONARR_API_KEY`,
  `KOMF_KAVITA_API_KEY`, ...). Cross-app API keys carry the consumer name.
- **Exposure**: app-template `route:` block to Gateway `internal` in
  namespace `network`, hostname `{{ .Release.Name }}.${SECRET_DOMAIN}`,
  `sectionName: https`, `timeouts.request: 0s`. Add `gethomepage.dev/*`
  annotations so the app shows on Homepage. Only seerr is public (Gateway
  `external`). tdarr's server port is a BGP LoadBalancer (`${TDARR_LB}`) for
  off-cluster nodes.
- **Metrics**: exportarr sidecar + `serviceMonitor:` block for the *arrs;
  `resources/lokirule.yaml` delivered through `configMapGenerator` with
  `loki_rule: "true"` for log-based alerts.
- **Probes**: use `/ping` with a `Host: localhost` header on the *arrs (their
  allowed-hosts list rejects the pod IP) and a `startup` probe so slow Postgres
  migrations do not get the pod killed.
- **Network policy**: the namespace is default-deny via
  [network-policies/app/kustomization.yaml](./network-policies/app/kustomization.yaml).
  App-specific egress (trackers, VPN, NAS) goes in a policy next to the
  HelmRelease, never by loosening the shared templates.
- **Resource hygiene**: `resources.requests` always, `limits.memory` always,
  never a CPU limit.

## Heuristics

- Adding an *arr: also propose the Recyclarr profile, Prowlarr sync, Bazarr
  wiring (video), Gatus endpoint (`../../../../templates/gatus/guarded`),
  Volsync and the `ExternalSecret`.
- Removing an app: grep the rest of `media/` for `dependsOn`, ConfigMaps and
  recyclarr references and clean them up in the same change.
- `recyclarr.yml` and the Kometa configs are code: review their diffs like
  manifests.
- Prefer fewer, well-tuned apps over duplicates; challenge requests that
  overlap existing functionality.

## Boundaries

- Do not modify anything outside `kubernetes/apps/media/`.
- Do not bump chart `version:` or CRDs of shared infra (cnpg, volsync,
  external-secrets, rook-ceph) from a media change.
- Never delete a PVC or Kopia snapshot: that is user data and needs named human
  approval.

## Validate

```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/media/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
flux build ks <app> --kustomization-file kubernetes/apps/media/<app>/ks.yaml --path kubernetes/apps/media/<app>/app --dry-run
yamllint kubernetes/apps/media/<app>
kubectl -n media get hr,ks,pods,pvc          # read-only, needs KUBECONFIG
```
