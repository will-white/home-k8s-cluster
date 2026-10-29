# Add an app

End-to-end checklist for a new workload. Copy the closest existing app in the
same namespace rather than writing from scratch; the namespace's `CLAUDE.md`
has the domain rules (media, default, observability, database, ...).

## 0. Decide

- **Namespace** is fixed by domain: media → `media`, Home Assistant / IoT /
  general self-hosted → `default`, brokers and databases → `database`,
  monitoring → `observability`. A new namespace is a conversation, not a PR.
- **Chart**: search <https://kubesearch.dev>. Default to
  `app-template` (bjw-s) via an `OCIRepository`; use the upstream chart only
  when it is clearly better (operators, charts with CRDs).
- **State**: does it keep user data? Then it needs the Volsync template, a
  StorageClass from the closed set and a canary identity. Does it support
  Postgres? Then it uses CloudNativePG, not SQLite.
- **Exposure**: internal by default. Public (`external` Gateway) is a security
  decision.

## 1. Files

```
kubernetes/apps/<ns>/<app>/
  ks.yaml
  app/
    kustomization.yaml
    ocirepository.yaml       # app-template chart ref (copy, same version/digest)
    helmrelease.yaml
    externalsecret.yaml      # if it needs secrets
    pvc.yaml                 # only when NOT using the Volsync template
    resources/               # ConfigMaps, scripts, lokirule.yaml
```

Register it: add `./<app>/ks.yaml` to `kubernetes/apps/<ns>/kustomization.yaml`.

### `ks.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app>
  namespace: flux-system
spec:
  targetNamespace: <ns>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: external-secrets-stores      # if it has an ExternalSecret
    - name: cloudnative-pg-cluster       # if it uses Postgres
    - name: volsync                      # if it uses the Volsync template
  path: ./kubernetes/apps/<ns>/<app>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  wait: false
  interval: 30m
  timeout: 5m
  postBuild:
    substitute:
      APP: *app
      NAMESPACE: <ns>
      # Gatus: GATUS_PORT / GATUS_PATH / GATUS_SUBDOMAIN
      # Volsync: VOLSYNC_CAPACITY, VOLSYNC_BOOTSTRAP_SOURCE_NAMESPACE,
      #          PVC_VOLSYNC_STORAGECLASS + VOLSYNC_STORAGECLASS + VOLSYNC_SNAPSHOTCLASS
```

### `app/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml
  - ./ocirepository.yaml
  - ./helmrelease.yaml
  - ../../../../templates/gatus/guarded      # or gatus/external for public apps
  - ../../../../templates/volsync            # stateful apps
```

### `helmrelease.yaml` essentials

- `image.tag` pinned with `@sha256:` digest (Renovate maintains it).
- `resources.requests` (cpu + memory) and `limits.memory`; **no CPU limit**.
- `securityContext`: `runAsNonRoot`, `runAsUser/Group 1000`, `fsGroup`,
  `seccompProfile: RuntimeDefault`, drop all capabilities,
  `readOnlyRootFilesystem` where the image allows (then an `emptyDir` on
  `/tmp`). Match `VOLSYNC_PUID/PGID` if you deviate from 1000.
- Probes: liveness, readiness and a `startup` probe for anything that migrates
  a database on boot.
- `env: TZ: ${TIMEZONE}`; never hard-code the domain or an IP: `${SECRET_DOMAIN}`,
  `${NAS_IP}`, `${<NAME>_LB}` from `kubernetes/flux/vars/`.
- `route:` block:

  ```yaml
  route:
    app:
      annotations:                       # optional Homepage tile
        gethomepage.dev/enabled: "true"
        gethomepage.dev/group: <Group>
        gethomepage.dev/name: <App>
      hostnames: ["{{ .Release.Name }}.${SECRET_DOMAIN}"]
      parentRefs:
        - name: internal                 # external = public via Cloudflare
          namespace: network
          sectionName: https
      rules:
        - backendRefs:
            - identifier: app
              port: http
          timeouts:
            request: 0s
  ```

- Metrics: a `metrics` port plus a `serviceMonitor:` block if the app
  exports Prometheus metrics (or an exporter sidecar such as exportarr).
- Postgres: `init-db` initContainer from `ghcr.io/home-operations/postgres-init`
  with `INIT_POSTGRES_*` from the `ExternalSecret`
  (see `kubernetes/apps/media/sonarr`).
- `reloader.stakater.com/auto: "true"` on the controller when it consumes a
  Secret or ConfigMap.

### Secrets

[add-a-secret.md](./add-a-secret.md). `ExternalSecret` → `<app>-secret`,
`envFrom` in the HelmRelease.

### Storage

- User data: Volsync template (claim is created from the bootstrap
  `ReplicationDestination`; set both storage-class variables explicitly).
- Scratch / cache: `openebs-hostpath` or `emptyDir`, labelled as not backed up.
- Shared media: inline NFS mount of `${NAS_IP}:/mnt/main/media`.
- Add `<app>@<ns>` to `kubernetes/apps/volsync-system/volsync-canary` identities
  when it is backed up.

### Network policy

Default-deny namespaces admit DNS, the API server, the Gateway, Prometheus,
homepage + gatus and LAN hosts through the shared templates. Anything else the
app needs (an external API, the NAS, MQTT) is a `NetworkPolicy` in `app/`.

## 2. Validate

```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/<ns>/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
flux build ks <app> --kustomization-file kubernetes/apps/<ns>/<app>/ks.yaml --path kubernetes/apps/<ns>/<app>/app --dry-run
yamllint kubernetes/apps/<ns>/<app>
task kubernetes:kubeconform
```

CI renders the whole tree with flate (`Flux Render`), so a wrong chart value
fails the PR. Open the PR, let the checks go green, merge, then watch:

```bash
flux -n flux-system get ks <app>
kubectl -n <ns> get hr,pods,pvc,externalsecret,httproute -l app.kubernetes.io/name=<app>
kubectl -n <ns> describe hr <app>      # on failure
```

## 3. After it is up

- The route creates the DNS record on its own (external-dns); check
  `https://<app>.${SECRET_DOMAIN}` from the LAN.
- Gatus shows the endpoint under `guarded` (or `external`).
- `kubectl get policyreport -n <ns>` is still clean (Kyverno).
- A dashboard, if upstream ships one worth having
  ([observability guide](../../kubernetes/apps/observability/CLAUDE.md)).
