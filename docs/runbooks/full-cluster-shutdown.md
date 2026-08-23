# Cluster shutdown, node loss & bring-up

Three scenarios, one recovery path:

| Scenario | Start here |
| --- | --- |
| All 8 nodes off for maintenance | [Shutdown](#shutdown) |
| Some nodes off deliberately | [Partial shutdown](#partial-shutdown-a-subset-of-nodes) |
| A node died on its own | [When a node goes down on its own](#when-a-node-goes-down-on-its-own) |

The bring-up and the aftershock cleanup are the same in all three.

Written after the 2026-08-08/09 maintenance shutdown (OSD drive replacement in
`mj0581m7`), which was the first full power-off in a long time and surfaced
several latent problems, and extended after taking `mj04968e`/`mj05g4ub` down on
2026-08-22. Everything below is what actually happened, not theory.

**TL;DR:** `task talos:cluster-down`, do the hardware work, power on, then
`task talos:cluster-up`. Read the gotchas before you start.

Taking only *some* nodes down is a materially different procedure, with a
real availability cost the full shutdown does not have — see
[Partial shutdown](#partial-shutdown-a-subset-of-nodes).

---

## Shutdown

`task talos:cluster-down` does all of this; the reasoning is here so you can
deviate safely.

1. **Suspend Flux** (`flux suspend kustomization --all`). Record what was already
   suspended first — resuming blindly would enable something you had parked:
   ```bash
   kubectl -n flux-system get kustomizations -o json \
     | jq -r '.items[] | select(.spec.suspend==true) | .metadata.name'
   ```
2. **Set Ceph flags:** `noout norebalance nobackfill norecover`.

   **Do NOT set `nodown`.** It seems right (stop the churn while nodes drop) and
   it is a trap. If any node fails to come back, Ceph keeps its OSDs marked `up`,
   so PGs try to peer with daemons that will never answer and *all* client I/O
   blocks indefinitely. On 2026-08-09 this left 258 PGs inactive and 75 ops
   blocked for ~26 minutes, and had to be undone under pressure. `noout` alone
   already prevents rebalancing.
3. **Check nothing is mid-flight — and nothing is about to start.** Volsync
   replications and running Jobs, but also the *next* tick of anything on a
   schedule. Volsync's default trigger is hourly (`0 * * * *`), so powering off
   at :55 walks straight into it. On 2026-08-22 that stranded five mover pods,
   some retrying against a CSI socket that no longer existed for 100+ minutes.
   Either time the window away from the hour boundary or suspend the sources.
4. **Power off with `--force`**, workers first, then control planes.

   `--force` skips the Kubernetes cordon/drain. That is *correct* here: draining
   evacuates pods onto other nodes, but every node is going down, and the PDBs
   (`postgres16-primary` and `emqx-core` allow **0** disruptions, `rook-ceph-osd`
   allows 1) would deadlock the drain for its full 30-minute timeout. `--force`
   only skips the k8s drain — Talos still stops containers and unmounts cleanly.

### Expect slow shutdowns

Nodes holding kernel CephFS/RBD mounts take **~12 minutes** to power off. Once
the cluster is unreachable, `libceph` retries forever and the Talos sequencer
blocks on unmount until it times out:

```
libceph: osd4 (2)192.168.5.50:6800 socket error on write   # repeats for minutes
```

`mj05ajfj` looked permanently wedged and was not — it powered off on its own.
**Do not hit the power button.** Re-issuing `talosctl shutdown` does not help
either; the sequencer is already past the point where the API can influence it.

---

## Bring-up

Power on **control planes first**, wait for etcd quorum, then workers. Then
`task talos:cluster-up`, which handles the two steps below in order.

### Gotcha 1: the `out-of-service` taint (highest time cost)

Nodes that were down get:

```
node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
```

**Kubernetes never removes this — an admin must.** It is deeply misleading: the
node reports `Ready`, kubelet is healthy, all Talos services are `OK`, and yet
no pod can schedule there. `mj05ajfj` looked perfect at every layer while its
OSD sat `Pending`. Nodes that never went down (`mj0581m7`) do not get it, so
the cluster looks inconsistent for no visible reason.

```bash
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name) \([.spec.taints[]?.key]|join(","))"'
kubectl taint node <node> node.kubernetes.io/out-of-service-
```

Check this **before** debugging anything else about a node that "looks fine but
runs nothing".

### Gotcha 2: NTP gates the boot

Talos blocks its boot sequence on time sync, *before* `apid` starts. A node that
cannot reach an NTP server hangs with **no API to connect to** — there is no
remote fix, because the API you would use to change the config is what is gated.
Symptom on console (`Alt+F1` shows the boot log; the dashboard is on TTY2):

```
time query error with server "162.159.200.1"
```

`patches/global/ntp.yaml` now lists the LAN gateway (`192.168.5.1`) first so a
WAN outage cannot prevent booting. If you see this anyway, it is a link problem
on that node — the address is static, so it is cable/switch/port, not DHCP.

### Order matters at the end

1. All nodes `Ready`, taints cleared, uncordoned
2. Ceph **peers** — wait until `ceph status` reports no inactive PGs
3. **Then** unset the flags (`norecover nobackfill norebalance noout`)
4. Watch it settle to `HEALTH_OK` / all PGs `active+clean`
5. **Then** resume Flux

Step 2 is the one that reads wrong until you have done it once. Do *not* wait
for `active+clean` before unsetting the flags: `norecover` and `nobackfill` are
precisely what stops PGs reaching it, so that wait never finishes. Peering only
needs the OSDs back and talking to each other; **recovery is what the flags are
holding back**. Wait for the inactive count to reach zero, unset, then watch the
degraded percentage fall:

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status | grep -E "osd:|inactive|degraded"
```

On 2026-08-22 the OSDs peered about a minute after the nodes came back, and
unsetting the flags took the cluster from 23% degraded to `active+clean` in
under five minutes — because `noout` had kept the returning OSDs' data valid,
so this was recovery of the write delta, not a full backfill.

Resuming Flux earlier makes 96 reconciling apps compete with Ceph recovery for
the same disks — especially bad if a fresh OSD is backfilling.

---

## Partial shutdown (a subset of nodes)

Taking a *few* nodes down is not a smaller version of the above. The cluster
stays up, so drains, PDBs and Ceph `min_size` all matter in ways they do not
when everything goes down together. Written from taking `mj04968e` (`.53`) and
`mj05g4ub` (`.54`) down on 2026-08-22.

### Know the Ceph cost before you start

Every pool is `size 3 / min_size 2` with failure domain `host`, and there is
exactly **one OSD per host** across 8 hosts. Any PG mapped to two downed hosts
drops to a single replica — below `min_size` — and **blocks client I/O** until
one of them returns. About 6 of the 56 possible host-triples contain any given
pair, so expect roughly 10% of PGs affected.

Measured with two hosts down: **19 PGs inactive (7.2%)**, 3 erasure-coded PGs
`down` in `ceph-objectstore.rgw.buckets.data`, 23% of objects degraded, the MDS
reporting slow metadata IOs, and RGW down from 2 daemons to 1. Everything else
kept serving, including all 3 mons, both mgrs, all 3 EMQX cores and both
ingress-nginx controllers.

**One host down is free** — every PG keeps at least 2 replicas. Two is the
threshold where availability starts costing you. If the nodes will be gone for
longer than a maintenance window, reweight their OSDs out of the CRUSH map and
let backfill finish *first*; then nothing is degraded while they are away.

### Procedure

1. **Move any CNPG primary off the doomed nodes first**, or you take an
   unplanned failover instead of a clean switchover. There is no `cnpg` kubectl
   plugin installed here, so patch exactly what the plugin's `promote` patches:
   ```bash
   kubectl -n database patch cluster postgres16 --subresource=status \
     --type=merge -p '{"status":{"targetPrimary":"postgres16-4"}}'
   ```
   Replication is async (`minSyncReplicas: 0`), so even a lone surviving
   instance still accepts writes — there is no synchronous-quorum stall to
   plan around.
2. **Set the Ceph flags** exactly as for a full shutdown: `noout norebalance
   nobackfill norecover`. The `nodown` warning above applies unchanged.
3. **Cordon** the nodes, so pods evicted off them are not scheduled straight
   back onto a node that is about to disappear.
4. **`talosctl -n <ips> shutdown --force --wait=false`.** `--force` is still
   required, but for a different reason than the full shutdown: `rook-ceph-osd`
   and `emqx-core` sit at `maxUnavailable: 1` and `postgres16-primary` at 0, so
   draining *two* nodes deadlocks on those PDBs for the full 30-minute timeout.

Do **not** suspend Flux for a partial shutdown. The cluster keeps serving and
rescheduling is ordinary behaviour; suspending every Kustomization is a much
larger blast radius than the thing you are protecting against.

### Partial bring-up

`task talos:cluster-up` is whole-cluster — it waits on *all* nodes being Ready
— so for a partial return run the steps by hand:

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
  bash -c 'for f in norecover nobackfill norebalance noout; do ceph osd unset $f; done'
kubectl uncordon <nodes>
kubectl taint node <node> node.kubernetes.io/out-of-service-   # only if applied
```

Wait for the nodes to be `Ready` and for Ceph to settle **before** unsetting the
flags, for the reason in "Order matters at the end" above. CNPG rebuilds the
missing replicas on its own, and there is no need to switch the primary back.

`node-fencer` in `kube-system` only applies the `out-of-service` taint after
`UNREACHABLE_THRESHOLD_SECONDS` (3600), so a sub-hour window never trips it.
Check rather than assume — Gotcha 1 covers why a missed taint is so expensive.

### Aftershock: RBD volumes remount read-only

The blocked-I/O window leaves some RBD volumes remounted **read-only**, and the
kernel does not undo it when Ceph recovers. The pods stay up and keep failing,
so this outlives the outage and is easy to misread as an application bug.
Affected pods sit on nodes that **never went down** — the read-only remount
follows the blocked PGs, not the missing nodes.

Seen on 2026-08-22, all three needing nothing more than a pod delete:

| Pod | Symptom in logs |
| --- | --- |
| `prometheus-kube-prometheus-stack-0` | `open /prometheus/queries.active: read-only file system` |
| `frigate` | `attempt to write a readonly database`, `Config file is read-only` |
| `zigbee2mqtt` | `ENOENT ... mkdir '/config/log/<timestamp>'` |

The zigbee2mqtt one is the misleading case: `ENOENT` rather than `EROFS` reads
like data loss. Verify before assuming — scale the deployment to 0, mount the
PVC in a throwaway pod and check. On 2026-08-22 the volume was completely
intact (`configuration.yaml`, `database.db`, `state.json` all present, and
`/config/log` existed and was writable); scaling back up was the entire fix.

Sweep for these after the PGs go `active+clean`:

```bash
kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed"'
```

Volsync movers also strand themselves — jobs scheduled during the outage retry
forever against a CSI socket that has gone (`csi.sock: connect: connection
refused`) or lose their snapshot PVC entirely. Delete the stuck mover pods and
let the next scheduled sync recreate them. One caveat: a CephFS clone reporting
`rpc error: code = Aborted desc = clone from snapshot is already in progress` is
**succeeding, not failing** — the message carries a percentage that climbs.
Leave it alone; `max_concurrent_clones` is 4 and a backlog drains on its own.

A stuck `mon.m has slow ops` on a `log(...)` entry from the outage window is
cosmetic — it is a cluster-log message, not client I/O — but it holds
`HEALTH_WARN` until the mon is restarted.


## When a node goes down on its own

Everything above assumes you chose the moment. An unplanned loss is the same
event with the preparation removed, so the recovery is identical — but the first
few minutes differ, and ["Know the Ceph cost"](#know-the-ceph-cost-before-you-start)
is the part that matters most. **Two hosts lost at once is a partial storage
outage whether or not you planned it**, and the arithmetic does not care that
nobody chose it.

### What you have already lost

You do not get the switchover or the flags. Anything primary on that node has
already failed over on its own — CNPG handles this, though replication is async
(`minSyncReplicas: 0`), so a small window of un-replicated writes can be lost.
That is the price of not choosing the moment, and it is why the planned
procedure does the switchover first.

If the node took Prometheus or Alertmanager with it, the `Watchdog` heartbeat
stops and the external healthcheck pages. **Read that page correctly**: it means
monitoring is gone, not that the cluster is fine. Expect to be flying without
metrics for the duration — see the aftershock section, because Prometheus is
also one of the things that comes back read-only.

### First moves

1. **Confirm the blast radius before touching anything.** One host down leaves
   every PG at 2 or more replicas and is not urgent. Two is:
   ```bash
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
   ```
   The number that matters is `pgs inactive` — that is blocked client I/O, and
   it decides how hard you push on everything else.

2. **Decide `noout`, and get it right.** This is the one real fork:

   - **Back within the hour** (reboot, brief power cut) → set `noout`. It stops
     Ceph re-replicating data you are about to get back for free.
   - **Genuinely dead** (failed disk, dead board) → leave `noout` off and let
     Ceph heal onto the surviving hosts. Setting it here just prolongs the
     degraded window for no benefit.

   `noout` is right for a reboot and wrong for a funeral. The `nodown` warning
   in [Shutdown](#shutdown) applies unchanged and is worse here — a node that is
   never coming back is exactly the case that wedges all client I/O.

3. **Do not wait out the fencing timeout if the node is dead.** `node-fencer`
   applies the `out-of-service` taint only after
   `UNREACHABLE_THRESHOLD_SECONDS` (3600), which is a long time to leave RWO
   PVCs stranded on a corpse. That taint is what force-detaches
   VolumeAttachments so RBD volumes can reattach on a live node, so apply it by
   hand:
   ```bash
   kubectl taint node <node> node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
   ```
   Only do this once you are certain the kubelet is really gone, not merely
   unreachable — the taint evicts every pod on the node. And remove it when the
   node returns; see [Gotcha 1](#gotcha-1-the-out-of-service-taint-highest-time-cost).

### Then treat it as a bring-up

Once the node is back, follow [Partial bring-up](#partial-bring-up): clear the
taint, uncordon, wait for peering, unset whatever flags you set, and **sweep for
the read-only RBD aftershock**. That last step is not optional and it bites
hardest here — nobody scheduled the outage, so nobody is watching for the pods
that come back running-but-broken.

---

## Latent failures a full restart exposes

Things that are broken but invisible while pods keep running. Budget time for
finding at least one of these.

- **Readiness gates.** EMQX had been broken since a Renovate bump on 2026-07-25
  but nothing showed it: the `apps.emqx.io/on-serving` gate persists on running
  pods and is only re-granted when pods are recreated. After the restart, the
  operator could not grant it, so `emqx-listeners` had **zero ready endpoints**
  and every MQTT client got `ECONNREFUSED` — against a healthy 3-node broker.
  Pods showed `1/1 Running`; only `kubectl get endpointslices` revealed it.
  There are now alerts for this (`prometheusrules/service-endpoints.yaml`).
- **CRD `storedVersions` drift.** Four CRDs (`emqxes`, plus `imagepolicies`,
  `imagerepositories`, `imageupdateautomations`) had stored versions no longer in
  the incoming chart's `spec.versions`, so the apply was rejected. This had
  stopped Flux managing its own components. Detect with:
  ```bash
  kubectl get crd -o json | jq -r '.items[] | . as $c
    | (($c.status.storedVersions // []) - ($c.spec.versions|map(.name))) as $orphan
    | select($orphan|length>0) | "\($c.metadata.name): \($orphan|join(","))"'
  ```
  Fix, once you have confirmed nothing is stored in the dead version (check the
  object count!), is to narrow it — back up the CRD first:
  ```bash
  kubectl patch crd <name> --subresource=status --type=merge \
    -p '{"status":{"storedVersions":["<keep>"]}}'
  ```
  If a live object *is* stored in the dying version, you must first make the
  surviving version the storage version, rewrite every object (any no-op update
  works), and only then narrow `storedVersions`.
- **Comment-only version pins.** A `# DO NOT bump` comment does not stop
  Renovate. `emqx-operator` was re-bumped past a previous revert this way. Pins
  need a real `packageRule` with `allowedVersions` in `.github/renovate.json5`.
- **Scheduling skew.** Pods pile onto whichever nodes stayed up and never move
  back — `mj04ew44` held 70 pods while `mj0581m7` held 16. Anything on
  `openebs-hostpath` is pinned to one node and simply cannot schedule if that
  node is full (`postgres16-4` blocked 9 Kustomizations this way). The
  descheduler now runs `LowNodeUtilization` to correct this automatically.
- **External dependencies.** `dahua-companion` crashlooped on
  `no route to host 192.168.5.163` — the doorbell had not come back yet. Not a
  cluster fault; check the devices too.
