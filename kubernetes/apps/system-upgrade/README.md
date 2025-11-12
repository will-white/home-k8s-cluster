# System Upgrade Controller

Automated upgrade orchestration for **Talos Linux** with GitOps-native workflow using the [Rancher System Upgrade Controller](https://github.com/rancher/system-upgrade-controller).

## Overview

This system automates **Talos OS upgrades** with a safe, sequential approach:

1. **GitHub Actions monitors** for new Talos versions weekly
2. **Automatic PR creation** with upgrade Plans when updates are available
3. **Workers upgrade first** automatically after PR merge (via Flux)
4. **Control plane upgrades** require manual Plan application (safety gate)

**Important**: This automation handles **Talos OS upgrades only**. Kubernetes version upgrades are handled separately (see below).

The System Upgrade Controller introduces a declarative API for orchestrating node upgrades. It watches for `Plan` resources and creates Jobs to execute upgrades on selected nodes with proper cordoning, draining, and sequencing.

## Talos vs Kubernetes Upgrades

| Aspect | Talos OS Upgrades | Kubernetes Upgrades |
|--------|-------------------|---------------------|
| **Automation** | System Upgrade Controller + Flux | Manual `task talos:upgrade-k8s` |
| **Workflow** | `.github/workflows/talos-version-check.yaml` | `.github/workflows/kubernetes-version-check.yaml` |
| **PR Creation** | ✅ Automatic with Plans | ✅ Automatic (config update only) |
| **Execution** | ✅ Automatic (workers), Manual (control plane) | ⚠️ Manual command required |
| **Why Different?** | Node-level, independent | Requires coordinated control plane upgrade |
| **Command** | Handled by controller | `task talos:upgrade-k8s` |

**Recommended upgrade order**: Talos OS first, then Kubernetes (verify compatibility matrix).

## Automated Upgrade Workflow

### How It Works

```
Weekly Check → Determine Path → PR Created → PR Merged → Workers Upgrade → Manual Control Plane → Repeat
```

**Talos Upgrade Path Requirements:**

Talos follows a strict upgrade sequence to ensure compatibility:

1. **Update to latest patch in current minor** (e.g., v1.11.0 → v1.11.6)
2. **Then upgrade to next major** (e.g., v1.11.6 → v1.12.0)
3. **Repeat**: Latest patch → Next major → Latest patch → Next major

Example multi-major upgrade path (v1.10.0 → v1.13.0):
```
v1.10.0 → v1.10.8 (latest in 1.10)
v1.10.8 → v1.11.0 (major upgrade)
v1.11.0 → v1.11.6 (latest in 1.11)
v1.11.6 → v1.12.0 (major upgrade)
v1.12.0 → v1.12.4 (latest in 1.12)
v1.12.4 → v1.13.0 (major upgrade)
```

The automation handles this automatically by creating sequential PRs for each step.

1. **Version Monitoring** (Every Monday 9 AM UTC)
   - GitHub Actions workflow checks for new Talos releases
   - Determines correct upgrade path based on current version:
     - If not on latest patch: Creates PR for patch update
     - If on latest patch: Creates PR for next major version
   - Follows Talos upgrade sequence automatically

2. **Automatic PR Creation**
   - When an update is available, workflow creates a new branch
   - Updates `talconfig.yaml` with target version
   - Generates two sequential upgrade Plans:
     - `01-talos-workers-upgrade.yaml` - Worker nodes
     - `02-talos-controlplane-upgrade.yaml` - Control plane
   - Creates PR with detailed upgrade instructions
   - Labels: `talos`, `upgrade`, `automation`
   - PR title indicates patch update or major upgrade

3. **Worker Upgrade (Automatic)**
   - Merge the PR to start worker upgrades
   - Flux detects the new Plan and applies it
   - System Upgrade Controller processes workers one at a time
   - Each worker: cordon → drain → upgrade → uncordon → health check

4. **Control Plane Upgrade (Manual)**
   - **WAIT** for all workers to complete successfully
   - Manually apply control plane Plan:
     ```bash
     kubectl apply -f kubernetes/apps/system-upgrade/plans/02-talos-controlplane-upgrade.yaml
     ```
   - Monitor progress until complete

### Example PR Flow

When Talos releases are detected, the automation creates PRs for each step:

**Scenario: Upgrading from v1.11.2 to v1.13.0**

```bash
# Step 1: Patch update within current minor
[Monday 9 AM UTC] ✓ Detected: v1.11.2 → v1.11.6 (latest in 1.11)
PR #1 created: "chore(talos): patch update to v1.11.6"

[You] Review and merge PR #1
[Flux] Workers upgrade automatically to v1.11.6
[You] Apply control plane Plan manually
All nodes: v1.11.6 ✓

# Step 2: Major version upgrade
[Next Monday] ✓ Detected: v1.11.6 → v1.12.0 (next major)
PR #2 created: "chore(talos): major upgrade to v1.12.0"

[You] Review and merge PR #2
[Flux] Workers upgrade automatically to v1.12.0
[You] Apply control plane Plan manually
All nodes: v1.12.0 ✓

# Step 3: Patch update in new minor
[Next Monday] ✓ Detected: v1.12.0 → v1.12.5 (latest in 1.12)
PR #3 created: "chore(talos): patch update to v1.12.5"

[You] Review and merge PR #3
[Flux] Workers upgrade automatically to v1.12.5
[You] Apply control plane Plan manually
All nodes: v1.12.5 ✓

# Step 4: Next major version upgrade
[Next Monday] ✓ Detected: v1.12.5 → v1.13.0 (next major)
PR #4 created: "chore(talos): major upgrade to v1.13.0"

[You] Review and merge PR #4
[Flux] Workers upgrade automatically to v1.13.0
[You] Apply control plane Plan manually
All nodes: v1.13.0 ✓ TARGET REACHED

# Automation continues monitoring for future updates
[Next Monday] ✓ Already on latest available version
```

Each PR is self-contained with:
- Updated `talconfig.yaml`
- Worker and control plane upgrade Plans
- Detailed instructions
- Release notes link
- Information about next upgrade step

The automation handles the complexity of multi-major upgrades by creating one PR at a time, ensuring each step is completed before proceeding.

### Manual Trigger

Test the version check workflow manually:

```bash
# Trigger via GitHub UI:
# Actions → Talos Version Check → Run workflow

# Or via gh CLI:
gh workflow run talos-version-check.yaml
```

## Architecture

```
Plan CRD → Controller watches → Creates Job per node → Cordons → Drains → Upgrades → Uncordons
```

- **Controller**: Runs in the `system-upgrade` namespace, watches Plan resources
- **Plans**: Define upgrade policies (what to upgrade, which nodes, how many concurrent)
- **Jobs**: Created by controller to execute upgrades on individual nodes
- **Service Account**: `system-upgrade` with `cluster-admin` permissions for node operations
- **Version Checker**: CronJob that monitors for new Talos releases (weekly)
- **GitHub Actions**: Creates PRs with upgrade Plans when new versions detected

## When to Use System Upgrade Controller

### Good Use Cases ✅

- **Talos OS upgrades** across worker nodes with rolling updates
- **Scheduled maintenance** windows with automated node upgrades
- **Large clusters** where manual node-by-node upgrades are time-consuming
- **Consistent upgrade patterns** that can be codified in Plans

### When Manual Approach is Better ❌

- **Initial cluster setup** or first-time upgrades
- **Kubernetes version upgrades** in Talos (use `talosctl upgrade-k8s` instead)
- **Small clusters** (3-5 nodes) where manual control is preferred
- **High-risk changes** requiring careful observation
- **Testing and experimentation** with upgrade procedures

## Quick Start

### 1. System is Already Configured

The entire upgrade automation is deployed and ready:

- ✓ System Upgrade Controller running
- ✓ Version checker CronJob (runs weekly)
- ✓ GitHub Actions workflow configured
- ✓ Flux configured to auto-apply worker Plans

Check controller status:

```bash
kubectl -n system-upgrade get pods
```

Expected output:
```
NAME                                         READY   STATUS    RESTARTS   AGE
system-upgrade-controller-xxxxx              1/1     Running   0          5m
```

### 2. Wait for Automatic PR

When a new Talos version is released:
- Version checker will detect it (Monday 9 AM UTC)
- GitHub Actions will create a PR automatically
- PR will include upgrade Plans and instructions

Or trigger manually:
```bash
gh workflow run talos-version-check.yaml
```

### 3. Review and Merge PR

Review the PR to check:
- [ ] Talos version update is appropriate
- [ ] Release notes reviewed
- [ ] No breaking changes
- [ ] Plans look correct

Merge when ready - **worker upgrades start immediately**.

### 4. Monitor Worker Upgrades

```bash
# Watch Plan status
kubectl -n system-upgrade get plan talos-workers-upgrade -w

# Check Jobs
kubectl -n system-upgrade get jobs

# Watch nodes
kubectl get nodes -w

# View upgrade Job logs
kubectl -n system-upgrade logs -l upgrade.cattle.io/plan=talos-workers-upgrade -f
```

### 5. Apply Control Plane Plan

**ONLY after all workers complete successfully:**

```bash
# Verify all workers upgraded
kubectl get nodes -o wide

# Apply control plane Plan
kubectl apply -f kubernetes/apps/system-upgrade/plans/02-talos-controlplane-upgrade.yaml

# Monitor
kubectl -n system-upgrade get plan talos-controlplane-upgrade -w
```

## Manual Upgrade Workflow (Recommended for Most Users)

For safer, more controlled upgrades, use the existing Task commands:

### Talos OS Upgrade

Upgrade a single node:

```bash
task talos:upgrade-node HOSTNAME=mj05ajfj
```

This command:
- Takes down observability components temporarily
- Runs `talosctl upgrade` with the factory image from talconfig.yaml
- Waits for node health checks
- Brings observability back up

### Kubernetes Version Upgrade

Upgrade Kubernetes across the entire cluster:

```bash
task talos:upgrade-k8s
```

This command:
- Upgrades all control plane nodes in sequence
- Upgrades worker nodes automatically
- Handles etcd quorum and API server availability
- Uses the version specified in `talconfig.yaml`

### Incremental Worker Upgrade Pattern

For rolling upgrades with more control:

```bash
# Upgrade workers one at a time
for node in mj05ajfj mj0581rw mj04968e mj05g4ub; do
  task talos:upgrade-node HOSTNAME=$node
  sleep 300  # Wait 5 minutes between nodes
done
```

## Plan Configuration

### Key Plan Fields

```yaml
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: talos-upgrade
  namespace: system-upgrade
spec:
  # Maximum concurrent node upgrades (start with 1)
  concurrency: 1
  
  # Prevent other Plans from running simultaneously
  exclusive: true
  
  # Static version
  version: v1.12.0
  
  # OR dynamic version from URL
  channel: https://factory.talos.dev/.../latest.txt
  
  # Target specific nodes
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/worker: ""
  
  # Service account (already configured)
  serviceAccountName: system-upgrade
  
  # Cordon node before upgrade
  cordon: true
  
  # Drain configuration
  drain:
    force: true
    ignoreDaemonSets: true
    deleteEmptyDirData: true
    timeout: 900
    gracePeriod: 600
  
  # Upgrade container
  upgrade:
    image: factory.talos.dev/installer/<schematic>:<version>
    command: ["/bin/sh"]
    args:
      - -c
      - talosctl upgrade --nodes $NODE --image <image>
```

### Node Selection Strategies

**Upgrade workers first, then control plane:**

```yaml
# Plan 1: Workers
nodeSelector:
  matchLabels:
    node-role.kubernetes.io/worker: ""

# Plan 2: Control plane (apply after workers complete)
nodeSelector:
  matchLabels:
    node-role.kubernetes.io/control-plane: ""
```

**Upgrade specific nodes:**

```yaml
nodeSelector:
  matchLabels:
    kubernetes.io/hostname: mj05ajfj
```

**Upgrade by zone or rack:**

```yaml
nodeSelector:
  matchLabels:
    topology.kubernetes.io/zone: zone-a
```

## Safety Features

### Drain Configuration

The controller can drain nodes before upgrading:

```yaml
drain:
  # Force drain (ignore PodDisruptionBudgets)
  force: true
  
  # Ignore DaemonSets (they run on all nodes)
  ignoreDaemonSets: true
  
  # Delete pods with emptyDir volumes
  deleteEmptyDirData: true
  
  # Disable eviction API (use deletion)
  disableEviction: true
  
  # Maximum time to wait for drain
  timeout: 900
  
  # Grace period for pod termination
  gracePeriod: 600
```

### Concurrency Control

Limit simultaneous node upgrades:

```yaml
spec:
  concurrency: 1  # One node at a time
  exclusive: true # Prevent other Plans from running
```

### Tolerations

Allow upgrade Jobs to run on all nodes:

```yaml
tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

## Troubleshooting

### Plan Not Creating Jobs

Check Plan status:

```bash
kubectl -n system-upgrade get plan talos-upgrade -o yaml
```

Common issues:
- No nodes match `nodeSelector`
- Version already applied (check node labels)
- Controller not running

### Job Failed

View Job logs:

```bash
kubectl -n system-upgrade logs job/apply-talos-upgrade-on-<node>
```

Common issues:
- Image pull errors (check image URL and schematic ID)
- Talos API access denied (check `kubernetesTalosAPIAccess` in talconfig.yaml)
- Drain timeout (increase `drain.timeout`)

### Upgrade Stuck

Check node status:

```bash
kubectl get nodes
kubectl describe node <node-name>
```

Manual intervention:

```bash
# Uncordon stuck node
kubectl uncordon <node-name>

# Delete stuck Job
kubectl -n system-upgrade delete job <job-name>

# Suspend Plan
kubectl -n system-upgrade patch plan talos-upgrade -p '{"spec":{"concurrency":0}}'
```

### Rollback

If an upgrade fails:

1. **Suspend the Plan:**
   ```bash
   kubectl -n system-upgrade delete plan talos-upgrade
   ```

2. **Check node status:**
   ```bash
   kubectl get nodes
   talosctl -n <node> version
   ```

3. **Manual rollback (if needed):**
   ```bash
   # Talos doesn't support downgrade, but you can:
   # - Reboot to previous version (if not yet wiped)
   # - Reset and reimage node
   task talos:reset  # Careful!
   ```

## Advanced Usage

### Using Channels for Auto-Discovery

Instead of static versions, use a channel URL:

```yaml
spec:
  # Remove version field
  # version: v1.12.0
  
  # Add channel field
  channel: https://factory.talos.dev/installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/latest.txt
```

The controller will query the URL to get the latest version.

### Prepare Container

Run a container before cordoning/draining:

```yaml
spec:
  prepare:
    image: alpine:3
    command: ["/bin/sh"]
    args:
      - -c
      - |
        # Pre-upgrade checks
        echo "Checking disk space..."
        df -h /host
```

### Environment Variables

Pass environment to upgrade container:

```yaml
upgrade:
  image: factory.talos.dev/...
  env:
    - name: CUSTOM_VAR
      value: "custom-value"
    - name: NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
```

### Secrets

Mount secrets in upgrade Jobs:

```yaml
spec:
  secrets:
    - name: talos-secrets
      path: /var/run/secrets/talos
      ignoreUpdates: false
```

## Integration with Existing Workflows

### Update talconfig.yaml First

Before creating a Plan:

```bash
cd kubernetes/bootstrap/talos
vim talconfig.yaml  # Update talosVersion

task talos:generate  # Generate new configs
git add . && git commit -m "chore: update Talos to v1.12.0"
git push
```

### Flux Integration

Plans can be managed via Flux:

```yaml
# kubernetes/apps/system-upgrade/plans/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: system-upgrade-plans
  namespace: flux-system
spec:
  path: ./kubernetes/apps/system-upgrade/plans
  prune: false  # Don't auto-delete Plans
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
```

**Warning**: Be cautious with auto-applying Plans. Manual review is recommended.

## Comparison: System Upgrade Controller vs Manual

| Aspect | System Upgrade Controller | Manual (Task) |
|--------|---------------------------|---------------|
| **Automation** | Fully automated | Human-driven |
| **Concurrency** | Configurable (1-N nodes) | One at a time |
| **Drain handling** | Automatic | Manual (handled by Task) |
| **Error handling** | Limited (Job retries) | Human judgment |
| **Observability** | Job logs, Plan status | Direct feedback |
| **Rollback** | Manual | Manual |
| **Learning curve** | High (Plan syntax) | Low (Task commands) |
| **Best for** | Large clusters, routine updates | Small clusters, first-time upgrades |

## References

- [System Upgrade Controller Documentation](https://github.com/rancher/system-upgrade-controller)
- [Talos Upgrade Guide](https://www.talos.dev/v1.11/talos-guides/upgrading-talos/)
- [Kubernetes Upgrade Best Practices](https://kubernetes.io/docs/tasks/administer-cluster/cluster-upgrade/)

## Kubernetes Version Upgrades

While Talos OS upgrades are automated via System Upgrade Controller, **Kubernetes version upgrades require manual execution** but still benefit from automated monitoring and PR creation.

### Kubernetes Upgrade Workflow

1. **Automated Monitoring** (Every Monday 10 AM UTC)
   - GitHub Actions checks for new Kubernetes releases
   - Follows same upgrade path rules (latest patch → next minor → repeat)
   - Creates PR when updates are available

2. **PR Review and Merge**
   - PR updates `kubernetesVersion` in `talconfig.yaml`
   - Includes detailed upgrade instructions
   - Includes Talos compatibility verification
   - Labeled with `manual-action-required`

3. **Manual Upgrade Execution** (After PR Merge)
   ```bash
   task talos:upgrade-k8s
   ```
   
   This command:
   - Upgrades all control plane nodes in correct sequence
   - Maintains etcd quorum throughout
   - Upgrades worker nodes automatically
   - Provides real-time feedback

4. **Monitor Progress**
   ```bash
   kubectl get nodes -w
   kubectl get pods -n kube-system
   ```

### Why Manual for Kubernetes?

Kubernetes upgrades in Talos require complex orchestration:
- ✓ Control plane components must upgrade in specific order (etcd, API server, controller manager, scheduler)
- ✓ etcd quorum must be maintained
- ✓ API server availability is critical
- ✓ Talos's native `upgrade-k8s` provides best error handling

System Upgrade Controller is excellent for node-level operations (Talos OS), but Kubernetes upgrades benefit from Talos's built-in orchestration.

### Upgrade Path Example

Similar to Talos, Kubernetes follows strict versioning:

```bash
# Starting from v1.33.2, targeting v1.35.0

PR #1: v1.33.2 → v1.33.8 (latest patch)
[You] Merge PR, run: task talos:upgrade-k8s

PR #2: v1.33.8 → v1.34.0 (next minor)
[You] Merge PR, run: task talos:upgrade-k8s

PR #3: v1.34.0 → v1.34.5 (latest patch)
[You] Merge PR, run: task talos:upgrade-k8s

PR #4: v1.34.5 → v1.35.0 (target)
[You] Merge PR, run: task talos:upgrade-k8s
```

### Compatibility Verification

Always verify Talos and Kubernetes compatibility:
- Talos N typically supports Kubernetes N-2, N-1, N, N+1
- Check: https://www.talos.dev/latest/introduction/support-matrix/
- Upgrade Talos first if needed for compatibility

## Support

For issues with:
- **System Upgrade Controller**: Check [GitHub Issues](https://github.com/rancher/system-upgrade-controller/issues)
- **Talos Upgrades**: Refer to [Talos Documentation](https://www.talos.dev)
- **Kubernetes Upgrades**: Refer to [Talos Kubernetes Upgrade Guide](https://www.talos.dev/latest/kubernetes-guides/upgrading-kubernetes/)
- **This Cluster**: Review existing Task commands in `.taskfiles/talos/Taskfile.yaml`

## Summary

This repository provides **comprehensive upgrade automation**:

### Talos OS Upgrades (Fully Automated)
✓ **Automatic detection** - Weekly checks for new Talos versions  
✓ **Automatic PRs** - Upgrade Plans generated and committed via GitHub Actions  
✓ **Automatic execution** - Workers upgrade via Flux after PR merge  
✓ **Manual gate** - Control plane requires explicit Plan application  
✓ **Safe sequencing** - Follows Talos upgrade path automatically  

### Kubernetes Upgrades (Semi-Automated)
✓ **Automatic detection** - Weekly checks for new Kubernetes versions  
✓ **Automatic PRs** - Configuration updates with detailed instructions  
✓ **Manual execution** - Run `task talos:upgrade-k8s` after PR merge  
✓ **Safe orchestration** - Talos handles control plane coordination  
✓ **Path management** - Follows Kubernetes versioning rules  

**Recommended workflow:**
1. Let automation create PRs when updates are available
2. Review PR and merge when ready
3. For Talos: Monitor worker upgrades (automatic), apply control plane Plan (manual)
4. For Kubernetes: Run `task talos:upgrade-k8s` and monitor progress

**For urgent updates or troubleshooting**, use manual Task commands:
```bash
# Talos OS
task talos:upgrade-node HOSTNAME=<node>

# Kubernetes
task talos:upgrade-k8s
```

This hybrid approach provides automation with safety gates at critical points.
