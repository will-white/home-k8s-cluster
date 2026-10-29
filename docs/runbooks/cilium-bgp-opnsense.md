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

Done 2026-10-28 on OPNsense 26.7.7 / os-frr 2.0 (backup of the prior config:
`/root/config.xml.pre-frr-20261028`).

1. **System → Firmware → Plugins**: install `os-frr`.
2. **Routing → General**: enable, and **untick "Firewall rules"**. That
   option registers `pass in tcp to (self) port 179` on *every* interface,
   WAN included, and the WAN address is public. The LAN default-allow rule
   (`LAN net → any`) already admits the nodes, so nothing else is needed.
3. **Routing → BGP → General**: enable, BGP AS Number `64513`, Router ID
   `192.168.5.1`, Log Neighbor Changes on, Maximum Paths `8`, save.
4. **Routing → BGP → Prefix Lists**: two IPv4 lists, so a node (or anything
   impersonating one) can only inject Service `/32`s, and OPNsense sends the
   cluster nothing:

   | Name | Seq | Action | Network |
   |---|---|---|---|
   | `cilium-in` | 10 | Permit | `192.168.110.0/24 ge 32` |
   | `cilium-out` | 10 | Deny | `0.0.0.0/0 le 32` |

5. **Routing → BGP → Neighbors**: one entry per node, all identical except the
   address:

   | Field | Value |
   |---|---|
   | Enabled | yes |
   | Peer-IP | `192.168.5.40` (then .41, .42, .50, .51, .52, .53, .54) |
   | Remote AS | `64512` |
   | Update-Source Interface | LAN |
   | Next-Hop-Self | yes |
   | BFD | off |
   | Prefix-List In / Out | `cilium-in` / `cilium-out` |

   The plugin also offers peer groups with a listen range, which would make
   new nodes peer automatically, but a `/24` listen range lets any LAN host
   open a session. Explicit neighbors keep that list closed.
6. **System → Settings → Tunables**: set `net.route.multipath` to `1`.
   OPNsense defaults it to `0`, which makes zebra install a single next-hop per
   Service IP instead of ECMP across the nodes.
7. Apply. **Routing → Diagnostics → BGP → Summary** lists the eight neighbors
   as `Active` until the cluster side lands, then `Established` within ~30 s.
   From a shell: `vtysh -c 'show bgp ipv4 unicast summary'`.

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

**Before the first Service moves**, on OPNsense (done 2026-10-29; the rules
use an alias `K8S_BGP_NET` = `192.168.110.0/24`):

- **LAN clients route asymmetrically.** A LAN host reaches `192.168.110.x`
  through OPNsense, but the node answers it directly on the shared L2, so pf
  sees only the client half of each TCP connection. A strict state never
  leaves the opening phase and expires after 30 s. pf keeps a state for each
  direction the packet crosses the router (LAN in, then LAN out), so both
  need **sloppy state**:
  - **Firewall → Rules → LAN**, above the default-allow: pass, source
    `LAN net`, destination `K8S_BGP_NET`, *Advanced → State type* `sloppy state`.
  - **Firewall → Rules → Floating**: pass, interface LAN, direction **out**,
    destination `K8S_BGP_NET`, quick, `sloppy state`.

  (The "bypass firewall rules for traffic on the same interface" option does
  not help: it only covers static routes, not BGP-learned ones.) Verify with a
  keep-alive connection that outlives 30 s, e.g.
  `curl -sk --rate 2/m -w '%{num_connects}\n' -o /dev/null URL -o /dev/null URL -o /dev/null URL`
  printing `1 0 0`.
- **VLANs** route symmetrically (the node replies via its default gateway), but
  check each VLAN's rules in *both* directions. An "internet only" rule
  written as `→ !LAN net` (as on IOT here) silently **admits** the routed
  range, so IOT needs a **block** `IOT_NET → K8S_BGP_NET` above it. Add explicit
  passes only where a VLAN should reach a moved Service.
- **Anything else that routes only the LAN `/24`** loses the moved Services:
  the Tailscale subnet router on skylab must also advertise `192.168.110.0/24`
  (and the route must be approved in the Tailscale admin console).
- **Make sure both AdGuard external-dns releases are Ready.** The
  `adguard-dns-external` Kustomization `dependsOn` `adguard-dns-internal`; if
  the latter is stalled, the new `--default-targets` never deploys and every
  external-Gateway name keeps resolving to the dead L2 address (this happened
  on the first run, see #1579).
- No NAT changes: the Service IPs are only reachable from inside.

Order, from least to most disruptive (only the first two are in the phase-2
PR; the rest need their external clients repointed first):

| Service | Old | New | Watch out for |
|---|---|---|---|
| Gateway `internal` | 192.168.5.46 | 192.168.110.46 | AdGuard records follow automatically |
| Gateway `external` | 192.168.5.48 | 192.168.110.48 | `adguard-dns-external --default-targets` must match |
| postgres (CNPG) | 192.168.5.23 | 192.168.110.23 | only in-cluster + `postgres.<domain>` clients |
| tdarr | 192.168.5.24 | 192.168.110.24 | the Tdarr node on plex.internal uses `tdarr.internal`, an OPNsense dnsmasq host override: repoint it, then `systemctl restart tdarr-node` there to skip its reconnect backoff |
| EMQX (mqtt) | 192.168.5.21 | 192.168.110.21 | checked 2026-10-29 with `emqx ctl clients list`: only off-cluster client is the Roborock, via `mqtt.<domain>`; HA uses the ClusterIP name |
| go2rtc | 192.168.5.22 | 192.168.110.22 | only consumer is Frigate (in-cluster); no WebRTC candidate pinned to the LB IP |
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
