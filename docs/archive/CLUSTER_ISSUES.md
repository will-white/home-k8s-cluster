# Cluster Issues — Backlog

Pre-existing issues surfaced during post-deploy monitoring on **2026-04-28**
(after commit `a556fb4`). None are caused by the recent best-practices
baseline work; they need separate triage.

---

## 1. Intermittent `bitwarden-sdk-server` timeouts

**Symptom**
ExternalSecret / PushSecret reconciles across multiple namespaces fail with:

```
failed to do request: Get "https://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998/rest/api/1/secret":
context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

**Observed in**
- `rook-ceph/pushsecret/cloudnative-pg-push` (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
- `media/externalsecret/radarr`
- `default/externalsecret/paperless-volsync`

**Hypothesis**
Single-replica `bitwarden-sdk-server` pod is overloaded or hitting upstream
Bitwarden API rate limits / latency spikes. Self-recovers on retry.

**Investigation**
- `kubectl -n external-secrets get pods,deploy -l app.kubernetes.io/name=bitwarden-sdk-server`
- Logs + resource usage on the pod over 24h
- Consider scaling to 2 replicas, raising client timeout in ESO `ClusterSecretStore`,
  or adding caching.

**Severity:** medium (no data loss, but blocks reconciles)

---

## 2. Kubernetes v1.36.0 system-upgrade job failed permanently

**Symptom**
```
default 4m28s Warning UpgradeFailed kubernetesupgrade/kubernetes
Kubernetes upgrade to v1.36.0 failed: Kubernetes upgrade job failed permanently
```

**Current state**
Cluster is on v1.35.1 (Talos v1.12.1). Upgrade plan is stuck.

**Investigation**
- `kubectl get plan -A -o yaml` (system-upgrade-controller)
- `kubectl -n system-upgrade logs -l upgrade.cattle.io/plan=kubernetes --tail=200`
- Check Talos compatibility matrix — Talos v1.12 may not yet support k8s 1.36;
  may need Talos upgrade first, or pin the plan back to 1.35.x until ready.

**Severity:** medium (cluster is healthy on 1.35.1, but upgrade pipeline is broken)

---

## 3. EMQX operator reconcile hitting 404

**Symptom**
```
database 12m Warning ReconcilerFailed emqx/emqx
reconcile failed at step updateStatus, reason: failed to get node evacuation status:
error accessing emqx-core-866689f45-0 API
http://10.69.1.61:18083/api/v5/load_rebalance/global_status: HTTP 404
{"code": "NOT_FOUND", "message": "Request Path Not Found"}
```

**Hypothesis**
Operator/chart version drift — operator expects a load-rebalance API path
that the running EMQX broker version doesn't expose. Likely benign (status
update only) but pollutes events and may block rolling updates.

**Investigation**
- `kubectl -n database get emqx emqx -o yaml | yq .spec.image`
- Cross-reference EMQX operator version vs broker image tag
- Either bump operator to match broker, or pin broker to a version with the
  rebalance API.

**Severity:** low (status-only failure; messaging plane works)

---

## 4. Stuck PV detach on node `mj05ajfj`

**Symptom**
Repeated `VolumeFailedDelete` events in `default` namespace:
```
persistentvolume pvc-XXXXXX is still attached to node mj05ajfj
```
Multiple PVs affected over the last hour (pvc-48de7514, pvc-366c2cfb,
pvc-0f5d2467, pvc-59e7bd50, pvc-c4d3a3ce, pvc-01819599).

**Hypothesis**
CSI detach hung on that node — could be Ceph RBD watcher leak, Talos kubelet
issue, or pods stuck terminating.

**Investigation**
- `kubectl get pods -A -o wide --field-selector spec.nodeName=mj05ajfj | grep -v Running`
- `kubectl describe node mj05ajfj`
- `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- rbd status <pool>/<image>` for one of the stuck PVs
- Check `csi-rbdplugin` pod logs on that node
- Likely fix: cordon + drain + reboot the node (Talos: `talosctl reboot --nodes <ip>`)

**Severity:** medium (storage plane risk; can stall future pod scheduling)

---

## 5. Alertmanager dispatcher excessive retries on `CephNodeNetworkPacketDrops`

**Symptom**
```
level=ERROR component=dispatcher
fingerprint=2f2fdf41721684bc
route="{}/{severity=~\"critical|warning\"}"
alert=CephNodeNetworkPacketDrops retries=101
msg="excessive retries creating aggregation group"
```

**Hypothesis**
Old alertmanager state from before the receiver rewire — the alert was firing
into the (then) null receiver and the dispatcher couldn't form an aggregation
group. Should resolve once the new Pushover receiver is fully wired (after
issue #6 below).

**Followup**
Re-check after `alertmanager` Bitwarden item is created and ES populates.
If still firing after 24h with the new config, investigate the underlying
Ceph alert (network packet drops are real and worth fixing — likely the
NIC on a Ceph node, possibly related to issue #4).

**Severity:** low (noise) → could indicate real Ceph network issue (medium)

---

## 6. (Action required) Create `alertmanager` item in Bitwarden Secrets Manager

**Status**
`externalsecret/alertmanager` in `observability` is failing:
```
no secret found for project id 72d238f3-0dde-4bde-b98e-b17500919b9e
and name alertmanager
```

**Required keys**
- `ALERTMANAGER_PUSHOVER_TOKEN`
- `ALERTMANAGER_PUSHOVER_USER_KEY`
- `ALERTMANAGER_HEARTBEAT_URL` (healthchecks.io / OpsGenie heartbeat ping URL)

**Until done**
Alertmanager runs but mounted secret files are empty → notifications won't
deliver and the heartbeat receiver is silent.

**Severity:** high (blocks alert delivery)
