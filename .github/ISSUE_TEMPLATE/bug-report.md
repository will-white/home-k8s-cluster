---
name: 🐛 Bug Report
about: Report a bug or issue with the cluster or applications
title: '[BUG] '
labels: ['bug']
assignees: []

---

## Bug Description

<!-- A clear and concise description of the bug -->

## Affected Component

**Type**: <!-- Application / Infrastructure / CI/CD / Documentation -->
**Namespace**: <!-- If applicable -->
**Application**: <!-- If applicable -->

## Current Behavior

<!-- What is currently happening? -->

## Expected Behavior

<!-- What should be happening? -->

## Steps to Reproduce

1. 
2. 
3. 

## Environment

**Branch/Commit**: 
**Last Known Working**: <!-- If known -->

## Logs/Errors

<!-- Paste relevant logs, error messages, or kubectl output -->

```
# Paste logs here
```

## Agent Investigation Checklist

For AI agents investigating this issue:

- [ ] Check application logs: `kubectl logs -n <namespace> <pod>`
- [ ] Check pod status: `kubectl describe pod -n <namespace> <pod>`
- [ ] Check events: `kubectl get events -n <namespace>`
- [ ] Check HelmRelease status: `flux get helmreleases -n <namespace>`
- [ ] Check Kustomization status: `flux get kustomizations -A`
- [ ] Review recent commits for changes
- [ ] Check dependency status (see .agent-hints/dependency-map.md)
- [ ] Consult .agent-hints/troubleshooting.md for known issues
- [ ] Validate manifests: `./scripts/validate-app.sh <namespace> <app>`

## Possible Solution

<!-- If you have suggestions on how to fix this -->

## Additional Context

<!-- Any other relevant information -->
