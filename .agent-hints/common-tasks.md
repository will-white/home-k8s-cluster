# Common Tasks Reference for Agents

This file provides quick command references for common agent tasks.

## Validation Commands

### Quick Validation
```bash
# Validate everything
task kubernetes:kubeconform

# Validate specific app
kustomize build kubernetes/apps/<namespace>/<app> | kubeconform -strict -

# YAML linting
yamllint kubernetes/

# Use validation script
./scripts/validate-app.sh <namespace> <app>
```

### Pre-Commit Validation
```bash
# Run all pre-commit checks
./scripts/validate-before-commit.sh
```

## Application Management

### Add New Application
```bash
# 1. Generate scaffold (easier)
./scripts/generate-app-scaffold.sh <app-name> <namespace>

# 2. Or copy template manually
cp -r kubernetes/templates/app-scaffold kubernetes/apps/<namespace>/<app>

# 3. Edit files, replace placeholders

# 4. Add to namespace kustomization
# Edit kubernetes/apps/<namespace>/kustomization.yaml
# Add: - ./<app>/ks.yaml

# 5. Validate
task kubernetes:kubeconform
```

### Update Application
```bash
# 1. Find the app
find kubernetes/apps -name "<app-name>" -type d

# 2. Edit HelmRelease
vi kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml

# 3. Validate
./scripts/validate-app.sh <namespace> <app>

# 4. Dry-run (if cluster access)
flux build ks <app> \
  --kustomization-file kubernetes/apps/<namespace>/<app>/ks.yaml \
  --path kubernetes/apps/<namespace>/<app> \
  --dry-run
```

## Discovery Commands

### Find Applications
```bash
# List all apps
find kubernetes/apps -name "ks.yaml" -exec dirname {} \;

# Find by namespace
ls kubernetes/apps/<namespace>/

# Search for specific resource
grep -r "kind: HelmRelease" kubernetes/apps | grep <app-name>
```

### Find Configuration
```bash
# Find Helm repositories
find kubernetes/flux/repositories -name "*.yaml"

# Find cluster variables
cat kubernetes/flux/vars/cluster-settings.yaml
cat kubernetes/flux/vars/cluster-secrets.yaml  # SOPS encrypted

# Find ingress classes
kubectl get ingressclass  # if cluster access
```

## Secrets Management

### ExternalSecret (Recommended)
```bash
# 1. Create ExternalSecret from template
cp kubernetes/templates/app-scaffold/app/externalsecret.yaml \
   kubernetes/apps/<namespace>/<app>/app/

# 2. Edit with Bitwarden item ID
vi kubernetes/apps/<namespace>/<app>/app/externalsecret.yaml

# 3. Add to kustomization
# Add to kubernetes/apps/<namespace>/<app>/app/kustomization.yaml:
# - ./externalsecret.yaml

# 4. Reference in HelmRelease
# envFrom:
#   - secretRef:
#       name: <app>-secret
```

### SOPS (If Needed - Requires Approval)
```bash
# Create secret
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: <app>-secret
stringData:
  key: value
EOF

# Encrypt (REQUIRES HUMAN APPROVAL)
sops --encrypt --in-place secret.yaml

# Verify encryption
grep "sops:" secret.yaml
```

## Troubleshooting

### Validation Failures
```bash
# Detailed kubeconform output
kustomize build kubernetes/apps/<namespace>/<app> | \
  kubeconform -strict -ignore-missing-schemas -verbose -

# Check YAML syntax
yamllint kubernetes/apps/<namespace>/<app>/

# Build kustomization
kustomize build kubernetes/apps/<namespace>/<app>/app
```

### Find Issues
```bash
# Find unencrypted secrets
find kubernetes/apps -name "*secret*.yaml" -exec sh -c 'grep -L "sops:" "$1"' _ {} \;

# Find latest tags
grep -r "tag: latest" kubernetes/apps

# Find missing resource limits
grep -r "resources:" kubernetes/apps -A 10 | grep -v "limits:"
```

## Git Operations

### Check Status
```bash
# View changes
git status
git diff

# View staged changes
git diff --cached

# View commit history
git log --oneline -10
```

### Commit Changes (Use report_progress tool instead)
The agent should use the `report_progress` tool, but if needed:
```bash
# Stage changes
git add .

# Commit
git commit -m "feat(apps): add <app> to <namespace>"

# Push (handled by report_progress)
git push
```

## Cluster Operations (Require Approval)

### View Resources
```bash
# List resources
task kubernetes:resources

# Get specific resource
kubectl get <resource> -A

# Describe resource
kubectl describe <resource> <name> -n <namespace>
```

### Apply Changes (REQUIRES APPROVAL)
```bash
# Apply specific Kustomization
task kubernetes:apply-ks PATH=<namespace>/<app>

# Force reconcile (REQUIRES APPROVAL)
task kubernetes:reconcile
```

## Namespace Reference

| Namespace | Purpose | Common Apps |
|-----------|---------|-------------|
| `cert-manager` | Certificates | cert-manager |
| `database` | Databases | cloudnative-pg, dragonfly |
| `default` | Home automation | home-assistant, frigate |
| `downloads` | Download automation | qbittorrent, autobrr |
| `media` | Media automation | sonarr, radarr, prowlarr |
| `monitoring` | Observability | grafana, loki |
| `network` | Network services | external-dns, ingress-nginx |
| `observability` | Metrics | kube-prometheus-stack |

## Helm Repository Reference

| Repo Name | Purpose | Charts URL |
|-----------|---------|-----------|
| `bjw-s` | App template | https://bjw-s.github.io/helm-charts |
| `jetstack` | cert-manager | https://charts.jetstack.io |
| `prometheus-community` | Monitoring | https://prometheus-community.github.io/helm-charts |
| `grafana` | Grafana & Loki | https://grafana.github.io/helm-charts |

## Storage Classes

| Class | Use Case | Access Mode |
|-------|----------|-------------|
| `ceph-block` | Single-pod storage | ReadWriteOnce |
| `ceph-filesystem` | Shared storage | ReadWriteMany |
| `openebs-hostpath` | Node-local | ReadWriteOnce |

## Safety Checklist

Before making changes:
- [ ] Read AGENTS.md for role boundaries
- [ ] Check agent-config.yaml for policies
- [ ] Ask user for namespace (never assume)
- [ ] Search for existing chart on kubesearch.dev
- [ ] Validate with task kubernetes:kubeconform
- [ ] Never commit unencrypted secrets
- [ ] Use dry-run before applying to cluster

## External Resources

- Helm Charts: https://kubesearch.dev
- Flux Docs: https://fluxcd.io/docs/
- bjw-s Template: https://bjw-s.github.io/helm-charts/docs/app-template/
- Home Ops Discord: https://discord.gg/home-operations
