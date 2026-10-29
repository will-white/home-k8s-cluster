# Bitwarden Secrets Manager — naming schema

Every secret in the `home-cluster` BWS project is a **single flat value** —
never a JSON blob. ExternalSecrets reference them with explicit `data:`
entries (`remoteRef.key` = BWS secret name); `dataFrom.extract` of JSON blobs
is retired. SOPS survives only for the 4 bootstrap-capsule files
(`talsecret`, `github-deploy-key`, `cluster-secrets`, `bitwarden-access-token`).
How to add or rotate one: [runbooks/add-a-secret.md](./runbooks/add-a-secret.md).

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

## History

The August 2026 flattening replaced every JSON blob with flat values and
renamed to the schema above; the mapping is in git history (`git log -S
'Renames applied' -- docs/secrets.md`). Blobs and unreferenced leftovers
(`volsync-kopia`, `volsync-restic`, `overseerr`, `portainer`,
`cloudnative-pg-s3`, `HOMEPAGE_HASS_TOKEN`) were deletion candidates at the
time; confirm with `bws secret list` before assuming they still exist.

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
