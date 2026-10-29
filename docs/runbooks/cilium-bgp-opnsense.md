# Cilium BGP peering with OPNsense

Cilium's BGP control plane advertises LoadBalancer IPs to OPNsense so they are
**routed** rather than ARP-announced. Only Services in the BGP pool
(`192.168.110.0/24`, label `lb-pool=bgp`) use it; everything else stays on the
L2 announcement policy for the LAN `/24`.

Cluster side: `kubernetes/apps/kube-system/cilium/config/cilium-bgp.yaml`
(`bgpControlPlane.enabled` in the Helm values).

| | Cluster | OPNsense |
|---|---|---|
| ASN | 64512 | 64513 |
| Peer address | every node's LAN IP (below) | 192.168.5.1 |
| Advertised | `192.168.110.0/24` Service IPs as /32s | nothing (no default route needed) |

Nodes: `.40 .41 .42` (control plane), `.50 .51 .52 .53 .54` (workers). Each node
opens its own eBGP session to OPNsense, so OPNsense sees eight neighbors and
installs each Service IP as an ECMP route via the nodes that host it.

---

## Phase 1: establish the sessions (nothing moves yet)

### OPNsense

1. **System → Firmware → Plugins**: install `os-frr`.
2. **Routing → General**: enable routing, save.
3. **Routing → BGP → General**: enable, BGP AS Number `64513`, Router ID
   `192.168.5.1`, save.
4. **Routing → BGP → Neighbors**: one entry per node, all identical except the
   address:

   | Field | Value |
   |---|---|
   | Enabled | yes |
   | Peer-IP | `192.168.5.40` (then .41, .42, .50, .51, .52, .53, .54) |
   | Remote AS | `64512` |
   | Update-Source Interface | LAN |
   | Next-Hop-Self | yes |
   | BFD | off |

   If your FRR plugin version offers **peer groups** with a listen range,
   one group `cilium` with `bgp listen range 192.168.5.0/24 peer-group cilium`
   replaces the eight entries. Nodes added later then peer automatically.
5. **Firewall → Rules → LAN**: allow TCP `179` from the node IPs (or the LAN
   net) to `This Firewall`. Without it the sessions sit in `Active`.
6. Apply. **Routing → Diagnostics → BGP → Summary** should list eight
   neighbors in state `Established` within ~30 s of the Cilium side landing.

### Cluster

Merge the phase-1 PR. Then:

```bash
cilium bgp peers
```

Every node should show `Session State: established`, `Uptime` climbing, and
`Received/Advertised: 0/0` (nothing labelled yet).

```bash
kubectl -n kube-system get ciliumbgpclusterconfig,ciliumbgppeerconfig,ciliumbgpadvertisement,ciliumloadbalancerippool
```

`bgp-pool` should report `0` IPs in use and `l2-pool` unchanged.

Nothing user-facing changes in this phase. If a session will not come up:
`kubectl -n kube-system logs ds/cilium -c cilium-agent | grep -i bgp` on the
node in question, and `vtysh -c 'show bgp neighbors'` on OPNsense.

---

## Phase 2: move Services into the BGP pool

Done per Service by adding the label and a new pinned IP:

```yaml
metadata:
  labels:
    lb-pool: bgp
  annotations:
    lbipam.cilium.io/ips: 192.168.110.x
```

For the Cilium Gateways that is `spec.infrastructure.labels` plus the
`lbipam.cilium.io/ips` annotations (metadata and infrastructure). The moment
the label lands, L2 stops announcing the old IP and OPNsense learns the new
one; external-dns re-points the DNS records from the Gateway/Service status.

**Before the first Service moves**, on OPNsense:

- **Firewall → Rules** on LAN and every VLAN that should reach cluster
  services: allow traffic to `192.168.110.0/24` (it is now a routed network,
  not the connected LAN, so existing "LAN net" rules do not cover it).
- If OPNsense does NAT for outbound only, nothing else; the Service IPs are
  only reachable from inside.

Order, from least to most disruptive (only the first two are in the phase-2
PR; the rest need their external clients repointed first):

| Service | Old | New | Watch out for |
|---|---|---|---|
| Gateway `internal` | 192.168.5.46 | 192.168.110.46 | AdGuard records follow automatically |
| Gateway `external` | 192.168.5.48 | 192.168.110.48 | `adguard-dns-external --default-targets` must match |
| postgres (CNPG) | 192.168.5.23 | 192.168.110.23 | only in-cluster + `postgres.<domain>` clients |
| tdarr | 192.168.5.24 | | the external Tdarr node on plex.internal connects by IP |
| EMQX (mqtt) | 192.168.5.21 | | every ESPHome/Tasmota/Zigbee device configured with the IP |
| go2rtc | 192.168.5.22 | | cameras/HA using the IP |
| UniFi | 192.168.5.25 | | adopted APs inform to this IP; re-adopt or set inform host first |

Verify after each move:

```bash
cilium bgp routes advertised ipv4 unicast
kubectl -n network get gateway       # ADDRESS shows the 192.168.110.x
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.110.46 -H 'Host: grafana.<domain>'
```

On OPNsense, **Routing → Diagnostics → BGP → Routes** lists each Service IP
as `/32` with the node next-hops.

## Rollback

Remove the `lb-pool: bgp` label and restore the old `lbipam.cilium.io/ips`
on the Service: L2 takes it back immediately. Disabling BGP entirely is
`bgpControlPlane.enabled: false` plus deleting `cilium-bgp.yaml`; OPNsense
withdraws the routes when the sessions drop.

## Why not advertise the LAN /24 IPs over BGP as well

OPNsense would install `/32` host routes for addresses inside its own
connected LAN subnet. Hosts on that subnet never consult the router for
on-link addresses; they ARP, which only the L2 announcer answers. BGP for
those IPs would only ever matter to other VLANs, which already reach them
through the LAN interface. The clean split is the routed `/24` above.
