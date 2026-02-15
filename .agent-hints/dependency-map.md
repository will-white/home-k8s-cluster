# Repository Dependency Map

This file helps agents understand dependencies and relationships in the cluster.

## Core Infrastructure Stack

```
┌─────────────────────────────────────────────────────────┐
│                    Talos Linux OS                        │
│              (kubernetes/bootstrap/talos/)               │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Flux GitOps System                          │
│           (kubernetes/flux-system/)                      │
│    - GitRepository, HelmRepository configs               │
│    - Cluster-wide Kustomizations                        │
└─────────────────────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌─────────┐      ┌──────────┐    ┌──────────┐
    │ Network │      │ Storage  │    │ Security │
    └─────────┘      └──────────┘    └──────────┘
```

## Dependency Layers

### Layer 0: Foundation (Must deploy first)
- **Flux System** (`flux-system`)
  - Manages entire GitOps workflow
  - All apps depend on Flux being operational

### Layer 1: Core Infrastructure
- **Cilium** (`kube-system/cilium`)
  - CNI networking
  - Network policies
  - Required by: ALL applications
  
- **CoreDNS** (`kube-system/coredns`)
  - DNS resolution
  - Required by: ALL applications
  
- **Cert-Manager** (`cert-manager/cert-manager`)
  - TLS certificate management
  - Required by: Applications using HTTPS ingress

### Layer 2: Platform Services
- **External Secrets** (`external-secrets/external-secrets`)
  - Bitwarden integration
  - Secret management
  - Required by: Apps using ExternalSecrets
  
- **Rook-Ceph** (`rook-ceph/rook-ceph-cluster`)
  - Persistent storage backend
  - Required by: Apps with PVCs using ceph-block or ceph-filesystem
  
- **Ingress-Nginx** (`network/ingress-nginx`)
  - HTTP/HTTPS ingress
  - Required by: Apps with Ingress resources

### Layer 3: Supporting Services
- **Metrics Server** (`kube-system/metrics-server`)
  - Resource metrics
  - Required by: HPA, monitoring
  
- **Reloader** (via annotation)
  - Auto-reload on ConfigMap/Secret changes
  - Required by: Apps with `reloader.stakater.com/auto: "true"`
  
- **External-DNS** (`network/external-dns`)
  - Automatic DNS record management
  - Required by: Apps with external-dns annotations

### Layer 4: Applications
All user-facing applications depend on layers 0-3.

## Application Dependencies

### Common Dependency Patterns

#### Basic Web Application
```yaml
dependsOn:
  - name: external-secrets-stores  # If using ExternalSecrets
  # Implicit: Flux, Cilium, CoreDNS, Ingress-Nginx
```

#### Application with Storage
```yaml
dependsOn:
  - name: rook-ceph-cluster
    namespace: rook-ceph
  - name: external-secrets-stores  # If using ExternalSecrets
```

#### Database Application
```yaml
dependsOn:
  - name: rook-ceph-cluster
    namespace: rook-ceph
  - name: external-secrets-stores
# Often requires backup: VolSync
```

## Namespace Dependencies

### cert-manager
- No external dependencies
- Required by: Apps using TLS certificates

### database
- **CloudNative-PG**: Requires Rook-Ceph for storage
- **Dragonfly**: Requires Rook-Ceph for persistence
- **EMQX**: Requires Rook-Ceph for persistence

### default (Home Automation)
- **home-assistant**: Requires Rook-Ceph, ExternalSecrets
- **frigate**: Requires Rook-Ceph, potentially hostNetwork
- **zigbee2mqtt**: Requires EMQX (database namespace)

### downloads
- **qbittorrent**: Requires Rook-Ceph, ExternalSecrets
- **autobrr**: Requires Rook-Ceph, ExternalSecrets

### media
- **sonarr/radarr/prowlarr**: Require Rook-Ceph, ExternalSecrets
- All depend on qBittorrent (downloads namespace)

### monitoring
- **grafana**: Requires Prometheus (observability)
- **loki**: Standalone

### observability
- **kube-prometheus-stack**: Core monitoring
- Required by: ServiceMonitor resources across all namespaces

### network
- **ingress-nginx**: Required by most apps
- **external-dns**: Optional, for automatic DNS

## Cross-Namespace Dependencies

```
home-assistant (default)
    └── EMQX (database) - MQTT broker
    └── CloudNative-PG (database) - PostgreSQL

media apps (media)
    └── qBittorrent (downloads) - Download client
    └── CloudNative-PG (database) - PostgreSQL

All apps with ServiceMonitor
    └── kube-prometheus-stack (observability) - Metrics collection

All apps with Ingress
    └── ingress-nginx (network) - Ingress controller
    └── cert-manager (cert-manager) - TLS certificates
```

## Storage Dependencies

### Applications Using Ceph Block Storage
- home-assistant
- frigate
- All *arr apps (sonarr, radarr, etc.)
- qbittorrent
- Database clusters (CloudNative-PG)

### Applications Using Ceph Filesystem
- Shared media storage (if configured)

### Applications Using EmptyDir (No persistence)
- Stateless applications
- Temporary caches

## Secret Management Dependencies

### Applications Using ExternalSecrets
All apps with `externalsecret.yaml` depend on:
1. `external-secrets-stores` Kustomization
2. Bitwarden Secrets Manager (external service)
3. Network connectivity to Bitwarden API

### Applications Using SOPS
- Require `SOPS_AGE_KEY_FILE` for decryption
- Flux automatically decrypts on apply

## Monitoring Dependencies

### Applications with ServiceMonitor
All depend on:
- `kube-prometheus-stack` (observability namespace)
- Prometheus operator CRDs

### Applications Sending Metrics
Common metrics endpoints:
- Prometheus exporters: Standard `/metrics`
- Home Assistant: `/api/prometheus`
- CloudNative-PG: Built-in operator metrics

## Backup Dependencies

### Applications with VolSync
Require:
- Rook-Ceph RGW or external S3 endpoint
- ReplicationSource/ReplicationDestination CRDs
- SOPS-encrypted credentials

## Network Policy Dependencies

Applications with NetworkPolicies need:
1. Cilium CNI (for enforcement)
2. Proper namespace labels
3. Pod labels matching selectors

## Ingress Dependencies

### External Ingress
```
Application
    └── Ingress (className: external)
        └── ingress-nginx-external (network)
            └── Cloudflare (external)
```

### Internal Ingress
```
Application
    └── Ingress (className: internal)
        └── ingress-nginx-internal (network)
            └── LAN access only
```

## Safe Modification Order

When updating multiple components:

1. **Infrastructure** (with caution):
   - Cilium
   - Rook-Ceph
   - Flux

2. **Platform Services**:
   - cert-manager
   - external-secrets
   - ingress-nginx

3. **Supporting Services**:
   - metrics-server
   - external-dns

4. **Databases**:
   - CloudNative-PG clusters
   - Dragonfly
   - EMQX

5. **Applications**:
   - Safe to update anytime
   - Test with dry-run first

## Breaking Changes to Avoid

### High Impact (Avoid unless necessary)
- Upgrading Flux major versions
- Changing Cilium CNI configuration
- Modifying Rook-Ceph cluster
- Changing storage classes

### Medium Impact
- Updating cert-manager (may affect certificate renewals)
- Changing ingress controllers
- Modifying ExternalSecrets store configuration

### Low Impact (Safe)
- Application version updates
- ConfigMap changes
- Adding new applications
- Updating Helm values

## Quick Reference: "What depends on X?"

### Rook-Ceph
All apps with PVCs using `storageClassName: ceph-block` or `ceph-filesystem`

### ExternalSecrets
All apps with `externalsecret.yaml` files

### Ingress-Nginx
All apps with `ingress:` section in HelmRelease

### Prometheus (kube-prometheus-stack)
All apps with `serviceMonitor:` section in HelmRelease

### CloudNative-PG
Apps configured with PostgreSQL databases:
- home-assistant
- Many media apps
- Custom applications needing PostgreSQL

## Agent Tips

1. **Before modifying infrastructure**:
   - Check what depends on it
   - Plan for downtime of dependent apps
   - Test in non-production first

2. **When adding applications**:
   - List required dependencies in ks.yaml
   - Ensure dependencies are deployed first
   - Use `wait: false` for non-critical apps

3. **When troubleshooting**:
   - Check dependency chain bottom-up
   - Verify lower layers are healthy first
   - Use `task kubernetes:resources` to see status
