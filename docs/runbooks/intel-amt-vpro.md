# Intel AMT / vPro — out-of-band management

All 8 nodes are vPro machines with Intel AMT: a management coprocessor (the
Management Engine, ME) that runs independently of the host OS and provides
remote power control, KVM, and boot management even when Talos is wedged or
the box is powered off. This runbook covers how AMT hangs together on these
nodes, the activation + CIRA/MeshCentral setup, and recovery when AMT goes
dark. For remotely re-imaging a node once you have AMT KVM, see
[bare-metal-rebuild.md](./bare-metal-rebuild.md).

## How it hangs together

- **AMT is firmware, not software.** The ME shares the host's physical NIC
  and MAC address but runs its own IP stack. Nothing Talos loads (or fails
  to load) affects whether AMT answers on the network — a node with a dead
  OS still has working AMT, and a perfectly healthy node can have dead AMT.
- **The `siderolabs/mei` extension** (in the factory schematic — see
  `talconfig.yaml`) provides `/dev/mei0` via the `mei_me` driver. This is
  the *host↔ME* channel only: it is required for host-based (in-OS)
  activation and local AMT queries, and is **not** required for out-of-band
  reachability. Check it with:
  `talosctl -n <ip> read /proc/modules | grep mei_me`.
- **AMT listens on** 16992 (HTTP/WSMAN), 16993 (HTTPS), 16994/16995
  (redirection), and 5900 (KVM/VNC when enabled) — on *AMT's* IP, which is
  only the host's IP if you configure it that way.
- **Hosts are static-IP'd** (`dhcp: false` in `talconfig.yaml`), which is
  why AMT's factory-default DHCP shared-IP mode was flaky here: the ME runs
  its own DHCP client, gets a pool address nobody expects (or none at all),
  and drops off on lease/link hiccups. This is the root cause of
  "sometimes it works, sometimes it doesn't".

## Node inventory

AMT IPs follow the host IP + 100 convention. Confirm they sit outside the
OPNsense DHCP pool (or add static mappings for them) before provisioning.

| Hostname | Host IP        | MAC                 | AMT IP (planned) |
| -------- | -------------- | ------------------- | ---------------- |
| mj0583jp | 192.168.5.40   | `6c:0b:84:e3:07:55` | 192.168.5.140    |
| mj0581m7 | 192.168.5.41   | `6c:0b:84:e3:64:51` | 192.168.5.141    |
| mj0583eq | 192.168.5.42   | `6c:0b:84:e3:05:cd` | 192.168.5.142    |
| mj05ajfj | 192.168.5.50   | `6c:4b:90:01:c4:11` | 192.168.5.150    |
| mj04ew44 | 192.168.5.51   | `6c:0b:84:e0:20:b1` | 192.168.5.151    |
| mj0581rw | 192.168.5.52   | `6c:0b:84:e3:64:b1` | 192.168.5.152    |
| mj04968e | 192.168.5.53   | `00:23:24:ba:59:9d` | 192.168.5.153    |
| mj05g4ub | 192.168.5.54   | `6c:4b:90:0a:7b:a7` | 192.168.5.154    |

(192.168.5.45 is the k8s control-plane VIP — unrelated to AMT.)

## Decisions and why

- **Activation mode: ACM (Admin Control Mode), via MEBx.** Host-based
  activation is zero-touch but lands in CCM, where KVM *permanently*
  requires a consent code shown on the physical display — useless on
  headless nodes. ACM = consent-free KVM. The cert-based zero-touch ACM
  path needs a purchased provisioning cert plus a DHCP-supplied DNS suffix;
  not worth it for 8 static-IP machines.
- **Static AMT IPs.** CIRA does not require them (the tunnel is outbound),
  but they are the fallback path when the CIRA/MeshCentral layer is itself
  what broke, and they keep AMT reachable during exactly the disasters
  (power/DHCP outages) where you want it most. Costs ~30s while already in
  MEBx.
- **CIRA to MeshCentral for day-to-day**, direct-to-static-IP as fallback.

## 1. MEBx activation (per node, one console visit)

1. Reboot, press **Ctrl+P** during POST (Lenovo Tiny: if no prompt, enable
   the MEBx hotkey in BIOS setup first).
2. Log in with default password `admin`; it forces a change. **One shared
   password for the fleet, stored in Bitwarden SM** (suggested key:
   `CLUSTER_AMT_MEBX_PASSWORD`) — never in git. With manual provisioning
   this MEBx password *is* the network `admin` password AMT tools use.
3. Intel AMT Configuration → **Network Setup**: static IP from the table
   above, netmask `255.255.255.0`, gateway `192.168.5.1`, and DNS —
   required for CIRA if the MPS is configured by FQDN rather than IP.
4. Intel AMT Configuration → **Activate Network Access** (confirm).
5. **Power Policies → "Always On (S0–S5)"** and disable any idle/link
   power-saving timeout. Without this, AMT sleeps when the host is off —
   the single most common "AMT was reachable yesterday" cause.
6. Exit; from any LAN machine verify:
   `for p in 16992 16993; do nc -zvw2 <amt-ip> $p; done`

## 2. MeshCentral + CIRA

Server prerequisites (once):

- `config.json` → `settings.mpsPort: 4433` (the default; `0` disables).
  Docker: publish 4433. Reverse proxy: the MPS is raw TLS, **do not** route
  it through the HTTP proxy — expose 4433 directly.
- From the node VLAN: `nc -zvw2 <meshcentral-host> 4433`.

Per fleet:

1. Create a device group of type **"Intel AMT only, no agent"**; add each
   node by its **AMT IP** with the `admin` credentials. Direct management
   should work immediately — good checkpoint before layering CIRA.
2. Group → **Intel AMT CIRA setup** → download `cira_setup.mescript`
   (MeshCentral bakes in the MPS address, generated credentials, its root
   cert hash, and an always-connect environment-detection domain).
3. Push it to each node from any LAN machine:

   ```bash
   meshcmd amtscript --script cira_setup.mescript \
     --host 192.168.5.140 --user admin --pass '<mebx-password>'
   ```

4. The device flips to a persistent CIRA connection in MeshCentral within
   a minute or two. `cira_cleanup.mescript` (same page) undoes it.
5. **Verify the failure modes that matter:** power-cycle a node from
   MeshCentral with the OS up; then shut it down and confirm AMT/KVM still
   answers (proves the S0–S5 power package took).

## Alternative: zero-touch CCM activation from the cluster

Because `mei` is loaded on every node, `meshcmd amtactivate --url <activation
URL from the group's invite dialog>` can activate AMT + configure CIRA via
local `/dev/mei0` with **no console visit** — even from AMT's current dead
state. On Talos that means a privileged one-shot Job per node with
`/dev/mei0` host-mounted. Trade-off: CCM locks KVM behind on-screen consent
(power control and monitoring stay consent-free). Use it for nodes where a
console visit is impractical, or if power control is all you need.

## Troubleshooting

- **Is AMT alive anywhere?** Port-probe the expected IPs, then sweep every
  node's ARP cache for a node MAC appearing at a *second* IP (= a live AMT
  DHCP lease somewhere unexpected):

  ```bash
  for ip in 192.168.5.{40,41,42,50,51,52,53,54}; do
    talosctl -n $ip read /proc/net/arp
  done | awk '{print $1, $4}' | sort -u | grep -iE '<mac1>|<mac2>|...'
  ```

  As of 2026-08-12 both checks came back empty on all 8 nodes — AMT fully
  network-dead fleet-wide (unprovisioned or deactivated by the 2026-08-08/09
  power event). That is what prompted this runbook.
- **CIRA shows connected but commands hang:** known ME firmware quirk. Try
  unconfigure/reconfigure CIRA (`cira_cleanup` + `cira_setup`); if the ME
  itself is wedged, full AC drain — unplug ~30s — resets it.
- **KVM demands a consent code:** the node is in CCM, not ACM. Reprovision
  via MEBx (unprovision first: MEBx → Unconfigure Network Access).
- **AMT settings gone after a site power event:** deep power loss can
  revert ME network activation. Re-check `nc -zv <amt-ip> 16992` across the
  fleet after any outage; re-run §1 where needed.
- **ME firmware updates** (Lenovo, per model) fix CIRA/stability bugs —
  worth applying during MEBx rounds.
