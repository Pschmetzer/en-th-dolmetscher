#!/usr/bin/env python3
# ruff: noqa: E501
"""Haelt die Web-Version konsistent: PRESET_IDS in index.html und sw.js aus presets-index.json, Cache-Version von sw.js per Inhalts-Hash.

Aufruf im Repo-Ordner:  python3 tools/sync_web.py          (schreibt index.html und sw.js neu, zaehlt CACHE hoch, wenn sich Vorab-Dateien geaendert haben)
                        python3 tools/sync_web.py --check  (Exitcode 1, wenn etwas veraltet ist; fuer CI und tools/check_all.sh)
PRESET_IDS = Reihenfolge von presets-index.json ohne die Pakete aus tools/web_pending_presets.txt.
Hash = SHA-256 ueber alle Dateien, die der Service Worker vorab speichert (CORE ohne index.html, das immer zuerst vom Netz kommt,
plus presets/<id>.json). Steht der Hash in der Zeile `// content-hash:` von sw.js nicht mehr, ist CACHE zu erhoehen.
"""
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIST_RE = re.compile(r"const PRESET_IDS = \[[^\]]*\];")
CACHE_RE = re.compile(r"const CACHE = 'dolmetscher-web-v(\d+)';")
HASH_RE = re.compile(r"^// content-hash: ([0-9a-f]{16})$", re.M)


def pending(root=ROOT):
    f = pathlib.Path(root) / "tools" / "web_pending_presets.txt"
    if not f.exists():
        return set()
    return {x.strip() for x in f.read_text(encoding="utf-8").splitlines() if x.strip() and not x.startswith("#")}


def preset_ids(root=ROOT):
    idx = json.loads((pathlib.Path(root) / "presets-index.json").read_text(encoding="utf-8"))["packs"]
    skip = pending(root)
    return [p["id"] for p in idx if p["id"] not in skip]


def js_list(src, name):
    m = re.search(r"const " + name + r" = \[([^\]]*)\]", src)
    return re.findall(r"'([\w./-]+)'", m.group(1)) if m else []


def content_hash(sw_src, ids, root=ROOT):
    """Hash ueber Namen und Inhalt aller Vorab-Dateien (ohne index.html); fehlende Dateien zaehlen als leer."""
    root = pathlib.Path(root)
    files = sorted({f for f in js_list(sw_src, "CORE") if f not in ("./", "index.html")} | {"presets/%s.json" % i for i in ids})
    h = hashlib.sha256()
    for f in files:
        p = root / f
        h.update(f.encode("utf-8") + b"\0" + (p.read_bytes() if p.is_file() else b"") + b"\0")
    return h.hexdigest()[:16]


def render_list(ids):
    return "const PRESET_IDS = [" + ", ".join("'%s'" % i for i in ids) + "];"


def sync(root=ROOT, write=True):
    """Gibt (Liste der Abweichungen, neuer sw-Text, neuer index-Text) zurueck."""
    root = pathlib.Path(root)
    ids = preset_ids(root)
    html = (root / "index.html").read_text(encoding="utf-8")
    sw = (root / "sw.js").read_text(encoding="utf-8")
    problems = []
    for name, src in (("index.html", html), ("sw.js", sw)):
        if not LIST_RE.search(src):
            problems.append("%s: PRESET_IDS nicht gefunden" % name)
        elif js_list(src, "PRESET_IDS") != ids:
            problems.append("%s: PRESET_IDS weicht von presets-index.json ab" % name)
    new_html = LIST_RE.sub(lambda m: render_list(ids), html, count=1)
    new_sw = LIST_RE.sub(lambda m: render_list(ids), sw, count=1)
    want = content_hash(new_sw, ids, root)
    have = HASH_RE.search(new_sw)
    if not have or have.group(1) != want:
        problems.append("sw.js: Inhalts-Hash veraltet (CACHE erhoehen)")
        m = CACHE_RE.search(new_sw)
        if m:
            bumped = "const CACHE = 'dolmetscher-web-v%d';" % (int(m.group(1)) + 1)
            new_sw = CACHE_RE.sub(lambda _m: bumped, new_sw, count=1)
        line = "// content-hash: " + want
        new_sw = HASH_RE.sub(line, new_sw, count=1) if have else new_sw.replace("\nconst CACHE =", "\n" + line + "\nconst CACHE =", 1)
    if write:
        (root / "index.html").write_text(new_html, encoding="utf-8")
        (root / "sw.js").write_text(new_sw, encoding="utf-8")
    return problems, new_sw, new_html


if __name__ == "__main__":
    probs, _sw, _html = sync(write="--check" not in sys.argv)
    if "--check" in sys.argv:
        for p in probs:
            print(p, file=sys.stderr)
        if probs:
            print("Abhilfe: python3 tools/sync_web.py", file=sys.stderr)
        sys.exit(1 if probs else 0)
    print("index.html und sw.js synchron" + (" (%s)" % "; ".join(probs) if probs else " (nichts zu tun)"))
