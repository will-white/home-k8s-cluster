# Agent Hints Directory

This directory contains context files to help AI agents work effectively with this Kubernetes cluster repository.

## Files Overview

### `common-tasks.md`
Quick reference for frequent operations:
- Validation commands
- Application management (add, update, delete)
- Discovery commands
- Secrets management
- Git operations
- Cluster operations

**Use when:** You need to quickly look up how to perform a common task.

### `dependency-map.md`
Visual and textual map of cluster dependencies:
- Infrastructure layers
- Application dependencies
- Cross-namespace relationships
- Storage and secret dependencies
- Safe modification order

**Use when:** You need to understand what depends on what, or the impact of a change.

### `troubleshooting.md`
Common errors and their solutions:
- Validation errors
- Kustomize errors
- Secrets errors
- Helm errors
- Dependency errors
- Network errors
- Debug commands

**Use when:** Something isn't working and you need to diagnose the issue.

## How to Use These Files

### For General Tasks
1. Start with `common-tasks.md` for step-by-step commands
2. Reference `../QUICK_START.md` for detailed workflows
3. Check `../CONVENTIONS.md` for naming and structure standards

### For Understanding the Cluster
1. Read `dependency-map.md` to understand relationships
2. Review `../AGENTS.md` for agent roles and boundaries
3. Check `../.github/agent-config.yaml` for policies

### When Things Go Wrong
1. Look up error in `troubleshooting.md`
2. Try suggested solutions
3. Use debug commands to investigate
4. Ask user if still stuck

## Quick Navigation

```
Repository Root
├── AGENTS.md                    ← Agent personas & roles
├── QUICK_START.md              ← Step-by-step guides
├── CONVENTIONS.md              ← Standards & best practices
├── .agent-hints/               ← You are here
│   ├── common-tasks.md         ← Quick command reference
│   ├── dependency-map.md       ← Cluster relationships
│   └── troubleshooting.md      ← Error solutions
├── .github/
│   └── agent-config.yaml       ← Machine-readable policies
├── kubernetes/
│   ├── apps/                   ← Application deployments
│   ├── flux/                   ← Flux configuration
│   ├── templates/              ← Reusable templates
│   │   └── app-scaffold/       ← New app template
│   └── bootstrap/              ← Cluster bootstrap
└── scripts/
    ├── validate-before-commit.sh    ← Pre-commit validation
    ├── validate-app.sh              ← Test single app
    └── generate-app-scaffold.sh     ← Create new app
```

## Related Documentation

- **Primary Guide**: `../QUICK_START.md` - Start here for detailed workflows
- **Standards**: `../CONVENTIONS.md` - Naming, structure, best practices
- **Agent Roles**: `../AGENTS.md` - Specialist agent capabilities
- **Policies**: `../.github/agent-config.yaml` - Security boundaries
- **Templates**: `../kubernetes/templates/` - Starting points for new resources
- **Project Status**: `../TODO.md` - Planned work and priorities

## Tips for Agents

1. **Always read the hints first**: These files are designed to save you time and prevent common mistakes.

2. **Follow the workflows**: Don't try to reinvent the wheel - use established patterns.

3. **Validate early and often**: Use the validation scripts before making commits.

4. **Understand dependencies**: Check the dependency map before modifying infrastructure.

5. **When in doubt, ask**: It's better to ask the user than to make incorrect assumptions.

6. **Use the templates**: The app-scaffold template has all the best practices built in.

7. **Check troubleshooting first**: Many errors have known solutions documented.

## File Update Policy

These files should be updated when:
- New common tasks are identified
- Dependency relationships change
- New error patterns emerge
- Agent feedback suggests improvements

Last Updated: 2026-02-15
