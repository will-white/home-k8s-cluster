---
name: validate-app
description: >-
  Run the repo's inner-loop validation for one app (yamllint, kustomize build
  + kubeconform, flux build dry-run, flate render) and read the result. Use
  before proposing any change under kubernetes/apps/<ns>/<app>, when the user
  says "validate", "check", "lint" or "does this render", and after every
  edit to a HelmRelease, Kustomization, ExternalSecret or ks.yaml.
---

# Validate one app

One command, same checks as CI, seconds instead of minutes:

```bash
task kubernetes:validate APP=<ns>/<app>      # e.g. APP=media/sonarr
# or without task:
scripts/validate-app.sh <ns>/<app>
```

It runs, in order: `yamllint` (repo config) → `kustomize build
--load-restrictor=LoadRestrictionsNone` piped into `kubeconform -strict` with
CI's skip list → `flux build ks --dry-run` (skipped without a kubeconfig) →
`flate test` scoped to the app folder (renders the HelmRelease with the real
chart; skipped if flate is missing). Tools come from the devcontainer or, in a
cloud session, from `.claude/hooks/session-start.sh`.

## Reading failures

| Output | Meaning | Fix |
|---|---|---|
| yamllint `line too long` / `wrong indentation` | Style gate the YAML Lint workflow enforces | Wrap at 200, match sibling indent; the PostToolUse hook shows these on edit |
| kustomize `accumulating resources ... no such file` | A path in `kustomization.yaml` is wrong (templates are `../../../../templates/...` from `app/`) | Count the `..` |
| kubeconform `additional properties`, `expected ... got` | Field not in the CRD / API schema at that version | Compare with the chart's schema; app-template fields are documented in its `values.schema.json` |
| kubeconform `could not find schema` as an error | New CRD kind not in either catalog | `-ignore-missing-schemas` already covers it; if it errors, the kind name is misspelled |
| flux build `variable substitution failed` | `${VAR}` with no default and no value in `cluster-settings` / `cluster-secrets` | Add a default (`${VAR:-x}`) or the variable; for scripts with `$`, set `kustomize.toolkit.fluxcd.io/substitute: disabled` |
| flate `values not used` / render error | A values key the chart does not know, or a template failure | Read the chart's `values.yaml` at the pinned version; this is exactly what fails the PR's Flux Render job |

## After it passes

- Whole tree: `task kubernetes:kubeconform` (and `task kubernetes:rules-lint`
  when rules or the Alloy pipeline changed).
- Open the PR; CI's Flux Render / Flux Diff comment shows what actually
  changes in the rendered output: read it before asking for a merge.
