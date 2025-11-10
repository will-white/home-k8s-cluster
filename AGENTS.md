# AGENT Instructions for Home K8s Cluster

> **Note**: This repository includes machine-parseable agent policies. See [agent-config.yaml](.github/agent-config.yaml) for the canonical policy configuration and the [agent-validation workflow](.github/workflows/agent-validation.yml) for automated validation checks.

---
agent_policy:
  version: 1
  allowed_actions:
    - read_repo
    - run_local_validation
    - open_pull_request
    - propose_changes
  forbidden_actions:
    - apply_to_cluster
    - edit_secrets
    - push_secrets
    - run_sudo
    - exfiltrate_data
  requires_human_approval:
    - task kubernetes:reconcile
    - task kubernetes:apply-ks
    - sops --encrypt
  env_required:
    - KUBECONFIG
    - SOPS_AGE_KEY_FILE
  recommended_timeouts_seconds:
    configure: 120
    install_tools: 300
  agent_behavior: |
    Agents must not run cluster-affecting commands without explicit, recorded human approval. Prefer dry-run alternatives. Log all attempted actions in the PR description.
---

## Overview

This is a home Kubernetes cluster managed with Flux, Renovate, and GitHub Actions. The cluster runs on Talos Linux and uses SOPS for secret encryption.

This repository manages a home Kubernetes cluster using Talos Linux, Flux GitOps, and Task automation. The cluster runs on multiple Lenovo Tiny machines with CEPH storage and includes comprehensive monitoring, media services, and infrastructure applications.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Repository Structure

- `kubernetes/apps/` - Application manifests and Kustomizations
- `kubernetes/flux/` - Flux system configuration
- `kubernetes/bootstrap/` - Bootstrap configuration including Talos patches
- `.taskfiles/` - Task definitions for cluster management
- `scripts/` - Helper scripts including kubeconform validation

### Critical Directories
- `kubernetes/apps/`: All application manifests organized by namespace
- `kubernetes/bootstrap/`: Cluster bootstrap configurations (Talos, Flux, Helm)
- `kubernetes/flux/`: Flux GitOps system configuration
- `.taskfiles/`: Modular Task definitions for automation
- `scripts/`: Shell scripts for validation and utilities

### Configuration Files
- `config.yaml`: Main cluster configuration (created from config.sample.yaml)
- `Taskfile.yaml`: Main task runner configuration
- `requirements.txt`: Python dependencies for template processing
- `.sops.yaml`: Secret encryption configuration
- `.envrc`: Environment variables (if using direnv)

## Working with this Repository

### Safe Operations (Allowed for Agents)

Agents can safely perform these operations:

1. **Read repository contents** - Browse files, understand structure
2. **Run local validation** - Execute kubeconform, kustomize build, yamllint
3. **Propose changes** - Open pull requests with suggested modifications
4. **Generate documentation** - Update README files and comments

### Dangerous Operations (Human Approval Required)

The following operations require explicit human approval and should be marked with `HUMAN_APPROVAL_REQUIRED:` prefix:

- **HUMAN_APPROVAL_REQUIRED: task kubernetes:reconcile** - Forces Flux to pull changes from Git
  - Dry-run alternative: `flux diff kustomization cluster --path ./kubernetes`
  
- **HUMAN_APPROVAL_REQUIRED: task kubernetes:apply-ks PATH=<path>** - Applies a Flux Kustomization to the cluster
  - Dry-run alternative: `flux build ks <name> --kustomization-file <file> --path <path> --dry-run`
  
- **HUMAN_APPROVAL_REQUIRED: sops --encrypt** - Encrypts secrets with SOPS
  - Validation alternative: Review the `.sops.yaml` configuration file and verify SOPS config with `sops --config .sops.yaml updatekeys --yes <file>` (Note: SOPS does not support a `--dry-run` flag)

### Configuration Tasks

When running configuration tasks, NEVER CANCEL (agent: run with dry-run and respect recommended_timeouts). These tasks require time to complete:

- `task configure` - Renders and validates configuration files (recommended timeout: 120 seconds)
- `task workstation:install-tools` - Installs required tools (recommended timeout: 300 seconds)

### Validation Commands

These commands are safe to run and should be used before proposing changes:

```bash
# Validate all Kubernetes manifests
task kubernetes:kubeconform

# Build and validate specific kustomization
kustomize build kubernetes/apps/<app-name> | kubeconform -strict -

# Validate YAML syntax
yamllint kubernetes/

# Check for unencrypted secrets
grep -r "apiVersion.*Secret" kubernetes/ | grep -v "sops:"
```

### Secret Management

- All secrets MUST be encrypted with SOPS before committing
- The `.sops.yaml` file defines encryption rules
- NEVER commit unencrypted secrets, API keys, or credentials
- Encrypted files contain `sops:` metadata block
- Always run `task configure` after editing config.yaml to re-encrypt secrets

### Flux Operations

- Flux automatically syncs changes from the `main` branch
- Use `flux diff` to preview changes before applying
- Test changes in a feature branch before merging to main

## Working Effectively

### Initial Setup - NEVER CANCEL These Commands
Bootstrap the development environment in this exact order:

```bash
# Install Task runner (required for all operations)
curl -sL https://github.com/go-task/task/releases/latest/download/task_linux_amd64.tar.gz | tar -xz -C /tmp && sudo mv /tmp/task /usr/local/bin/task

# Set up Python virtual environment - takes 30 seconds. NEVER CANCEL.
task workstation:venv

# Initialize configuration file
task init

# Install CLI tools (if on Linux) - takes 2-5 minutes. NEVER CANCEL.
# Note: May fail in restricted networks - install tools individually if needed
task workstation:generic-linux || echo "Manual tool installation required"
```

### Required Tools Installation (if workstation:generic-linux fails)
Install these tools manually if automated installation fails due to network restrictions:

```bash
# Create .bin directory for local tools
mkdir -p .bin && cd .bin

# kubeconform (for manifest validation) - ESSENTIAL
curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz
chmod +x kubeconform

# kubectl (essential for Kubernetes operations)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl

# Add to PATH
export PATH="$(pwd):$PATH"
cd ..
```

### Configuration and Validation - TIMING CRITICAL

```bash
# NEVER CANCEL: Configure cluster manifests - takes 30-60 seconds
# This processes templates and encrypts secrets
# NOTE: Requires the kubernetes/bootstrap directory, which is present in this repository
task configure

# NEVER CANCEL: Validate Kubernetes manifests - takes 3-30 seconds depending on network
# This validates 340+ YAML files across the entire cluster
# NOTE: May fail in restricted networks due to schema downloads - validation logic is sound
task kubernetes:kubeconform
```

### Python Environment Management
The repository requires Python tools for template processing:

```bash
# Virtual environment is required for makejinja
source .venv/bin/activate  # Not needed if using direnv, because .envrc sets VIRTUAL_ENV

# Verify makejinja installation
.venv/bin/makejinja --version

# Install/update requirements - takes 30-60 seconds. NEVER CANCEL.
.venv/bin/python3 -m pip install --upgrade --requirement requirements.txt
```

## Validation Requirements

### CRITICAL: Always Run These Validation Steps
After making ANY changes to Kubernetes manifests:

```bash
# 1. Validate YAML syntax and Kubernetes compliance
task kubernetes:kubeconform

# 2. If you have cluster access, test Flux resource application
task kubernetes:apply-ks PATH=path/to/changed/app

# 3. Check cluster resources (if connected to cluster)
task kubernetes:resources
```

### Manual Validation Scenarios
For substantial changes, perform these validation scenarios:

1. **Manifest Changes**: Run `task kubernetes:kubeconform` and verify all YAML files validate correctly
2. **Application Changes**: Test specific app deployment with `task kubernetes:apply-ks PATH=apps/namespace/app-name`
3. **Secret Changes**: Verify SOPS encryption works: `sops --encrypt --in-place test-secret.sops.yaml`
4. **Template Changes**: Re-run `task configure` and check generated manifests

### Network-Restricted Validation
When `task kubernetes:kubeconform` fails due to network restrictions:

```bash
# Test individual kustomization builds (takes <1 second each)
kustomize build kubernetes/apps/media/radarr/app/
kustomize build kubernetes/apps/default/unifi/app/

# Validate YAML syntax
find kubernetes/apps -name "*.yaml" -exec yq eval . {} \; >/dev/null

# Check for common issues in manifests
grep -r "CHANGEME\|TODO\|FIXME" kubernetes/apps/ || echo "No placeholder values found"
```

## Critical Timing Information

**NEVER CANCEL these operations - they WILL complete:**

- **task workstation:venv**: 30 seconds - Python package installation
- **task configure**: 30-60 seconds - Template processing and secret encryption  
- **task kubernetes:kubeconform**: 3-30 seconds - Manifest validation (340+ files)
- **task workstation:generic-linux**: 2-5 minutes - CLI tool installation
- **Bootstrap operations** (if running full cluster bootstrap): 15-45 minutes

**Set timeouts of 60+ seconds for configure commands and 90+ seconds for tool installation.**

## Key Technologies and Commands

### Task Runner (Primary Interface)
```bash
# List all available tasks
task --list

# Key tasks for daily operations
task init                          # Initialize config.yaml from sample
task configure                     # Process templates and encrypt secrets
task kubernetes:kubeconform        # Validate all manifests
task kubernetes:reconcile          # Force Flux sync (requires cluster access)
task bootstrap:age-keygen          # Generate new SOPS age key
```

### SOPS Secret Management
```bash
# Encrypt a secret file
sops --encrypt --in-place filename.sops.yaml

# Decrypt for editing
sops filename.sops.yaml

# Check encryption status
sops filestatus filename.sops.yaml
```

### Cluster Operations (requires cluster access)
```bash
# Apply specific Flux Kustomization
task kubernetes:apply-ks PATH=apps/media/radarr

# Check cluster health
task kubernetes:resources

# Sync Flux from Git
task kubernetes:reconcile
```

## Common Tasks

### Working with Applications
The cluster manages 420+ Kubernetes resources across these main categories:
- **Media**: Radarr, Sonarr, Bazarr, qBittorrent, Overseerr, Prowlarr (kubernetes/apps/media/)
- **Database**: PostgreSQL, Redis (kubernetes/apps/database/)
- **Monitoring**: Prometheus, Grafana (kubernetes/apps/observability/)
- **Storage**: Rook-CEPH, OpenEBS (kubernetes/apps/rook-ceph/, kubernetes/apps/openebs-system/)
- **Network**: Cilium, cert-manager (kubernetes/apps/kube-system/, kubernetes/apps/cert-manager/)
- **Default**: UniFi, Homebox, and other utility applications (kubernetes/apps/default/)

### Editing Applications
```bash
# Navigate to specific app
cd kubernetes/apps/media/radarr/app/

# Edit configuration
vim helm-values.yaml

# Validate changes
task kubernetes:kubeconform

# Apply to cluster (if connected)
task kubernetes:apply-ks PATH=apps/media/radarr
```

### Adding New Applications
1. Create directory structure: `kubernetes/apps/namespace/app-name/app/`
2. Add Kubernetes manifests or Helm values
3. Create `ks.yaml` for Flux Kustomization
4. Run `task kubernetes:kubeconform` to validate
5. Apply with `task kubernetes:apply-ks PATH=apps/namespace/app-name`

## Environment Setup

### Development Container Support
The repository includes devcontainer configuration with:
- Pre-installed tools (Task, kubectl, Flux, Python)
- Configured environment variables
- Fish shell with useful plugins

### Required Environment Variables
```bash
export KUBECONFIG="./kubeconfig"              # Kubernetes config
export SOPS_AGE_KEY_FILE="./age.key"          # SOPS encryption key
export VIRTUAL_ENV="./.venv"                  # Python virtual environment
# TALOSCONFIG is generated during Talos bootstrap (see bootstrap docs)
export TALOSCONFIG="./kubernetes/bootstrap/talos/clusterconfig/talosconfig"
```

## Troubleshooting

### Common Issues
1. **kubeconform fails with network errors**: Normal in restricted environments - validation logic is sound
2. **task workstation:generic-linux fails**: Install tools manually using commands above
3. **SOPS errors**: Ensure age.key exists and SOPS_AGE_KEY_FILE is set
4. **Template processing fails**: Verify Python venv is activated and makejinja is installed

### Recovery Commands
```bash
# Reset to clean state
git checkout config.yaml           # Reset config to last commit
task workstation:venv              # Rebuild Python environment
rm -rf .bin && mkdir .bin          # Reset tool directory
```

### Validation Failures
```bash
# Check specific manifest
kubeconform kubernetes/apps/media/radarr/app/helmrelease.yaml

# Validate single kustomization
kustomize build kubernetes/apps/media/radarr | kubeconform -
```

## Security Notes
- All secrets use SOPS encryption with Age keys
- Never commit unencrypted secrets
- Age public key is in config.yaml, private key is in age.key (gitignored)
- Always run `task configure` after editing config.yaml to re-encrypt secrets

## Best Practices for Agents

1. **Always validate before proposing changes** - Run kubeconform and kustomize build
2. **Never modify secrets directly** - Use SOPS encryption workflow
3. **Use dry-run modes** - Test commands with `--dry-run` flag when available
4. **Document all changes** - Explain the reasoning in PR descriptions
5. **Respect timeouts** - Some operations take time; don't cancel prematurely
6. **Check for existing workflows** - Review `.github/workflows/` before adding new validation
7. **Test locally when possible** - Use local kustomize/kubeconform instead of cluster access
8. **Flag validation warnings** - Include output of validation commands in PR description
9. **Summarize impact** - Explain changes made and their impact on the cluster

## Common Pitfalls

- **DON'T** run `task kubernetes:reconcile` without human approval - it affects the live cluster
- **DON'T** commit unencrypted secrets - always use SOPS
- **DON'T** modify files in `kubernetes/bootstrap/flux/` without understanding Flux bootstrap process
- **DON'T** change `.sops.yaml` without verifying age key compatibility
- **DO** use the existing kubeconform script instead of reinventing validation
- **DO** respect the load restrictor settings in kustomize commands
- **DO** test changes against the validation workflow before merging

---

# Agent Workflow Guide

This document provides a systematic approach for AI agents working with this Kubernetes cluster repository. It's based on successful troubleshooting and implementation patterns.

---

## Table of Contents

1. [Initial Assessment](#initial-assessment)
2. [Diagnostic Workflow](#diagnostic-workflow)
3. [Implementation Pattern](#implementation-pattern)
4. [Validation Steps](#validation-steps)
5. [Best Practices](#best-practices)
6. [Common Pitfalls](#common-pitfalls)

---

## Initial Assessment

### 1. Understand the Problem Statement

**What to do:**
- Read the user's request carefully
- Identify the specific component or service mentioned
- Determine if this is a bug fix, new feature, or configuration change

**Example from this session:**
```
User: "Hey I'm seeing this error for the external-dns..."
→ Component: external-dns
→ Type: Bug fix
→ Namespace: network (inferred from context)
```

### 2. Gather Context

**Check these resources in order:**

```bash
# 1. Get pod status
kubectl --kubeconfig kubeconfig -n <namespace> get pods -l app.kubernetes.io/name=<app>

# 2. Check pod events
kubectl --kubeconfig kubeconfig -n <namespace> describe pod <pod-name> | grep -A 10 "Events:"

# 3. Check container logs
kubectl --kubeconfig kubeconfig -n <namespace> logs <pod-name> -c <container-name> --tail=50

# 4. Check HelmRelease status
kubectl --kubeconfig kubeconfig -n <namespace> get helmrelease <name> -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'
```

**Key questions to answer:**
- Is the pod running? (READY column)
- Are there multiple containers? (0/1, 0/2, etc.)
- What's the actual error message?
- Is this a new deployment or existing one with issues?

---

## Diagnostic Workflow

### Phase 1: Identify the Root Cause

#### Step 1: Check Pod Status

```bash
kubectl --kubeconfig kubeconfig -n <namespace> get pods -l <label-selector>
```

**Status indicators:**
- `CreateContainerConfigError` → Secret or ConfigMap missing
- `CrashLoopBackOff` → Application startup failure
- `ImagePullBackOff` → Image not found or registry auth issue
- `Pending` → Resource constraints or scheduling issues

#### Step 2: Examine Error Messages

```bash
# For pod events
kubectl --kubeconfig kubeconfig -n <namespace> describe pod <pod-name>

# For container logs
kubectl --kubeconfig kubeconfig -n <namespace> logs <pod-name> -c <container-name>
```

**In our case:**
```
Error: secret "external-dns-secret" not found
```
→ This immediately told us there's a secret mismatch

#### Step 3: Verify Configuration

```bash
# Check what the pod is trying to reference
kubectl --kubeconfig kubeconfig -n <namespace> get deployment <name> -o yaml | grep -A 10 "secret"

# Check what secrets actually exist
kubectl --kubeconfig kubeconfig -n <namespace> get secrets | grep <keyword>

# Check the HelmRelease values
kubectl --kubeconfig kubeconfig -n <namespace> get helmrelease <name> -o yaml
```

**What we discovered:**
- Pod was looking for `external-dns-secret`
- ExternalSecret was creating `adguard-dns-secret`
- HelmRelease referenced `adguard-dns-secret` correctly
- Conclusion: Helm release had stale deployment with old secret name

#### Step 4: Check for Stale Resources

```bash
# Check ReplicaSets to see if old configuration exists
kubectl --kubeconfig kubeconfig -n <namespace> get rs -l app.kubernetes.io/instance=<name> --sort-by=.metadata.creationTimestamp

# Check Helm release history
helm --kubeconfig kubeconfig -n <namespace> list
helm --kubeconfig kubeconfig -n <namespace> history <release-name>
```

### Phase 2: Research External Dependencies

When working with third-party providers or webhooks:

#### Check Provider Documentation

**Example: AdGuard Home webhook provider**

```bash
# Use GitHub search to understand configuration
github_repo --repo muhlba91/external-dns-provider-adguard --query "configuration environment variables TLS"
```

**Key findings:**
- Available environment variables: `ADGUARD_URL`, `ADGUARD_USER`, `ADGUARD_PASSWORD`, `DRY_RUN`, `ADGUARD_SET_IMPORTANT_FLAG`
- **No TLS skip verification option available** (important limitation)
- URL must include scheme (http:// or https://)

#### Understand Error Messages

When encountering errors like:
```
tls: failed to verify certificate: x509: cannot validate certificate for 192.168.5.2
```

**Analysis steps:**
1. Is this a TLS certificate issue? ✓
2. Can we skip TLS verification? ✗ (not supported by provider)
3. Can we use HTTP instead? ✓ (AdGuard supports HTTP API)
4. What's the proper URL format? → `http://<ip>:<port>`

---

## Implementation Pattern

### 1. Make Incremental Changes

**Don't try to fix everything at once.** Make one change, test, observe, repeat.

#### Example progression from our session:

```
Change 1: Add `env: []` to clear stale environment variables
├─ Commit: "fix(external-dns): clear stale Cloudflare env vars"
├─ Test: Reconcile HelmRelease
└─ Result: Still failing (but different error)

Change 2: Update Bitwarden secret to use http:// with port
├─ Action: Force ExternalSecret sync
├─ Test: Check secret value
└─ Result: Webhook now connects but wrong source type

Change 3: Change sources from gateway-httproute to ingress
├─ Commit: "fix(external-dns): watch ingress resources"
├─ Test: Reconcile and check logs
└─ Result: ✓ Working! Records being synced
```

### 2. File Editing Best Practices

#### Always Include Context

When using `replace_string_in_file`, include 3-5 lines before and after:

```yaml
# BAD - Not enough context
oldString: "sources:\n  - gateway-httproute"

# GOOD - Clear, unambiguous
oldString: |
  registry: txt
  sources:
    - gateway-httproute
    - service
  triggerLoopOnEvent: true
```

#### Verify Before Committing

```bash
# Check what changed
git diff <file-path>

# Validate YAML syntax
kustomize build <path> --load-restrictor=LoadRestrictionsNone
```

### 3. Git Workflow

```bash
# Make atomic commits
git add <specific-files>
git commit -m "fix(component): describe what and why"

# Push to trigger Flux
git push

# Force reconciliation (optional, Flux will sync automatically)
flux --namespace <namespace> reconcile helmrelease <name> --kubeconfig kubeconfig
```

**Commit message format:**
```
<type>(<scope>): <subject>

Types: fix, feat, chore, docs
Scope: Component name (external-dns, gatus, etc.)
Subject: Imperative mood, lowercase, no period
```

---

## Validation Steps

### 1. Check Pod Health

```bash
# Pod should show all containers ready
kubectl --kubeconfig kubeconfig -n <namespace> get pods -l <selector>
# Expected: 2/2 Running (or 1/1, 3/3 depending on containers)
```

### 2. Verify Logs

```bash
# Check main application logs
kubectl --kubeconfig kubeconfig -n <namespace> logs -l <selector> -c <container>

# Look for success indicators
# ✓ "All records are already up to date"
# ✓ "retrieved status: {Version:... Running:true}"
# ✓ "successfully connected"

# Look for errors
# ✗ "failed to", "error", "unable to"
```

### 3. Test Functionality

**For DNS providers (external-dns):**

```bash
# Check what records are being managed
kubectl logs <pod> -c webhook | grep "found rule" | grep " IN A "

# Verify against expected ingresses
kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[0].host}{"\n"}{end}'
```

**For monitoring (gatus):**

```bash
# Check if endpoints are being monitored
kubectl logs <pod> -c app | grep -E "(endpoint|check|status)"

# Verify configuration was loaded
kubectl logs <pod> -c init-config
```

### 4. End-to-End Verification

Ask the user to verify the final result:
```
"Can you verify that the ingress is properly pushing DNS records to AdGuard?"
"Can you check if you see the changes in the custom filtering rules?"
```

---

## Best Practices

### 1. Safety First

**Always respect agent policies:**

```yaml
# From .github/agent-config.yaml
forbidden_actions:
  - apply_to_cluster
  - edit_secrets
  - push_secrets

requires_human_approval:
  - task kubernetes:reconcile
  - task kubernetes:apply-ks
  - sops --encrypt
```

**Use dry-run when available:**
```bash
# Prefer this
flux build ks <name> --kustomization-file <file> --dry-run

# Over this
task kubernetes:apply-ks PATH=<path>  # Requires human approval
```

### 2. Work With the System

**Leverage existing tools:**
- `task` commands for common operations
- `flux` CLI for GitOps operations
- `kubectl` for direct cluster access
- Existing validation scripts (e.g., `./scripts/kubeconform.sh`)

**Don't reinvent:**
```bash
# Use the existing validation
bash ./scripts/kubeconform.sh ./kubernetes

# Don't create new validation from scratch
```

### 3. Document Your Findings

When you discover something important:

```bash
# Add comments to configuration files
env: []  # Clear any existing env vars from previous Cloudflare config

# Update README or docs if needed
# Create GitHub issues for limitations found
```

### 4. Clean Up After Yourself

**If you create test resources:**
```bash
# Always clean up
kubectl delete pod <test-pod>
flux suspend helmrelease <name>  # If testing
```

**If a deployment fails:**
```bash
# Don't leave it in a broken state
flux suspend helmrelease <name>
# Fix the issue
flux resume helmrelease <name>
```

---

## Common Pitfalls

### 1. Secret Mismatches

**Problem:** Pod references a secret that doesn't exist or has the wrong name.

**Detection:**
```
Error: secret "xyz" not found
Status: CreateContainerConfigError
```

**Solution:**
1. Check what secret the pod is looking for
2. Check what secrets actually exist
3. Verify ExternalSecret configuration
4. Force ExternalSecret refresh if needed

```bash
kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite
```

### 2. Stale Helm Deployments

**Problem:** HelmRelease updated but deployment still uses old configuration.

**Detection:**
```bash
helm list  # Shows old release
kubectl get helmrelease  # Shows InstallFailed or UpgradeFailed
```

**Solution:**
```bash
# Suspend, uninstall, resume
flux suspend helmrelease <name>
helm uninstall <name>
flux resume helmrelease <name>
```

### 3. Wrong Source Configuration

**Problem:** Service is configured to watch the wrong resource type.

**Example:** external-dns watching `gateway-httproute` when you have Ingress resources.

**Detection:**
- Service reports "All records up to date"
- But no records are actually being created
- Check the `sources:` configuration

**Solution:**
```yaml
sources:
  - ingress     # Change from gateway-httproute
  - service
```

### 4. Missing URL Schemes

**Problem:** URLs missing `http://` or `https://` prefix.

**Detection:**
```
unsupported protocol scheme ""
Get "192.168.5.2/control/status": unsupported protocol scheme
```

**Solution:**
- Add the scheme: `http://192.168.5.2:8083`
- Update in Bitwarden or ExternalSecret template
- Force secret refresh

### 5. TLS Certificate Issues with Self-Signed Certs

**Problem:** Service can't verify TLS certificates for internal services.

**Detection:**
```
tls: failed to verify certificate: x509: cannot validate certificate
```

**Solution Options:**
1. Check if provider supports `insecure` or `skipTLSVerify` flag
2. Use HTTP instead if supported
3. Add proper certificates with IP SANs
4. Use a reverse proxy with proper TLS termination

### 6. Configuration Not Applied

**Problem:** Made changes but pod still has old configuration.

**Common causes:**
- Didn't commit and push changes
- Flux hasn't synced yet
- HelmRelease failed to upgrade
- Pod hasn't restarted

**Solution:**
```bash
# 1. Verify changes are committed
git log --oneline -1

# 2. Force Flux to reconcile
flux reconcile kustomization cluster --with-source

# 3. Force HelmRelease to upgrade
flux reconcile helmrelease <name>

# 4. Force pod restart (if needed)
kubectl delete pod <pod-name>
```

---

## Advanced Debugging

### Enable Debug Logging

Many applications support debug logging via environment variables:

```yaml
env:
  - name: LOG_LEVEL
    value: debug
```

### Check Multiple Containers

For pods with sidecars:

```bash
# List all containers
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].name}'

# Check each container
kubectl logs <pod> -c <container-name>
```

### Inspect Applied Resources

```bash
# See what's actually running
kubectl get deployment <name> -o yaml

# Compare with desired state
kubectl get helmrelease <name> -o yaml
```

### Network Troubleshooting

```bash
# Check if service can reach external API
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- curl -v http://192.168.5.2:8083/control/status
```

---

## Example: Complete Troubleshooting Session

Here's the complete flow from our external-dns troubleshooting:

```
1. ASSESS
   ├─ User reports: "Error: secret 'external-dns-secret' not found"
   ├─ Component: external-dns in network namespace
   └─ Type: Configuration issue

2. DIAGNOSE
   ├─ Check pod status: CreateContainerConfigError
   ├─ Check deployment: References "external-dns-secret"
   ├─ Check secrets: Only "adguard-dns-secret" exists
   ├─ Check HelmRelease: References "adguard-dns-secret" (correct)
   └─ Conclusion: Stale deployment with old config

3. FIX #1: Clear stale environment variables
   ├─ Add `env: []` to HelmRelease
   ├─ Commit and reconcile
   └─ Result: Different error (progress!)

4. DIAGNOSE #2
   ├─ New error: TLS certificate validation failure
   ├─ Research: Check provider documentation
   └─ Finding: No TLS skip option, but HTTP supported

5. FIX #2: Update secret to use HTTP
   ├─ User updates Bitwarden: http://192.168.5.2:8083
   ├─ Force ExternalSecret refresh
   └─ Result: Webhook connects successfully!

6. DIAGNOSE #3
   ├─ Pods running but no DNS records created
   ├─ Check logs: "All records are already up to date"
   ├─ Check sources: Watching "gateway-httproute"
   ├─ Check cluster: Has Ingress resources, not Gateway API
   └─ Conclusion: Wrong source type

7. FIX #3: Change source type
   ├─ Update sources: gateway-httproute → ingress
   ├─ Commit and reconcile
   └─ Result: ✓ DNS records being synced!

8. VALIDATE
   ├─ Check pod: 2/2 Running
   ├─ Check logs: "found rule" entries for all ingresses
   ├─ User confirms: Sees records in AdGuard
   └─ Success! ✓

9. DOCUMENT
   └─ Create this AGENTS.md file
```

---

## Quick Reference Commands

### Most Common Checks

```bash
# Pod status
kubectl --kubeconfig kubeconfig -n <ns> get pods -l app.kubernetes.io/name=<app>

# Pod logs
kubectl --kubeconfig kubeconfig -n <ns> logs -l app.kubernetes.io/name=<app> --tail=50

# HelmRelease status
kubectl --kubeconfig kubeconfig -n <ns> get hr <name> -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'

# Force reconciliation
flux --namespace <ns> reconcile helmrelease <name> --kubeconfig kubeconfig

# Check secrets
kubectl --kubeconfig kubeconfig -n <ns> get secrets | grep <keyword>

# View secret value
kubectl --kubeconfig kubeconfig -n <ns> get secret <name> -o jsonpath='{.data.<key>}' | base64 -d
```

### Useful Filters

```bash
# Get all ingress hosts
kubectl --kubeconfig kubeconfig get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[0].host}{"\n"}{end}' | sort

# Get pods not running
kubectl --kubeconfig kubeconfig get pods -A | grep -v Running

# Check for failing HelmReleases
kubectl --kubeconfig kubeconfig get hr -A | grep False
```

---

## Conclusion

The key to successful troubleshooting:

1. **Understand before acting** - Gather context, don't guess
2. **Make incremental changes** - One fix at a time
3. **Validate each step** - Don't assume it worked
4. **Document findings** - Help future agents (and humans)
5. **Respect boundaries** - Follow agent policies strictly

Remember: This is a production cluster. Every change should be:
- ✓ Tested locally when possible
- ✓ Committed with clear messages
- ✓ Validated after deployment
- ✓ Rolled back if issues arise

Good luck, fellow agent! 🤖
