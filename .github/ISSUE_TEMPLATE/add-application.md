---
name: 🚀 Add New Application
about: Request to add a new application to the cluster
title: '[APP] Add <application-name>'
labels: ['enhancement', 'new-app']
assignees: []

---

## Application Information

**Application Name**: 
**Namespace**: <!-- e.g., media, default, database -->
**Helm Chart**: <!-- e.g., bjw-s/app-template, link to chart -->
**Chart Version**: 

## Purpose

<!-- Describe what this application does and why it's needed -->

## Configuration Requirements

**Storage Needed**: <!-- Yes/No, if yes specify size -->
**External Secrets**: <!-- Yes/No, if yes list required secrets -->
**Ingress Required**: <!-- Yes/No, if yes internal or external -->
**Dependencies**: <!-- List any other apps this depends on -->

## Resources

**Helm Chart Repository**: <!-- URL to Helm chart repo -->
**Documentation**: <!-- Links to app documentation -->
**Similar Apps**: <!-- Any similar apps already in cluster for reference -->

## Agent Checklist

For AI agents implementing this request:

- [ ] Search for chart on https://kubesearch.dev
- [ ] Ask user to confirm namespace if not specified above
- [ ] Use `./scripts/generate-app-scaffold.sh <app-name> <namespace>` to create structure
- [ ] Configure HelmRelease with appropriate values
- [ ] Add ExternalSecret if secrets needed
- [ ] Add PVC if storage needed
- [ ] Configure Ingress if external access needed
- [ ] Add ServiceMonitor if app exposes metrics
- [ ] Update namespace kustomization.yaml
- [ ] Validate with `./scripts/validate-app.sh <namespace> <app-name>`
- [ ] Run `./scripts/validate-before-commit.sh`
- [ ] Document any special configuration in app README

## Additional Notes

<!-- Any other relevant information -->
