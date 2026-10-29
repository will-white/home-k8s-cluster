# Network layout

Reference for every address the cluster owns or depends on. Change the source
file named in each row, not this page alone.

## Addressing

| Range / address | What | Source of truth |
|---|---|---|
| `192.168.5.0/24` | LAN. OPNsense `.1`, AdGuard `.2`, NAS `.10` | `kubernetes/flux/vars/cluster-settings.yaml` (`ADGUARD_IP`, `NAS_IP`) |
| `192.168.5.40 .41 .42` | Control-plane nodes | `cluster-settings.yaml` (`CONTROL_PLANE_*_IP`), `kubernetes/bootstrap/talos/talconfig.yaml` |
| `192.168.5.50 … .54` | Worker nodes | `talconfig.yaml` |
| `192.168.5.0/24` (L2 pool) | LoadBalancer IPs announced by ARP. Only Services **without** `lb-pool: bgp`. Today: UniFi `.25` | `kubernetes/apps/kube-system/cilium/config/cilium-l2.yaml` |
| `192.168.110.0/24` (BGP pool) | LoadBalancer IPs routed via OPNsense (eBGP 64512 ↔ 64513). Services labelled `lb-pool: bgp` | `cilium-bgp.yaml`, runbook [cilium-bgp-opnsense.md](./runbooks/cilium-bgp-opnsense.md) |

### LoadBalancer allocations

| IP | Service | Variable |
|---|---|---|
| `192.168.110.21` | EMQX MQTT listeners | `${EMQX_LB}` |
| `192.168.110.22` | go2rtc (camera streams, WebRTC) | `${GO2RTC_LB}` |
| `192.168.110.23` | CloudNativePG `postgres16-rw` for off-cluster clients | `${POSTGRES_LB}` |
| `192.168.110.24` | tdarr server (off-cluster transcode nodes) | `${TDARR_LB}` |
| `192.168.110.46` | Gateway `internal` | pinned in `kubernetes/apps/network/cilium-gateway/app/gateway.yaml` |
| `192.168.110.48` | Gateway `external` | pinned in `gateway.yaml` and `adguard-dns-external --default-targets` |
| `192.168.5.25` | UniFi controller (L2; adopted APs inform to this IP) | `${UNIFI_LB}` |

New LoadBalancer Services get a `${NAME_LB}` variable in `cluster-settings.yaml`,
the `lb-pool: bgp` label and the next free `.110.x`. L2 is reserved for things
that have a LAN IP burned into off-cluster devices.

## HTTP ingress

```
LAN client ──DNS (AdGuard)──► 192.168.110.46  Gateway internal ──► HTTPRoute ──► Service
LAN client ──DNS (AdGuard)──► 192.168.110.48  Gateway external ──► HTTPRoute ──► Service
Internet   ──Cloudflare CNAME──► cloudflared tunnel ──► cilium-gateway-external.network.svc:443 ──► HTTPRoute
```

- Both Gateways terminate TLS with the wildcard Let's Encrypt certificate from
  `cilium-gateway/certificates/wildcard.yaml` (`${SECRET_DOMAIN/./-}-gateway-tls`).
- An app is exposed by a `route:` block (app-template) or a raw `HTTPRoute`
  with `parentRefs` to `internal` or `external`, `sectionName: https`,
  `timeouts.request: 0s`. Port 80 on both Gateways only serves the
  HTTP → HTTPS redirect route.
- Default-deny namespaces admit the Gateway's Envoy through the
  `allow-from-ingress` `CiliumNetworkPolicy` template (`fromEntities: [ingress]`).
- Public apps today: home-assistant (`hass`), stirling-pdf, seerr, gatus
  (`status`) and the Flux webhook receiver (`flux-webhook`). Attaching anything
  else to `external` is a security decision.

## DNS (split horizon)

| Instance | Provider | Source | Result |
|---|---|---|---|
| `adguard-dns-internal` | AdGuard rewrites | HTTPRoutes on Gateway `internal`, plus `dnsendpoint.yaml` static LAN names | `app.${SECRET_DOMAIN}` → `192.168.110.46` on the LAN |
| `adguard-dns-external` | AdGuard rewrites | HTTPRoutes on Gateway `external` (`--force-default-targets 192.168.110.48`) | Public apps resolve to the Gateway on-LAN instead of hairpinning through Cloudflare |
| `cloudflare-dns` | Cloudflare | HTTPRoutes on Gateway `external` + `DNSEndpoint`s not labelled `dns.home.arpa/target=adguard` | Proxied CNAME → `external.${SECRET_DOMAIN}` (the tunnel). Private target networks are excluded as a fail-closed guard |

LAN-only names served by the router (Caddy on OPNsense), the NAS or AdGuard
itself live in `adguard-dns-internal/app/dnsendpoint.yaml` with the AdGuard
label. There is deliberately no wildcard rewrite: AdGuard answers with the
union of matching rewrites, so a catch-all would give every in-cluster name a
second address.

All three instances need `--annotation-prefix=external-dns.alpha.kubernetes.io/`
(external-dns ≥ 0.22 changed the default with no fallback and once deleted the
public records, #1381 / #1402).

## Other protocols

| Flow | Path |
|---|---|
| MQTT from LAN devices | `${EMQX_LB}:1883/8883` (BGP) |
| Camera RTSP / WebRTC | cameras → go2rtc (`${GO2RTC_LB}`) → Frigate; HA uses go2rtc streams |
| Home Assistant discovery (mDNS, Matter, Sonos) | `hostNetwork: true` on home-assistant, matter-server, music-assistant |
| NFS media | every media app mounts `${NAS_IP}:/mnt/main/media` inline (csi-driver-nfs is a backlog item) |
| Prometheus remote-write from LAN hosts | `allow-ingress-lan` template on `observability` |
| Postgres from LAN tools | `${POSTGRES_LB}:5432` |

## Network policy posture

Namespaces `cert-manager`, `external-secrets`, `observability`, `media`,
`default`, `database` are default-deny via `kubernetes/templates/network-policies/`
(DNS, API server, Gateway, Prometheus, homepage + gatus, LAN hosts admitted by
the shared templates; app-specific egress in a policy next to the HelmRelease).
`network`, `kube-system` and `flux-system` host their own controllers and carry
bespoke policies. The LAN is the trust boundary of this homelab.
