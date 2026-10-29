# volsync-system — domain guide (`@storage-agent`)

Loaded automatically for work under `kubernetes/apps/volsync-system/` and
`kubernetes/templates/volsync/`. This is the PVC backup and restore path for
every stateful app.

## Components

| Flux Kustomization | Role |
|---|---|
| `volsync` | Operator (perfectra1n fork with the Kopia mover) |
| `snapshot-controller` | CSI snapshots used by `copyMethod: Snapshot` |
| `kopia` | The shared repository (`s3://volsync-backups` on RGW) and the Kopia web UI at `kopia.${SECRET_DOMAIN}` for browsing / ad-hoc restores |
| `volsync-maintenance` | One `KopiaMaintenance` for the whole repository |
| `volsync-canary` | Daily job that fails (→ `KubeJobFailed` alert) if any identity in `volsync-canary-identities` is missing or stale |

## How an app is wired

1. The app's `app/kustomization.yaml` includes `../../../../templates/volsync`
   (claim + `ReplicationDestination <app>-bootstrap` + `ReplicationSource
   <app>` + `ExternalSecret`), or `templates/volsync/source-only` when the app
   already owns its PVC.
2. Its `ks.yaml` sets `dependsOn: volsync`, `VOLSYNC_CAPACITY`,
   `VOLSYNC_BOOTSTRAP_SOURCE_NAMESPACE` and **both** storage-class knobs
   (`PVC_VOLSYNC_STORAGECLASS` for the claim, `VOLSYNC_STORAGECLASS` for mover
   volumes) plus the matching `VOLSYNC_SNAPSHOTCLASS`; RWX apps also set the
   `*_ACCESSMODES`.
3. The PVC's `dataSourceRef` points at the bootstrap destination, so a fresh
   cluster restores the last snapshot before the app starts.
4. Add the `<app>@<namespace>` identity to the canary ConfigMap.

Full variable list: [templates/volsync/README.md](../../templates/volsync/README.md).
Restore procedure: [docs/runbooks/volsync-restore.md](../../../docs/runbooks/volsync-restore.md).

## Conventions

- `moverResources` stay at the proven floor (`requests.memory: 512Mi`,
  `limits.memory: 2Gi`); raise per app only with evidence (Kopia mmap errors).
- `VOLSYNC_PUID` / `VOLSYNC_PGID` must match the app's `runAsUser` or the
  mover cannot read the data (default 1000; the `default` namespace has no
  privileged-movers annotation).
- Pure caches (recyclarr, kometa) opt out on purpose; label them as such in
  the PR rather than adding canary noise.
- Template changes hit every consumer: reconcile, then watch one
  `ReplicationSource` complete before calling it done.

## Boundaries (hard)

- Never delete a PVC, `ReplicationDestination` snapshot or anything in the
  Kopia repository without named human approval.
- Chart `version:` / CRD bumps through `@infra-agent`.

## Validate

```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/<ns>/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
kubectl get replicationsource,replicationdestination -A        # read-only
kubectl -n volsync-system logs job/<volsync-canary-job>
```
