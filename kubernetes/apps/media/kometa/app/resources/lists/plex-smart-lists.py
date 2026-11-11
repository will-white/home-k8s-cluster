#!/usr/bin/env python3
"""Plex smart "Next Up" lists driven by labels (stdlib only).

sync              label the episodes named in each source list, then make sure
                  every user (owner + shared users) has the smart playlist.
reset NAME [--user U]   mark every item of list NAME unwatched for user U
                  (default: owner), so the smart playlist refills.
Config: plex-smart-lists.json next to this file. Token: KOMETA_PLEX_TOKEN.
Env: PLEX_URL (default http://plex.internal:32400), DRY_RUN=1 to only report,
RECREATE=1 to rebuild playlists (after changing a filter or sort).
"""
import json, os, re, sys, urllib.parse, urllib.request
import xml.etree.ElementTree as ET

URL = os.environ.get("PLEX_URL", "http://plex.internal:32400")
TOKEN = os.environ["KOMETA_PLEX_TOKEN"]
DRY = os.environ.get("DRY_RUN") == "1"
HERE = os.path.dirname(os.path.abspath(__file__))


def call(path, method="GET", token=None, **q):
    q["X-Plex-Token"] = token or TOKEN
    u = URL + path + "?" + urllib.parse.urlencode(q, safe="[]")
    r = urllib.request.Request(u, method=method, headers={"Accept": "application/json"})
    with urllib.request.urlopen(r, timeout=120) as f:
        b = f.read()
    return json.loads(b) if b else {}


def container(path, token=None, **q):
    return call(path, token=token, **q).get("MediaContainer", {})


def section_id(title):
    for d in container("/library/sections")["Directory"]:
        if d["title"] == title:
            return d["key"]
    sys.exit(f"library {title!r} not found")


def parse_source(path):
    """tvdb_episode:<show>_<season>_<episode> lines -> {show: {(s, e)}}"""
    out = {}
    for line in open(path):
        m = re.match(r"\s*tvdb_episode:(\d+)_(\d+)_(\d+)", line)
        if m:
            out.setdefault(m[1], set()).add((int(m[2]), int(m[3])))
    return out


def shows_by_tvdb(sec):
    res = {}
    for s in container(f"/library/sections/{sec}/all", type=2, includeGuids=1).get("Metadata", []):
        for g in s.get("Guid", []):
            if g["id"].startswith("tvdb://"):
                res[g["id"][7:]] = s["ratingKey"]
    return res


def label_id(sec, tag):
    for l in container(f"/library/sections/{sec}/label").get("Directory", []):
        if l["title"].lower() == tag.lower():
            return l["key"]
    return None


def labelled(sec, tag):
    lid = label_id(sec, tag)
    if not lid:
        return {}
    items = container(f"/library/sections/{sec}/all", type=4, label=lid).get("Metadata", [])
    return {i["ratingKey"]: i for i in items}


def users():
    """owner + every shared user: (name, token)."""
    mid = container("/identity")["machineIdentifier"]
    r = urllib.request.Request(f"https://plex.tv/api/servers/{mid}/shared_servers?X-Plex-Token={TOKEN}")
    xml = ET.fromstring(urllib.request.urlopen(r, timeout=30).read())
    out = [("owner", TOKEN)]
    out += [(s.get("username"), s.get("accessToken")) for s in xml.iter("SharedServer") if s.get("accessToken")]
    return mid, out


def sync_labels(cfg, sec):
    want_by_show = parse_source(os.path.join(HERE, cfg["source"]))
    shows = shows_by_tvdb(sec)
    want = {}
    for tvdb, eps in want_by_show.items():
        if tvdb not in shows:
            print(f"  show tvdb {tvdb} not in Plex, skipped")
            continue
        for e in container(f"/library/metadata/{shows[tvdb]}/allLeaves").get("Metadata", []):
            if (e["parentIndex"], e["index"]) in eps:
                want[e["ratingKey"]] = e
    have = labelled(sec, cfg["label"])
    add = sorted(set(want) - set(have))
    drop = sorted(set(have) - set(want))
    print(f"{cfg['label']}: want {len(want)}, have {len(have)}, add {len(add)}, remove {len(drop)}")
    if DRY:
        return
    for rk in add:
        call(f"/library/sections/{sec}/all", "PUT", type=4, id=rk, **{"label[0].tag.tag": cfg["label"], "label.locked": 1})
    for rk in drop:
        call(f"/library/sections/{sec}/all", "PUT", type=4, id=rk, **{"label[].tag.tag-": cfg["label"]})


def sync_playlists(cfg, sec):
    lid = label_id(sec, cfg["label"])
    if not lid:
        print("  no label yet, no playlist")
        return
    mid, accounts = users()
    uri = (f"server://{mid}/com.plexapp.plugins.library/library/sections/{sec}/all"
           f"?type=4&label={lid}&unwatched=1&sort={cfg.get('sort', 'show.titleSort,season.index,episode.index')}")
    for name, tok in accounts:
        have = [p for p in container("/playlists", token=tok).get("Metadata", []) if p["title"] == cfg["name"]]
        if have and have[0].get("smart") and os.environ.get("RECREATE") != "1":
            print(f"  {name}: playlist ok")
            continue
        print(f"  {name}: creating playlist")
        if DRY:
            continue
        for p in have:
            call(f"/playlists/{p['ratingKey']}", "DELETE", token=tok)
        call("/playlists", "POST", token=tok, type="video", title=cfg["name"], smart=1, uri=uri)


def reset(name, user):
    cfg = next(c for c in json.load(open(os.path.join(HERE, "plex-smart-lists.json"))) if c["name"] == name)
    sec = section_id(cfg["library"])
    _, accounts = users()
    tok = dict(accounts).get(user)
    if not tok:
        sys.exit(f"unknown user {user!r}; choices: {[a for a, _ in accounts]}")
    items = labelled(sec, cfg["label"])
    print(f"{user}: marking {len(items)} items unwatched")
    if DRY:
        return
    for rk in items:
        call("/:/unscrobble", token=tok, key=rk, identifier="com.plexapp.plugins.library")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sync"
    if cmd == "reset":
        user = sys.argv[sys.argv.index("--user") + 1] if "--user" in sys.argv else "owner"
        return reset(sys.argv[2], user)
    for cfg in json.load(open(os.path.join(HERE, "plex-smart-lists.json"))):
        sec = section_id(cfg["library"])
        sync_labels(cfg, sec)
        sync_playlists(cfg, sec)


main()
