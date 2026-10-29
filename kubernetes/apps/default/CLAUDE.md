# default — domain guide (`@home-agent`)

Loaded automatically for work under `kubernetes/apps/default/`. Policy and the
shared rules live in [AGENTS.md](../../../AGENTS.md); mechanics in the root
[CLAUDE.md](../../../CLAUDE.md).

## What lives here

| Group | Apps | Notes |
|---|---|---|
| Home automation hub | home-assistant, matter-server, music-assistant | `hostNetwork: true` (mDNS, Matter, Sonos/Chromecast discovery); this is why the namespace enforces PSA `privileged` while warning/auditing `restricted` |
| Zigbee / Z-Wave | zigbee2mqtt, zigbee2mqtt-ota, zwave-js-ui | Radios are network coordinators (SLZB remote serial over TCP), so no USB passthrough today. If a USB device is ever needed: `nodeSelector` on node-feature-discovery labels, never a hard-coded node name, and only one pod may hold it |
| Cameras | frigate, go2rtc, dahua-companion | Frigate consumes streams via go2rtc, never RTSP straight from a camera. go2rtc has a BGP LoadBalancer (`${GO2RTC_LB}`); Frigate needs explicit GPU / Coral device requests |
| Voice | wyoming-whisper, wyoming-piper, wyoming-openwakeword | Wyoming protocol services for Home Assistant Assist |
| Network appliance | unifi | L2 LoadBalancer `${UNIFI_LB}` (adopted APs inform to that IP); HTTPS-only UI, so no HTTPRoute yet (see backlog) |
| General self-hosted | convertx, homebox, homepage, karakeep, litellm, manyfold, mealie, meilisearch, paperless, spoolman, stirling-pdf, tandoor | Ordinary app-template apps; Postgres via CNPG, Redis via Dragonfly (paperless) |

Helper script: `scripts/amcrest.sh` (camera provisioning).

## Conventions

- **Namespaces are fixed**: Home Assistant, IoT and the general apps live in
  `default`; the MQTT broker (EMQX) lives in `database`. Do not move them and do
  not deploy a second broker: reference `emqx-listeners.database.svc` and
  create per-client credentials `<CLIENT>_EMQX_USERNAME` / `_PASSWORD` via
  `ExternalSecret`.
- **Per-app layout** mirrors the existing apps (`ks.yaml` + `app/`), charts via
  `app-template` `OCIRepository` unless upstream is clearly better.
- **Storage**: Home Assistant config and every other stateful app use the
  shared Volsync template (`../../../../templates/volsync`) with
  `PVC_VOLSYNC_STORAGECLASS` set explicitly (claim class is immutable).
  Frigate recordings belong on `ceph-filesystem`. Never put HA config on
  `openebs-hostpath`.
- **Secrets**: `ExternalSecret` only. Camera stream URLs are
  `RTSP_<CAMERA>[_SUB|_2W]`, HA tokens `HASS_TOKEN`, Zigbee network keys
  `Z2M_*` (see [docs/secrets.md](../../../docs/secrets.md)).
- **Exposure**: `route:` block to Gateway `internal`, `sectionName: https`,
  `timeouts.request: 0s` (HA, Frigate, go2rtc and z2m hold WebSocket / MJPEG
  streams). Only home-assistant (`hass.${SECRET_DOMAIN}`) and stirling-pdf
  attach to Gateway `external`; adding another public app is a deliberate
  decision, not a default. `hostNetwork` apps still get a Service + route.
- **Health**: `../../../../templates/gatus/guarded` for every user-facing app
  (`GATUS_PORT` / `GATUS_PATH` / `GATUS_SUBDOMAIN` via `postBuild.substitute`).
- **Network policy**: default-deny via `network-policies/`. The shared
  templates admit the Gateway, Prometheus, homepage + gatus
  (`allow-from-integrations`) and LAN hosts (`allow-ingress-lan`); anything
  else an app needs is a policy next to its HelmRelease.
- **Resource hygiene**: `resources.requests` always, `limits.memory` always,
  never a CPU limit; declare GPU / Coral devices explicitly.

## Heuristics

- New IoT integration: propose the HA configuration entry, MQTT topic plan,
  `ExternalSecret` for credentials and a Gatus check together.
- New camera: go2rtc stream first, then the Frigate camera block referencing
  it, then any HA camera entity.
- Changing Z2M: check that HA's MQTT integration and automations referencing
  device IDs still resolve.
- HA YAML, Z2M `configuration.yaml` and Frigate config are code: review their
  diffs like manifests.

## Boundaries

- EMQX chart `version:`, CRDs and topology belong to `@db-agent` /
  `@infra-agent`; you may add users, ACLs and topic config via
  ConfigMap / `ExternalSecret`.
- Do not modify other namespace folders; hand off network, storage and
  observability changes.
- Never delete a PVC or Kopia snapshot without named human approval.

## Validate

```bash
task kubernetes:validate APP=<ns>/<app>      # wraps the checks below
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/default/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
flux build ks <app> --kustomization-file kubernetes/apps/default/<app>/ks.yaml --path kubernetes/apps/default/<app>/app --dry-run
yamllint kubernetes/apps/default/<app>
kubectl -n default get hr,ks,pods,pvc -l app.kubernetes.io/name=<app>   # read-only, needs KUBECONFIG
```
