---
name: new-app
description: >-
  Scaffold a new application under kubernetes/apps/<ns>/<app> following the
  repo's per-app layout (ks.yaml, app-template HelmRelease, ExternalSecret,
  Gatus, Volsync, network policy), validate it and open a PR. Use when the
  user asks to "add", "deploy", "install" or "onboard" an app or service.
---

# Scaffold a new app

Follow `docs/runbooks/add-an-app.md`; this skill is the order of operations.
The namespace's `CLAUDE.md` (media, default, observability, database) holds
the domain rules and wins over anything generic here.

## 1. Decide, then confirm only what is actually open

- Namespace is fixed by domain (media → `media`; Home Assistant / IoT /
  general → `default`; brokers and DBs → `database`; monitoring →
  `observability`). Only a **new** namespace needs the user's confirmation.
- Chart: look the app up on <https://kubesearch.dev> and in this repo first.
  `app-template` via `OCIRepository` by default.
- State: user data → Volsync template + `ceph-block` (RWO) or
  `ceph-filesystem` (RWX); supports Postgres → CloudNativePG, never SQLite.
- Exposure: `internal`. Public is a security decision the user makes.

If any of those is genuinely ambiguous, ask once with the options; otherwise
state the assumption in the PR.

## 2. Copy the closest sibling

Pick the app in the same namespace with the nearest shape (stateful +
Postgres: `media/sonarr` or `default/paperless`; stateless UI:
`default/stirling-pdf`; hostNetwork: `default/music-assistant`) and copy its
`ks.yaml` + `app/`. Then edit, in this order:

1. `ks.yaml`: name, `targetNamespace`, `path`, `dependsOn`
   (`external-secrets-stores`, `cloudnative-pg-cluster`, `volsync` as needed),
   `postBuild.substitute` (`APP`, `NAMESPACE`, `GATUS_*`, `VOLSYNC_*`).
2. `app/kustomization.yaml`: resources + the `gatus/guarded` and `volsync`
   templates.
3. `app/ocirepository.yaml`: keep the pinned app-template version/digest.
4. `app/helmrelease.yaml`: image (`tag@sha256`), env, probes, `securityContext`,
   `resources` (requests + memory limit, no CPU limit), `route:` block
   (`timeouts.request: 0s`), `persistence`, `serviceMonitor` if it has metrics.
5. `app/externalsecret.yaml`: keys per `docs/secrets.md`; tell the user which
   Bitwarden keys must exist (create them only if explicitly asked, never print
   values).
6. Register `./<app>/ks.yaml` in `kubernetes/apps/<ns>/kustomization.yaml`.
7. Backed-up data: add `<app>@<ns>` to the `volsync-canary` identities.

## 3. Validate and ship

```bash
task kubernetes:validate APP=<ns>/<app>
task kubernetes:kubeconform
```

Commit on a feature branch, push, open the PR with: what it is, namespace,
storage choice, exposure, secrets the user must create, and the validation
output. Do not merge from a session without cluster credentials.

## 4. Offer the follow-ups, do not bundle them

Dashboard / ServiceMonitor (observability guide), Homepage tile annotations,
MEDIA_TUNING entries for media apps, a `NetworkPolicy` for any egress the
app needs beyond DNS/API/Gateway.
