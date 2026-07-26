---
name: merge-renovate-prs
description: >-
  Triage and merge the repo's open dependency PRs (Renovate/dependabot bumps
  for container images, Helm charts, and tooling) safely, in bulk. Use when the
  user asks to "go through the PRs", "merge the PRs", "clear the Renovate
  backlog", "update dependencies", or similar. Handles duplicate major/minor
  PRs, researches breaking changes on majors, and holds high-risk changes for
  explicit approval.
---

# Merge Renovate / dependency PRs

This is a Flux GitOps cluster repo. Most open PRs are Renovate bumps. The goal is
to merge everything safe, resolve duplicates to the highest appropriate version,
fix breaking changes that a major bump requires, and **stop and ask** before
anything that rolls the live cluster or performs an irreversible migration.

The git remote is `will-white/new-cluster`. Its GitHub Actions/URLs still say
`home-k8s-cluster` (renamed) — always target the remote from `git remote -v`.

## 0. Preflight

- `gh api user -q .login` — confirm auth. If it fails, ask the user to run
  `! gh auth login` (or set `GH_TOKEN`).
- **Workflow scope:** the device-flow token often lacks `workflow` scope, so
  merging any PR that edits `.github/workflows/*` fails with
  *"refusing to allow an OAuth App … without workflow scope"*. Fix:
  `! gh auth refresh -h github.com -s workflow`.
- `gh api repos/<owner>/<repo>/branches/main/protection` — usually 404 (no
  protection, no required checks), so CI red does not block merges.

## 1. Survey every open PR

```bash
gh pr list --repo <owner>/<repo> --state open --limit 200 \
  --json number,title,mergeable,mergeStateStatus,isDraft \
  --jq '.[] | "\(.number)\t\(.mergeable)\t\(.mergeStateStatus)\t\(.title)"' | sort -n
```

Build a **file-conflict map** — which PRs touch the same file (determines merge
order):

```bash
for pr in <all numbers>; do
  echo "$pr :: $(gh pr view $pr --repo <owner>/<repo> --json files --jq '[.files[].path]|join(" ")')"
done
```

`mergeStateStatus: UNSTABLE` is almost always just the **Gitleaks** check —
historically a red herring (shallow-clone bug, fixed 2026-07). Confirm with
`gh pr checks <pr>`; the checks that matter are **Flux Diff, Kubeconform,
Validate Kubernetes Manifests**.

## 2. Classify

- **True duplicates** = two PRs editing the **same line/file** for the same
  package (e.g. `v86` vs `v87` of one Helm chart, or `helm v3` vs `helm v4` in
  `.devcontainer/Dockerfile`). Keep the **highest** appropriate version, **close
  the other** with a note. Default policy: prefer highest.
- **NOT duplicates** (merge both): Renovate splits one package across files — the
  CLI in `.devcontainer/Dockerfile` vs the cluster manifest, or a bootstrap
  `helmfile.yaml` entry vs an `app/helmrelease.yaml`. Different files → both
  merge. Examples seen: spegel (helmfile + helmrelease), talos (talconfig +
  devcontainer talosctl), kubernetes (talconfig + devcontainer kubectl).
- **Majors** (title has `!` or a whole-number version jump): research breaking
  changes (§4).
- **Non-Renovate / feature PRs**: review individually, don't lump in.

## 3. HOLD and ASK (do not auto-merge)

Surface these with `AskUserQuestion` before merging:

1. **Live cluster rolls** — Talos or Kubernetes version bumps. These edit
   `kubernetes/apps/system-upgrade/**` (system-upgrade-controller / tuppr plans)
   and `kubernetes/bootstrap/talos/talconfig.yaml`, and **trigger real node OS /
   control-plane upgrades** on merge.
2. **Irreversible data migrations** — e.g. a major app bump whose first startup
   runs a one-way DB schema migration (paperless-ngx v3 is the canonical case).
   Requires a fresh DB backup first (§6).
3. **Known-broken upstream** — e.g. `helm v4` breaks the helmfile bootstrap
   (`helmfile apply` passes the removed `--validate` flag). Hold, take latest v3
   instead. Document the exception to the "highest version" rule.

## 4. Research breaking changes on majors

Fan out one general-purpose agent per major (parallel). Each agent must: read the
affected manifest + its values, fetch the upstream CHANGELOG/release notes, and
cross-reference **this repo's actually-set keys** against removed/renamed ones —
report `file:line` edits needed, plus any version-lock requirement. Known links:

- **kube-prometheus-stack** chart major ⇔ **prometheus-operator-crds** major must
  move together (the operator version needs the matching CRD schema). Merge as a
  pair.
- **GitHub Actions** majors (checkout/cache/labeler): usually safe — check for
  `pull_request_target` + checkout combos and the labeler v5 config-schema
  change; this repo uses hosted runners and the post-v5 schema already.

Only edit manifests when the research says a key was removed/renamed (e.g.
paperless v3: `PAPERLESS_CONSUMER_POLLING` → `PAPERLESS_CONSUMER_POLLING_INTERVAL`).

## 5. Merge

**Squash-merge** (`gh pr merge <pr> --repo <owner>/<repo> --squash`; branches
auto-delete). gh is silent on success — verify with
`gh pr view <pr> --json state,mergedAt`.

- **Unique-file PRs**: batch-merge freely; they can't invalidate each other.
- **Shared-file clusters**: merge one, then the rest — GitHub 3-way-merges
  different lines cleanly (they usually stay mergeable). If one goes
  CONFLICTING, `gh pr update-branch <pr>` and retry.
- **Renovate may auto-close** a PR whose branch conflicts after you merge a
  same-file sibling (it shows `state: CLOSED, mergedAt: null`). If the bump is
  still wanted, **recreate it**: new branch off `main`, re-apply the one-line
  change (grab the target digest from `gh pr diff <old-pr>`), push the branch,
  open a PR, merge via API.

### Gotchas

- **Shell is fish.** `for x in $VAR` does NOT word-split, and `status` is a
  read-only builtin. Wrap loops in `bash -c '...'`.
- **Workflow files** (`.github/workflows/*`) need `workflow` token scope to merge
  after a rebase (§0).
- **Direct push to `main` is blocked** by the harness. Never `git push origin
  main`. Do everything via branch + PR + API merge.

## 6. Irreversible DB migration handling (CNPG)

Backups already run: a `ScheduledBackup` (`@daily`) + continuous WAL archiving to
Ceph RGW S3, 30-day retention, on the `postgres16` CNPG cluster
(`kubernetes/apps/database/cloudnative-pg/`). That gives PITR. Before merging a
one-way migration, with the user's explicit OK, take a fresh on-demand backup and
wait for `completed`:

```bash
export KUBECONFIG=/workspaces/new-cluster/kubeconfig
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: { name: <app>-premigration, namespace: database }
spec: { cluster: { name: postgres16 }, method: barmanObjectStore }
EOF
# poll: kubectl get backup <app>-premigration -n database  (until PHASE=completed)
```

CNPG rollback is a **manual PITR restore into a new cluster** (see the commented
`bootstrap.recovery` / `serverName` block in `cluster16.yaml`), not an instant
revert.

## 7. Verify (read-only)

After merging cluster-affecting changes, **observe** — do not force reconciles
(`flux reconcile` / annotating the GitRepository triggers a cluster-wide deploy
and is blocked; let Flux sync on its interval):

```bash
export KUBECONFIG=/workspaces/new-cluster/kubeconfig
kubectl get helmrelease <app> -n <ns>            # READY True / "upgrade succeeded"
kubectl get pods -n <ns> | grep <app>            # 1/1 Running
kubectl logs -n <ns> -l app.kubernetes.io/name=<app> --tail=200 | grep -iE "migrat|error|listening"
```
Avoid `-o custom-columns='...[...]...'` / `jsonpath` with brackets in fish — use
plain `get` + `grep`, or wrap in `bash -c`.

## 8. Report

Summarize: merged count, duplicates closed, breaking-change fixes applied, and
the **held PRs with the reason for each**. Offer to schedule/hold the
cluster-roll PRs.
