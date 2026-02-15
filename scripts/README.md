# Scripts Directory

This directory contains helper scripts for managing the Kubernetes cluster repository.

## Available Scripts

### 🔍 Validation Scripts

#### `validate-before-commit.sh`
Pre-commit validation suite that checks:
- Required tools availability
- Unencrypted secrets (with smart detection)
- YAML syntax
- Kubernetes manifest validation
- Common issues (latest tags, missing limits, etc.)

**Usage:**
```bash
./scripts/validate-before-commit.sh
```

**Exit Codes:**
- `0`: All checks passed
- `1`: One or more checks failed

---

#### `validate-app.sh`
Validate a single application in isolation.

**Usage:**
```bash
./scripts/validate-app.sh <namespace> <app-name>

# Example
./scripts/validate-app.sh media bazarr
```

**What it checks:**
- Required files present
- YAML syntax
- Kustomize build
- Kubeconform validation
- Common issues
- Flux dry-run (if available)

---

### 🏗️ Scaffolding Scripts

#### `generate-app-scaffold.sh`
Generate a new application structure from template with placeholders replaced.

**Usage:**
```bash
./scripts/generate-app-scaffold.sh <app-name> <namespace> [chart-name] [chart-version] [repo-name]

# Basic usage (uses app-template defaults)
./scripts/generate-app-scaffold.sh bazarr media

# Full usage
./scripts/generate-app-scaffold.sh bazarr media app-template 3.7.3 bjw-s
```

**What it creates:**
```
kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml
└── app/
    ├── helmrelease.yaml
    ├── kustomization.yaml
    ├── externalsecret.yaml
    ├── pvc.yaml
    ├── configmap.yaml
    ├── servicemonitor.yaml
    └── networkpolicy.yaml
```

**Next steps after generation:**
1. Edit `app/helmrelease.yaml` with your configuration
2. Remove unused optional files
3. Update `app/kustomization.yaml` to reference only needed files
4. Add to namespace kustomization
5. Validate with `validate-app.sh`

---

### 📊 Utility Scripts

#### `generate-repo-map.sh`
Generate a visual map of the repository structure.

**Usage:**
```bash
./scripts/generate-repo-map.sh > REPO_MAP.md
```

**Output includes:**
- Namespaces and applications inventory
- Helm repositories
- Storage classes (if cluster access available)
- Directory structure
- Statistics

---

#### `kubeconform.sh`
Run kubeconform validation on all Kubernetes manifests.

**Usage:**
```bash
bash scripts/kubeconform.sh kubernetes/
```

**Note:** Typically called via `task kubernetes:kubeconform`

---

## Workflow Examples

### Adding a New Application

```bash
# 1. Generate scaffold
./scripts/generate-app-scaffold.sh myapp media

# 2. Edit configuration
vim kubernetes/apps/media/myapp/app/helmrelease.yaml

# 3. Validate
./scripts/validate-app.sh media myapp

# 4. Pre-commit check
./scripts/validate-before-commit.sh

# 5. Commit (using report_progress for agents)
git add .
git commit -m "feat(apps): add myapp to media namespace"
```

### Updating an Existing Application

```bash
# 1. Find and edit
vim kubernetes/apps/media/bazarr/app/helmrelease.yaml

# 2. Validate
./scripts/validate-app.sh media bazarr

# 3. Pre-commit check
./scripts/validate-before-commit.sh

# 4. Commit
git add .
git commit -m "chore(apps): update bazarr to v1.2.3"
```

### Full Repository Validation

```bash
# Run all validation
./scripts/validate-before-commit.sh

# Or use task
task kubernetes:kubeconform
```

## Integration with Other Tools

### With Task

These scripts are integrated into the Taskfile:

```bash
# Validation
task kubernetes:kubeconform

# Get resources
task kubernetes:resources
```

### With Make

Convenience wrappers available:

```bash
# Validation
make validate

# Specific app
make validate-app NAMESPACE=media APP=bazarr

# Generate scaffold
make scaffold APP=myapp NAMESPACE=media
```

### With Pre-commit

Scripts can be integrated into pre-commit hooks:

```bash
# Install pre-commit
pip install pre-commit
pre-commit install

# Run manually
pre-commit run --all-files
```

## Requirements

### Required Tools

- `bash` - Shell interpreter
- `kustomize` - Kubernetes manifest processor
- `kubeconform` - Kubernetes validator

### Optional Tools

- `task` - Task runner (recommended)
- `yamllint` - YAML linting
- `flux` - GitOps toolkit (for dry-run)
- `kubectl` - Kubernetes CLI (for cluster operations)
- `yq` - YAML processor

### Installing Tools

**macOS (Homebrew):**
```bash
brew install task flux kubectl kustomize kubeconform yamllint yq
```

**Linux:**
```bash
# See individual tool documentation
# Most available via package managers or direct download
```

## Troubleshooting

### Script Not Found
```bash
# Make scripts executable
chmod +x scripts/*.sh
```

### Tool Not Found
```bash
# Check if tool is installed
which kustomize

# Install missing tools
brew install kustomize  # macOS
```

### Validation Fails
```bash
# Get detailed output
bash -x ./scripts/validate-app.sh media myapp

# Check specific validation
kustomize build kubernetes/apps/media/myapp | kubeconform -strict -verbose -
```

### Permission Denied
```bash
# Make script executable
chmod +x scripts/validate-app.sh
```

## Contributing

When adding new scripts:

1. **Follow naming convention**: `verb-noun.sh`
2. **Add help/usage**: Include usage instructions in header
3. **Make executable**: `chmod +x script-name.sh`
4. **Document here**: Add to this README
5. **Add to Makefile**: Add convenience wrapper if appropriate
6. **Test**: Verify script works in clean environment

## See Also

- [QUICK_START.md](../QUICK_START.md) - Using scripts in workflows
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution guidelines
- [.agent-hints/common-tasks.md](../.agent-hints/common-tasks.md) - Command reference
- [Makefile](../Makefile) - Convenience wrappers
