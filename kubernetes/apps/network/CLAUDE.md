# network — domain guide (`@infra-agent`)

Loaded automatically for work under `kubernetes/apps/network/`. The full IP /
DNS picture is in [docs/network-layout.md](../../../docs/network-layout.md);
the BGP side in [docs/runbooks/cilium-bgp-opnsense.md](../../../docs/runbooks/cilium-bgp-opnsense.md).

## Components

| App | Role |
|---|---|
| cilium-gateway | `GatewayClass cilium` + Gateways `internal` (`192.168.110.46`) and `external` (`192.168.110.48`), both on the BGP pool; wildcard Let's Encrypt cert `certificates/wildcard.yaml`; HTTP → HTTPS redirect route; Envoy access-log Loki rules |
| cloudflared | Tunnel: `*.${SECRET_DOMAIN}` → `cilium-gateway-external.network.svc:443` |
| cloudflare-dns | external-dns → Cloudflare, `gateway-httproute` + `crd` sources, only routes on Gateway `external`; CNAME target from the Gateway's `external-dns.alpha.kubernetes.io/target` annotation; refuses private targets |
| adguard-dns-internal | external-dns → AdGuard, routes on Gateway `internal` resolve to its LB address; `dnsendpoint.yaml` holds the LAN-only static names (router-served services) |
| adguard-dns-external | external-dns → AdGuard, routes on Gateway `external` forced to `--default-targets=192.168.110.48` so public apps resolve on-LAN without hairpinning through Cloudflare |

## Conventions

- **Apps never create DNS records or Ingress objects.** A `route:` block (or
  raw `HTTPRoute`) with `parentRefs` to `internal` or `external` is the whole
  contract; the three external-dns instances derive the records.
- **`timeouts.request: 0s`** on every route unless the app is a short request
  API: Envoy's default is 15 s, nginx had none.
- **Public exposure** = attach to `external`. That single change publishes a
  Cloudflare CNAME and an AdGuard record; treat it as a security review, not a
  config tweak.
- **Gateway IPs** are pinned twice (metadata annotation and
  `infrastructure.annotations`) plus `infrastructure.labels.lb-pool: bgp`.
  Changing one means updating `adguard-dns-external --default-targets` and the
  AdGuard rewrite too.
- **LAN-only names** served by the router or NAS go in
  `adguard-dns-internal/app/dnsendpoint.yaml` with the
  `dns.home.arpa/target: adguard` label; the Cloudflare instance filters on
  that label and on private target networks, so they can never leak.
- **external-dns 0.22+** needs `--annotation-prefix=external-dns.alpha.kubernetes.io/`
  on every instance: dropping it once deleted the public records (#1381/#1402).
- Secrets (Cloudflare token, tunnel credentials, AdGuard login) via
  `ExternalSecret`.

## Boundaries

- Changes here affect every app's reachability; `flux build` / `flate test`
  before proposing, and check `kubectl -n network get gateway,httproute -A`
  after.
- Never advertise the LAN `/24` over BGP (see the runbook's last section).

## Validate

```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/network/<app>/app | kubeconform -strict -ignore-missing-schemas -skip Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute -
kubectl -n network get gateway,httproute,svc        # read-only
kubectl -n network logs deploy/cloudflare-dns | grep -E 'action=(DELETE|CREATE)'
```
