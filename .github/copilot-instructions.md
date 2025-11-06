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

This is a home Kubernetes cluster managed with Flux, Renovate, and GitHub Actions. The cluster runs on Talos Linux and uses SOPS for secret encryption.

## Repository Structure

- `kubernetes/apps/` - Application manifests and Kustomizations
- `kubernetes/flux/` - Flux system configuration
- `kubernetes/bootstrap/` - Bootstrap configuration including Talos patches
- `.taskfiles/` - Task definitions for cluster management
- `scripts/` - Helper scripts including kubeconform validation

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
  - Validation alternative: Verify SOPS config with `sops --config .sops.yaml updatekeys --yes <file> --dry-run` (if supported)

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

### Flux Operations

- Flux automatically syncs changes from the `main` branch
- Use `flux diff` to preview changes before applying
- Test changes in a feature branch before merging to main

## PR Checklist for Agents

When creating or updating a pull request, agents should automatically perform these validation steps:

1. **Run kubeconform validation**
   ```bash
   bash ./scripts/kubeconform.sh ./kubernetes
   ```

2. **Build all affected kustomizations**
   ```bash
   # For each changed kustomization directory
   kustomize build <path> --load-restrictor=LoadRestrictionsNone
   ```

3. **Validate YAML syntax**
   ```bash
   # Check for YAML syntax errors
   find kubernetes/ -name "*.yaml" -type f -exec yamllint {} \;
   ```

4. **Check for unencrypted secrets**
   ```bash
   # Ensure no unencrypted secrets are committed
   git diff --cached --name-only | xargs grep -l "kind: Secret" | while read file; do
     if ! grep -q "sops:" "$file"; then
       echo "WARNING: Unencrypted secret found in $file"
     fi
   done
   ```

5. **Add validation results to PR**
   - Include output of validation commands in PR description
   - Flag any warnings or errors for human review
   - Summarize changes made and their impact

## Environment Variables

Required for cluster operations (DO NOT run without these):

- `KUBECONFIG` - Path to kubeconfig file (default: `./kubeconfig`)
- `SOPS_AGE_KEY_FILE` - Path to SOPS age key file (default: `./age.key`)

## Tools Required

- `flux` - FluxCD CLI
- `kubectl` - Kubernetes CLI
- `kustomize` - Kustomize CLI
- `kubeconform` - Kubernetes manifest validation
- `sops` - Secret encryption
- `task` - Task runner
- `yq` - YAML processor
- `yamllint` - YAML linter (optional)

## Best Practices for Agents

1. **Always validate before proposing changes** - Run kubeconform and kustomize build
2. **Never modify secrets directly** - Use SOPS encryption workflow
3. **Use dry-run modes** - Test commands with `--dry-run` flag when available
4. **Document all changes** - Explain the reasoning in PR descriptions
5. **Respect timeouts** - Some operations take time; don't cancel prematurely
6. **Check for existing workflows** - Review `.github/workflows/` before adding new validation
7. **Test locally when possible** - Use local kustomize/kubeconform instead of cluster access

## Common Pitfalls

- **DON'T** run `task kubernetes:reconcile` without human approval - it affects the live cluster
- **DON'T** commit unencrypted secrets - always use SOPS
- **DON'T** modify files in `kubernetes/bootstrap/flux/` without understanding Flux bootstrap process
- **DON'T** change `.sops.yaml` without verifying age key compatibility
- **DO** use the existing kubeconform script instead of reinventing validation
- **DO** respect the load restrictor settings in kustomize commands
- **DO** test changes against the validation workflow before merging
