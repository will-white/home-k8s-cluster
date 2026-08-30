---
name: merge-renovate-prs
description: >-
  Triage and merge the repo's open dependency PRs (Renovate bumps for container
  images, Helm charts, GitHub Actions, and tooling) safely, in bulk. Use when the
  user asks to "go through the PRs", "merge the PRs", "clear the Renovate
  backlog", "update dependencies", or similar. Every PR is judged on evidence
  gathered by scripts/evidence.py (repo diff, rendered Flux diff, the full
  upstream changelog range, cross-reference against this repo's config,
  Renovate locks, history, live cluster state) — never on the semver label
  alone. Resolves duplicates, applies required config fixes, verifies rollouts
  with scripts/verify.sh, and holds one-way migrations / cluster rolls for
  explicit approval.
---

# Merge Renovate / dependency PRs

This is a Flux GitOps cluster repo. Most open PRs are Renovate bumps. The goal is
to merge everything that is *shown* to be safe, resolve duplicates to the highest
appropriate version, fix what a bump actually requires, verify each rollout, and
**stop and ask** before anything that rolls the live cluster or performs an
irreversible migration.

## Principle: the version number is not the risk

A `type/major` label is a hint, not a verdict. Real examples from this repo:

- `bazarr 1.6.0` (patch) migrated the shared Postgres schema — one-way.
- `emqx-operator 2.3.1` (patch) took MQTT down at the next restart.
- `chart openebs 4.5.1 → 4.6.0` (minor) removed Helm values and rewrote probes,
  ports and helper images — visible only in the rendered diff and the notes.
- `postgresql 16 → 18` (major) is not a bigger image bump: it is an offline
  `pg_upgrade` expressed as a *new* `ImageCatalog` entry, and the Renovate PR as
  written (rewriting the `major: 16` line) was wrong in shape.
- GitHub Actions majors are usually a no-op for this repo.

So **every PR gets the evidence pass in §2**, and the verdict in §3 comes from
what the evidence says. Renovate's PR body alone is not evidence: for many
images it carries no notes, and where notes exist they show only the newest
release, not the whole `current → new` range.

## Scripts (in `scripts/`, next to this file)

| script | what it does |
|---|---|
| `evidence.py <pr>` | the whole §2 pass for one PR → markdown report + `LEDGER` row; writes notes/diffs under `$SCRATCH/evidence/<pr>/` |
| `verify.sh -n <ns> <app> [--chart v] [--image s] [--timeout s]` | bounded post-merge wait (§8): HelmRelease Ready + revision, pods Running/ready, image landed, no restarts |

Both are read-only against the cluster and need only `gh`, `git`, `python3`
(+ `helm` for chart bumps, `kubectl` + kubeconfig for cluster state).

## 0. Preflight

- `ROOT=$(git rev-parse --show-toplevel)`; `SKILL=$ROOT/.claude/skills/merge-renovate-prs`;
  remote from `git remote -v` (currently `will-white/new-cluster`; GitHub still
  shows `home-k8s-cluster` URLs — renamed). `export KUBECONFIG=$ROOT/kubeconfig`;
  `export SCRATCH=<scratchpad dir>`.
- Environment varies: devcontainer = fish + full toolchain; WSL = bash and
  `flux`/`kustomize`/`yq`/`jq` may be missing. `command -v gh helm kubectl python3`.
- `gh api user -q .login` — confirm auth. If it fails: `! gh auth login`.
- **Workflow scope:** merging any PR that edits `.github/workflows/*` needs it:
  `! gh auth refresh -h github.com -s workflow` when you see *"refusing to allow
  an OAuth App … without workflow scope"*.
- Branch protection is absent (`gh api repos/<o>/<r>/branches/main/protection`
  → 404), so CI red never blocks a merge — reading the checks is your job.
- **Cluster health before touching anything:**
  ```bash
  kubectl get hr -A --request-timeout=10s | grep -v ' True '   # expect only the header
  kubectl get pods -A --request-timeout=10s | grep -vE 'Running|Completed'
  ```
  Merging onto an already-failing app makes the post-merge diagnosis ambiguous.
  Note anything unhealthy and either fix/hold it first or exclude its PRs.
- Glance at the Renovate Dependency Dashboard (issue #6) for "pending approval"
  items and "could not be looked up" warnings.

## 1. Survey and rebase

```bash
gh pr list --repo <o>/<r> --state open --limit 200 \
  --json number,title,mergeable,mergeStateStatus,isDraft,labels,headRefName,headRefOid,baseRefName \
  --jq '.[] | "\(.number)\t\(.mergeable)\t\(.mergeStateStatus)\t\([.labels[].name]|join(","))\t\(.title)"' | sort -n
```

**Rebase stale branches first.** Renovate now uses `rebaseWhen:
behind-base-branch`, but anything created before that (or between Renovate
runs) can still be behind `main`, and a stale branch means the Flux Diff CI
comment was rendered against an old base — misleading evidence (#1289's diff
showed an unrelated code-server downgrade). For each open PR:

```bash
gh api repos/<o>/<r>/compare/main...<headRefOid> --jq .behind_by   # >0 → stale
gh pr update-branch <pr> --repo <o>/<r>                             # then wait for Flux Diff to re-run
```

Do this for all stale PRs up front, then let CI finish before §2. Also build the
**file-conflict map** (which PRs touch the same file — decides merge order and
reveals duplicates, §4):

```bash
for pr in <all numbers>; do
  echo "$pr :: $(gh pr view $pr --repo <o>/<r> --json files --jq '[.files[].path]|join(" ")')"
done
```

Non-Renovate / feature PRs: review individually, don't lump in.

## 2. Evidence — run the script for EVERY dependency PR

```bash
python3 $SKILL/scripts/evidence.py <pr>            # add --no-cluster if kubeconfig is absent
```

It is fast (a handful of `gh` calls), so run it for the whole backlog in a loop
and read the reports; fan out general-purpose agents only for the *judgment* on
PRs whose report is long (many signals / cross-reference hits / chart values
changes). Each report contains, in order:

1. **PR + kind** — package table parsed from the body, touched files, the
   app(s), and the change kind (`CHART`, `IMAGE`, `CNPG-IMAGE`,
   `NODE/CONTROL-PLANE ROLL`, `CRD`, `GITHUB-ACTION`, `TOOLING`, …). The kind
   decides which evidence matters (an image bump needs the *app's* changelog;
   a chart bump needs chart notes **and** the appVersion delta).
2. **Flux Diff** — branch freshness (`behind_by`), the CI comments (and the
   full `diff.patch` artifact if the comment was truncated), objects changed,
   image lines, **immutable-field candidates** (`selector`, `serviceName`,
   `volumeClaimTemplates`, `storageClassName`…: Helm upgrade will fail →
   delete+recreate → RED), CRD/apiVersion lines, and objects *outside* the PR's
   apps (stale base or shared template).
3. **Source & notes** — resolved upstream repo (Renovate body link →
   `home-operations` `docker-bake.hcl` SOURCE → ghcr org/name → vendor map),
   `helm show chart` at both versions (appVersion, kubeVersion), a
   `helm show values` diff for non-app-template charts, and **every release in
   `(current, new]`** (falls back to the commit range, then `CHANGELOG.md`).
   If the chart's appVersion moved, the app's release range is pulled too.
4. **Signals** — lines from those notes matching migration/removal/breaking
   patterns, tagged with the release they came from.
5. **Cross-reference** — backticked / `UPPER_SNAKE` tokens from the signal
   lines and removed values keys grepped in `kubernetes/apps/<ns>/<app>/`.
   Hits = the change touches something *we set*.
6. **Locks** — `renovate.json5` rules gating this package (`allowedVersions`,
   `dependencyDashboardApproval`, `enabled: false`, `automerge: false`) with
   their descriptions — the repo's institutional memory, read live.
7. **History** — recent commits on the touched files (reverts/reapplies
   flagged) and prior PRs for the package.
8. **Cluster** — server version vs chart `kubeVersion`, not-Ready
   HelmReleases cluster-wide, the app's HelmRelease/pods right now.
9. **`LEDGER` row** — one line summarising all of the above with `verdict=?`
   for you to fill in.

**What the script cannot do — you still must:**

- Read the signal lines, not just count them. 26 signals on openebs 4.6.0 were
  all rawfile/Mayastor (not used here) → GREEN; one signal saying "run the
  migration before upgrading" on an app we run → RED.
- Follow vendor links it prints for images without GitHub releases
  (`postgresql.org/docs/release`, `docs.ceph.com/…/releases`) with WebFetch,
  and read docs pages named upgrade/upgrading/migration/breaking-changes when
  the notes point at them.
- For `app-template` bumps read the chart's release notes and the Flux Diff
  (its values.yaml is empty, so there is no values diff).
- Treat `notes=…:NONE` / `UNRESOLVED` / `fluxdiff=NONE` / `branch=STALE` as
  findings: no evidence is not "no change".
- Sanity-check the cross-reference (it is a token grep: it can miss a renamed
  nested key and it can hit an unrelated word).

Keep the ledger rows in one scratch file; they become the report (§9).

## 3. Verdict — by evidence tier, not by semver

**GREEN — merge in batch.** No migration/removal signal touches anything we
set; Flux Diff is fresh and shows only the expected tag/label churn; no
immutable-field candidates; no lock; cluster healthy; not a cluster roll.
Digest bumps, GitHub Action minors, devcontainer tool pins, most app-template
and exporter patch/minor bumps land here.

**YELLOW — merge alone after a fix-up (§6), then `verify.sh` before the next
PR on the same app.** A key we set was renamed/removed; a default we relied on
flipped; CRDs need a paired merge; a chart minor carries an app minor with a
reversible auto-migration; `kubeVersion`/dependency floors need checking.

**RED — HOLD, surface with `AskUserQuestion`, do not merge.**

1. **Live cluster rolls** — Talos / Kubernetes / kubelet / installer bumps
   (`talconfig.yaml`, `system-upgrade/**`, tuppr plans). Merging triggers real
   node OS / control-plane upgrades.
2. **One-way data migrations** — DB schema migrations that can't be reverted,
   Postgres/Ceph/storage majors, on-disk format changes, "cannot downgrade" in
   the notes, app majors whose first start migrates state. Requires a verified
   fresh backup first (§7) and an explicit OK.
3. **Immutable-field / delete-and-recreate upgrades** (from the Flux Diff).
4. **A lock or gate** in `renovate.json5` / file comments (the script prints
   them) — or known-broken upstream.
5. **Evidence gap** — no changelog located, stale/absent Flux Diff that can't
   be regenerated, or the diff contradicts the title (wrong line edited).

When surfacing a RED item, give the user the *evidence*: quote the changelog
line, name the file:line the diff touches, and state the correct upgrade path
(merge as-is / edit / close and do by hand).

## 4. Duplicates vs. split PRs

- **True duplicates** = two PRs editing the **same line/file** for the same
  package. Keep the **highest version that passes §3**, close the other with a
  note. A hold on the higher one (helm v4) means take the lower.
- **NOT duplicates** (merge both): Renovate splits one package across files —
  CLI in `.devcontainer/Dockerfile` vs cluster manifest, bootstrap
  `helmfile.yaml` vs `app/helmrelease.yaml` (spegel, talos, kubernetes). Keep
  bootstrap and in-cluster copies at the same version.
- `separateMultipleMajor` is on: a two-major jump arrives as two PRs — merge
  in order, verify between.

## 5. Knowledge that lives nowhere else

Version locks and approval gates live in `renovate.json5` (the script prints
the ones that apply); file-local rules live in comments next to the pinned
value. Only the following is *not* recorded in either place:

- **kube-prometheus-stack** chart major ⇔ **prometheus-operator-crds** major
  move together (operator needs the matching CRD schema). CRDs first.
- **CNPG Postgres major** (`imagecatalog.yaml`): add a `major: <N>` entry, then
  bump `cluster16.yaml` `imageCatalogRef.major` — CNPG ≥1.26 runs `pg_upgrade`
  declaratively, **offline, in place, one-way**. Fresh backup first (§7).
  Renovate majors for this image are disabled; the upgrade is hand-written.
- **helm v4** breaks the helmfile bootstrap (`--validate` removed). Take latest
  v3.
- **Gitleaks** check: historically red for a shallow-clone reason, not a leak.
  Still open the check output before dismissing it.

When a lock turns out to be obsolete, say so in the report and offer to update
`renovate.json5` / the comment — don't add a rule here.

## 6. Fix-ups on a PR branch

Only edit manifests when the evidence shows a key we set was removed/renamed,
or a paired change is required. Push onto the Renovate branch (Renovate stops
rebasing a branch with human commits unless the rebase box is ticked) or open a
fresh branch off `main` with the bump + fix and close the Renovate PR
referencing it.

```bash
gh pr checkout <pr> --repo <o>/<r>
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
kubectl apply -f - <<EOT
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: { name: <app>-premigration, namespace: database }
spec: { cluster: { name: postgres16 }, method: barmanObjectStore }
EOT
# poll: kubectl get backup <app>-premigration -n database  (until PHASE=completed)
```

For apps backed by volsync, confirm the latest `ReplicationSource`
`lastSyncTime` is recent before merging.

CNPG rollback is a **manual PITR restore into a new cluster** (see the commented
`bootstrap.recovery` / `serverName` block in `cluster16.yaml`), not an instant
revert.

## 8. Merge and verify

**Squash-merge** (`gh pr merge <pr> --repo <o>/<r> --squash`; branches
auto-delete). gh is silent on success — verify with
`gh pr view <pr> --json state,mergedAt`.

- **Unique-file GREEN PRs**: batch-merge freely.
- **YELLOW / same-app PRs**: one at a time, `verify.sh` between.
- **Shared-file clusters**: merge one, then the rest. If one goes CONFLICTING,
  `gh pr update-branch <pr>` and retry. If Renovate **auto-closes** a sibling
  (`state: CLOSED, mergedAt: null`) and the bump is still wanted, recreate it:
  branch off `main`, re-apply the one-line change (digest from
  `gh pr diff <old-pr>`), push, open a PR, merge via API.
- **Merge order** must respect `dependsOn` pairs (CRDs → operator).

**Verify every cluster-affecting merge with a bounded wait** — "verified"
means the new revision is running, not "Flux hadn't synced yet":

```bash
$SKILL/scripts/verify.sh -n <ns> <app> --chart <new-chart-version>      # chart bump
$SKILL/scripts/verify.sh -n <ns> <app> --image <new-tag>                # image bump
# exit 0 = rolled out; 1 = timeout (default 600s; Flux interval is the usual cause — extend or check
#   `flux get sources git`/`kubectl get gitrepository -n flux-system`); 2 = failure detected (events printed)
```

Then the app's own signal: `kubectl logs -n <ns> -l app.kubernetes.io/name=<app> --tail=200 | grep -iE "migrat|error|listening|deprecat"`
and, for user-facing apps, its Gatus endpoint. Do not force cluster-wide
reconciles; reconciling a single app's Kustomization is acceptable under the
owner's standing approval if the user wants faster feedback.

If an upgrade fails with an immutable-field error, that is a RED you missed —
stop, report, and don't "fix" it by deleting resources without approval (PVCs
are user data; see AGENTS.md).

### Shell gotchas

- **fish** (devcontainer): `for x in $VAR` does NOT word-split, `status` is a
  read-only builtin, and `jsonpath` brackets need quoting. Wrap loops in
  `bash -c '...'`; the scripts are bash/python and don't care.
- **bash** (WSL): fine, but `jq`/`yq`/`flux` may be absent — use `gh --jq`.
- **Direct push to `main` is blocked**. Branch + PR + API merge, always.

## 9. Report

Summarize: merged count, duplicates closed, fix-ups applied, verification
results, and the **held PRs with the evidence for each** (quoted changelog line
/ diff hunk, the file:line it affects, the recommended path). Include the
ledger rows. For each RED/YELLOW PR leave the same summary as a PR comment
(`gh pr comment <pr> --body-file …`) so the reasoning lives with the PR, and
offer to schedule the cluster-roll PRs.

Also report **process findings** — a lock that is now obsolete, a package whose
changelog the script couldn't resolve (candidate for a `sourceUrl` rule), a
GREEN class that keeps recurring (candidate for Renovate automerge) — so the
tooling improves alongside the merges.
