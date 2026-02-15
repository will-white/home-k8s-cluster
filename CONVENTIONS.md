# Repository Conventions & Standards

> **For AI Agents**: This document defines the naming conventions, structure standards, and best practices for this Kubernetes cluster repository.

## 📁 Directory Structure

### Standard Application Layout

```
kubernetes/apps/<namespace>/<app-name>/
├── app/                          # Application resources
│   ├── helmrelease.yaml         # REQUIRED: Helm deployment
│   ├── kustomization.yaml       # REQUIRED: Kustomize config
│   ├── externalsecret.yaml      # Optional: External secrets
│   ├── configmap.yaml           # Optional: Configuration
│   ├── pvc.yaml                 # Optional: Persistent volume claim
│   ├── networkpolicy.yaml       # Optional: Network policies
│   ├── servicemonitor.yaml      # Optional: Prometheus monitoring
│   └── gatus.yaml               # Optional: Health checks
└── ks.yaml                      # REQUIRED: Flux Kustomization
```

### Namespace Organization

Apps are organized by namespace with clear purpose:

| Namespace | Purpose | Examples |
|-----------|---------|----------|
| `cert-manager` | Certificate management | cert-manager |
| `database` | Database services | cloudnative-pg, dragonfly, emqx |
| `default` | Home automation & utilities | home-assistant, frigate, mealie |
| `downloads` | Download automation | qbittorrent, autobrr, recyclarr |
| `external-secrets` | Secrets management | external-secrets |
| `flux-system` | GitOps system | flux, headlamp |
| `kube-system` | Cluster core services | cilium, coredns, metrics-server |
| `media` | Media streaming & automation | jellyfin, sonarr, radarr, prowlarr |
| `monitoring` | Observability stack | grafana, prometheus, loki |
| `network` | Network services | external-dns, ingress-nginx |
| `observability` | Metrics & monitoring | kube-prometheus-stack |
| `rook-ceph` | Storage backend | rook-ceph-cluster |
| `security` | Security tools | (future: trivy, falco) |
| `storage` | Storage solutions | (future: minio, nfs) |
| `system-upgrade` | System upgrades | system-upgrade-controller |

## 🏷️ Naming Conventions

### Resource Names

**Application Names**:
- Use lowercase with hyphens: `home-assistant`, `kube-prometheus-stack`
- Match official project names when possible
- Keep names concise but descriptive

**File Names**:
- Use lowercase with descriptive names
- Standard names: `helmrelease.yaml`, `kustomization.yaml`, `ks.yaml`
- Feature-specific: `externalsecret.yaml`, `configmap.yaml`, `pvc.yaml`

**Metadata Names**:
```yaml
# Use YAML anchor for app name
metadata:
  name: &app my-app-name

# Reference throughout the file
spec:
  targetNamespace: default
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
```

### Labels

**Standard Labels** (all resources):
```yaml
metadata:
  labels:
    app.kubernetes.io/name: <app-name>
    app.kubernetes.io/instance: <app-name>
    app.kubernetes.io/component: <component>  # Optional
```

**Common Labels** (via Flux Kustomization):
```yaml
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
```

### Annotations

**Flux Annotations**:
```yaml
# Auto-reload on ConfigMap/Secret changes
reloader.stakater.com/auto: "true"

# Homepage dashboard integration
gethomepage.dev/enabled: "true"
gethomepage.dev/group: "Media"
gethomepage.dev/name: "App Name"
gethomepage.dev/icon: "app.png"
gethomepage.dev/description: "Description"

# Ingress annotations
external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

## 📦 Helm Configuration

### HelmRelease Structure

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app <app-name>
spec:
  interval: 30m              # Standard check interval
  chart:
    spec:
      chart: <chart-name>
      version: <semantic-version>
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
        namespace: flux-system
  install:
    remediation:
      retries: 3             # Standard retry count
  upgrade:
    cleanupOnFail: true      # Always cleanup failed upgrades
    remediation:
      strategy: rollback     # Rollback on failure
      retries: 3
  dependsOn:                 # Optional dependencies
    - name: <dependency>
      namespace: <namespace>
  values:
    # Chart-specific values
```

### Common Helm Repositories

| Repository Name | Purpose | URL |
|----------------|---------|-----|
| `bjw-s` | App-template chart | https://bjw-s.github.io/helm-charts |
| `jetstack` | cert-manager | https://charts.jetstack.io |
| `prometheus-community` | Monitoring stack | https://prometheus-community.github.io/helm-charts |
| `grafana` | Grafana & Loki | https://grafana.github.io/helm-charts |
| `external-secrets` | External Secrets Operator | https://charts.external-secrets.io |

## 🔐 Secrets Management

### ExternalSecret Naming

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: <app-name>-secret      # Suffix with -secret
spec:
  refreshInterval: 5m           # Standard: 5m or 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: bitwarden-login       # Or: bitwarden-fields, bitwarden-notes
  target:
    name: <app-name>-secret     # Match metadata name
    template:
      engineVersion: v2          # Use v2 template engine
```

### Secret Store Types

| Store Name | Use Case | Example |
|------------|----------|---------|
| `bitwarden-login` | Username/password pairs | Database credentials |
| `bitwarden-fields` | Custom fields | API keys, tokens |
| `bitwarden-notes` | JSON/YAML in notes | Complex configs |

## 🎨 bjw-s App Template Standards

### Container Configuration

```yaml
values:
  controllers:
    <app-name>:
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        app:
          image:
            repository: ghcr.io/org/app
            tag: 1.2.3@sha256:...    # Pin with SHA
          env:
            TZ: ${TIMEZONE}           # Use cluster variable
          envFrom:
            - secretRef:
                name: <app-name>-secret
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
          resources:
            requests:
              cpu: 10m                # Minimum request
              memory: 128Mi
            limits:
              memory: 512Mi           # Always set memory limit
```

### Security Context

**Default Pod Security**:
```yaml
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile: { type: RuntimeDefault }
```

### Persistence

```yaml
persistence:
  config:
    existingClaim: *app         # Use PVC with same name as app
    globalMounts:
      - path: /config
  tmp:
    type: emptyDir              # Use for temporary data
    globalMounts:
      - path: /tmp
```

## 🌐 Ingress Standards

### Internal vs External

**External Ingress** (internet-facing):
```yaml
ingress:
  app:
    className: external
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    hosts:
      - host: app.${SECRET_DOMAIN}
        paths:
          - path: /
            service:
              identifier: app
              port: http
```

**Internal Ingress** (LAN only):
```yaml
ingress:
  app:
    className: internal
    hosts:
      - host: app.${SECRET_DOMAIN}
        paths:
          - path: /
            service:
              identifier: app
              port: http
```

## 📊 Monitoring Standards

### ServiceMonitor

```yaml
serviceMonitor:
  app:
    serviceName: <app-name>     # Must match service name
    endpoints:
      - port: metrics           # Port name from service
        scheme: http
        path: /metrics          # Prometheus endpoint
        interval: 1m            # Scrape interval
        scrapeTimeout: 30s
```

### Common Metrics Paths

| Application | Path | Port |
|------------|------|------|
| Prometheus exporters | `/metrics` | varies |
| Home Assistant | `/api/prometheus` | 8123 |
| Frigate | `/api/stats` | 5000 |
| PostgreSQL (CloudNativePG) | `/metrics` | 9187 |

## 💾 Storage Standards

### PVC Naming

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: &app <app-name>         # Match app name
spec:
  accessModes:
    - ReadWriteOnce             # Standard for single-pod apps
  resources:
    requests:
      storage: 10Gi             # Specify size
  storageClassName: ceph-block  # Or: ceph-filesystem, openebs-hostpath
```

### Storage Classes

| Class | Use Case | Access Mode |
|-------|----------|-------------|
| `ceph-block` | Databases, single-pod apps | ReadWriteOnce |
| `ceph-filesystem` | Shared storage, multi-pod | ReadWriteMany |
| `openebs-hostpath` | Node-local storage | ReadWriteOnce |

## 🔄 Flux Kustomization Standards

### Standard ks.yaml

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
  namespace: flux-system
spec:
  targetNamespace: <namespace>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:                    # Optional
    - name: <dependency>
      namespace: <namespace>
  path: ./kubernetes/apps/<namespace>/<app-name>/app
  prune: true                   # Always enable pruning
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  wait: false                   # Standard: false (use true for critical deps)
  interval: 30m                 # Standard check interval
  retryInterval: 1m
  timeout: 5m
  postBuild:                    # Optional
    substitute:
      APP: *app
```

### Common Dependencies

```yaml
dependsOn:
  # For apps using ExternalSecrets
  - name: external-secrets-stores
    namespace: flux-system
  
  # For apps using Rook-Ceph storage
  - name: rook-ceph-cluster
    namespace: rook-ceph
  
  # For apps using PostgreSQL
  - name: cloudnative-pg
    namespace: database
```

## 📝 Documentation Standards

### README Files

Apps with complex setup should include:
```
kubernetes/apps/<namespace>/<app-name>/README.md
```

Include:
- Purpose of the application
- Configuration notes
- Dependencies
- External integrations
- Disaster recovery notes

### Inline Comments

Add comments for non-obvious configuration:
```yaml
# Allow traffic from monitoring namespace for metrics scraping
# Required for Prometheus ServiceMonitor to function
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
```

## 🏗️ Kustomize Standards

### app/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <namespace>         # Set default namespace
resources:
  - ./helmrelease.yaml
  - ./externalsecret.yaml      # If exists
  - ./pvc.yaml                 # If exists
  - ./configmap.yaml           # If exists
  - ./networkpolicy.yaml       # If exists
labels:
  - pairs:
      app.kubernetes.io/name: <app-name>
      app.kubernetes.io/instance: <app-name>
```

### Namespace kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./app1/ks.yaml
  - ./app2/ks.yaml
  # Add new apps here
```

## 🔧 Variables & Substitution

### Cluster Variables

Located in `kubernetes/flux/vars/`:

```yaml
# cluster-settings.yaml
data:
  TIMEZONE: "America/New_York"
  CLUSTER_CIDR: "10.69.0.0/16"
  SERVICE_CIDR: "10.96.0.0/16"

# cluster-secrets.yaml (SOPS encrypted)
stringData:
  SECRET_DOMAIN: "example.com"
  SECRET_CLOUDFLARE_EMAIL: "user@example.com"
```

### Usage in Manifests

```yaml
# Direct substitution
env:
  TZ: ${TIMEZONE}

# In strings
hosts:
  - host: app.${SECRET_DOMAIN}
```

## ✅ Validation Requirements

### Pre-Commit Checks

All changes must pass:

1. **YAML Linting**:
   ```bash
   yamllint kubernetes/
   ```

2. **Kubeconform Validation**:
   ```bash
   task kubernetes:kubeconform
   ```

3. **Kustomize Build**:
   ```bash
   kustomize build kubernetes/apps/<namespace>/<app> | kubeconform -strict -
   ```

### CI/CD Validation

GitHub Actions automatically run:
- Agent validation (policy compliance)
- Kubeconform (manifest validation)
- Flux diff (change preview)

## 🎯 Best Practices

### Do's ✅

- Use semantic versioning for Helm charts
- Pin container images with SHA256
- Set resource requests and limits
- Use readiness and liveness probes
- Enable security contexts
- Use ExternalSecrets for sensitive data
- Document complex configurations
- Test changes with dry-run before applying

### Don'ts ❌

- Don't commit unencrypted secrets
- Don't use `latest` image tags
- Don't omit resource limits (especially memory)
- Don't disable security features without justification
- Don't modify other agent's domains (see AGENTS.md)
- Don't apply changes to cluster without approval
- Don't assume default namespace (always ask)

## 📚 References

- **Flux Documentation**: https://fluxcd.io/docs/
- **Kustomize**: https://kustomize.io/
- **bjw-s App Template**: https://bjw-s.github.io/helm-charts/docs/app-template/
- **Kubernetes Best Practices**: https://kubernetes.io/docs/concepts/configuration/overview/
- **SOPS**: https://github.com/mozilla/sops

---

**Last Updated**: 2026-02-15
**Maintained By**: @infra-agent
