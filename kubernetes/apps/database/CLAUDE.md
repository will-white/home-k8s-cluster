# database — domain guide (`@db-agent`)

Loaded automatically for work under `kubernetes/apps/database/`. Shared data
services consumed by every other namespace; a mistake here takes several apps
down at once.

## Components

| App | Flux Kustomizations | Role |
|---|---|---|
| cloudnative-pg | `cloudnative-pg` (operator), `cloudnative-pg-cluster` (the `postgres16` cluster) | Shared Postgres. Service `postgres16-rw.database.svc.cluster.local`; BGP LoadBalancer `${POSTGRES_LB}` for off-cluster clients. Barman backups to the RGW bucket `cloudnative-pg` (credentials via `PushSecret`), mirrored to Garage nightly |
| dragonfly | `dragonfly-operator`, `dragonfly-cluster` | Redis-compatible cache (paperless) |
| emqx | `emqx` (operator), `emqx-cluster` | The one MQTT broker; BGP LoadBalancer `${EMQX_LB}` for LAN devices |

## Conventions

- **Consumers depend on the cluster, not the operator**: `dependsOn:
  cloudnative-pg-cluster`, `dragonfly-cluster`, `emqx-cluster` in the consuming
  app's `ks.yaml`.
- **Database provisioning** is per app: an `init-db` initContainer
  (`ghcr.io/home-operations/postgres-init`) driven by `INIT_POSTGRES_HOST`,
  `_DBNAME`, `_USER`, `_PASS` and `_SUPER_PASS` (`POSTGRES_SUPERUSER_PASSWORD`)
  from the app's `ExternalSecret`. No shared app user, no manual `CREATE
  DATABASE`.
- **Secret names**: `<APP>_POSTGRES_USER` / `<APP>_POSTGRES_PASSWORD`,
  `<CLIENT>_EMQX_USERNAME` / `_PASSWORD`
  ([docs/secrets.md](../../../docs/secrets.md)).
- **MQTT users and ACLs** are config (ConfigMap / `ExternalSecret`), fine for
  `@home-agent` to add; broker topology and the operator chart are not.
- **Network policy**: the namespace is default-deny; cross-namespace clients
  are admitted through the shared templates, LAN devices through
  `allow-ingress-lan`.

## Boundaries

- A Postgres **major** upgrade is an offline `pg_upgrade` expressed as a new
  `ImageCatalog` entry, not an image tag bump; it is one-way and needs an
  explicit plan plus human approval (see the `merge-renovate-prs` skill).
- Changing `instances`, storage size or the backup schedule is
  change-controlled: write the rationale in the PR.
- Never delete the CNPG cluster, its PVCs or the RGW backup bucket without
  named human approval; recovery is documented in
  [rook-ceph/backup/DISASTER-RECOVERY.md](../rook-ceph/rook-ceph/backup/DISASTER-RECOVERY.md).

## Validate

```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/database/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
kubectl -n database get cluster,pooler,dragonfly,emqx,pods    # read-only
```
