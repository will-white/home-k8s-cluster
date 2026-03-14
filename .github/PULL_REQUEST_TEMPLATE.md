# Pull Request

## Description

<!-- Provide a clear description of what this PR does -->

## Type of Change

<!-- Mark relevant options with an [x] -->

- [ ] 🚀 New application deployment
- [ ] 🔧 Application configuration update
- [ ] 🏗️ Infrastructure change
- [ ] 📚 Documentation update
- [ ] 🐛 Bug fix
- [ ] 🤖 Agent workflow improvement
- [ ] 🔒 Security update

## Changes

<!-- List the specific changes made -->

- 
- 
-

## Related Issues

<!-- Link any related issues -->

Closes #
Related to #

## Testing & Validation

### Pre-commit Checks

- [ ] Ran `./scripts/validate-before-commit.sh` successfully
- [ ] No YAML linting errors
- [ ] All kubeconform validation passed
- [ ] No unencrypted secrets detected

### Application-Specific

- [ ] Ran `./scripts/validate-app.sh <namespace> <app>` (if applicable)
- [ ] Tested with `flux build ks --dry-run` (if cluster access available)
- [ ] Verified all dependencies are available
- [ ] Checked resource requests/limits are set

### Code Review

- [ ] Requested code review via `code_review` tool (for agents)
- [ ] Addressed all review comments
- [ ] Ran security scanner (codeql_checker for code changes)

## Documentation

- [ ] Updated relevant documentation (QUICK_START.md, CONVENTIONS.md, etc.)
- [ ] Added inline comments for complex configurations
- [ ] Updated .agent-hints if workflow changed
- [ ] Added app README if new application

## Agent Workflow Compliance

<!-- For AI agents - verify compliance with agent policies -->

- [ ] Followed naming conventions from CONVENTIONS.md
- [ ] Respected agent boundaries from AGENTS.md
- [ ] Used approved patterns from templates
- [ ] No forbidden actions from agent-config.yaml
- [ ] Obtained approval for restricted operations (if any)

## Breaking Changes

<!-- List any breaking changes and migration steps -->

- [ ] No breaking changes
- [ ] Breaking changes documented below:

<!-- If breaking changes exist, describe them and provide migration guide -->

## Rollback Plan

<!-- How can this change be reverted if needed? -->

## Screenshots

<!-- If applicable, add screenshots showing the changes -->

## Checklist for Reviewers

- [ ] Changes follow repository conventions
- [ ] No security vulnerabilities introduced
- [ ] Documentation is adequate
- [ ] Tests pass (if applicable)
- [ ] Resource limits are appropriate
- [ ] Dependencies are properly declared

## Additional Notes

<!-- Any other information relevant to this PR -->

---

**Agent Submission**: <!-- Yes/No - was this PR created by an AI agent? -->
**Review Required**: <!-- Yes/No/Urgent -->
