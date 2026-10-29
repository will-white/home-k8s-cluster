# Add or change a secret

Every runtime secret lives in Bitwarden Secrets Manager (project
`home-cluster`) and reaches the cluster through an `ExternalSecret`. SOPS is
only for the four bootstrap files Flux needs before External Secrets exists.
Naming rules and the current inventory: [docs/secrets.md](../secrets.md).

Never paste a secret value into a chat, a PR, a commit, a log line or a
ConfigMap. Confirm by key name and success only.

## 1. Pick the key name

`<OWNER>_<PURPOSE>` in `UPPER_SNAKE_CASE`, where OWNER is the system that
issues the credential, not the app that consumes it:

| Example | Why |
|---|---|
| `SONARR_API_KEY` | Sonarr issues it |
| `PLEX_TOKEN` | used by bazarr and kometa, owned by Plex |
| `HOMEPAGE_KAVITA_API_KEY` vs `KOMF_KAVITA_API_KEY` | per-consumer keys for the same service carry the consumer |
| `<APP>_POSTGRES_USER` / `_PASSWORD` | database users keep `_USER` |
| `<CLIENT>_EMQX_USERNAME` / `_PASSWORD` | MQTT clients |
| `RTSP_<CAMERA>[_SUB\|_2W]` | camera stream URLs (they embed credentials) |

One flat value per secret. No JSON blobs; `dataFrom.extract` is retired.

## 2. Create it in Bitwarden

From a workstation with `BWS_ACCESS_TOKEN` exported (the devcontainer passes
it through):

```bash
bws secret create <KEY_NAME> "$(cat value.txt)" "$BWS_PROJECT_ID"
```

Read the value from a file or a prompt, never from shell history. Agents may
run this **only when explicitly asked for a named app**, and report only the
key name and whether it succeeded. `bws secret get` and
`scripts/bws-secret.sh` print raw values and are for the talhelper flow, not
for routine use.

To rotate: `bws secret edit --value "$(cat new.txt)" <SECRET_ID>`. The
`ExternalSecret` refreshes within its `refreshInterval` (1h default); force it
with `kubectl -n <ns> annotate externalsecret <name> force-sync=$(date +%s) --overwrite`.

## 3. Reference it from the app

`kubernetes/apps/<ns>/<app>/app/externalsecret.yaml`, mirroring an existing
one:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app>
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: bitwarden-secrets-manager
  target:
    name: <app>-secret
    template:
      engineVersion: v2
      data:
        APP_ENV_VAR: "{{ .MY_KEY }}"          # shape the env the app wants here
  data:
    - secretKey: MY_KEY
      remoteRef:
        key: MY_KEY                             # the Bitwarden key name
```

Then in the HelmRelease: `envFrom: [{secretRef: {name: <app>-secret}}]` or a
`valueFrom.secretKeyRef`, and `reloader.stakater.com/auto: "true"` on the
controller so a rotated value restarts the pod. The app's `ks.yaml` must list
`dependsOn: external-secrets-stores`.

## 4. Validate

```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/<ns>/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
# after merge (needs KUBECONFIG):
kubectl -n <ns> get externalsecret <app>        # STATUS SecretSynced, READY True
kubectl -n <ns> describe externalsecret <app>   # on failure: the event names the missing key
```

`SecretSyncedError ... not found` means the Bitwarden key name and
`remoteRef.key` differ, or the machine account cannot read the project.

## Bootstrap (SOPS) secrets

Only `talsecret`, `github-deploy-key`, `cluster-secrets` and the Bitwarden
access token are SOPS files (`*.sops.yaml`, rules in `.sops.yaml`). Editing one
is `sops kubernetes/flux/vars/cluster-secrets.sops.yaml`; it decrypts in the
editor and re-encrypts on save with the Age key at `age.key`. `sops --encrypt`
on a new file needs human approval, and the `.githooks/pre-commit` gitleaks gate
refuses a plaintext value. After rotating `age.key`, run
`task bootstrap:secrets-push` so the key survives a workstation loss.
