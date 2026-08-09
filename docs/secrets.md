# Bitwarden Secrets Manager — naming schema & inventory

Every secret in the `home-cluster` BWS project is a **single flat value** —
never a JSON blob. ExternalSecrets reference them with explicit `data:`
entries (`remoteRef.key` = BWS secret name); `dataFrom.extract` of JSON blobs
is retired. SOPS survives only for the 4 bootstrap-capsule files
(`talsecret`, `github-deploy-key`, `cluster-secrets`, `bitwarden-access-token`).

## Naming rules

1. `UPPER_SNAKE_CASE`, named `<OWNER>_<PURPOSE>`, where OWNER is the system
   that *issues or owns* the credential — not the app that consumes it
   (`PLEX_TOKEN` is used by bazarr and kometa; `PIA_USERNAME` by qbittorrent's
   gluetun).
2. Standard suffixes: `_USERNAME`/`_USER` (DB users keep `_USER`), `_PASSWORD`,
   `_API_KEY`, `_TOKEN`, `_SECRET_KEY`/`_ACCESS_KEY`, `_URL`, `_HOST`.
3. Per-consumer API keys for the same service stay distinct and carry the
   consumer: `HOMEPAGE_KAVITA_API_KEY` vs `KOMF_KAVITA_API_KEY`.
4. Site-wide constants are unprefixed: `LATITUDE`, `LONGITUDE`, `ELEVATION`,
   `NFS_SERVER`.
5. MQTT client credentials: `<CLIENT>_EMQX_USERNAME/_PASSWORD`.
6. Camera stream URLs (contain credentials): `RTSP_<CAMERA>[_SUB|_2W]`.

## Renames applied in the 2026-08 flattening

| Old (blob/field or flat name) | New flat name |
|---|---|
| `cloudflare/CLOUDFLARE_Tunnel_ID` | `CLOUDFLARE_TUNNEL_ID` |
| `adguard/ADGUARD_USER` | `ADGUARD_USERNAME` |
| `unpoller/USERNAME`, `/PASSWORD` | `UNPOLLER_USERNAME`, `UNPOLLER_PASSWORD` |
| `zigbee2mqtt/PAN_ID`, `/EXT_PAN_ID`, `/NETWORK_KEY` | `Z2M_PAN_ID`, `Z2M_EXT_PAN_ID`, `Z2M_NETWORK_KEY` |
| `karakeep/NEXTAUTH_SECRET`, `/OPENAI_API_KEY` | `KARAKEEP_NEXTAUTH_SECRET`, `KARAKEEP_OPENAI_API_KEY` |
| `EMQX/DAHUA_COMPANION_*`, `/AMBIENTWEATHER_*` | `DAHUA_EMQX_*`, `AMBIENTWEATHER_EMQX_*` |
| `security-cameras/camera1[_sub]`, `/doorbell[_sub|_2w]`, `/mechanical[_sub]` | `RTSP_CAMERA1[_SUB]`, `RTSP_DOORBELL[_SUB|_2W]`, `RTSP_MECHANICAL[_SUB]` |
| `rclone-rgw-backup/GARAGE_*` | `GARAGE_*` (unchanged names, now flat) |
| `kopia-restic-password` | `VOLSYNC_KOPIA_PASSWORD` |
| `volsync-bucket-key` / `-secret` | `VOLSYNC_BUCKET_ACCESS_KEY` / `VOLSYNC_BUCKET_SECRET_KEY` (PushSecret-managed) |
| `cloudnative-pg-bucket-key` / `-secret` | `CNPG_BUCKET_ACCESS_KEY` / `CNPG_BUCKET_SECRET_KEY` (PushSecret-managed) |
| `alertmanager/ALERTMANAGER_PUSHOVER_USER_KEY` | `PUSHOVER_USER_KEY` (account-level, shared) |
| `alertmanager/ALERTMANAGER_PUSHOVER_TOKEN` | `PUSHOVER_TOKEN` (single shared app token — used by alertmanager AND gatus) |
| SOPS `OPENVPN_USER` / `OPENVPN_PASSWORD` | `PIA_USERNAME` / `PIA_PASSWORD` |
| SOPS homebox pepper / flux webhook token | `HOMEBOX_PEPPER` / `FLUX_GITHUB_WEBHOOK_TOKEN` |

All other blob fields already followed the schema and kept their names as
flat secrets (e.g. `HOMEBOX_POSTGRES_PASSWORD`, `TRAKT_CLIENT_SECRET`).

## Deliberately NOT migrated (deletion candidates after cutover)

Unreferenced by any manifest: `volsync-kopia` (blob), `volsync-restic` (blob),
`overseerr`, `portainer` (flat), `cloudnative-pg-s3` (only the hand-applied
`test-cloudnative-pg-s3` ExternalSecret in `database` references it — delete
that too), `POSTGRES/POSTGRES_S3_KEY` + `_S3_SECRET_KEY`,
`rclone-rgw-backup/CEPH_ACCESS_KEY` + `CEPH_SECRET_KEY`,
`HOMEPAGE_HASS_TOKEN` (duplicate of `HASS_TOKEN`).

## Pushover

The old `pushover` blob was deleted from BWS ~2026-07-25 (it held per-app
tokens for gatus/radarr/sonarr, and left the gatus ExternalSecret failing for
15 days). Decision (2026-08-09): a **single shared app token** `PUSHOVER_TOKEN`
(seeded from alertmanager's surviving token) serves all senders, alongside the
account-level `PUSHOVER_USER_KEY`. To give an app its own Pushover identity
later, register a new application at pushover.net and point that app's
ExternalSecret at a new `<APP>_PUSHOVER_TOKEN`. radarr/sonarr pushover
notifications were already disabled before the migration and remain off —
copy the gatus pattern to enable them.
