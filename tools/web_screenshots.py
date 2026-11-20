#!/usr/bin/env python3
"""Screenshots der Web-Seite fuer manifest.webmanifest ("screenshots"), mit Chrome im Headless-Modus (kein Playwright noetig).

Aufruf (Repo-Wurzel): python3 tools/web_screenshots.py [--url http://localhost:8000/] [--chrome PFAD]
Ohne --url startet das Skript einen lokalen Server auf Port 8765. Die Bilder landen in screenshots/ und werden mit den
passenden Eintraegen in manifest.webmanifest verknuepft. Die Seite zeigt dabei die englische Oberflaeche (Hash ui=en). Headless-Chrome ist mindestens ca. 500 Pixel breit.
"""
import argparse
import http.server
import json
import pathlib
import shutil
import subprocess
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = [  # Datei, Fenstergroesse, Adresse (Hash waehlt den Bereich), Beschriftung, form_factor
    ("speak-narrow.png", (540, 1100), "#speak&ui=en", "Speak: choose who talks, type, two-person screen", "narrow"),
    ("phrasebook-narrow.png", (540, 1100), "#book&ui=en", "Phrasebook with show cards and quick answers", "narrow"),
    ("cards-narrow.png", (540, 1100), "#cards&ui=en&open=allergyBox", "Allergy card and own cards", "narrow"),
    ("phrasebook-wide.png", (1280, 900), "#book&ui=en", "Phrasebook on a large screen", "wide"),
]
CHROME = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "google-chrome", "chromium", "chromium-browser"]


def find_chrome(given):
    for c in ([given] if given else CHROME):
        if c and (pathlib.Path(c).exists() or shutil.which(c)):
            return c
    raise SystemExit("Chrome nicht gefunden: --chrome PFAD angeben")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url")
    ap.add_argument("--chrome")
    a = ap.parse_args()
    chrome, server, url = find_chrome(a.chrome), None, a.url
    if not url:
        h = type("H", (http.server.SimpleHTTPRequestHandler,), {"__init__": lambda s, *x, **k: http.server.SimpleHTTPRequestHandler.__init__(s, *x, directory=str(ROOT), **k),
                                                                "log_message": lambda *x: None})
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), h)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = "http://127.0.0.1:8765/"
    out = ROOT / "screenshots"
    out.mkdir(exist_ok=True)
    entries = []
    for name, (w, h), frag, label, ff in SHOTS:
        with tempfile.TemporaryDirectory() as prof:   # frisches Profil: Standardeinstellungen, englisch erzwungen ueber die Browsersprache
            target = out / name
            target.unlink(missing_ok=True)
            proc = subprocess.Popen([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={prof}", "--lang=en-US",
                                     f"--window-size={w},{h}", "--virtual-time-budget=6000", f"--screenshot={target}", url + frag],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:   # Chrome beendet sich im neuen Headless-Modus nicht immer von selbst: warten, bis das Bild fertig ist, dann beenden
                for _ in range(240):
                    time.sleep(0.5)
                    if target.exists() and target.stat().st_size > 0:
                        time.sleep(1)
                        break
                else:
                    raise SystemExit(f"Kein Screenshot fuer {name}")
            finally:
                proc.terminate()
                try:
                    proc.wait(10)
                except subprocess.TimeoutExpired:
                    proc.kill()
        entries.append({"src": f"screenshots/{name}", "sizes": f"{w}x{h}", "type": "image/png", "form_factor": ff, "label": label})
    if server:
        server.shutdown()
    mf = ROOT / "manifest.webmanifest"
    m = json.loads(mf.read_text(encoding="utf-8"))
    m["screenshots"] = entries
    mf.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("ok:", ", ".join(e["src"] for e in entries))


if __name__ == "__main__":
    main()
