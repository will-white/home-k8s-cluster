---
name: merge-renovate-prs
description: >-
  Triage and merge the repo's open dependency PRs (Renovate bumps for container
  images, Helm charts, GitHub Actions, and tooling) safely, in bulk. Use when the
  user asks to "go through the PRs", "merge the PRs", "clear the Renovate
  backlog", "update dependencies", or similar. Every PR is judged on evidence
  (repo diff, rendered Flux diff, the full upstream changelog range, and a
  cross-reference against this repo's config) — never on the semver label
  alone. Resolves duplicates, applies required config fixes, and holds
  one-way migrations / cluster rolls for explicit approval.
---

# Merge Renovate / dependency PRs

This is a Flux GitOps cluster repo. Most open PRs are Renovate bumps. The goal is
to merge everything that is *shown* to be safe, resolve duplicates to the highest
appropriate version, fix what a bump actually requires, and **stop and ask**
before anything that rolls the live cluster or performs an irreversible
migration.

## Principle: the version number is not the risk

A `type/major` label is a hint, not a verdict. Real examples from this repo:

- `fix(container): bazarr 1.6.0` (patch) migrated the shared Postgres schema and
  moved to an unsupported Python — one-way.
- `emqx-operator 2.3.1` (patch) took MQTT down at the next restart.
- `feat(helm): chart openebs 4.5.1 → 4.6.0` (minor) rewrote probes, ports and
  helper images — visible only in the rendered diff.
- `postgresql 16 → 18` (major) is not "a bigger image bump": it is an offline
  `pg_upgrade` that must be expressed as a *new* `ImageCatalog` entry, and the
  Renovate PR as written is wrong (it edits the `major: 16` line).
- GitHub Actions majors are usually a no-op for this repo.

So: **every PR gets the evidence pass in §2**, and the verdict in §3 is derived
from what the evidence says. Cost is cheap (a few `gh` calls); skipping it is
how migrations get merged blind.

Renovate's PR body is **not** sufficient evidence: for docker images it usually
contains no release notes at all (e.g. `ghcr.io/cloudnative-pg/postgresql`,
`home-operations/*`), and where notes exist they show only the *newest* release,
not the whole `current → new` range.

## 0. Preflight

- Repo root: `ROOT=$(git rev-parse --show-toplevel)`; remote from `git remote -v`
  (currently `will-white/new-cluster`; GitHub Action URLs still say
  `home-k8s-cluster` — renamed). `KUBECONFIG=$ROOT/kubeconfig`.
- Shell/tools vary by environment (devcontainer = fish + full toolchain; WSL =
  bash, and `flux`/`kustomize`/`yq`/`jq` may be **missing**). Check with
  `command -v flux kustomize kubeconform yq jq helm`. Use `gh --jq` instead of
  `jq`; `helm` is the one tool the evidence pass depends on.
- `gh api user -q .login` — confirm auth. If it fails, ask the user to run
  `! gh auth login` (or set `GH_TOKEN`).
- **Workflow scope:** the device-flow token often lacks `workflow` scope, so
  merging any PR that edits `.github/workflows/*` fails with
  *"refusing to allow an OAuth App … without workflow scope"*. Fix:
  `! gh auth refresh -h github.com -s workflow`.
- `gh api repos/<owner>/<repo>/branches/main/protection` — usually 404 (no
  protection, no required checks), so CI red does not block merges. That makes
  reading the checks *your* job (§2b).
- Glance at the Renovate Dependency Dashboard (issue #6) for "pending approval"
  items (bazarr, emqx-operator are gated there on purpose) and "could not be
  looked up" warnings.

## 1. Survey every open PR

```bash
gh pr list --repo <owner>/<repo> --state open --limit 200 \
  --json number,title,mergeable,mergeStateStatus,isDraft,labels \
  --jq '.[] | "\(.number)\t\(.mergeable)\t\(.mergeStateStatus)\t\([.labels[].name]|join(","))\t\(.title)"' | sort -n
```

Build a **file-conflict map** — which PRs touch the same file (determines merge
order and reveals duplicates, §4):

```bash
for pr in <all numbers>; do
  echo "$pr :: $(gh pr view $pr --repo <owner>/<repo> --json files --jq '[.files[].path]|join(" ")')"
done
```

Non-Renovate / feature PRs: review individually, don't lump in.

## 2. Gather evidence — for EVERY dependency PR

Keep an **evidence ledger** (scratchpad file) with one row per PR; it feeds the
verdict (§3) and the report (§9):

```
PR | package | current → new | kind | repo diff | flux diff read? (fresh/stale/truncated/none) | changelog sources + range covered | signals found | keys we set that are affected | verdict + why
```

Fan out one general-purpose agent per **non-trivial** PR (anything that is not a
digest-only bump or a GitHub Action minor/patch) so the passes run in parallel;
each agent returns its ledger row. Trivial PRs you can do inline.

### 2a. Repo diff — what actually changes in Git

```bash
gh pr diff <pr> --repo <owner>/<repo>
```

Identify the **kind** of change, because it decides what the rest of the
evidence looks like:

| kind | file / key | what it really means |
|---|---|---|
| chart bump | `helmrelease.yaml spec.chart.spec.version` or `ocirepository.yaml ref.tag` | new templates **and** possibly a new `appVersion` → app image bump hidden inside a "chart minor" |
| image bump | app-template `values.controllers.*.containers.*.image.tag` | app upgrade; the app's changelog matters, not the image repo's |
| CNPG image | `cloudnative-pg/cluster/imagecatalog.yaml` | minor = rolling restart; **major = offline pg_upgrade, needs a new catalog entry (§5)** |
| node / control plane | `talconfig.yaml`, `system-upgrade/**`, `tuppr` plans, `siderolabs/installer|kubelet` | rolls real nodes on merge (§3 RED) |
| CRD chart | `*-crds` HelmRelease | must move with its operator (§5) |
| tooling | `.devcontainer/Dockerfile`, workflow `*_VERSION` pins | affects only dev/CI, not the cluster |
| GitHub Action | `.github/workflows/*` `uses:` | needs `workflow` scope to merge; low cluster risk |
| grafana dashboards | `revision:` ints | cosmetic; check the flux diff isn't empty and move on |

### 2b. Rendered cluster diff — the Flux Diff CI comment

CI (`.github/workflows/flux-diff.yaml`) renders `main` vs the PR branch and posts
the resulting **Kubernetes-object diff** as PR comments. This is the closest
thing to "what will Helm/Flux actually do", and it is where chart minors reveal
probe/port/env/image/CRD changes.

```bash
gh pr view <pr> --repo <owner>/<repo> --json comments \
  --jq '.comments[] | select(.author.login=="github-actions") | .body'
# two comments: add-pr-comment:<pr>/kubernetes/kustomization (Flux objects) and
#               add-pr-comment:<pr>/kubernetes/helmrelease   (rendered Helm output)
gh pr checks <pr> --repo <owner>/<repo>   # Flux Diff, Kubeconform, Validate Kubernetes Manifests matter
```

Read it for:

- image tags changing that the PR title didn't mention (chart carrying an app
  bump) → add that app's changelog to §2c;
- **immutable-field edits**: `Deployment.spec.selector`, StatefulSet
  `volumeClaimTemplates`/`serviceName`, PVC size/StorageClass, Job specs → Helm
  upgrade will fail; needs delete+recreate → RED;
- new/changed CRDs or `apiVersion` changes → confirm the HelmRelease's
  `install.crds` / `upgrade.crds` policy (`CreateReplace` is what this repo uses
  for operator charts) or that the paired `-crds` PR exists;
- probes/ports/env/securityContext/volume changes → sanity-check against our
  `values` overrides (a renamed default we override is a silent no-op);
- resources removed from the render (a template we relied on was dropped);
- NetworkPolicy / Service / ingress changes that alter exposure.

**Trust checks on the diff:**

- **Stale branch:** if the diff includes objects the PR doesn't touch (e.g. a
  Postgres PR showing `code-server` going *backwards*), the branch is behind
  `main`; CI compared old base. `gh pr update-branch <pr>` (or tick the Renovate
  rebase box), wait for Flux Diff to re-run, re-read.
- **Truncated:** the comment is capped at 50 KB, but the workflow uploads the
  whole `diff.patch` as an artifact (`flux-diff-helmrelease` /
  `flux-diff-kustomization`); the truncated comment names the run.
  ```bash
  RUN=$(gh run list --repo <owner>/<repo> --workflow "Flux Diff" --branch <pr-head-branch> --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run download "$RUN" --repo <owner>/<repo> -n flux-diff-helmrelease -D "$SCRATCH/<pr>-diff"
  ```
  If the artifact is missing too (older run, expired after 14 days), render
  locally if tools exist (`flux build ks <app> --kustomization-file .../ks.yaml
  --path .../app --dry-run` or `helm template` at both chart versions with the
  same values); otherwise say so in the ledger and lean harder on §2c.
- **None:** CI didn't run / no comment → don't assume "no change". Render
  locally or hold until it runs.

`mergeStateStatus: UNSTABLE` is almost always just **Gitleaks** (historically a
red herring — shallow-clone bug fixed 2026-07). Confirm with `gh pr checks`.

### 2c. Upstream changelog — the FULL range, not just the newest tag

Resolve the **source repo** in this order:

1. `[source](…)` / package link in the Renovate body:
   `gh pr view <pr> --json body --jq .body | grep -oE 'https://redirect.github.com/[^)/]+/[^)/]+' | head -3`
2. Helm chart → chart repo **and** app:
   ```bash
   helm show chart <oci://… or --repo https://…> <chart> --version <cur>  | grep -E '^(appVersion|kubeVersion):'
   helm show chart … --version <new>  | grep -E '^(appVersion|kubeVersion):'
   ```
   If `appVersion` moved, the *app's* changelog is in scope too (e.g.
   `chart cloudnative-pg 0.29.0` ⇒ operator `1.30.0`). Chart-repo tag formats:
   `bjw-s-labs/helm-charts` → `app-template-X.Y.Z`;
   `prometheus-community/helm-charts` → `kube-prometheus-stack-X.Y.Z`;
   most single-chart repos → `vX.Y.Z`.
3. Docker image:
   - `ghcr.io/home-operations/<app>` / `ghcr.io/onedr0p/<app>`: repackaged
     upstream; the tag **is** the upstream version. Find upstream via
     `gh api repos/home-operations/containers/contents/apps/<app>/docker-bake.hcl -q .content | base64 -d | grep -A1 SOURCE`.
   - `ghcr.io/<org>/<name>`: try `gh api repos/<org>/<name>/releases`.
   - No GitHub releases/tags (e.g. `cloudnative-pg/postgresql`, `quay.io/ceph/ceph`):
     use the vendor's notes — `https://www.postgresql.org/docs/release/`,
     `https://docs.ceph.com/en/latest/releases/` — via WebFetch.
4. `github-releases` / `github-tags` / `github-actions` datasources: the
   depName is the repo.

Then pull **every release between current (exclusive) and new (inclusive)** —
a 16→18 or 4.3→4.6 jump has intermediate releases whose notes carry the
migration steps:

```bash
# newest first; print until we reach the currently-deployed tag (v-prefix tolerant).
# The marker line is deliberately not markdown — release bodies contain their own "## " headings.
gh api "repos/<o>/<r>/releases?per_page=100" --paginate \
  --jq '.[] | select(.prerelease|not) | "@@RELEASE \(.tag_name) \(.published_at[:10])\n\(.body)\n"' \
  | awk -v cur="<cur-version>" '
      /^@@RELEASE /{ t=$2; sub(/^v/,"",t); c=cur; sub(/^v/,"",c); if (t==c) stop=1; sub(/^@@RELEASE/,"##") }
      !stop' > "$SCRATCH/<pkg>-notes.md"
grep -c '^## ' "$SCRATCH/<pkg>-notes.md"   # should equal the number of releases in (cur, new]
# if releases are empty/thin, fall back to the changelog file and commit range:
gh api repos/<o>/<r>/contents/CHANGELOG.md -q .content | base64 -d | sed -n '1,400p'
gh api "repos/<o>/<r>/compare/<cur-tag>...<new-tag>" --jq '.commits[].commit.message' | grep -iE '^[a-z]+(\(.*\))?!:|BREAKING' 
# docs pages named upgrade/upgrading/migration/breaking-changes also count (WebFetch)
```

For Helm charts also diff the **defaults**, which changelogs routinely omit
(skip for `app-template`, whose values.yaml is empty — read its release notes
and the flux diff instead):

```bash
helm show values … --version <cur> > "$SCRATCH/<chart>-cur.yaml"
helm show values … --version <new> > "$SCRATCH/<chart>-new.yaml"
diff -u "$SCRATCH/<chart>-cur.yaml" "$SCRATCH/<chart>-new.yaml"
```

Grep the collected notes for the signals below and quote the matching lines in
the ledger:

```
breaking|BREAKING|deprecat|remov|renam|migrat|schema|database|irreversib|cannot (be )?(downgrad|revert|roll(ed)? back)|backup|pg_upgrade|dump|restore|
CRD|apiVersion|minimum|requires? (kubernetes|k8s|helm|postgres)|drop(ped)? support|default(s)? (changed|now)|security|auth|token|password|permission|
StatefulSet|PVC|volume|persist|on-disk|format|reindex|manual (step|action|intervention)|before (upgrading|you upgrade)|upgrade notes
```

If **no changelog can be found** for a change that is more than a digest/patch
with an empty flux diff, that is itself a finding: do not merge on the label —
say so and ask.

### 2d. Cross-reference against what THIS repo actually sets

The changelog tells you what upstream changed; only the repo tells you whether
it applies to us. For each removed/renamed/defaulted key in §2c:

```bash
# keys this app sets (chart values, env, args, config files under resources/)
sed -n '/^\s*values:/,$p' kubernetes/apps/<ns>/<app>/app/helmrelease.yaml | grep -nE '^\s*[A-Za-z_]+:'
grep -rn -E '<old-key>|<OLD_ENV>' kubernetes/apps/<ns>/<app>/
# who else consumes the same chart/image (a template or shared chart change hits everyone)
grep -rln '<chart-or-image>' kubernetes/apps | sort
```

Also check the things that are ours, not upstream's:

- `dependsOn` in `ks.yaml` still describes the real order (CRDs before operator,
  `cloudnative-pg-cluster` before DB users, `external-secrets-stores`).
- Backup posture for the app if the change is stateful (volsync
  `ReplicationSource`, CNPG `ScheduledBackup`) — see §7.
- Version locks written into comments/`renovate.json5` `allowedVersions`
  (helm v3, emqx-operator `<2.3.0`, ceph `x.2.z` only, bazarr approval gate).

## 3. Verdict — by evidence tier, not by semver

**GREEN — merge in batch.** Notes show no migration/removal signals that touch
keys we set; flux diff is fresh and only shows the expected tag/label changes
(or harmless template churn); no immutable-field edits; not a cluster roll.
Digest-only bumps, GitHub Action minors, devcontainer tool pins, and most
app-template patch/minor bumps land here.

**YELLOW — merge after a fix-up (§6), on its own, then verify (§8).** A key we
set was renamed/removed; a default we relied on flipped; CRDs need a paired
merge; a chart minor carries an app minor with a reversible auto-migration;
`kubeVersion`/dependency floors need checking against the cluster. Apply the
edit on the PR branch, validate, merge, then watch the rollout before the next
PR that touches the same app.

**RED — HOLD, surface with `AskUserQuestion`, do not merge.**

1. **Live cluster rolls** — Talos / Kubernetes / kubelet / installer bumps
   (`talconfig.yaml`, `system-upgrade/**`, tuppr plans). Merging triggers real
   node OS / control-plane upgrades.
2. **One-way data migrations** — DB schema migrations that can't be reverted,
   Postgres/Ceph/storage majors, on-disk format changes, "cannot downgrade" in
   the notes, app majors whose first start migrates state (paperless-ngx v3,
   bazarr 1.6). Requires a verified fresh backup first (§7) and an explicit OK.
3. **Immutable-field / delete-and-recreate upgrades** (StatefulSet, selector,
   PVC changes in the flux diff).
4. **Known-broken upstream** or a version lock in `renovate.json5` /
   file comments (helm v4 vs helmfile bootstrap, emqx-operator ≥2.3.0, Ceph
   RC tags).
5. **Evidence gap** — no changelog located, stale/absent flux diff that can't be
   regenerated, or the diff contradicts the title (e.g. the PR edits the wrong
   line, as with the Postgres 16→18 catalog PR).

When surfacing a RED item, give the user the *evidence*, not the label: quote
the changelog line, name the file:line the diff touches, and state what the
correct upgrade path is (and whether the Renovate PR should be merged as-is,
edited, or closed and done by hand).

## 4. Duplicates vs. split PRs

- **True duplicates** = two PRs editing the **same line/file** for the same
  package (`v86` vs `v87` of one chart, `helm v3` vs `helm v4` in the
  devcontainer). Keep the **highest version that passes §3**, close the other
  with a note. Default: prefer highest — but a hold on the higher one (helm v4)
  means take the lower.
- **NOT duplicates** (merge both): Renovate splits one package across files —
  CLI in `.devcontainer/Dockerfile` vs cluster manifest, bootstrap
  `helmfile.yaml` vs `app/helmrelease.yaml`. Seen: spegel, talos (talconfig +
  talosctl), kubernetes (talconfig + kubectl). Different files → both merge —
  but keep bootstrap and in-cluster copies at the same version.

## 5. Repo-specific knowledge (verify, don't assume it's still true)

- **kube-prometheus-stack** chart major ⇔ **prometheus-operator-crds** major
  move together (operator needs the matching CRD schema). Merge as a pair,
  CRDs first.
- **CNPG Postgres major** (`imagecatalog.yaml`): do **not** merge a Renovate PR
  that rewrites the `major: 16` image to an 18 tag. Correct path (see the
  comment in the file): add a `major: 18` entry, then bump
  `cluster16.yaml` `imageCatalogRef.major` — CNPG ≥1.26 runs `pg_upgrade`
  declaratively, **offline, in place, one-way**. Fresh backup first (§7).
  Close or rewrite the Renovate PR; note that Renovate will re-open it until the
  catalog has the new major.
- **helm v4** breaks the helmfile bootstrap (`--validate` removed). Take latest
  v3; document the exception.
- **emqx-operator** `<2.3.0` (`allowedVersions` in renovate.json5); OSS EMQX
  5.8.9 is the last open-source release.
- **bazarr** is approval-gated on the dashboard (Python 3.14 image, shared
  schema already migrated — no downgrade).
- **Ceph** image: only `x.2.z` is stable; `x.1.z` RC, `x.0.z` dev.
- **paperless-ngx v3**: `PAPERLESS_CONSUMER_POLLING` →
  `PAPERLESS_CONSUMER_POLLING_INTERVAL`, one-way DB migration.
- **GitHub Actions majors** (checkout/cache/labeler): usually safe; watch for
  `pull_request_target` + checkout combos and the labeler v5 config schema
  (already adopted).
- **Gitleaks** check: historically red for a shallow-clone reason, not a leak.
  Still open the check output before dismissing it.

When one of these rules turns out to be obsolete (lock lifted upstream), say so
in the report and offer to update `renovate.json5` / the file comment.

## 6. Fix-ups on a PR branch

Only edit manifests when §2c/§2d shows a key we set was removed/renamed, or a
paired change is required. Either push onto the Renovate branch (Renovate stops
rebasing a branch with human commits unless the rebase box is ticked — that's
fine) or open a fresh branch off `main` with the bump + fix and close the
Renovate PR referencing it.

```bash
gh pr checkout <pr> --repo <owner>/<repo>
# edit …
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/<ns>/<app>/app | kubeconform -strict -   # if tools present
git commit -am "fix(<app>): <key> renamed in <pkg> <ver>" && git push
```

## 7. Irreversible DB migration handling (CNPG)

Backups already run: a `ScheduledBackup` (`@daily`) + continuous WAL archiving to
Ceph RGW S3, 30-day retention, on the `postgres16` CNPG cluster
(`kubernetes/apps/database/cloudnative-pg/`). That gives PITR. Before merging a
one-way migration, with the user's explicit OK, take a fresh on-demand backup and
wait for `completed`:

```bash
export KUBECONFIG="$(git rev-parse --show-toplevel)/kubeconfig"
kubectl apply -f - <<EOT
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: { name: <app>-premigration, namespace: database }
spec: { cluster: { name: postgres16 }, method: barmanObjectStore }
EOT
# poll: kubectl get backup <app>-premigration -n database  (until PHASE=completed)
```

For apps backed by volsync instead, confirm the latest `ReplicationSource`
`lastSyncTime` is recent (or trigger a manual sync) before merging.

CNPG rollback is a **manual PITR restore into a new cluster** (see the commented
`bootstrap.recovery` / `serverName` block in `cluster16.yaml`), not an instant
revert.

## 8. Merge and verify

**Squash-merge** (`gh pr merge <pr> --repo <owner>/<repo> --squash`; branches
auto-delete). gh is silent on success — verify with
`gh pr view <pr> --json state,mergedAt`.

- **Unique-file GREEN PRs**: batch-merge freely.
- **YELLOW / same-app PRs**: one at a time, verify between.
- **Shared-file clusters**: merge one, then the rest — GitHub 3-way-merges
  different lines cleanly. If one goes CONFLICTING, `gh pr update-branch <pr>`
  and retry. If Renovate **auto-closes** a sibling (`state: CLOSED, mergedAt:
  null`) and the bump is still wanted, recreate it: branch off `main`, re-apply
  the one-line change (digest from `gh pr diff <old-pr>`), push, open a PR,
  merge via API.
- **Merge order** must respect `dependsOn` pairs (CRDs → operator).

**Verify (read-only) after each cluster-affecting merge** — observe, don't
force. Cluster-wide `flux reconcile` / annotating the GitRepository is out of
scope here; let Flux sync on its interval (reconciling a single app's
Kustomization is acceptable under the owner's standing approval if the user
wants faster feedback).

```bash
export KUBECONFIG="$(git rev-parse --show-toplevel)/kubeconfig"
kubectl get helmrelease <app> -n <ns>            # READY True / "upgrade succeeded"
kubectl get pods -n <ns> | grep <app>            # Running, no CrashLoop / restarts climbing
kubectl logs -n <ns> -l app.kubernetes.io/name=<app> --tail=200 | grep -iE "migrat|error|listening|deprecat"
```

If an upgrade fails with an immutable-field error, that is a RED you missed —
stop, report, and don't "fix" it by deleting resources without approval (PVCs
are user data; see AGENTS.md).

### Shell gotchas

- **fish** (devcontainer): `for x in $VAR` does NOT word-split, and `status` is a
  read-only builtin; avoid `jsonpath`/`custom-columns` with brackets. Wrap loops
  in `bash -c '...'`.
- **bash** (WSL): fine, but `jq`/`yq`/`flux` may be absent — use `gh --jq`,
  `grep`/`sed`, and `helm`.
- **Workflow files** need `workflow` token scope to merge after a rebase (§0).
- **Direct push to `main` is blocked**. Never `git push origin main`; branch +
  PR + API merge.

## 9. Report

Summarize: merged count, duplicates closed, fix-ups applied, and the **held PRs
with the evidence for each** (quoted changelog line / diff hunk, the file:line it
affects, the recommended path). Include the ledger so the decisions are
auditable. For each RED PR, also leave the same summary as a PR comment
(`gh pr comment <pr> --body-file …`) so the reasoning lives with the PR, and
offer to schedule the cluster-roll PRs.

Also report any **process findings** — a renovate rule that is now obsolete, a
package whose changelog Renovate can't find (candidate for a `sourceUrl` /
`changelogUrl` packageRule), a Flux Diff that keeps truncating — so the
tooling improves alongside the merges.
