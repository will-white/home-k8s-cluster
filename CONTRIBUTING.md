# Contributing to home-k8s-cluster

Thank you for contributing! This guide will help you get started whether you're a human developer or an AI agent.

## 🚀 Quick Start

### For Humans

1. **Read the Documentation**
   - [README.md](./README.md) - Repository overview
   - [QUICK_START.md](./QUICK_START.md) - Step-by-step guides
   - [CONVENTIONS.md](./CONVENTIONS.md) - Standards and patterns
   - [AGENTS.md](./AGENTS.md) - Agent roles and guidelines

2. **Set Up Your Environment**
   ```bash
   # Install required tools
   brew install task flux kubectl kustomize kubeconform yamllint
   
   # Install pre-commit hooks (optional but recommended)
   pip install pre-commit
   pre-commit install
   ```

3. **Validate Your Changes**
   ```bash
   # Before committing
   ./scripts/validate-before-commit.sh
   
   # Test a specific app
   ./scripts/validate-app.sh <namespace> <app>
   ```

### For AI Agents

1. **Understand Your Role**
   - Read [AGENTS.md](./AGENTS.md) for persona-specific guidelines
   - Check [.github/agent-config.yaml](./.github/agent-config.yaml) for policies
   - Review [.agent-hints/](./.agent-hints/) for quick references

2. **Follow the Workflow**
   - Use templates from `kubernetes/templates/app-scaffold/`
   - Run validation scripts before committing
   - Consult `.agent-hints/troubleshooting.md` for common errors
   - Use `report_progress` tool to commit changes

3. **Key Resources**
   - [.agent-hints/common-tasks.md](./.agent-hints/common-tasks.md) - Command reference
   - [.agent-hints/dependency-map.md](./.agent-hints/dependency-map.md) - Cluster relationships
   - [QUICK_START.md](./QUICK_START.md) - Detailed workflows

## 📋 Contribution Types

### Adding a New Application

1. **Search for the Helm chart**
   - Visit https://kubesearch.dev
   - Find the chart and note repository/version

2. **Generate scaffold**
   ```bash
   ./scripts/generate-app-scaffold.sh <app-name> <namespace>
   ```

3. **Configure the application**
   - Edit `kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml`
   - Add secrets with ExternalSecret if needed
   - Configure storage, ingress, monitoring as needed

4. **Update namespace kustomization**
   ```bash
   # Edit kubernetes/apps/<namespace>/kustomization.yaml
   # Add: - ./<app>/ks.yaml
   ```

5. **Validate**
   ```bash
   ./scripts/validate-app.sh <namespace> <app>
   ./scripts/validate-before-commit.sh
   ```

See [QUICK_START.md](./QUICK_START.md#1-adding-a-new-application) for detailed instructions.

### Updating an Application

1. **Locate the application**
   ```bash
   find kubernetes/apps -name "<app-name>" -type d
   ```

2. **Make changes**
   - Update version in `app/helmrelease.yaml`
   - Modify values as needed

3. **Validate**
   ```bash
   ./scripts/validate-app.sh <namespace> <app>
   ```

### Infrastructure Changes

⚠️ **WARNING**: Infrastructure changes can affect the entire cluster.

- **Requires**: @infra-agent role (see [AGENTS.md](./AGENTS.md))
- **Scope**: `kubernetes/flux/`, `kubernetes/bootstrap/`, core services
- **Validation**: Extra scrutiny on dependencies
- **Testing**: Must test with dry-run before applying

See [.agent-hints/dependency-map.md](./.agent-hints/dependency-map.md) for impact analysis.

### Documentation Updates

1. **Identify affected files**
   - README.md, QUICK_START.md, CONVENTIONS.md
   - .agent-hints/* for reference materials
   - Inline documentation in templates

2. **Ensure consistency**
   - Check cross-references
   - Validate code examples
   - Update related documentation

3. **Validate**
   ```bash
   # Check for broken links (if link checker installed)
   markdown-link-check *.md
   
   # Validate YAML examples
   yamllint <file>
   ```

## 🔒 Security Guidelines

### Secrets Management

**DO:**
- ✅ Use ExternalSecret for all sensitive data
- ✅ Encrypt with SOPS if ExternalSecret not suitable (requires approval)
- ✅ Reference secrets in Bitwarden Secrets Manager
- ✅ Validate encryption with `./scripts/validate-before-commit.sh`

**DON'T:**
- ❌ Commit plain Kubernetes Secrets
- ❌ Include credentials in code or comments
- ❌ Share secrets in PR descriptions or commits
- ❌ Disable secret scanning checks

### Validation Requirements

All changes MUST pass:

1. **YAML Linting**
   ```bash
   yamllint kubernetes/
   ```

2. **Kubernetes Validation**
   ```bash
   task kubernetes:kubeconform
   ```

3. **Secret Scanning**
   - Automated by `validate-before-commit.sh`
   - Also checked in pre-commit hooks

## 🎯 Best Practices

### Code Quality

- **Use templates**: Start with `kubernetes/templates/app-scaffold/`
- **Follow conventions**: See [CONVENTIONS.md](./CONVENTIONS.md)
- **Pin versions**: Use specific versions with SHA256 for container images
- **Set limits**: Always define resource requests and limits
- **Add monitoring**: Include ServiceMonitor if app has metrics
- **Document**: Add inline comments for complex configurations

### Git Workflow

1. **Create feature branch**
   ```bash
   git checkout -b feature/add-app-name
   ```

2. **Make small commits**
   - Use conventional commit messages
   - One logical change per commit

3. **Validate before pushing**
   ```bash
   ./scripts/validate-before-commit.sh
   ```

4. **Create pull request**
   - Fill out PR template completely
   - Link related issues
   - Request review

### Commit Message Format

Use conventional commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature or application
- `fix`: Bug fix
- `docs`: Documentation changes
- `chore`: Maintenance tasks
- `refactor`: Code refactoring
- `test`: Test changes
- `ci`: CI/CD changes

**Examples:**
```
feat(apps): add bazarr to media namespace
fix(apps): correct home-assistant resource limits
docs: update QUICK_START with new validation script
chore(deps): update kube-prometheus-stack to 55.0.0
```

## 🤖 Agent-Specific Guidelines

### Agent Personas

Different agents have different scopes:

- **@app-agent**: `kubernetes/apps/` - Application deployments
- **@infra-agent**: `kubernetes/flux/`, `kubernetes/bootstrap/` - Infrastructure
- **@test-agent**: CI/CD, validation scripts
- **@ops-agent**: Cluster operations, secrets (requires approval)

See [AGENTS.md](./AGENTS.md) for detailed boundaries.

### Required Actions for Agents

**Before Making Changes:**
- [ ] Read AGENTS.md for role boundaries
- [ ] Check agent-config.yaml for policies
- [ ] Review CONVENTIONS.md for standards
- [ ] Consult .agent-hints/ for guidance

**When Adding Applications:**
- [ ] ALWAYS ask user for namespace (never assume)
- [ ] Search kubesearch.dev for charts
- [ ] Use generate-app-scaffold.sh script
- [ ] Follow naming conventions
- [ ] Validate with scripts

**When Committing:**
- [ ] Use report_progress tool
- [ ] Never use git commands directly
- [ ] Include descriptive commit messages
- [ ] Update documentation if needed

### Forbidden Actions

Agents MUST NOT:
- ❌ Run `kubectl apply` without approval
- ❌ Execute `task kubernetes:reconcile` without approval
- ❌ Modify secrets without using SOPS/ExternalSecret
- ❌ Make changes outside their designated scope
- ❌ Commit unencrypted secrets
- ❌ Use `sudo` commands

## 🧪 Testing

### Local Testing

1. **Validate manifests**
   ```bash
   # Specific app
   kustomize build kubernetes/apps/<namespace>/<app> | kubeconform -strict -
   
   # All apps
   task kubernetes:kubeconform
   ```

2. **Dry-run with Flux** (if cluster access available)
   ```bash
   flux build ks <app> \
     --kustomization-file kubernetes/apps/<namespace>/<app>/ks.yaml \
     --path kubernetes/apps/<namespace>/<app> \
     --dry-run
   ```

3. **Pre-commit validation**
   ```bash
   ./scripts/validate-before-commit.sh
   ```

### CI/CD

Pull requests automatically run:
- Agent validation (policy compliance)
- Kubeconform (manifest validation)
- Flux diff (change preview)

## 📚 Additional Resources

### Documentation
- [QUICK_START.md](./QUICK_START.md) - Step-by-step task guides
- [CONVENTIONS.md](./CONVENTIONS.md) - Repository standards
- [AGENTS.md](./AGENTS.md) - Agent roles and guidelines
- [.agent-hints/common-tasks.md](./.agent-hints/common-tasks.md) - Command reference
- [.agent-hints/dependency-map.md](./.agent-hints/dependency-map.md) - Cluster relationships
- [.agent-hints/troubleshooting.md](./.agent-hints/troubleshooting.md) - Error solutions

### External Resources
- [Flux Documentation](https://fluxcd.io/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [KubeSearch](https://kubesearch.dev/) - Helm chart search
- [bjw-s App Template](https://bjw-s.github.io/helm-charts/docs/app-template/)
- [Home Operations Discord](https://discord.gg/home-operations)

### Tools
- [Task](https://taskfile.dev/) - Task runner
- [Flux](https://fluxcd.io/) - GitOps toolkit
- [SOPS](https://github.com/mozilla/sops) - Secret encryption
- [Kubeconform](https://github.com/yannh/kubeconform) - Kubernetes validation

## 💬 Getting Help

### For Humans

- Open an issue using the appropriate template
- Ask in Home Operations Discord
- Review documentation in `.agent-hints/`

### For Agents

1. **Check documentation first**
   - .agent-hints/troubleshooting.md for errors
   - .agent-hints/common-tasks.md for commands
   - QUICK_START.md for workflows

2. **If stuck**
   - Ask the user for clarification
   - Request approval for restricted operations
   - Document the issue for future improvement

## 📝 Review Process

### For Pull Requests

1. **Automated checks** must pass
   - YAML linting
   - Kubeconform validation
   - Secret scanning
   - Agent policy compliance

2. **Manual review** focuses on
   - Architecture and design
   - Security implications
   - Documentation completeness
   - Best practices compliance

3. **Approval required** for
   - Infrastructure changes
   - Security-sensitive changes
   - Breaking changes

## 🎉 Recognition

Contributors are recognized in:
- Git commit co-authors
- Release notes
- IMPROVEMENTS_SUMMARY.md for significant enhancements

---

**Questions?** Open an issue or consult the documentation in `.agent-hints/`

**Thank you for contributing!** 🚀
