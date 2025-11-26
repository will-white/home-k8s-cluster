# Grafana Dashboard Configuration Comparison

**Date:** 2025-11-18  
**Source Repos:**
- joryirving/home-ops: `kubernetes/apps/base/observability/kube-prometheus-stack/grafanadashboard.yaml`
- onedr0p/home-ops: `kubernetes/apps/observability/kube-prometheus-stack/app/grafanadashboard.yaml`
- Current repo: `kubernetes/apps/observability/grafana/app/helmrelease.yaml`

## Overview

The reference repositories use **separate GrafanaDashboard CRDs** managed by the Grafana Operator, while this repository uses **Helm chart dashboard provisioning** via the Grafana Helm chart's `dashboards` configuration.

### Key Architectural Difference

**Reference Repos (joryirving & onedr0p):**
- Uses `GrafanaDashboard` custom resources (CRD from grafana-operator)
- Dashboards defined as separate Kubernetes resources
- Each dashboard is a separate manifest with `kind: GrafanaDashboard`
- Uses `instanceSelector` to target Grafana instances
- Supports `allowCrossNamespaceImport: true`

**Current Repo:**
- Uses Grafana Helm chart's built-in dashboard provisioning
- Dashboards configured in `helmrelease.yaml` values under `dashboards.default`
- Managed through ConfigMaps created by the Helm chart
- Uses sidecar containers for dashboard discovery

---

## Dashboard Coverage Comparison

### Core Kubernetes Dashboards

| Dashboard | joryirving | onedr0p | Current Repo | Notes |
|-----------|------------|---------|--------------|-------|
| **kubernetes-api-server** | ✅ (rev 20) | ✅ (rev 20) | ✅ (rev 19) | Current is 1 revision behind |
| **kubernetes-coredns** | ✅ (rev 22) | ✅ (rev 22) | ✅ (rev 20) | Current is 2 revisions behind |
| **kubernetes-global** | ✅ (rev 43) | ✅ (rev 43) | ✅ (rev 43) | ✅ Up to date |
| **kubernetes-namespaces** | ✅ (rev 44) | ✅ (rev 44) | ✅ (rev 42) | Current is 2 revisions behind |
| **kubernetes-nodes** | ✅ (rev 40) | ✅ (rev 40) | ✅ (rev 34) | Current is 6 revisions behind |
| **kubernetes-pods** | ✅ (rev 37) | ✅ (rev 37) | ✅ (rev 36) | Current is 1 revision behind |
| **kubernetes-volumes** | ✅ (rev 14) | ✅ (rev 14) | ✅ (rev 14) | ✅ Up to date |

### System & Infrastructure Dashboards

| Dashboard | joryirving | onedr0p | Current Repo | Notes |
|-----------|------------|---------|--------------|-------|
| **node-exporter-full** | ✅ (rev 42) | ✅ (rev 42) | ✅ (rev 37) | Current is 5 revisions behind |
| **prometheus** | ✅ (rev 8) | ✅ (rev 8) | ✅ (rev 7) | Current is 1 revision behind |
| **etcd** | ✅ (rev 4) | ❌ | ❌ | **MISSING in current repo** |
| **kubernetes-pvc** | ✅ (rev 6) | ❌ | ❌ | **MISSING in current repo** |

### Storage Dashboards

| Dashboard | joryirving | onedr0p | Current Repo | Notes |
|-----------|------------|---------|--------------|-------|
| **ceph-cluster** | ❌ | ❌ | ✅ (rev 18) | Current has this |
| **ceph-osd** | ❌ | ❌ | ✅ (rev 9) | Current has this |
| **ceph-pools** | ❌ | ❌ | ✅ (rev 9) | Current has this |
| **garage** | ✅ | ❌ | ❌ | joryirving uses Garage S3 |
| **zfs** | ❌ | ❌ | ✅ (rev 4) | Current has this |

---

## Missing Dashboards in Current Repo

### Critical Missing Dashboards

1. **etcd Dashboard (ID: 22236, rev 4)**
   - **Source:** joryirving only
   - **Purpose:** Monitor etcd cluster health (critical for Kubernetes control plane)
   - **URL:** `https://grafana.com/api/dashboards/22236/revisions/4/download`
   - **Impact:** HIGH - No visibility into etcd performance/health

2. **kubernetes-pvc Dashboard (ID: 23233, rev 6)**
   - **Source:** joryirving only
   - **Purpose:** PersistentVolumeClaim monitoring with detailed capacity tracking
   - **URL:** `https://grafana.com/api/dashboards/23233/revisions/6/download`
   - **Impact:** MEDIUM - Limited PVC-specific insights (though kubernetes-volumes covers some)
   - **Note:** More detailed than kubernetes-volumes dashboard

---

## Configuration Differences

### Schema References

**joryirving:**
```yaml
# yaml-language-server: $schema=https://kube-schemas.pages.dev/grafana.integreatly.org/grafanadashboard_v1beta1.json
```

**onedr0p:**
```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/grafana.integreatly.org/grafanadashboard_v1beta1.json
```

**Current Repo:**
- No schema validation (uses Helm values format)

### Datasource Configuration

**Reference Repos (GrafanaDashboard CRD approach):**
```yaml
spec:
  datasources:
    - datasourceName: prometheus
      inputName: DS_PROMETHEUS
```

**Current Repo (Helm values approach):**
```yaml
dashboards:
  default:
    some-dashboard:
      datasource: Prometheus
      # OR for specific input mappings:
      datasource:
        - name: DS_PROMETHEUS
          value: Prometheus
```

### Instance Selection

**Reference Repos:**
```yaml
spec:
  instanceSelector:
    matchLabels:
      grafana.internal/instance: grafana
  allowCrossNamespaceImport: true
```

**Current Repo:**
- Not applicable (uses Helm chart's sidecar mechanism)
- Configured via `sidecar.dashboards.searchNamespace: ALL`

---

## Outdated Dashboard Revisions

### High Priority Updates

| Dashboard | Current Rev | Latest Rev | Revisions Behind |
|-----------|-------------|------------|------------------|
| **kubernetes-nodes** | 34 | 40 | 6 |
| **node-exporter-full** | 37 | 42 | 5 |

### Medium Priority Updates

| Dashboard | Current Rev | Latest Rev | Revisions Behind |
|-----------|-------------|------------|------------------|
| **kubernetes-coredns** | 20 | 22 | 2 |
| **kubernetes-namespaces** | 42 | 44 | 2 |

### Low Priority Updates

| Dashboard | Current Rev | Latest Rev | Revisions Behind |
|-----------|-------------|------------|------------------|
| **kubernetes-api-server** | 19 | 20 | 1 |
| **kubernetes-pods** | 36 | 37 | 1 |
| **prometheus** | 7 | 8 | 1 |

---

## Dashboards Unique to Current Repo

These dashboards are present in the current repo but NOT in the reference repos:

1. **apc-ups** (ID: 12340) - APC UPS monitoring via SNMP
2. **ceph-cluster** (ID: 2842) - Ceph storage cluster
3. **ceph-osd** (ID: 5336) - Ceph OSD monitoring
4. **ceph-pools** (ID: 5342) - Ceph pool monitoring
5. **cert-manager** (ID: 20842) - Certificate management
6. **cloudnative-pg** (ID: 20417) - PostgreSQL operator
7. **cloudflared** (ID: 17457) - Cloudflare tunnels
8. **external-dns** (ID: 15038) - External DNS controller
9. **external-secrets** - External Secrets operator
10. **flux-cluster** - Flux GitOps cluster view
11. **flux-control-plane** - Flux control plane
12. **home-assistant** (ID: 15309) - Home Assistant
13. **nginx** - Ingress NGINX
14. **nginx-request-handling-performance** - NGINX performance
15. **node-feature-discovery** - NFD dashboard
16. **qbittorrent** (ID: 15080) - Torrent client
17. **smartctl-exporter** (ID: 22604) - SMART disk monitoring
18. **unifi-insights** (ID: 11315) - UniFi client insights
19. **unifi-network-sites** (ID: 11311) - UniFi network sites
20. **unifi-uap** (ID: 11314) - UniFi access points
21. **unifi-usw** (ID: 11312) - UniFi switches
22. **unpackerr** (ID: 18817) - Archive unpacker
23. **volsync** (ID: 21356) - Volume synchronization

---

## Recommendations

### 1. Add Missing Critical Dashboards

Add these two dashboards to your Grafana configuration:

```yaml
dashboards:
  default:
    # ... existing dashboards ...
    
    etcd:
      datasource: Prometheus
      # renovate: depName="etcd"
      gnetId: 22236
      revision: 4
    
    kubernetes-pvc:
      datasource:
        - name: DS_PROMETHEUS
          value: Prometheus
      # renovate: depName="Kubernetes / Persistent Volumes"
      gnetId: 23233
      revision: 6
```

### 2. Update Outdated Dashboard Revisions

Priority order:
1. **kubernetes-nodes**: 34 → 40 (6 revisions)
2. **node-exporter-full**: 37 → 42 (5 revisions)
3. **kubernetes-coredns**: 20 → 22 (2 revisions)
4. **kubernetes-namespaces**: 42 → 44 (2 revisions)
5. **kubernetes-api-server**: 19 → 20 (1 revision)
6. **kubernetes-pods**: 36 → 37 (1 revision)
7. **prometheus**: 7 → 8 (1 revision)

### 3. Consider Architecture Migration

**Current State:**
- ✅ Good: Helm-based provisioning is simple and works well
- ✅ Good: All dashboards centrally managed in one place
- ❌ Con: Requires Helm upgrade to update dashboards
- ❌ Con: No namespace-level dashboard management

**Alternative (GrafanaDashboard CRD):**
- ✅ Pro: Dashboards can be co-located with applications
- ✅ Pro: GitOps-friendly (can be in app namespaces)
- ✅ Pro: Cross-namespace dashboard sharing
- ❌ Con: Requires grafana-operator installation
- ❌ Con: More complex architecture

**Recommendation:** Keep current Helm-based approach unless you need:
- Per-namespace dashboard management
- Application teams managing their own dashboards
- Dynamic dashboard discovery across namespaces

### 4. Enable Renovate for Dashboard Updates ✅ COMPLETED

The current repo already has renovate comments (e.g., `# renovate: depName="..."`), which is excellent.

**Status:** Renovate configuration has been updated with Grafana dashboard tracking:
- ✅ Custom regex manager added to `.github/renovate.json5`
- ✅ Configured to track `gnetId` and `revision` fields
- ✅ Uses `grafana-dashboards` datasource
- ✅ Will automatically create PRs for dashboard updates on weekend schedule
- ⚠️ Dashboards using GitHub URLs (external-secrets, flux, nginx, node-feature-discovery) are intentionally NOT tracked as they pull from main/master branches of stable projects

---

## Summary

### What's Good ✅
- Current repo has **significantly more dashboards** (32 vs 10-12 in reference repos)
- Good coverage of application-specific dashboards
- Renovate annotations present for automated updates
- Covers Ceph, UniFi, media apps, etc.

### What Needs Attention ⚠️
- **Missing etcd dashboard** - Important for control plane monitoring
- **Missing kubernetes-pvc dashboard** - More detailed PVC monitoring
- **7 dashboards are outdated** - ranging from 1-6 revisions behind
- **kubernetes-nodes** is most outdated (6 revisions behind)

### Migration Complexity
- **LOW** - Adding missing dashboards is straightforward
- **LOW** - Updating revisions is a simple version bump
- **HIGH** - Migrating to GrafanaDashboard CRD would require architectural changes

---

## Next Steps

1. **Immediate:** Add etcd and kubernetes-pvc dashboards
2. **Short-term:** Update the 7 outdated dashboard revisions
3. **Long-term:** Monitor reference repos for new dashboards
4. **Optional:** Evaluate GrafanaDashboard CRD migration if needed

---

## References

- **joryirving/home-ops:** Uses GrafanaDashboard CRDs with 12 dashboards
- **onedr0p/home-ops:** Uses GrafanaDashboard CRDs with 10 dashboards  
- **Current repo:** Uses Helm chart provisioning with 32 dashboards
- **Schema validator:** `kube-schemas.pages.dev` or `kubernetes-schemas.pages.dev`
- **Grafana.com:** Dashboard repository with version tracking
