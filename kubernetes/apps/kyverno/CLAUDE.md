# kyverno — domain guide (`@infra-agent`)

Loaded automatically for work under `kubernetes/apps/kyverno/`. Kyverno audits
the repo's own conventions; it does not enforce anything yet.

## Policies (`policies/app/`)

| Policy | Rule it encodes |
|---|---|
| `require-resources` | `resources.requests` and `limits.memory` on every container |
| `disallow-cpu-limits` | No CPU limits anywhere |
| `disallow-latest-tag` | No `:latest` (Renovate pins digests) |
| `require-image-digest` | Image references carry a `@sha256` digest |

All are `validate.failureAction: Audit` with `features.forceFailurePolicyIgnore`
so a Kyverno outage can never block admissions.

## Conventions

- A new convention worth auditing gets a `ClusterPolicy` here **and** a line
  in root `CLAUDE.md`; the policy is the check, the doc is the rule.
- Keep `kubectl get policyreport -A` clean: fix the workload, do not add an
  exclusion unless the exception is documented in the policy itself.
- Graduating a policy to `Enforce` is a backlog item
  ([docs/backlog.md](../../../docs/backlog.md)): only after the reports are
  clean, one policy at a time, with `forceFailurePolicyIgnore` dropped last.

## Validate

```bash
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/kyverno/policies/app | kubeconform -strict -ignore-missing-schemas -
kubectl get policyreport -A          # read-only
```
