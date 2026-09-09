#!/usr/bin/env python3
"""Evidence pass for one Renovate PR (see SKILL.md §2).

Usage: evidence.py <pr-number> [--repo owner/repo] [--out DIR] [--no-cluster]

Prints a markdown report and a one-line ledger row. Writes the collected
release notes, flux diffs and helm values diffs to --out (default:
$SCRATCH/evidence/<pr>). Needs: git, python3 (stdlib only). GitHub access goes
through the gh CLI when it is authenticated, otherwise straight to the REST API:
anonymous works for PUBLIC repos (60 req/h per IP, no Flux Diff artifact download);
GH_TOKEN / GITHUB_TOKEN lifts both. --no-gh forces the REST path. Optional: helm
(chart bumps), kubectl + kubeconfig at the repo root or $KUBECONFIG (cluster state).
"""
import argparse, base64, json, os, re, subprocess, sys, difflib
import hashlib, io, time, urllib.error, urllib.parse, urllib.request, zipfile
from pathlib import Path

SIGNAL_RE = re.compile(
    r"breaking|deprecat|\bremov|renam|migrat|schema|\bdatabase\b|irreversib|"
    r"cannot (?:be )?(?:downgrad|revert|roll(?:ed)? back)|no (?:downgrade|rollback)|"
    r"backup|pg_upgrade|\bdump\b|\brestore\b|\bCRD|apiVersion|minimum|"
    r"requires? (?:kubernetes|k8s|helm|postgres|flux)|drop(?:ped)? support|"
    r"default(?:s)? (?:changed|now|is now)|security|\bauth|token|password|permission|"
    r"StatefulSet|\bPVC\b|volume|persist|on-disk|reindex|"
    r"manual (?:step|action|intervention)|before (?:upgrading|you upgrade)|upgrade notes|"
    r"incompatib|not backward|no longer",
    re.I,
)
IMMUTABLE_RE = re.compile(
    r"^-\s+(selector:|matchLabels:|serviceName:|volumeClaimTemplates:|storageClassName:|"
    r"clusterIP:|podManagementPolicy:|completions:|parallelism:)"
)
VENDOR_NOTES = {
    "ghcr.io/cloudnative-pg/postgresql": "https://www.postgresql.org/docs/release/",
    "quay.io/ceph/ceph": "https://docs.ceph.com/en/latest/releases/",
    "docker.io/library/python": "https://docs.python.org/3/whatsnew/changelog.html",
}
GH_ORG_MAP = {  # image org/name -> github repo when the obvious mapping is wrong
    "ghcr.io/siderolabs/installer": "siderolabs/talos",  # installer image ended with Talos 1.13
    "ghcr.io/siderolabs/talos": "siderolabs/talos",
    "ghcr.io/siderolabs/kubelet": "kubernetes/kubernetes",
    "ghcr.io/dragonflydb/operator": "dragonflydb/dragonfly-operator",
    "registry.k8s.io/git-sync/git-sync": "kubernetes/git-sync",
    "docker.io/caddy": "caddyserver/caddy",
    "docker.io/kometateam/kometa": "Kometa-Team/Kometa",
    "ghcr.io/cloudnative-pg/postgresql": "cloudnative-pg/postgres-containers",
    "quay.io/ceph/ceph": "ceph/ceph",
}


def run(cmd, check=False, input=None):
    p = subprocess.run(cmd, capture_output=True, text=True, input=input)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}: {p.stderr.strip()[:300]}")
    return p.returncode, p.stdout


def _git_repo_slug():
    rc, out = run(["git", "remote", "get-url", "origin"])
    m = re.search(r"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$", out.strip())
    return m.group(1) if m else None


# ---------------------------------------------------------------- GitHub access
# Two interchangeable backends. Both return gh-shaped dicts so the collectors do
# not care which one is in use. Selection happens in make_github().
class GhCli:
    # the authenticated gh CLI: 5000 req/h, can download Flux Diff artifacts
    mode = "gh"

    @staticmethod
    def available():
        return run(["gh", "auth", "status"])[0] == 0

    def _json(self, args):
        rc, out = run(["gh"] + args)
        if rc != 0 or not out.strip():
            return None
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return None

    def default_repo(self):
        return (self._json(["repo", "view", "--json", "nameWithOwner"]) or {}).get("nameWithOwner") or _git_repo_slug()

    def pr(self, repo, n):
        return self._json(["pr", "view", str(n), "--repo", repo, "--json",
                           "number,title,state,labels,files,headRefName,headRefOid,baseRefName,body,"
                           "mergeable,mergeStateStatus,comments,url,mergedAt"])

    def pr_diff(self, repo, n):
        return run(["gh", "pr", "diff", str(n), "--repo", repo])[1]

    def api(self, path, cache=True):
        return self._json(["api", path])

    def contents(self, repo, path):
        rc, out = run(["gh", "api", f"repos/{repo}/contents/{path}", "-q", ".content"])
        return base64.b64decode(out).decode(errors="replace") if rc == 0 and out.strip() else None

    def repo_exists(self, repo):
        # exit status, not --jq output: `--jq .full_name` prints a bare string that is not JSON
        return run(["gh", "api", f"repos/{repo}"])[0] == 0

    def prs_all(self, repo, limit=300):
        return self._json(["pr", "list", "--repo", repo, "--state", "all", "--limit", str(limit),
                           "--json", "number,title,state,mergedAt"]) or []

    def flux_runs(self, repo, branch):
        return self._json(["run", "list", "--repo", repo, "--workflow", "Flux Diff", "--branch", branch,
                           "--limit", "3", "--json", "databaseId,headSha,status"]) or []

    def download_artifact(self, repo, run_id, name, dest):
        return run(["gh", "run", "download", str(run_id), "--repo", repo, "-n", name, "-D", str(dest)])[0] == 0

    def banner(self):
        return "github access: gh CLI (authenticated)"

    def footer(self):
        return self.banner()


class Rest:
    # GitHub REST via urllib. Anonymous = PUBLIC repos only, 60 req/h per IP, and
    # artifact zips are refused; GH_TOKEN/GITHUB_TOKEN lifts both. Shared,
    # slow-moving endpoints (releases, tags, contents, the PR list) are cached on
    # disk so a whole backlog costs ~6 requests per PR instead of ~12.
    mode = "rest"

    def __init__(self, cache_dir, token=None, ttl=6 * 3600):
        self.token, self.ttl = token, ttl
        self.cache = Path(cache_dir)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.remaining, self.calls = None, 0

    def _get(self, path, accept="application/vnd.github+json", cache=True):
        url = path if path.startswith("http") else f"https://api.github.com/{path}"
        key = self.cache / (hashlib.sha1((accept + url).encode()).hexdigest() + ".cache")
        if cache and key.exists() and time.time() - key.stat().st_mtime < self.ttl:
            return key.read_bytes()
        req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "merge-renovate-prs/evidence.py",
                                                   "X-GitHub-Api-Version": "2022-11-28"})
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(req, timeout=30) as r:  # follows the 301 of a renamed repo
                self.calls += 1
                self.remaining = r.headers.get("X-RateLimit-Remaining", self.remaining)
                body = r.read()
        except urllib.error.HTTPError as e:
            self.calls += 1
            self.remaining = e.headers.get("X-RateLimit-Remaining", self.remaining)
            if e.code in (403, 429) and e.headers.get("X-RateLimit-Remaining") == "0":
                reset = e.headers.get("X-RateLimit-Reset")
                when = time.strftime("%H:%M:%S", time.localtime(int(reset))) if reset else "?"
                sys.exit(f"GitHub API rate limit exhausted ({'token' if self.token else 'anonymous = 60/h'}); "
                         f"resets at {when}. Set GH_TOKEN or `gh auth login`, or wait.")
            return None
        except (urllib.error.URLError, TimeoutError):
            return None
        if cache:
            key.write_bytes(body)
        return body

    def _json(self, path, cache=True):
        body = self._get(path, cache=cache)
        if body is None:
            return None
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return None

    def default_repo(self):
        return _git_repo_slug()

    def pr(self, repo, n):
        p = self._json(f"repos/{repo}/pulls/{n}", cache=False)
        if not p:
            return None
        files = self._json(f"repos/{repo}/pulls/{n}/files?per_page=100", cache=False) or []
        comments = self._json(f"repos/{repo}/issues/{n}/comments?per_page=100", cache=False) or []
        return {
            "number": p["number"], "title": p["title"],
            "state": "MERGED" if p.get("merged_at") else p["state"].upper(),
            "labels": [{"name": l["name"]} for l in p.get("labels", [])],
            "files": [{"path": f["filename"]} for f in files],
            "headRefName": p["head"]["ref"], "headRefOid": p["head"]["sha"], "baseRefName": p["base"]["ref"],
            "body": p.get("body") or "",
            "mergeable": {True: "MERGEABLE", False: "CONFLICTING"}.get(p.get("mergeable"), "UNKNOWN"),
            "mergeStateStatus": (p.get("mergeable_state") or "unknown").upper(),
            # gh (GraphQL) reports the bot as "github-actions"; REST says "github-actions[bot]"
            "comments": [{"author": {"login": ((c.get("user") or {}).get("login") or "").removesuffix("[bot]")},
                          "body": c.get("body") or ""} for c in comments],
            "url": p["html_url"], "mergedAt": p.get("merged_at"),
        }

    def pr_diff(self, repo, n):
        body = self._get(f"repos/{repo}/pulls/{n}", accept="application/vnd.github.diff", cache=False)
        return body.decode(errors="replace") if body else ""

    def api(self, path, cache=True):
        return self._json(path, cache=cache)

    def contents(self, repo, path):
        j = self._json(f"repos/{repo}/contents/{path}")
        if not j or "content" not in j:
            return None
        return base64.b64decode(j["content"]).decode(errors="replace")

    def repo_exists(self, repo):
        return self._json(f"repos/{repo}") is not None

    def prs_all(self, repo, limit=300):
        out = []
        for page in range(1, max(1, limit // 100) + 1):
            chunk = self._json(f"repos/{repo}/pulls?state=all&sort=created&direction=desc&per_page=100&page={page}") or []
            out += [{"number": x["number"], "title": x["title"], "mergedAt": x.get("merged_at"),
                     "state": "MERGED" if x.get("merged_at") else x["state"].upper()} for x in chunk]
            if len(chunk) < 100:
                break
        return out

    def flux_runs(self, repo, branch):
        q = urllib.parse.quote(branch, safe="")
        runs = (self._json(f"repos/{repo}/actions/runs?branch={q}&per_page=20", cache=False) or {}).get("workflow_runs", [])
        return [{"databaseId": r["id"], "headSha": r["head_sha"], "status": r["status"]} for r in runs if r.get("name") == "Flux Diff"]

    def download_artifact(self, repo, run_id, name, dest):
        if not self.token:
            return False  # artifact zips need an authenticated request even on public repos
        arts = (self._json(f"repos/{repo}/actions/runs/{run_id}/artifacts", cache=False) or {}).get("artifacts", [])
        for a in arts:
            if a.get("name") == name and a.get("archive_download_url"):
                data = self._get(a["archive_download_url"], accept="application/octet-stream", cache=False)
                if data:
                    Path(dest).mkdir(parents=True, exist_ok=True)
                    zipfile.ZipFile(io.BytesIO(data)).extractall(dest)
                    return True
        return False

    def banner(self):
        return "github access: REST " + ("with token" if self.token else "anonymous (public repos only, 60 req/h)")

    def footer(self):
        return f"{self.banner()}; {self.calls} request(s) this run, rate-limit remaining={self.remaining}"


def make_github(no_gh, cache_dir):
    if not no_gh and GhCli.available():
        return GhCli()
    return Rest(cache_dir, os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"))


def core_version(v):
    """'v1.2.3' -> '1.2.3'; '18.6-standard-bookworm' -> '18.6'; 'app-template-5.1.0' -> '5.1.0'."""
    if not v:
        return ""
    m = re.search(r"(\d+(?:\.\d+)*)", v)
    return m.group(1) if m else v


def vtuple(v):
    return tuple(int(x) for x in core_version(v).split(".") if x.isdigit())


# ---------------------------------------------------------------- JSON5 (renovate.json5)
def json5_load(text):
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    text = re.sub(r"'((?:[^'\\]|\\.)*)'", lambda m: json.dumps(m.group(1).replace("\\'", "'")), text)
    text = re.sub(r"(?m)^(\s*)([A-Za-z_$][\w$]*)\s*:", r'\1"\2":', text)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def rule_matches_package(patterns, name):
    short = name.rsplit("/", 1)[-1]
    for p in patterns or []:
        if p.startswith("!"):
            continue
        if p.startswith("/") and p.endswith("/"):
            if re.search(p[1:-1], name):
                return True
        elif "*" in p:
            rx = "^" + re.escape(p).replace(r"\*\*", ".*").replace(r"\*", "[^/]*") + "$"
            if re.match(rx, name):
                return True
        elif p in (name, short):
            return True
    return False


# ---------------------------------------------------------------- collectors
class Evidence:
    def __init__(self, pr, repo, out, cluster, gh):
        self.pr, self.repo, self.out, self.cluster, self.gh = pr, repo, out, cluster, gh
        self.root = Path(run(["git", "rev-parse", "--show-toplevel"])[1].strip() or ".")
        self.out.mkdir(parents=True, exist_ok=True)
        self.report, self.ledger = [], {}

    def say(self, s=""):
        self.report.append(s)

    # ---- PR
    def load_pr(self):
        self.meta = self.gh.pr(self.repo, self.pr)
        if not self.meta:
            sys.exit(f"cannot read PR {self.pr} in {self.repo} ({self.gh.banner()})"
                     + ("" if self.gh.mode == "gh" else " — private repo or bad number? set GH_TOKEN or `gh auth login`"))
        m = self.meta
        self.files = [f["path"] for f in m["files"]]
        self.labels = [l["name"] for l in m["labels"]]
        self.diff = self.gh.pr_diff(self.repo, self.pr)
        self.say(f"# Evidence: PR #{m['number']} — {m['title']}")
        if self.gh.mode != "gh":
            self.say(f"> {self.gh.banner()} — gh CLI unavailable/unauthenticated: truncated Flux Diff artifacts "
                     f"{'need a token' if not getattr(self.gh, 'token', None) else 'are fetched with the token'}; "
                     "rebase/merge/comment still need `gh auth login`")
        self.say(f"{m['url']}  state={m['state']} mergeable={m['mergeable']}/{m['mergeStateStatus']} labels={','.join(self.labels)}")
        self.say(f"files: {', '.join(self.files)}")
        self.apps = sorted({tuple(p.split('/')[2:4]) for p in self.files if p.startswith('kubernetes/apps/') and p.count('/') >= 3})
        self.say(f"apps: {', '.join('/'.join(a) for a in self.apps) or '(none — not a cluster app path)'}")

    def parse_packages(self):
        self.packages = []
        for line in (self.meta.get("body") or "").splitlines():
            if "→" not in line or not line.startswith("|"):
                continue
            cols = [c.strip() for c in line.strip("|").split("|")]
            if len(cols) < 3:
                continue
            name_col, update, change = cols[0], cols[1], cols[2]
            name = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", name_col)
            name = re.sub(r"\s*\(.*?\)\s*$", "", name).strip()
            links = re.findall(r"\((https?://[^)]+)\)", name_col)
            vers = re.findall(r"`([^`]+)`", change)
            cur, new = (vers + ["", ""])[:2]
            self.packages.append({"name": name, "update": update, "cur": cur, "new": new, "links": links})
        if not self.packages:
            self.say("\n> no Renovate package table in body — not a Renovate PR? evidence below is diff-only")
        for p in self.packages:
            self.say(f"\n## {p['name']}  {p['cur']} → {p['new']}  ({p['update']})")

    # ---- kind
    def classify(self):
        kinds = set()
        for f in self.files:
            if "imagecatalog.yaml" in f:
                kinds.add("CNPG-IMAGE (major ⇒ pg_upgrade via NEW catalog entry, see §5)")
            elif "talconfig" in f or "system-upgrade" in f or "tuppr" in f or "siderolabs" in self.diff:
                kinds.add("NODE/CONTROL-PLANE ROLL")
            elif f.endswith("ocirepository.yaml") or (f.endswith("helmrelease.yaml") and re.search(r"^[-+]\s+version:", self.diff, re.M)):
                kinds.add("CHART")
            elif f.endswith("helmrelease.yaml") and re.search(r"^[-+]\s+tag:", self.diff, re.M):
                kinds.add("IMAGE")
            elif f.startswith(".github/workflows"):
                kinds.add("GITHUB-ACTION/CI (workflow scope needed)")
            elif f.startswith(".devcontainer") or f.startswith(".taskfiles"):
                kinds.add("TOOLING (dev only)")
            elif "helmfile" in f:
                kinds.add("BOOTSTRAP-HELMFILE")
            elif "-crds" in f or "crds" in f:
                kinds.add("CRD")
            elif re.search(r"^[-+]\s+revision:", self.diff, re.M):
                kinds.add("GRAFANA-DASHBOARD")
            else:
                kinds.add("OTHER")
        self.kinds = sorted(kinds)
        self.say(f"\n**kind:** {'; '.join(self.kinds)}")
        self.ledger["kind"] = "+".join(k.split(" ")[0] for k in self.kinds)

    # ---- freshness + flux diff
    def flux_diff(self):
        m = self.meta
        cmp = self.gh.api(f"repos/{self.repo}/compare/{m['baseRefName']}...{m['headRefOid']}", cache=False) or {}
        behind = cmp.get("behind_by")
        fresh = "fresh" if behind == 0 else (f"STALE (behind main by {behind})" if behind else "unknown")
        comments = [c["body"] for c in m.get("comments", []) if c["author"]["login"] == "github-actions" and "add-pr-comment" in c["body"]]
        self.say(f"\n### Flux Diff  — branch {fresh}; {len(comments)} CI comment(s)")
        if behind and m["state"] == "OPEN":
            self.say(f"> branch is behind main: `gh pr update-branch {self.pr}` then wait for Flux Diff to re-run before trusting the diff below")
        text = ""
        for c in comments:
            res = re.search(r"add-pr-comment:\d+/kubernetes/(\w+)", c)
            res = res.group(1) if res else "?"
            body = c
            if "Diff truncated" in c:
                art = self.fetch_artifact(res)
                if art:
                    body, self.ledger.setdefault("fluxdiff", []) .append(f"{res}:truncated→artifact")
                    body = art
                else:
                    self.ledger.setdefault("fluxdiff", []).append(f"{res}:TRUNCATED")
            else:
                self.ledger.setdefault("fluxdiff", []).append(f"{res}:ok")
            text += f"\n### {res}\n{body}\n"
            (self.out / f"fluxdiff-{res}.diff").write_text(body)
        if not comments:
            self.ledger["fluxdiff"] = ["NONE"]
            self.say("> no Flux Diff comment (CI not run / no kubernetes/** change) — render locally or wait")
        self.ledger["fresh"] = fresh.split(" ")[0]
        if not text:
            return
        objs = re.findall(r"^--- (.+)$", text, re.M)
        self.say(f"objects changed: {len(objs)}")
        for o in objs[:30]:
            self.say(f"- {o}")
        imgs = re.findall(r"^[-+]\s+image: (.+)$", text, re.M)
        if imgs:
            self.say("image lines:")
            for i in imgs[:20]:
                self.say(f"- {i}")
        imm = [l for l in text.splitlines() if IMMUTABLE_RE.match(l)]
        if imm:
            self.say("**IMMUTABLE-FIELD candidates (helm upgrade may fail; needs delete+recreate → RED):**")
            for l in imm[:20]:
                self.say(f"- `{l.strip()}`")
        self.ledger["immutable"] = len(imm)
        crd = [l for l in text.splitlines() if re.search(r"CustomResourceDefinition|^[-+]\s*apiVersion:", l)]
        if crd:
            self.say(f"CRD / apiVersion lines: {len(crd)} (check install/upgrade.crds policy or the paired -crds PR)")
        # stale noise: objects outside the PR's apps
        if self.apps:
            noise = [o for o in objs if not any(f"{a[0]}/{a[1]}" in o or f"/{a[1]} " in o or f"/{a[1]}\n" in o for a in self.apps)]
            if noise:
                self.say(f"**{len(noise)} object(s) outside this PR's apps appear in the diff** (stale base or shared template): " + "; ".join(noise[:5]))

    def fetch_artifact(self, res):
        runs = self.gh.flux_runs(self.repo, self.meta["headRefName"])
        for r in runs:
            if r["headSha"] == self.meta["headRefOid"] and r["status"] == "completed":
                d = self.out / f"artifact-{res}"
                if self.gh.download_artifact(self.repo, r["databaseId"], f"flux-diff-{res}", d):
                    for f in d.rglob("*.patch"):
                        return f.read_text()
        return None

    # ---- source resolution
    def resolve_source(self, p):
        name = p["name"]
        for l in p["links"]:
            m = re.match(r"https://(?:redirect\.)?github\.com/([^/]+/[^/#?]+)", l)
            if m and "compare" not in l:
                return m.group(1), "renovate body"
        if name in GH_ORG_MAP:
            return GH_ORG_MAP[name], "map"
        m = re.match(r"ghcr\.io/(home-operations|onedr0p)/([^/]+)$", name)
        if m:
            bake = self.gh.contents(f"{m.group(1)}/containers", f"apps/{m.group(2)}/docker-bake.hcl")
            if bake:
                src = re.search(r'SOURCE"\s*\{\s*default\s*=\s*"https://github\.com/([^"]+)"', bake)
                if src:
                    return src.group(1).rstrip("/"), "docker-bake SOURCE"
        m = re.match(r"ghcr\.io/([^/]+/[^/]+)$", name)
        if m and self.gh.repo_exists(m.group(1)):
            return m.group(1), "ghcr org/name"
        return None, "unresolved"

    def chart_info(self, p):
        """For chart bumps: find the chart's OCI/HTTP url from the manifest and diff appVersion/values."""
        url = chart = None
        for f in self.files:
            path = self.root / f
            if not path.exists():
                continue
            txt = path.read_text()
            if f.endswith("ocirepository.yaml"):
                u = re.search(r"^\s*url:\s*(oci://\S+)", txt, re.M)
                if u:
                    url = u.group(1)
            elif f.endswith("helmrelease.yaml"):
                c = re.search(r"^\s*chart:\s*([\w.-]+)\s*$", txt, re.M)
                s = re.search(r"sourceRef:\s*\n\s*kind:\s*(\w+)\s*\n\s*name:\s*([\w.-]+)", txt)
                if c:
                    chart = c.group(1)
                if s:
                    for cand in [path.parent / f"{s.group(2)}.yaml", path.parent / "ocirepository.yaml",
                                 self.root / "kubernetes/flux/repositories/helm" / f"{s.group(2)}.yaml"]:
                        if cand.exists():
                            u = re.search(r"^\s*url:\s*(\S+)", cand.read_text(), re.M)
                            if u and "${" not in u.group(1):
                                url = u.group(1)
                                break
                u = re.search(r"^\s*url:\s*(\S+)", txt, re.M)
                if not url and u and "${" not in u.group(1):
                    url = u.group(1)
        if not url:
            return None
        if url.startswith("oci://"):
            ref = url if (chart is None or url.rstrip("/").endswith("/" + chart)) else f"{url.rstrip('/')}/{chart}"
            base = [ref]
        else:
            base = [chart or "", "--repo", url]
        info = {}
        for tag, v in (("cur", p["cur"]), ("new", p["new"])):
            rc, out = run(["helm", "show", "chart"] + base + ["--version", core_version(v)])
            if rc == 0:
                info[tag] = dict(re.findall(r"^(appVersion|kubeVersion|version):\s*(.+)$", out, re.M))
                srcs = re.findall(r"^\s*-\s*(https://github\.com/[^\s]+)", out, re.M)
                info.setdefault("sources", srcs)
        if not info:
            return None
        info["ref"] = base
        if "app-template" not in str(base):
            vals = {}
            for tag, v in (("cur", p["cur"]), ("new", p["new"])):
                rc, out = run(["helm", "show", "values"] + base + ["--version", core_version(v)])
                vals[tag] = out if rc == 0 else ""
            d = list(difflib.unified_diff(vals["cur"].splitlines(), vals["new"].splitlines(), "values-cur", "values-new", lineterm="", n=2))
            info["values_diff"] = "\n".join(d)
            (self.out / f"values-{chart or 'chart'}.diff").write_text(info["values_diff"])
            info["removed_keys"] = sorted({m.group(1) for l in d if l.startswith("-") and (m := re.match(r"-(\w[\w.-]*):", l))})
        return info

    # ---- releases
    def releases_between(self, repo, cur, new, extra_prefix=None):
        rels = []
        page = 1
        while page <= 4:
            chunk = self.gh.api(f"repos/{repo}/releases?per_page=100&page={page}") or []
            rels += chunk
            if len(chunk) < 100:
                break
            page += 1
        curc, newc = core_version(cur), core_version(new)
        cands = [r for r in rels if r.get("tag_name", "").endswith(newc) or core_version(r.get("tag_name", "")) == newc]
        if not cands:
            return None, "no release tagged for new version"
        # prefer a tag whose prefix looks like the package (monorepos)
        newtag = cands[0]["tag_name"]
        prefix = newtag[: newtag.rfind(newc)] if newc in newtag else ""
        out, hit_cur = [], False
        for r in rels:
            t = r.get("tag_name", "")
            if not t.startswith(prefix) or r.get("prerelease") or r.get("draft"):
                continue
            if core_version(t[len(prefix):]) == curc:
                hit_cur = True
                break
            if vtuple(t[len(prefix):]) and vtuple(t[len(prefix):]) <= vtuple(curc):
                hit_cur = True
                break
            if vtuple(t[len(prefix):]) > vtuple(newc):
                continue
            out.append(r)
        note = "" if hit_cur else " (current tag not found — range may be incomplete)"
        return out, note

    def compare_commits(self, repo, cur, new, prefix=""):
        tags = self.gh.api(f"repos/{repo}/tags?per_page=100") or []
        def find(v):
            for t in tags:
                if core_version(t["name"]) == core_version(v) and t["name"].startswith(prefix):
                    return t["name"]
        a, b = find(cur), find(new)
        if not (a and b):
            return None
        cmp = self.gh.api(f"repos/{repo}/compare/{a}...{b}") or {}
        msgs = [c["commit"]["message"].splitlines()[0] for c in cmp.get("commits", [])]
        return a, b, msgs

    def notes_for(self, label, repo, cur, new):
        rels, note = self.releases_between(repo, cur, new)
        buf = []
        if rels:
            self.say(f"**{label}: {len(rels)} release(s) in ({core_version(cur)}, {core_version(new)}] from {repo}**{note}")
            for r in rels:
                self.say(f"- {r['tag_name']} {r.get('published_at', '')[:10]} {r.get('html_url', '')}")
                buf.append(f"## {r['tag_name']} ({r.get('published_at', '')[:10]})\n{r.get('body') or ''}\n")
            self.ledger.setdefault("notes", []).append(f"{label}:{len(rels)}rel")
        else:
            cc = self.compare_commits(repo, cur, new)
            if cc:
                a, b, msgs = cc
                self.say(f"**{label}: no releases ({note}); {len(msgs)} commits {a}...{b} in {repo}**")
                brk = [m for m in msgs if re.search(r"^[a-z]+(\(.*\))?!:|BREAKING", m)]
                for m in brk[:15]:
                    self.say(f"- ⚠ {m}")
                buf.append("## commits " + f"{a}...{b}\n" + "\n".join(msgs))
                self.ledger.setdefault("notes", []).append(f"{label}:{len(msgs)}commits")
            else:
                cl = self.gh.contents(repo, "CHANGELOG.md")
                if cl:
                    buf.append("## CHANGELOG.md (head)\n" + cl[:20000])
                    self.say(f"**{label}: no releases/tags matched in {repo}; CHANGELOG.md captured (first 20k)** — read it for the range by hand")
                    self.ledger.setdefault("notes", []).append(f"{label}:changelog.md")
                else:
                    self.say(f"**{label}: NO NOTES FOUND in {repo}** ({note}) — evidence gap; see vendor links if any")
                    self.ledger.setdefault("notes", []).append(f"{label}:NONE")
        text = "\n".join(buf)
        (self.out / f"notes-{label}.md").write_text(text)
        return text

    # ---- signals + cross-reference
    def signals(self, text, label):
        hits = []
        tag = ""
        for line in text.splitlines():
            if line.startswith("## "):
                tag = line[3:].split(" ")[0]
            elif SIGNAL_RE.search(line) and len(line) < 600:
                hits.append((tag, line.strip()))
        self.say(f"\n**signals in {label}: {len(hits)}**")
        for t, l in hits[:40]:
            self.say(f"- [{t}] {l}")
        if len(hits) > 40:
            self.say(f"- … {len(hits) - 40} more in {self.out}/notes-{label}.md")
        self.ledger["signals"] = self.ledger.get("signals", 0) + len(hits)
        return hits

    def cross_reference(self, hits, removed_keys):
        toks = set(removed_keys or [])
        for _, l in hits:
            toks |= {t for t in re.findall(r"`([A-Za-z_][\w.\-/]{2,60})`", l)}
            toks |= {t for t in re.findall(r"\b([A-Z][A-Z0-9_]{3,})\b", l)}
        toks = {t for t in toks if t.lower() not in {"true", "false", "null", "readme", "http", "https", "json", "yaml", "todo", "crd", "crds", "api", "pvc", "url"}}
        dirs = [self.root / "kubernetes/apps" / a[0] / a[1] for a in self.apps] or [self.root / "kubernetes"]
        found = []
        for t in sorted(toks)[:150]:
            for d in dirs:
                rc, out = run(["grep", "-rnF", "--include=*.yaml", "--include=*.yml", "--include=*.json", "--include=*.toml", t, str(d)])
                if rc == 0:
                    for l in out.splitlines()[:3]:
                        found.append((t, l.replace(str(self.root) + "/", "")))
        self.say(f"\n**cross-reference: {len(found)} hit(s) of {len(toks)} token(s) from signal lines / removed values keys in {', '.join(str(d.relative_to(self.root)) for d in dirs)}**")
        for t, l in found[:30]:
            self.say(f"- `{t}` → {l[:160]}")
        self.ledger["xref"] = len(found)

    # ---- renovate locks
    def locks(self, p):
        cfg = self.root / ".github/renovate.json5"
        if not cfg.exists():
            return
        try:
            rules = json5_load(cfg.read_text()).get("packageRules", [])
        except Exception as e:
            self.say(f"\n(renovate.json5 parse failed: {e})")
            return
        hits = []
        for r in rules:
            if not rule_matches_package(r.get("matchPackageNames"), p["name"]):
                continue
            lock = {k: r[k] for k in ("allowedVersions", "dependencyDashboardApproval", "enabled", "automerge", "minimumReleaseAge") if k in r}
            if lock and (lock.get("enabled") is False or lock.get("automerge") is False or "allowedVersions" in lock or lock.get("dependencyDashboardApproval")):
                hits.append((r.get("description", ["?"])[-1] if isinstance(r.get("description"), list) else r.get("description", "?"), lock, r.get("matchUpdateTypes")))
        if hits:
            self.say("\n**renovate.json5 locks/gates for this package:**")
            for d, l, ut in hits:
                self.say(f"- {d} → {l}{' (updateTypes ' + ','.join(ut) + ')' if ut else ''}")
        self.ledger["locks"] = len(hits)

    # ---- history
    def history(self, p):
        self.say("\n**history:**")
        for f in self.files[:4]:
            rc, out = run(["git", "log", "--date=short", "--format=%h %ad %s", "-n", "8", "--", f])
            lines = out.strip().splitlines()
            if lines:
                self.say(f"- `{f}`:")
                for l in lines:
                    flag = " ⚠" if re.search(r"revert|rollback|reapply|hold|hotfix|broke", l, re.I) else ""
                    self.say(f"  - {l}{flag}")
        short = p["name"].rsplit("/", 1)[-1]
        prs = self.gh.prs_all(self.repo, 300)
        prior = [x for x in prs if short in x["title"] and x["number"] != self.pr][:6]
        if prior:
            self.say(f"- prior PRs for *{short}*: " + "; ".join(f"#{x['number']} {x['state']} {(x.get('mergedAt') or '')[:10]}" for x in prior))

    # ---- cluster
    def cluster_state(self, chart_info):
        if not self.cluster:
            return
        kc = os.environ.get("KUBECONFIG") or str(self.root / "kubeconfig")
        if not Path(kc).exists():
            self.say("\n(cluster: no kubeconfig — skipped)")
            return
        env = dict(os.environ, KUBECONFIG=kc)
        def k(*a):
            p = subprocess.run(["kubectl", "--request-timeout=8s", *a], capture_output=True, text=True, env=env)
            return p.returncode, p.stdout.strip()
        rc, sv = k("version", "-o", "json")
        if rc != 0:
            self.say("\n(cluster: unreachable — skipped)")
            self.ledger["cluster"] = "unreachable"
            return
        server = json.loads(sv).get("serverVersion", {}).get("gitVersion", "?")
        self.say(f"\n### Cluster (server {server})")
        floor = (chart_info or {}).get("new", {}).get("kubeVersion")
        if floor:
            need = core_version(floor)
            ok = vtuple(server) >= vtuple(need)
            self.say(f"- chart kubeVersion `{floor}` vs server {server}: {'OK' if ok else '**NOT SATISFIED**'}")
        rc, hrs = k("get", "hr", "-A", "--no-headers")
        bad = [l for l in hrs.splitlines() if "\tTrue" not in l and " True " not in l]
        self.say(f"- HelmReleases not Ready cluster-wide: {len(bad)}" + (" → " + "; ".join(l.split()[0] + '/' + l.split()[1] for l in bad[:6]) if bad else ""))
        states = []
        for ns, app in self.apps:
            rc, hr = k("get", "hr", "-n", ns, app, "-o", "jsonpath={.status.conditions[?(@.type==\"Ready\")].status} {.status.lastAttemptedRevision} {.status.conditions[?(@.type==\"Ready\")].message}")
            if rc == 0:
                self.say(f"- hr {ns}/{app}: {hr[:200]}")
                states.append(hr.split(" ")[0] if hr else "?")
            rc, pods = k("get", "pods", "-n", ns, "-l", f"app.kubernetes.io/name={app}", "-o",
                         "jsonpath={range .items[*]}{.metadata.name} {.status.phase} restarts={.status.containerStatuses[0].restartCount}{\"\\n\"}{end}")
            if rc == 0 and pods:
                for l in pods.splitlines()[:5]:
                    self.say(f"  - {l}")
        self.ledger["cluster"] = ("hr:" + "/".join(states)) if states else f"{len(bad)}-notready"

    # ---- driver
    def run_all(self):
        self.load_pr()
        self.parse_packages()
        self.classify()
        self.flux_diff()
        ci = None
        for p in self.packages:
            self.say(f"\n### Source & notes — {p['name']}")
            if "CHART" in self.ledger["kind"] or p["name"].endswith(("/charts", "/helm")) or "chart" in self.meta["title"]:
                ci = self.chart_info(p)
                if ci:
                    self.say(f"- chart: cur {ci.get('cur')} → new {ci.get('new')}")
                    if "values_diff" in ci:
                        n = sum(1 for l in ci["values_diff"].splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---")))
                        self.say(f"- chart default values: {n} changed line(s) ({self.out}/values-*.diff)")
                    if ci.get("removed_keys"):
                        self.say(f"- values keys removed/changed at top level: {', '.join(ci['removed_keys'][:20])}")
            repo, how = self.resolve_source(p)
            if not repo and ci and ci.get("sources"):
                repo = re.sub(r"https://github\.com/", "", ci["sources"][0]).rstrip("/")
                how = "chart sources"
            self.say(f"- source repo: {repo or 'UNRESOLVED'} ({how})" + (f"; vendor notes: {VENDOR_NOTES[p['name']]}" if p["name"] in VENDOR_NOTES else ""))
            hits = []
            if repo:
                text = self.notes_for("pkg", repo, p["cur"], p["new"])
                hits += self.signals(text, "pkg")
                # app inside a chart
                if ci and ci.get("cur", {}).get("appVersion") != ci.get("new", {}).get("appVersion") and ci.get("sources"):
                    app_repo = re.sub(r"https://github\.com/", "", ci["sources"][0]).rstrip("/")
                    if app_repo != repo:
                        atext = self.notes_for("app", app_repo, ci["cur"].get("appVersion", ""), ci["new"].get("appVersion", ""))
                        hits += self.signals(atext, "app")
            else:
                self.ledger.setdefault("notes", []).append("UNRESOLVED")
            self.cross_reference(hits, (ci or {}).get("removed_keys"))
            self.locks(p)
            self.history(p)
        self.cluster_state(ci)
        L = self.ledger
        pk = self.packages[0] if self.packages else {"name": "?", "cur": "", "new": ""}
        row = (f"| #{self.pr} | {pk['name']} {pk['cur']}→{pk['new']} | {L.get('kind')} | "
               f"fluxdiff={','.join(L.get('fluxdiff', ['-']))} branch={L.get('fresh')} imm={L.get('immutable', 0)} | "
               f"notes={','.join(L.get('notes', ['-']))} | signals={L.get('signals', 0)} xref={L.get('xref', 0)} locks={L.get('locks', 0)} | "
               f"cluster={L.get('cluster', 'skipped')} | verdict=? |")
        self.say(f"\n_{self.gh.footer()}_")
        self.say("\n---\nLEDGER " + row)
        print("\n".join(self.report))
        (self.out / "report.md").write_text("\n".join(self.report))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pr", type=int)
    ap.add_argument("--repo")
    ap.add_argument("--out")
    ap.add_argument("--no-cluster", action="store_true")
    ap.add_argument("--no-gh", action="store_true", help="bypass the gh CLI and call the GitHub REST API directly")
    ap.add_argument("--cache-dir", help="REST response cache (default $SCRATCH/evidence/_cache, 6h TTL)")
    a = ap.parse_args()
    scratch = os.environ.get("SCRATCH", "/tmp")
    gh = make_github(a.no_gh, a.cache_dir or os.path.join(scratch, "evidence", "_cache"))
    repo = a.repo or gh.default_repo()
    if not repo:
        sys.exit("cannot determine repo; pass --repo owner/repo")
    base = a.out or os.path.join(scratch, "evidence", str(a.pr))
    Evidence(a.pr, repo, Path(base), not a.no_cluster, gh).run_all()


if __name__ == "__main__":
    main()
