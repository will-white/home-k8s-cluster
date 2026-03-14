# Troubleshooting Guide for Agents

Common errors and their solutions when working with this Kubernetes cluster repository.

## Validation Errors

### Error: "Resource not found in schema"

**Symptom:**
```
kubeconform: Resource not found in schema
```

**Cause:** Custom Resource Definitions (CRDs) not in standard schema.

**Solution:**
1. Add resource to skip list in `scripts/kubeconform.sh`:
   ```bash
   -skip "Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute,YourNewCRD"
   ```

2. Common CRDs already skipped:
   - ExternalSecret (from external-secrets-operator)
   - ReplicationSource/ReplicationDestination (from VolSync)
   - HTTPRoute (from Gateway API)

**Prevention:** Use standard Kubernetes resources when possible.

---

### Error: "Duplicate key in mapping"

**Symptom:**
```yaml
Error: Duplicate key 'metadata' in mapping
```

**Cause:** Same YAML key defined twice in the same level.

**Solution:**
1. Find the duplicate key:
   ```bash
   yamllint kubernetes/apps/<namespace>/<app>/
   ```

2. Merge or remove duplicate:
   ```yaml
   # Wrong:
   metadata:
     name: app
   metadata:
     labels: ...
   
   # Correct:
   metadata:
     name: app
     labels: ...
   ```

**Prevention:** Use YAML linter and proper indentation.

---

### Error: "Missing required field"

**Symptom:**
```
Error: spec.chart.spec.sourceRef.name is required
```

**Cause:** Required field not provided in YAML.

**Solution:**
1. Add the missing field:
   ```yaml
   chart:
     spec:
       chart: app-template
       version: 3.7.3
       sourceRef:
         kind: HelmRepository
         name: bjw-s  # Add this
         namespace: flux-system
   ```

2. Check chart documentation for required fields.

**Prevention:** Use templates from `kubernetes/templates/app-scaffold/`.

---

### Error: "Invalid value for field"

**Symptom:**
```
Error: spec.interval: Invalid value: "30": must be a duration
```

**Cause:** Value doesn't match expected format.

**Solution:**
```yaml
# Wrong:
interval: 30

# Correct:
interval: 30m
```

**Common Duration Formats:**
- `30s` - 30 seconds
- `5m` - 5 minutes
- `1h` - 1 hour

**Prevention:** Follow examples in existing apps.

---

## Kustomize Errors

### Error: "No matches for kind X"

**Symptom:**
```
Error: no matches for kind "HelmRelease" in version "helm.toolkit.fluxcd.io/v2"
```

**Cause:** API version mismatch or missing CRD.

**Solution:**
1. Check Flux version in cluster
2. Use correct API version:
   ```yaml
   # Flux v2
   apiVersion: helm.toolkit.fluxcd.io/v2
   
   # Older Flux
   apiVersion: helm.toolkit.fluxcd.io/v2beta1
   ```

3. Verify CRDs are installed:
   ```bash
   kubectl get crd helmreleases.helm.toolkit.fluxcd.io
   ```

**Prevention:** Match API versions with cluster's Flux version.

---

### Error: "Path not found"

**Symptom:**
```
Error: accumulating resources: accumulation err='accumulating resources from './missing': ...
```

**Cause:** Referenced file doesn't exist.

**Solution:**
1. Check `kustomization.yaml` resources:
   ```yaml
   resources:
     - ./helmrelease.yaml  # Verify this file exists
     - ./pvc.yaml          # Remove if not needed
   ```

2. Create missing file or remove reference.

**Prevention:** Only reference files that exist.

---

## Secrets Errors

### Error: "Unencrypted secret detected"

**Symptom:**
Pre-commit check warns about unencrypted secrets.

**Cause:** Plain Kubernetes Secret without SOPS encryption.

**Solution:**
Use ExternalSecret instead:
```yaml
# Replace plain Secret with ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secret
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: bitwarden-login
  target:
    name: app-secret
  dataFrom:
    - extract:
        key: <bitwarden-item-id>
```

**Alternative (if SOPS required):**
```bash
# Encrypt with SOPS (REQUIRES APPROVAL)
sops --encrypt --in-place secret.yaml
```

**Prevention:** Always use ExternalSecret for sensitive data.

---

### Error: "SOPS decryption failed"

**Symptom:**
```
Error: Failed to get the data key required to decrypt the SOPS file
```

**Cause:** Missing or incorrect `SOPS_AGE_KEY_FILE`.

**Solution:**
1. Verify environment variable:
   ```bash
   echo $SOPS_AGE_KEY_FILE
   ```

2. Check key file exists:
   ```bash
   ls -l $SOPS_AGE_KEY_FILE
   ```

3. This is a cluster operation - requires human with keys.

**Prevention:** Prefer ExternalSecrets over SOPS for new secrets.

---

## Helm Errors

### Error: "Chart not found"

**Symptom:**
```
Error: failed to download chart: failed to download
```

**Cause:** Helm repository not configured or chart name wrong.

**Solution:**
1. Check repository exists:
   ```bash
   find kubernetes/flux/repositories -name "*.yaml"
   ```

2. Verify chart name on https://kubesearch.dev

3. Check repository configuration:
   ```yaml
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: HelmRepository
   metadata:
     name: bjw-s
   spec:
     url: https://bjw-s.github.io/helm-charts
     interval: 1h
   ```

**Prevention:** Search kubesearch.dev before creating HelmRelease.

---

### Error: "Chart version not found"

**Symptom:**
```
Error: chart version "99.99.99" not found
```

**Cause:** Specified version doesn't exist.

**Solution:**
1. Check available versions:
   - Visit chart repository
   - Check on kubesearch.dev
   - Look at existing apps for recent versions

2. Update to valid version:
   ```yaml
   chart:
     spec:
       version: 3.7.3  # Use valid version
   ```

**Prevention:** Verify version exists before specifying.

---

## Dependency Errors

### Error: "Dependency not ready"

**Symptom:**
Flux shows dependency not reconciled.

**Cause:** Referenced dependency doesn't exist or isn't ready.

**Solution:**
1. Check dependency exists:
   ```bash
   flux get kustomizations -A | grep <dependency-name>
   ```

2. Verify dependency is in correct namespace:
   ```yaml
   dependsOn:
     - name: rook-ceph-cluster
       namespace: rook-ceph  # Must match
   ```

3. Wait for dependency to be ready or remove if not needed.

**Prevention:** Only add dependencies that actually exist.

---

### Error: "Circular dependency"

**Symptom:**
Apps never become ready, waiting on each other.

**Cause:** App A depends on App B, which depends on App A.

**Solution:**
1. Review dependency chain:
   ```bash
   grep -r "dependsOn:" kubernetes/apps/<namespace>/
   ```

2. Break the circle by removing unnecessary dependency.

**Prevention:** Keep dependency tree acyclic.

---

## Storage Errors

### Error: "PVC pending"

**Symptom:**
PersistentVolumeClaim stuck in Pending state.

**Cause:** Storage class not available or no capacity.

**Solution:**
1. Check storage class exists:
   ```bash
   kubectl get storageclass
   ```

2. Verify Rook-Ceph is healthy (if using Ceph):
   ```bash
   kubectl get cephcluster -n rook-ceph
   ```

3. Use correct storage class:
   ```yaml
   storageClassName: ceph-block  # Not ceph-blocks or cephblock
   ```

**Prevention:** Use standardized storage class names.

---

## Network Errors

### Error: "Ingress not accessible"

**Symptom:**
Cannot access app via ingress URL.

**Cause:** Multiple potential issues.

**Solution:**
1. Check Ingress exists:
   ```bash
   kubectl get ingress -n <namespace>
   ```

2. Verify IngressClass is correct:
   ```yaml
   ingress:
     className: external  # or 'internal'
   ```

3. Check service exists and has correct port:
   ```bash
   kubectl get svc -n <namespace>
   ```

4. Verify DNS (if using external-dns):
   ```bash
   dig app.${SECRET_DOMAIN}
   ```

**Prevention:** Test ingress configuration with existing working app first.

---

## Git Errors

### Error: "Merge conflict"

**Symptom:**
```
CONFLICT (content): Merge conflict in kubernetes/apps/...
```

**Cause:** Changes conflict with main branch.

**Solution:**
This requires human intervention:
1. User should pull latest changes
2. Resolve conflicts manually
3. Agent cannot fix merge conflicts

**Prevention:** Pull before making changes, make small incremental PRs.

---

## Common Warnings

### Warning: "Using 'latest' tag"

**Symptom:**
Validation warns about `tag: latest`.

**Cause:** Using mutable image tag.

**Solution:**
Pin to specific version with SHA:
```yaml
image:
  repository: ghcr.io/org/app
  tag: 1.2.3@sha256:abc123...  # Pin with SHA
```

**Prevention:** Always pin container images.

---

### Warning: "No resource limits"

**Symptom:**
Validation warns about missing limits.

**Cause:** Container can use unlimited resources.

**Solution:**
Add resource limits:
```yaml
resources:
  requests:
    cpu: 10m
    memory: 128Mi
  limits:
    memory: 512Mi  # Always set memory limit
```

**Prevention:** Use template with limits included.

---

## Debug Commands

### Check Application Status
```bash
# View all resources for an app
kubectl get all -n <namespace> -l app.kubernetes.io/name=<app>

# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Describe pod for events
kubectl describe pod -n <namespace> <pod-name>
```

### Check Flux Status
```bash
# All kustomizations
flux get kustomizations -A

# Specific kustomization
flux get kustomization <name> -n flux-system

# HelmRelease status
flux get helmreleases -A
```

### Check Dependencies
```bash
# View dependency tree
flux tree kustomization <name> -n flux-system

# Check if dependency exists
flux get kustomization <dependency> -n flux-system
```

### Validate Manually
```bash
# Build and validate
kustomize build kubernetes/apps/<namespace>/<app> | \
  kubeconform -strict -ignore-missing-schemas -verbose -

# Check for YAML errors
yamllint kubernetes/apps/<namespace>/<app>/

# Dry-run with Flux
flux build ks <app> \
  --kustomization-file kubernetes/apps/<namespace>/<app>/ks.yaml \
  --path kubernetes/apps/<namespace>/<app> \
  --dry-run
```

## When to Ask for Help

Agents should ask the user for help when:

1. **Cluster access required**:
   - Viewing actual cluster state
   - Applying changes to cluster
   - Debugging running pods

2. **Secrets management**:
   - SOPS encryption (requires approval)
   - Bitwarden integration issues
   - Missing credentials

3. **Infrastructure changes**:
   - Modifying Flux system
   - Changing core networking (Cilium)
   - Updating storage backend (Rook-Ceph)

4. **Merge conflicts**:
   - Git conflicts require manual resolution
   - Cannot automatically resolve

5. **Unclear requirements**:
   - Ambiguous namespace selection
   - Unknown chart repository
   - Unclear security requirements

## Prevention Checklist

Before making changes:

- [ ] Read QUICK_START.md
- [ ] Check CONVENTIONS.md for standards
- [ ] Use templates from `kubernetes/templates/`
- [ ] Validate with `./scripts/validate-app.sh`
- [ ] Ask user for namespace (never assume)
- [ ] Search kubesearch.dev for charts
- [ ] Test with dry-run if possible
- [ ] Run `./scripts/validate-before-commit.sh`
