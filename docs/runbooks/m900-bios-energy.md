# M900 BIOS energy pass — per-node firmware tuning

Firmware-level power tuning for the 8× ThinkCentre M900 Tiny nodes. Do this
in the **same console visit** as AMT provisioning
([intel-amt-vpro.md](./intel-amt-vpro.md)) — order matters, see below.
Expected gain is modest but permanent: roughly 1–3 W per node (8–24 W fleet)
depending on how much was left enabled from the office-desktop defaults.
Verify with wall watts (NUT exporter) rather than trusting the checklist —
measured before/after is the only truth here.

Menu names below are approximate (Lenovo FWKT-series BIOS, machine type
10FL); they drift slightly between BIOS versions.

## Order of operations per node

1. **BIOS + ME firmware update first** (Lenovo support, machine type 10FL).
   Updates fix Skylake C-state and AMT/CIRA bugs — and they can **reset
   MEBx and BIOS settings**, which is why they come before everything else.
2. This BIOS pass.
3. MEBx/AMT provisioning ([intel-amt-vpro.md §1](./intel-amt-vpro.md)).
4. Verification (below), including AMT reachability with the host off.

Do not change Secure Boot state — the Talos upgrade task reads the node's
`securitystate` and the nodes are provisioned non-secureboot.

## The checklist

| Setting | Where (approx.) | Set to | Why |
| --- | --- | --- | --- |
| After Power Loss | Power | **Power On** | Cluster self-recovers from outages (see [full-cluster-shutdown.md](./full-cluster-shutdown.md)). Confirm it — one node quietly set to "Last State"/"Off" stays down after an outage. |
| C-State Support (+ C1E) | Advanced → CPU Setup | **Enabled** | Deep idle states — the biggest single item on this list. Desktop BIOS defaults sometimes ship with these off. |
| Intel SpeedStep | Advanced → CPU Setup | Enabled | Should already be — Talos shows `intel_pstate` + HWP active. |
| Turbo Mode | Advanced → CPU Setup | Leave **Enabled** | Steady-state savings from disabling are tiny; burst latency cost is real. Turbo restraint is done OS-side via EPP instead. |
| Enhanced Power Saving Mode | Power | **OFF** | ⚠️ It powers down the ME/NIC in S5 — **breaks AMT wake and WoL**, i.e. the entire cold-spare wake plan. If you experiment with it, re-test AMT with the host powered off before trusting it. |
| Wake on LAN | Power → Automatic Power On | Enabled | Free backup wake path alongside AMT (same NIC standby power either way). |
| Audio | Devices → Audio Setup | Disabled | Headless. |
| WiFi / Bluetooth (M.2) | Devices / Network Setup | Disabled if present | Nodes are wired. Physically pulling the card at the next case-open saves another ~0.5–1 W. |
| Serial / parallel port | Devices | Disabled if present | Unused. |
| Unused SATA ports | Devices → ATA Drive Setup | Disabled | **Keep the boot SSD's port** (2.5" SATA = `/dev/sda`, the Talos install disk). NVMe (Ceph) is unaffected. |
| USB ports | Devices → USB Setup | Leave **enabled**; disable "Always On USB"/S5 charging only | Console keyboard is needed for MEBx and recovery. Nothing critical is USB-attached: the Zigbee coordinator is network-based (SLZB-06M over TCP), the Coral TPU is PCIe. |
| Fan profile | Power / Advanced | Leave default | Acoustic-vs-thermal profiles move ~0 W; not worth divergence between nodes. |

## OS-side twins (config PRs, not console work)

Two knobs belong to `talconfig.yaml` patches rather than this console pass —
listed so you don't hunt for them in BIOS (this platform's BIOS exposes
neither):

- **PCIe ASPM**: `pcie_aspm.policy=powersave` via
  `machine.install.extraKernelArgs` — takes effect on the next Talos
  upgrade/reinstall, so it should ride a planned node-upgrade cycle.
- **EPP** (`energy_performance_preference: balance_power`) via
  `machine.sysfs` — applies without reboot.

## Verify

- **Deep C-state residency** (µs counters since boot; the deepest state
  should accumulate rapidly on an idle-ish node):

  ```bash
  for s in 0 1 2 3 4; do
    echo -n "state$s: "
    talosctl -n <ip> read /sys/devices/system/cpu/cpu0/cpuidle/state$s/name 2>/dev/null
    talosctl -n <ip> read /sys/devices/system/cpu/cpu0/cpuidle/state$s/time 2>/dev/null
  done
  ```

- **Wall watts** before/after via the NUT exporter once deployed — per-node
  RAPL is not readable by the unprivileged node-exporter, so the UPS is the
  fleet-level meter.
- **AMT reachability with the host powered off** (`nc -zvw2 <amt-ip> 16992`)
  — proves the Enhanced-Power-Saving/Always-On interaction didn't regress
  the wake path.
- `After Power Loss` is easiest verified honestly: it either was already
  right, or the next outage finds the one node where it wasn't.
