# Flux troubleshooting

Flux reconciles `kubernetes/` from `main`. Entry points:
`kubernetes/flux/config/cluster.yaml` (GitRepository `home-kubernetes` +
root Kustomization `cluster`) → `kubernetes/flux/apps.yaml` (`cluster-apps`,
which applies every `kubernetes/apps/<ns>/kustomization.yaml`) → one Flux
`Kustomization` per app (`ks.yaml`) → `HelmRelease`. A GitHub webhook
(`flux-webhook.${SECRET_DOMAIN}`, Receiver `github-receiver`) triggers a pull
on push; otherwise the interval is 30 min. Headlamp (`flux-system`) shows the
same objects in a UI.

All commands need `KUBECONFIG` (set by `task`). Start read-only.

## Where is it stuck?

```bash
flux get sources git -A              # did the commit land?  (revision = main@sha1:...)
flux get ks -A | grep -v ' True '    # Kustomizations not Ready
flux get hr -A | grep -v ' True '    # HelmReleases not Ready
flux events -A --for Kustomization/<app>
kubectl -n flux-system describe ks <app>   # full message, last applied revision
kubectl -n <ns> describe hr <app>
flux logs -n flux-system --kind Kustomization --name <app> --since 10m
```

`task kubernetes:resources` dumps the lot for a support snapshot.

## Common failures

| Message | Cause | Fix |
|---|---|---|
| `dependency 'flux-system/<x>' is not ready` | A `dependsOn` target is failing | Fix the dependency first; nothing downstream reconciles until it is Ready |
| `kustomize build failed` / `variable substitution failed` | Bad YAML, a `${VAR}` with no value, or a `$` in a script that Flux tried to substitute | `flux build ks <app> --kustomization-file ... --dry-run` locally; add `kustomize.toolkit.fluxcd.io/substitute: disabled` to ConfigMaps that carry shell `$` (see `volsync-canary`) |
| `decryption failed` / `sops` errors | A `*.sops.yaml` not encrypted with the cluster's Age recipient | Re-encrypt with the key in `.sops.yaml`; CI `SOPS Encryption Check` should have caught plaintext |
| HelmRelease `install retries exhausted` / `upgrade retries exhausted` | The chart failed N times and Flux stopped trying | Fix the values, then `flux -n <ns> suspend hr <app> && flux -n <ns> resume hr <app>` to reset the retry counter |
| `values not used` warning in HelmRelease events | A values key the chart does not know (typo or moved key) | Compare against the chart's `values.yaml` at that version; CI `Flux Render` prints it too |
| HelmRelease stuck `Reconciliation in progress` | A hook or probe never completes | `kubectl -n <ns> get pods`, `describe` the failing pod; `flux -n <ns> suspend/resume hr` after fixing |
| `OCIRepository` not Ready, `digest mismatch` | Chart tag re-pushed upstream or `digest:` edited by hand | Renovate owns the digest; take its PR or re-pin from `helm show chart oci://...` |
| Kustomization applies but the object does not change | CRD stored-version drift: the API server rejects the apply silently | `task kubernetes:crd-drift`, then follow `docs/runbooks/full-cluster-shutdown.md` ("latent failures") |
| `ExternalSecret` `SecretSyncedError` | Bitwarden key missing or renamed | [add-a-secret.md](./add-a-secret.md) §4 |
| `HTTPRoute` has no address / 404 at the Gateway | `parentRefs` typo, missing `sectionName: https`, or the namespace policy blocks Envoy | `kubectl -n <ns> get httproute <app> -o yaml | yq .status`; check `allow-from-ingress` is in the namespace's network-policies |

## Forcing things

```bash
flux -n flux-system reconcile source git home-kubernetes       # pull now
flux -n flux-system reconcile ks <app> --with-source            # one app
task kubernetes:reconcile                                       # root cluster ks + source (owner standing approval; watch the rollout)
task kubernetes:apply-ks PATH=<ns>/<app>                        # server-side apply one ks from the working tree (bypasses Git: for emergencies only)
flux -n flux-system suspend ks <app>  /  resume ks <app>        # freeze one app while you work on it
```

Never `kubectl edit` a Flux-managed object to fix a problem: `prune: true`
and the next reconcile revert it. Change Git, let Flux apply, or suspend the
Kustomization first and say so in the PR.

## When Flux itself is down

`flux check`, `kubectl -n flux-system get pods`, and the Flux Loki rules
(`kubernetes/apps/observability/loki/app/resources/flux-lokirule.yaml`) plus
`prometheusrules/flux.yaml` alerts. Flux's own components are reinstalled by
`task bootstrap:*` per [bare-metal-rebuild.md](./bare-metal-rebuild.md); a
stuck `cluster` Kustomization with a stale `storedVersions` on Flux CRDs was
the 2026-08-09 incident described in `task kubernetes:crd-drift`.
