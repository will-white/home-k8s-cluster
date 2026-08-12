# Shibari platform — hosting the platform-x-club sites

Runs the **shibarixclub** and **queerxclub** websites from the private
[cawhitecode/platform-x-club](https://github.com/cawhitecode/platform-x-club)
monorepo: two brand hostnames, one runtime-branded Next.js `web` (brand is
resolved per request from the Host header), one NestJS `api`, one `worker`,
a **dedicated** CloudNative-PG cluster (customer data stays off the shared
`postgres16`), and a dedicated password-protected Dragonfly. Prod and a
public dev environment run side by side.

Manifests live in the app repo under `kubernetes/` (namespace-agnostic;
Flux's `targetNamespace` + substitutions supply the environment). This repo
owns the integration: GitRepository + deploy key, namespaces, network
policies, Gatus. Introduced by
[platform-x-club#1](https://github.com/cawhitecode/platform-x-club/pull/1)
and the companion PR here (#1254).

## Topology

| | prod | dev |
|---|---|---|
| Namespace | `shibari-platform` | `shibari-platform-dev` |
| App-repo overlay | `kubernetes/overlays/prod` | `kubernetes/overlays/dev` |
| Hostnames | `shibari.<domain>`, `queer.<domain>` | `shibari-dev.<domain>`, `queer-dev.<domain>` |
| Image tags | `latest` (SHA-pinnable) | `dev` |
| Postgres / Dragonfly | 3 instances / 2 replicas | 1 / 1 |
| BWS prefix | `SHIBARI_PROD_*` | `SHIBARI_DEV_*` |
| Gatus alerts | pushover | none (checks only) |

- **Images** come from the app repo's own deploy workflows (`docker buildx
  bake`): `ghcr.io/cawhitecode/platform-x-club/{api,web,worker}` with
  moving tags `latest` (prod pipeline) / `dev` (every push to main) plus
  immutable SHA tags. This repo builds nothing.
- **Traffic**: Cloudflare edge TLS → tunnel → `external` ingress-nginx
  (wildcard default cert covers the one-level subdomains). No per-host
  cert-manager TLS. Media is served by BunnyCDN, not through the house.
- **Secrets**: flat Bitwarden SM entries → ExternalSecrets. `${BWS_PREFIX}`
  is substituted per environment by the Flux Kustomization
  (`kubernetes/apps/shibari-platform*/platform-x-club/ks.yaml`).
- **Migrations**: TypeORM, run by an init container on the `api`
  deployment under a Postgres advisory lock. Manual re-run:
  `kubectl apply -n <ns> -f kubernetes/components/api/schema-sync-job.yaml`
  (app repo).

## Go-live checklist (one-time)

1. **Deploy key** — generate and install; Flux reads the app repo with it:

   ```bash
   ssh-keygen -t ed25519 -N '' -C flux-home-kubernetes-ro -f shibari-deploy-key
   # public half  -> app repo Settings -> Deploy keys (read-only)
   # private half -> BWS entry SHIBARI_DEPLOY_KEY (then shred the files)
   ```

2. **Bitwarden entries** (18 total, flat keys in the home-cluster project).
   Never echo values; create with
   `bws secret create <KEY> <value> <project-id>`.

   | Keys | Value |
   |---|---|
   | `SHIBARI_{PROD,DEV}_JWT_SECRET`, `_JWT_REFRESH_SECRET`, `_DB_PASSWORD`, `_REDIS_PASSWORD`, `_PAYOUT_ENCRYPTION_KEY` | generate: `openssl rand -base64 48` (10 entries) |
   | `SHIBARI_GHCR_USER` / `SHIBARI_GHCR_TOKEN` | GitHub user + PAT with **read:packages** only (GHCR packages are private) |
   | `SHIBARI_BUNNY_STORAGE_ZONE`, `_STORAGE_ACCESS_KEY`, `_CDN_BASE_URL`, `_CDN_SECURITY_KEY` | from the Bunny dashboard |
   | `SHIBARI_BREVO_API_KEY` | from Brevo |
   | `SHIBARI_DEPLOY_KEY` | private key from step 1 |

   `CNPG_BUCKET_ACCESS_KEY` / `CNPG_BUCKET_SECRET_KEY` already exist and are
   reused for barman (backups land under
   `s3://cloudnative-pg/shibari-platform/` on the RGW).

3. **Merge** platform-x-club#1, then the cluster PR. Until steps 1–2 are
   done the two app Kustomizations simply stay unready; nothing else is
   affected.

4. **Reconcile & verify**:

   ```bash
   flux reconcile kustomization cluster-apps --with-source
   kubectl -n shibari-platform get ks,pods,cluster,dragonfly,ingress
   kubectl -n shibari-platform-dev get pods
   # first backup fired? (ScheduledBackup has immediate: true)
   kubectl -n shibari-platform get backup
   ```

## Production-hardening TODO (ordered)

1. **Out-of-band prod backups — REQUIRED before real customer data.**
   Barman currently targets the in-cluster Rook RGW, which shares a
   failure domain with the database — and note that the NAS does **not**
   count as offsite either: it's the same house, same power, same fire.
   Production data must have an out-of-band copy that lives entirely away
   from the home lab: point `barmanObjectStore` at cloud object storage
   (R2/B2), or keep RGW as the fast local target and sync the bucket to
   the cloud on a schedule. Treat this as a launch gate, not a nice-to-have.
2. **Restore drill** — bootstrap a recovery into the dev namespace once
   (bump `serverName` per the recovery notes in the app repo's
   `cluster.yaml`; same procedure as the shared cluster's
   `DISASTER-RECOVERY.md`) — and run it **from the offsite copy**, not
   the local RGW. Untested backups don't count; untested offsite backups
   doubly so.
3. **Pin prod images to SHA tags** — `latest` is a moving tag; pin the SHA
   the bake also pushes (override in the prod overlay), or install Flux
   image-automation to bump it. Also removes dev's manual-restart caveat.
4. **PrometheusRules for the dedicated cluster** — it has a PodMonitor but
   none of the alert rules `postgres16` has
   (`kubernetes/apps/database/cloudnative-pg/cluster/prometheusrule.yaml`);
   a silently failing WAL archive is the failure mode that makes item 1
   matter.
5. **Flux Provider/Alert** for both namespaces (copy the pattern from
   `kubernetes/apps/database/namespace.yaml`) so a stuck Kustomization
   notifies instead of staying quietly stale.
6. **Real payments** — CCBill per-brand creds → BWS, flip
   `CCBILL_ENABLED` and `PAYMENT_PROVIDER` in the app repo's
   `api-config`. Mock mode until then.
7. **Renovate in the app repo** — the CNPG/Dragonfly image pins live there
   now and nothing bumps them; this repo's Renovate can't see them.

## Deferred / known constraints

- **Livestreaming is off in-cluster** (`OME_*` empty) — and it stays off
  *at home* by design: even CDN-fronted, one ABR live channel costs
  ~10 Mbps of cache-fill per CDN region, against ~35 Mbps of home
  upstream. One stream saturates the pipe and starves the sites. The end
  state is a small **stateless OME VPS as the streaming media plane**
  (cutover step 4); only that box, never the cluster, originates live
  segments.
- **Chunked uploads** disabled (matches compose default); flip
  `CHUNKED_UPLOAD_ENABLED` when needed.
- **Egress** allows all public 443 (Bunny/Brevo/payment callbacks);
  tighten to provider ranges later
  (`kubernetes/apps/shibari-platform*/network-policies/app/egress-https.yaml`).
- **Availability = home ISP/power** once the real domains point here.
  Gatus/pushover reports outages; whether that SLA is acceptable for a
  revenue site (or whether to keep a fallback anywhere) is a business
  call — nothing in this deployment requires one.
- Namespaces enforce PSS `baseline` (warn/audit `restricted`) — candidate
  to tighten after checking the CNPG/Dragonfly pods.

## Cutover from OVH (the end state)

This cluster deployment is fully self-contained — **nothing here needs the
OVH VPS**. But until the apex domains cut over, the cluster serves the
home subdomains while shibarixclub.com / queerxclub.com still point at the
VPS, and the VPS's deploy workflows are what push the container images.
Retiring OVH means, in order:

1. **Decouple image builds from VPS deploys** — add a build-only workflow
   to the app repo (the `docker buildx bake` + push step from
   `deploy-{dev,prod}.yml`, minus the SSH deploy). Otherwise disabling the
   VPS pipelines silently stops image publishing.
2. **Migrate production data** — the live customer database belongs to the
   OVH deployment. In a maintenance window: freeze writes, `pg_dump` the
   prod DB, restore into `shibari-platform-db` (CNPG `initdb` import or
   plain `psql` into the fresh cluster), verify row counts and log in.
   Redis state (sessions/queues) can be dropped; Bunny storage is external
   and shared, nothing to move.
3. **Point the apex domains at the cluster** — zones are already on
   Cloudflare: add tunnel hostname rules for the four hosts, DNS records to
   `<tunnel-id>.cfargotunnel.com`, swap the `DOMAIN_*` substitutes in the
   two `ks.yaml` files, and update any host-baked callbacks (CCBill,
   Brevo templates, OAuth redirect URIs). external-dns `domainFilters`
   only covers the home zone — manage the new zones manually or extend it.
4. **Stand up the streaming media plane** (if livestreams are wanted) — a
   small VPS (~€10 tier, 1 Gbps) running **only OME**: creators ingest
   RTMP/SRT straight to it (this is also what solves the raw-TCP ingest
   problem — the tunnel can't carry it from arbitrary clients), viewers
   pull through a Bunny pull zone with the VPS as origin, the in-cluster
   API drives OME over its token-authed HTTPS API, admission webhooks
   call back to the public API URL for stream-key auth, and recordings
   push to Bunny storage. The box holds **no customer data** — transient
   video and a config file — and rebuilds in minutes. Rationale: home
   upstream (~35 Mbps) cannot originate live segments; bandwidth lives in
   the cloud, state lives at home.
5. **Watch, then decommission** — after a comfortable soak, tear down the
   OVH platform hosts and disable the `deploy-*` workflows (keep the
   build-only one). The OME media-plane box, if any, is the only
   survivor — and it runs nothing but OME. From this moment the cluster
   holds the **only** copy of customer data, which is why hardening
   item 1 (out-of-band backups away from the home lab) is a hard
   prerequisite for this step, not a follow-up.

## Operating notes

- **Deploy to dev**: merge to app-repo main → bake pushes `:dev` →
  `kubectl -n shibari-platform-dev rollout restart deploy`.
- **Deploy to prod**: the app repo's prod pipeline pushes `:latest` →
  restart deployments, or (better, see TODO 3) bump SHA pins. Note the
  images currently come from the *VPS* deploy workflows — see the
  cutover section before disabling those.
- **Rotating secrets**: edit the BWS entry; ESO refreshes within 1h
  (`flux reconcile` the ks to force). The DB password propagates to
  Postgres automatically (`cnpg.io/reload` label); everything consumed via
  `envFrom` (JWT, Bunny, Brevo) needs a `rollout restart` to take effect.
- **Validate app-repo manifests** before merging changes there:

  ```bash
  kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/overlays/prod | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret -
  ```

- **Where things are defined**: hostnames/env → `ks.yaml` substitutes
  (this repo); app config → `api-config`/`worker-config` ConfigMaps (app
  repo); secret *names* → `base/externalsecret-app.yaml` (app repo);
  secret *values* → Bitwarden SM.
