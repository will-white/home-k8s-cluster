# etcd maintenance & alert triage

Talos runs etcd as a host-level service, **not** as a pod in `kube-system`.
`kubectl -n kube-system get pods -l component=etcd` returns nothing — that is
normal, not a fault. Everything here goes through `talosctl`.

Metrics come from `listen-metrics-urls: http://0.0.0.0:2381`
(`kubernetes/bootstrap/talos/patches/controller/etcd.yaml`), scraped per
control-plane IP, so alert `instance` labels look like `192.168.5.40:2381`.

Control plane: `mj0583jp` = .40, `mj0581m7` = .41, `mj0583eq` = .42.

Written after the 2026-08-24 triage of flapping etcd alerts, which turned out to
be two unrelated problems wearing one costume. Numbers below are what actually
happened.

---

## First: which alert is actually flapping?

Alertmanager notifications collapse detail. Get the real state from Prometheus:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 19090:9090 &
curl -s 'http://localhost:19090/api/v1/rules?type=alert' \
  | jq -r '.data.groups[] | select(.name|test("etcd";"i")) | .rules[]
           | "\(.state)\t\(.name)\tfor=\(.duration)s"'
```

Firing history over the last week — this is what separates "new" from
"always been like that":

```bash
curl -s --data-urlencode 'query=count_over_time(ALERTS{alertname=~"etcd.*",alertstate="firing"}[1h])' \
     --data-urlencode "start=$(($(date -u +%s)-604800))" \
     --data-urlencode "end=$(date -u +%s)" --data-urlencode 'step=3600' \
     http://localhost:19090/api/v1/query_range | jq .
```

Two alerts flapping at once usually means two *independent* causes. Do not
assume one explains the other.

### Thresholds worth memorising

| Alert | Fires when | `for` |
| --- | --- | --- |
| `etcdMemberCommunicationSlow` | peer RTT p99 > **150 ms** | 10m |
| `etcdHighFsyncDurations` | WAL fsync p99 > **500 ms** (crit > 1 s) | 10m |
| `etcdHighCommitDurations` | backend commit p99 > **250 ms** | 10m |
| `etcdHighNumberOfLeaderChanges` | ≥ **4** changes in 15m | 5m |
| `etcdDatabaseHighFragmentationRatio` | in-use/total < **50%** AND in-use > **100 MiB** | 10m |
| `etcdNoLeader` | `etcd_server_has_leader == 0` | 1m |

Healthy baseline on this cluster: fsync p99 ~4 ms, commit p99 ~6–25 ms,
peer RTT p99 ~13 ms.

**Do not clear the disk on a healthy p99.** At ~67 writes/s a multi-second
stall a few times an hour never reaches the 99th percentile — p99 stays at
4 ms while etcd is losing leadership. Always check the tail as well:

```bash
# p999 over the last hour, and the worst bucket reached in 24h
curl -s --data-urlencode 'query=histogram_quantile(0.999, rate(etcd_disk_wal_fsync_duration_seconds_bucket[1h]))' \
     http://localhost:19090/api/v1/query | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"'
curl -s --data-urlencode 'query=max_over_time(histogram_quantile(1.0, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))[24h:5m])' \
     http://localhost:19090/api/v1/query | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"'
```

etcd names the stalls outright — this is the fastest check of all:

```bash
talosctl -n <node> logs etcd | grep -E "slow fdatasync|took too long"
```

---

## Defragmentation

etcd never returns free pages to the filesystem. After enough compaction
cycles the file is mostly holes: on 2026-08-24 all three members held 105 MB
of live data in a 371 MB file (28%).

### The flapping trap

`etcdDatabaseHighFragmentationRatio` needs in-use > 100 MiB *and* ratio < 50%.
When in-use sits right at ~105 MB it crosses the 100 MiB arm repeatedly, so the
alert fires and resolves every few minutes even though fragmentation is
constantly bad. **Flapping here means "genuinely fragmented and sitting on the
threshold", not "transient".** Defrag fixes both.

### Procedure

Defrag blocks the member while it runs — it is a stop-the-world operation on
that node's backend. Quorum covers you as long as you do **one node at a time**.

1. Confirm health first. All members must show the same `RAFT INDEX` and
   `RAFT TERM`, and `etcd alarm list` must be empty:

   ```bash
   export TALOSCONFIG=./talosconfig
   talosctl -n 192.168.5.40,192.168.5.41,192.168.5.42 etcd status
   talosctl -n 192.168.5.40 etcd alarm list
   ```

   Note which member ID is `LEADER`. Do **not** proceed if a member is behind,
   an alarm is set, or a node is down — defrag needs a healthy quorum to hide
   behind.

2. **Followers first, leader last**, verifying between each:

   ```bash
   talosctl -n <follower-1> etcd defrag
   talosctl -n 192.168.5.40,192.168.5.41,192.168.5.42 etcd status   # verify
   talosctl -n <follower-2> etcd defrag
   talosctl -n 192.168.5.40,192.168.5.41,192.168.5.42 etcd status   # verify
   talosctl -n <leader>     etcd defrag
   ```

3. Verify the ratio is 1.000 and nothing elected:

   ```bash
   talosctl -n 192.168.5.40 etcd alarm list      # must be empty
   kubectl get --raw='/readyz'                   # must be ok
   ```

   `RAFT TERM` should be **unchanged** from step 1. A bumped term means the
   defrag stalled the leader long enough to trigger an election.

### What it actually cost (2026-08-24)

| Node | Before | After | Wall time |
| --- | --- | --- | --- |
| .41 (follower) | 369 MB / 28.2% | 104 MB / 100% | 2.0 s |
| .42 (follower) | 366 MB / 28.6% | 104 MB / 100% | 1.2 s |
| .40 (leader) | 371 MB / 28.1% | 105 MB / 100% | 2.4 s |

~266 MB reclaimed per node, ~798 MB total. Raft term stayed at 11816 — no
election, no blip, `/readyz` never went unready. At this DB size defragging the
leader is safe; if the DB ever reaches multiple GB, move leadership off first
with `talosctl -n <leader> etcd forfeit-leadership`.

There is **no automatic defrag** in this cluster. `talos-backup`
(`kubernetes/apps/system-upgrade/talos-backup/`) takes snapshots every 6h; it
does not defrag. Re-check the ratio a few times a year.

---

## Is it the network or the disk?

Both present as etcd latency and leader churn. The counters distinguish them
cleanly — this is the part worth remembering.

### Network

```bash
# per-interface rx errors, all nodes
curl -s --data-urlencode 'query=rate(node_network_receive_errs_total{device!="lo"}[10m]) > 0' \
     http://localhost:19090/api/v1/query | jq -r '.data.result[] |
     "\(.metric.instance) \(.metric.device) \(.value[1])"'
```

Then break the errors down by **type** — this is the diagnostic:

| Counter | Meaning if non-zero |
| --- | --- |
| `receive_frame` | CRC/alignment — corrupted bits on the wire → **cable, port, connector** |
| `receive_fifo` | ring-buffer overrun — **host** too slow to drain, not the cable |
| `receive_drop` | no buffer / filtered; small steady values are normal |
| `transmit_errs` | local NIC or driver fault |

**Frame errors with zero FIFO errors = physical layer.** That was the
2026-08-24 finding: `mj0583eq` (.42) `eno1` showed 6.8 rx errs/s and 3.4
frame errs/s with FIFO flat at 0, while .40 and .41 sat at exactly 0 errors
lifetime. 0.59% of received packets corrupted → TCP retransmits → peer RTT p99
to that member hit 93 ms against 13 ms between the healthy pair → flapping
`etcdMemberCommunicationSlow`.

Pin down *when* it started — the Talos link resource records it:

```bash
talosctl -n <node> get links eno1 -o yaml   # 'updated:' timestamp + driver/speed/duplex
```

A `LinkStatus` `updated:` timestamp that lines up with the first errors is a
link event, i.e. hardware. Fix order: reseat cable → replace cable → different
switch port → suspect the NIC.

Also check `bond0` is not silently down; on these nodes `eno1` is often the
sole uplink, so a degraded link has no redundancy.

### Disk

```bash
talosctl -n <nodes> etcd status     # DB size, in-use, raft index/term, ERRORS column
```

Plus fsync/commit p99 **and the tail** — see the warning under the threshold
table. A clean p99 does not clear the disk; grep the etcd log for
`slow fdatasync` before concluding anything.

Rising fsync **during** leader churn is usually an *effect*, not a cause: more
elections mean more raft writes. On 2026-08-24 .40's fsync p99 rose from a flat
4 ms baseline to 15.6 ms as elections spiked — still 32× below the 500 ms
alert threshold, and it settled once the churn eased.

---

## SMART: the `num_err_log_entries` red herring

`smartctl_device_num_err_log_entries` on the Kingston SNV2S250G in `.40` reads
**3.37 million** while the other two control-plane drives read 0. It looks like
a dying disk. It is not.

It increments by **exactly 240 per hour** — one per 15 seconds, which is the
smartctl-exporter scrape interval. Each poll issues a log-page command the
drive rejects, and the rejection is recorded. Real hardware faults are bursty
and irregular; a perfect metronome is a polling artifact. The WD Blue SN5000
and Kingston SNV3S1000G in the other two nodes simply do not log these.

**Judge NVMe health on these instead:**

```bash
for m in smartctl_device_smart_status smartctl_device_media_errors \
         smartctl_device_critical_warning smartctl_device_available_spare \
         smartctl_device_percentage_used smartctl_device_temperature; do
  echo "== $m"
  curl -s --data-urlencode "query=$m" http://localhost:19090/api/v1/query \
    | jq -r '.data.result[] | "  \(.metric.instance) \(.metric.device) \(.value[1])"'
done
```

- `smart_status` 1 = PASS
- `media_errors` > 0 = real uncorrectable errors — **this** is the failing-drive signal
- `critical_warning` > 0 = drive is telling you it is in trouble
- `available_spare` dropping toward its threshold = wear-out
- `percentage_used` ≥ 100 = past rated endurance

smartctl-exporter reports by **pod IP**, not node. Map it:

```bash
kubectl -n observability get pods -o wide | grep smartctl
```

### Open item: .40's NVMe stalls and runs hot

`mj0583jp`'s NVMe (Kingston SNV2S250G — DRAM-less QLC, 250 GB) sits at a
sustained **72–76°C** versus 52°C and 60°C on the other two, and it is the
dominant source of etcd leader elections on this cluster.

Measured 2026-08-25, `slow fdatasync` lines in the etcd log over the same period:

| Node | Drive | Temp | Stalls (max) |
| --- | --- | --- | --- |
| .40 | Kingston SNV2S250G | 72–75°C | **12 (3.21 s)** |
| .41 | Kingston SNV3S1000G | 52–56°C | 2 (2.82 s) |
| .42 | WD Blue SN5000 1TB | 60–61°C | **0** |

Stall count tracks drive quality and temperature exactly. SMART is clean on all
three (0 media errors, 0 critical warnings, spare 100%) — this is *not* a dying
drive, it is the wrong drive for an fsync-latency-sensitive workload. A raft
heartbeat cannot be served during a 3-second fdatasync, so the member loses
leadership and the cluster re-elects.

Since 2026-08-23 20:15 this has produced a steady ~2 real elections/hour
(≈7/hour on the per-member metric, which triple-counts). It stays below the
`etcdHighNumberOfLeaderChanges` threshold of 4-in-15m, so **nothing alerts on
it** — it only shows up as raft term climbing.

Fix: replace with a DRAM-backed TLC drive (the WD Blue SN5000 in .42 has zero
stalls and is the reference), and address M900 NVMe airflow —
see [m900-bios-energy.md](./m900-bios-energy.md).
