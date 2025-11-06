# Copilot Instructions for Home K8s Cluster

> **Note**: This repository includes machine-parseable agent policies. See [agent-config.yaml](./agent-config.yaml) for the canonical policy configuration and the [agent-validation workflow](./.github/workflows/agent-validation.yml) for automated validation checks.

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

This repository manages a home Kubernetes cluster using Talos Linux, Flux GitOps, and Task automation. The cluster runs on multiple Lenovo Tiny machines with CEPH storage and includes comprehensive monitoring, media services, and infrastructure applications.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

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
# NOTE: Requires bootstrap directory - may not be available in production repository
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
source .venv/bin/activate  # If not using direnv

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

1. **Manifest Changes**: Run `task kubernetes:kubeconform` and verify all 340+ YAML files validate correctly
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

## Repository Structure

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

## Common Tasks

### Working with Applications
The cluster manages 420+ applications across these main categories:
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

## Safe Operations (Allowed for Agents)

Agents can safely perform these operations:

1. **Read repository contents** - Browse files, understand structure
2. **Run local validation** - Execute kubeconform, kustomize build, yamllint
3. **Propose changes** - Open pull requests with suggested modifications
4. **Generate documentation** - Update README files and comments

## Dangerous Operations (Human Approval Required)

The following operations require explicit human approval and should be marked with `HUMAN_APPROVAL_REQUIRED:` prefix:

- **HUMAN_APPROVAL_REQUIRED: task kubernetes:reconcile** - Forces Flux to pull changes from Git
  - Dry-run alternative: `flux diff kustomization cluster --path ./kubernetes`
  
- **HUMAN_APPROVAL_REQUIRED: task kubernetes:apply-ks PATH=<path>** - Applies a Flux Kustomization to the cluster
  - Dry-run alternative: `flux build ks <name> --kustomization-file <file> --path <path> --dry-run`
  
- **HUMAN_APPROVAL_REQUIRED: sops --encrypt** - Encrypts secrets with SOPS
  - Validation alternative: Review the `.sops.yaml` configuration file and verify SOPS config with `sops --config .sops.yaml updatekeys --yes <file>` (Note: SOPS does not support a `--dry-run` flag)

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
