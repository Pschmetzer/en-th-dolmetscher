#!/usr/bin/env python3
"""Smoke-Test der ausgelieferten Web-Version (GitHub Pages oder jeder statische Server).

Aufruf:  python3 tools/pages_smoke.py https://pschmetzer.github.io/en-th-dolmetscher/ [--wait 600] [--sample 8]
         python3 tools/pages_smoke.py http://localhost:8000/        (lokal: python3 -m http.server)

Prüft: Kern-Dateien liefern 200 und sind nicht leer, JSON/Manifest sind gültig, index.html hat die CSP,
sw.js hat eine Cache-Version, eine Stichprobe der Phrasenpakete ist abrufbar. Mit --wait wird so lange gewartet
(Abfrage alle 15 s), bis die ausgelieferte Cache-Version von sw.js der im Repo entspricht: so findet der Test nach einem
Push den fertigen Deploy und nicht den alten Stand. Nur Standardbibliothek; Exitcode 1 bei Fehlern.
"""
import argparse
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = (
    "index.html", "sw.js", "manifest.webmanifest", "robots.txt", "sitemap.xml", "languages.json", "presets-index.json",
    "allergens.json", "icon.svg", "icon-192.png", "icon-512.png", "icon-maskable-192.png", "icon-maskable-512.png",
    "apple-touch-icon-180.png", "i18n/en.json", "i18n/th.json",
)
CACHE_RE = re.compile(r"const CACHE = '(dolmetscher-web-v\d+)';")
UA = "dolmetscher-pages-smoke/1"


def fetch(base, path, timeout=20):
    req = urllib.request.Request(base + path, headers={"User-Agent": UA, "Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=timeout) as r:        # noqa: S310 (nur http/https-Adressen aus main())
        return r.status, r.headers.get("Content-Type", ""), r.read()


def local_cache_version(root=ROOT):
    m = CACHE_RE.search((pathlib.Path(root) / "sw.js").read_text(encoding="utf-8"))
    return m.group(1) if m else None


PRESET_IDS_RE = re.compile(r"const PRESET_IDS = \[([^\]]*)\];")


def sw_preset_drift(sw_text, index_ids):
    """Runde 24: Paket-IDs, die sw.js offline vorhält, aber presets-index.json nicht kennt (oder umgekehrt).
    Sonst lädt der Service Worker nie existierende Dateien oder lässt neue Pakete offline fehlen."""
    m = PRESET_IDS_RE.search(sw_text or "")
    if not m:
        return ["sw.js: keine PRESET_IDS-Liste"]
    sw_ids = set(re.findall(r"'([^']+)'", m.group(1)))
    idx = set(index_ids)
    errors = [f"sw.js: PRESET_IDS enthält unbekanntes Paket {i}" for i in sorted(sw_ids - idx)]
    errors += [f"sw.js: Paket {i} fehlt in PRESET_IDS" for i in sorted(idx - sw_ids)]
    return errors


def check(base, sample=8, root=ROOT):
    """Liste der Fehler (leer = alles gut)."""
    errors, bodies = [], {}
    for path in CORE:
        try:
            status, _ctype, body = fetch(base, path)
        except (urllib.error.URLError, OSError) as e:
            errors.append(f"{path}: {e}")
            continue
        if status != 200 or not body:
            errors.append(f"{path}: Status {status}, {len(body)} Byte")
            continue
        bodies[path] = body
    for path in (p for p in bodies if p.endswith((".json", ".webmanifest"))):
        try:
            json.loads(bodies[path].decode("utf-8"))
        except ValueError as e:
            errors.append(f"{path}: kein gültiges JSON ({e})")
    html = bodies.get("index.html", b"").decode("utf-8", "replace")
    if html and "Content-Security-Policy" not in html:
        errors.append("index.html: keine Content-Security-Policy")
    sw = bodies.get("sw.js", b"").decode("utf-8", "replace")
    if sw and not CACHE_RE.search(sw):
        errors.append("sw.js: keine Cache-Version (const CACHE = ...)")
    if "presets-index.json" in bodies:
        try:
            ids = [p["id"] for p in json.loads(bodies["presets-index.json"])["packs"]]
        except (ValueError, KeyError, TypeError):
            ids = []
            errors.append("presets-index.json: keine Paketliste")
        if sw:
            errors.extend(sw_preset_drift(sw, ids))
        for pid in ids[:sample]:
            try:
                status, _c, body = fetch(base, f"presets/{pid}.json")
                json.loads(body.decode("utf-8"))
                if status != 200:
                    errors.append(f"presets/{pid}.json: Status {status}")
            except (urllib.error.URLError, OSError, ValueError) as e:
                errors.append(f"presets/{pid}.json: {e}")
    return errors


def wait_for_deploy(base, expected, wait, interval=15):
    """Wartet, bis sw.js die erwartete Cache-Version ausliefert; True bei Erfolg."""
    end = time.time() + wait
    seen = None
    while True:
        try:
            _s, _c, body = fetch(base, "sw.js")
            m = CACHE_RE.search(body.decode("utf-8", "replace"))
            seen = m.group(1) if m else None
            if seen == expected:
                return True
        except (urllib.error.URLError, OSError):
            pass
        if time.time() >= end:
            print(f"Ausgeliefert: {seen}, erwartet: {expected}", file=sys.stderr)
            return False
        time.sleep(interval)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("url", help="Basisadresse der Seite, z. B. https://example.org/dolmetscher/")
    ap.add_argument("--wait", type=int, default=0, help="Sekunden warten, bis die Cache-Version dem Repo entspricht")
    ap.add_argument("--sample", type=int, default=8, help="Anzahl der abgerufenen Phrasenpakete")
    a = ap.parse_args(argv)
    if not a.url.startswith(("http://", "https://")):
        ap.error("nur http:// oder https://")
    base = a.url if a.url.endswith("/") else a.url + "/"
    if a.wait:
        expected = local_cache_version()
        if not expected:                       # ohne Version würde "nichts gefunden" als Treffer gelten
            print("FEHLER: sw.js im Repo hat keine Cache-Version")
            return 1
        if not wait_for_deploy(base, expected, a.wait):
            print("FEHLER: Deploy mit der erwarteten Version nicht erschienen")
            return 1
    errors = check(base, a.sample)
    for e in errors:
        print("FEHLER:", e)
    if not errors:
        print(f"OK: {base} liefert alle Kern-Dateien (Cache {local_cache_version()})")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
