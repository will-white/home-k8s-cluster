# Quick Start Guide for Agents

> **For AI Agents**: This guide provides step-by-step instructions for common tasks in this Kubernetes cluster repository.

## 📋 Prerequisites

Before making changes, verify your environment:

```bash
# Check required tools are installed
task --version
flux --version
kubectl --version
kustomize --version
kubeconform --version

# Verify environment variables (for cluster operations)
echo $KUBECONFIG
echo $SOPS_AGE_KEY_FILE
```

## 🚀 Common Tasks

### 1. Adding a New Application

**Standard structure for all apps:**
```
kubernetes/apps/<namespace>/<app-name>/
├── app/
│   ├── helmrelease.yaml      # Helm chart deployment
│   ├── kustomization.yaml    # Kustomize configuration
│   ├── externalsecret.yaml   # (optional) External secrets
│   ├── configmap.yaml        # (optional) ConfigMaps
│   └── pvc.yaml              # (optional) Storage claims
└── ks.yaml                   # Flux Kustomization
```

**Step-by-step process:**

1. **Ask user for namespace** (CRITICAL - never assume):
   ```
   "Which namespace should this app be deployed to?"
   ```

2. **Search for existing Helm chart**:
   - Visit https://kubesearch.dev
   - Search for the application name
   - Note chart repository and version

3. **Create directory structure**:
   ```bash
   mkdir -p kubernetes/apps/<namespace>/<app-name>/app
   ```

4. **Create `ks.yaml`** (Flux Kustomization):
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
     dependsOn:
       - name: external-secrets-stores  # If using ExternalSecrets
     path: ./kubernetes/apps/<namespace>/<app-name>/app
     prune: true
     sourceRef:
       kind: GitRepository
       name: home-kubernetes
     wait: false
     interval: 30m
     retryInterval: 1m
     timeout: 5m
   ```

5. **Create `app/helmrelease.yaml`**:
   ```yaml
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: &app <app-name>
   spec:
     interval: 30m
     chart:
       spec:
         chart: <chart-name>
         version: <version>
         sourceRef:
           kind: HelmRepository
           name: <repo-name>
           namespace: flux-system
     install:
       remediation:
         retries: 3
     upgrade:
       cleanupOnFail: true
       remediation:
         strategy: rollback
         retries: 3
     values:
       # Chart-specific values here
   ```

6. **Create `app/kustomization.yaml`**:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - ./helmrelease.yaml
     # - ./externalsecret.yaml  # Uncomment if needed
     # - ./configmap.yaml       # Uncomment if needed
   ```

7. **Add to namespace kustomization**:
   ```bash
   # Edit kubernetes/apps/<namespace>/kustomization.yaml
   # Add reference to the new ks.yaml
   ```

8. **Validate**:
   ```bash
   # Validate the specific app
   kustomize build kubernetes/apps/<namespace>/<app-name> | kubeconform -strict -
   
   # Run full validation
   task kubernetes:kubeconform
   ```

### 2. Updating an Existing Application

1. **Locate the application**:
   ```bash
   find kubernetes/apps -name "<app-name>" -type d
   ```

2. **Edit the HelmRelease** (`app/helmrelease.yaml`):
   - Update `spec.chart.spec.version` for chart version changes
   - Update `spec.values` for configuration changes
   - Update image tags if using container images directly

3. **Validate changes**:
   ```bash
   kustomize build kubernetes/apps/<namespace>/<app> | kubeconform -strict -
   ```

4. **Test with dry-run** (if cluster access):
   ```bash
   flux build ks <app-name> \
     --kustomization-file kubernetes/apps/<namespace>/<app>/ks.yaml \
     --path kubernetes/apps/<namespace>/<app> \
     --dry-run
   ```

### 3. Managing Secrets

**CRITICAL RULES:**
- ✅ ALWAYS use SOPS encryption for secrets
- ❌ NEVER commit unencrypted secrets
- ✅ ALWAYS use ExternalSecrets for sensitive data
- ❌ NEVER use plain Kubernetes Secrets

**Using ExternalSecrets (Recommended):**

```yaml
# app/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: <app-name>-secret
spec:
  refreshInterval: 5m
  secretStoreRef:
    kind: ClusterSecretStore
    name: bitwarden-login  # or bitwarden-fields, bitwarden-notes
  target:
    name: <app-name>-secret
    template:
      engineVersion: v2
      data:
        KEY_NAME: "{{ .KEY_NAME }}"
  dataFrom:
    - extract:
        key: <bitwarden-item-id>
```

**Using SOPS (if needed):**

```bash
# Create secret file
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: <app-name>-secret
stringData:
  key: value
EOF

# Encrypt with SOPS (REQUIRES HUMAN APPROVAL)
sops --encrypt --in-place secret.yaml

# Verify encryption
grep "sops:" secret.yaml  # Should show SOPS metadata
```

### 4. Validation Workflow

**Before committing any changes:**

```bash
# 1. Validate YAML syntax
yamllint kubernetes/

# 2. Validate Kubernetes manifests
task kubernetes:kubeconform

# 3. Check for common issues
grep -r "Secret" kubernetes/apps --include="*.yaml" | grep -v "ExternalSecret"  # Find plain secrets
grep -r "sops:" kubernetes/apps --include="*.yaml"  # Verify SOPS encryption

# 4. Test specific app (if cluster access available)
flux build ks <app-name> \
  --kustomization-file kubernetes/apps/<namespace>/<app>/ks.yaml \
  --path kubernetes/apps/<namespace>/<app> \
  --dry-run
```

### 5. Directory Structure Overview

```
.
├── kubernetes/
│   ├── apps/                  # Application deployments
│   │   ├── <namespace>/       # Organized by namespace
│   │   │   ├── <app>/
│   │   │   │   ├── app/       # Application manifests
│   │   │   │   └── ks.yaml    # Flux Kustomization
│   │   │   ├── kustomization.yaml
│   │   │   └── namespace.yaml
│   ├── flux/                  # Flux system configuration
│   │   ├── config/
│   │   ├── repositories/      # Helm repos, Git repos
│   │   └── vars/              # Cluster-wide variables
│   ├── bootstrap/             # Cluster bootstrap configs
│   │   └── talos/             # Talos-specific configs
│   └── templates/             # Reusable templates
├── .taskfiles/                # Task automation
│   ├── kubernetes/
│   ├── talos/
│   └── bootstrap/
├── scripts/                   # Helper scripts
├── AGENTS.md                  # Agent personas & guidelines
└── .github/
    ├── agent-config.yaml      # Machine-readable policies
    └── workflows/             # CI/CD pipelines
```

## 🔍 Discovery Commands

```bash
# List all applications by namespace
find kubernetes/apps -name "ks.yaml" -exec dirname {} \;

# Find all HelmReleases
find kubernetes/apps -name "helmrelease.yaml"

# List all namespaces
find kubernetes/apps -maxdepth 1 -type d -name "[!.]*"

# Search for specific resources
grep -r "kind: HelmRelease" kubernetes/apps

# Find apps using specific Helm repo
grep -r "sourceRef:" kubernetes/apps -A 2 | grep "name: bjw-s"
```

## ⚠️ Safety Checks

**Before making changes:**

1. **Read AGENTS.md** for agent-specific guidelines
2. **Check agent-config.yaml** for policy restrictions
3. **Review TODO.md** for planned work and priorities
4. **Never assume default namespace** - always ask user

**Red flags to avoid:**

- ❌ Modifying `kubernetes/flux/` or `kubernetes/bootstrap/` (unless @infra-agent)
- ❌ Running `kubectl apply` without approval
- ❌ Running `task kubernetes:reconcile` without approval
- ❌ Creating unencrypted secrets
- ❌ Using `sudo` commands
- ❌ Pushing secrets to repository

## 📚 Reference Resources

- **Helm Charts**: https://kubesearch.dev
- **Flux Documentation**: https://fluxcd.io/docs/
- **Kustomize**: https://kustomize.io/
- **SOPS**: https://github.com/mozilla/sops
- **Bjw-s App Template**: https://bjw-s.github.io/helm-charts/docs/app-template/
- **Home Operations Discord**: https://discord.gg/home-operations

## 🎯 Agent Personas

Refer to different agents for specific tasks:

- **@app-agent**: Adding/updating apps in `kubernetes/apps/`
- **@infra-agent**: Infrastructure changes in `kubernetes/flux/`, `kubernetes/bootstrap/`
- **@test-agent**: Running validation and CI/CD
- **@ops-agent**: Cluster operations, secret management

See [AGENTS.md](./AGENTS.md) for detailed agent capabilities and boundaries.

## 🛠️ Troubleshooting

### Validation Failures

```bash
# Get detailed kubeconform output
task kubernetes:kubeconform

# Validate single kustomization
kustomize build kubernetes/apps/<namespace>/<app> | kubeconform -strict -

# Check YAML syntax
yamllint kubernetes/apps/<namespace>/<app>/
```

### Common Errors

**"Resource not found in schema"**
- Add to skip list in `scripts/kubeconform.sh`
- Common for CRDs: ExternalSecret, ReplicationSource, HTTPRoute

**"Duplicate key"**
- Check for duplicate fields in YAML
- Verify proper indentation

**"Invalid value"**
- Check API version compatibility
- Verify field names match chart schema

## 📝 Commit Message Format

Use conventional commits:

```
feat(apps): add new application <app-name> to <namespace>
fix(apps): update <app-name> configuration
chore(apps): update <app-name> to version X.Y.Z
docs: update documentation for <topic>
```

## ✅ Pre-Commit Checklist

- [ ] Validated with `task kubernetes:kubeconform`
- [ ] No unencrypted secrets committed
- [ ] Updated namespace kustomization if needed
- [ ] Followed naming conventions
- [ ] Added appropriate labels and annotations
- [ ] Tested dry-run (if cluster access available)
- [ ] Updated documentation (if needed)
