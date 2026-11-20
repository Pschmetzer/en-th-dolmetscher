# ruff: noqa: E501
"""Runde 22 (Web): Index == Pakete, Service-Worker-Listen, Cache-Hash, Manifest, Kopfdaten, tote Verweise, Thai-Unicode-Lint."""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import unicodedata

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import sync_web  # noqa: E402

HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
MANIFEST = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
INDEX = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))
PACKS = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "presets").glob("*.json"))}
NEW_R22 = ["numbers-prices", "negotiation", "buddhism-etiquette", "scooter-rental-damage", "doctor-symptom-detail",
           "tuk-tuk-scam-prevention", "embassy-consulate", "food-spice-level", "hearing-speech-impaired",
           "wheelchair-mobility", "halal-food-muslim", "refund-complaint-shop", "hotel-room-problems", "lost-wallet-cards"]
CANONICAL = "https://pschmetzer.github.io/en-th-dolmetscher/"


def _list(src, name):
    m = re.search(r"const " + name + r" = \[([^\]]*)\]", src)
    assert m, name
    return re.findall(r"'([\w./-]+)'", m.group(1))


# ---- Index == Pakete ----

def test_index_matches_package_files_exactly():
    ids = [p["id"] for p in INDEX["packs"]]
    assert len(ids) == len(set(ids))
    assert set(ids) == set(PACKS)
    for p in INDEX["packs"]:
        d = PACKS[p["id"]]
        assert p["names"] == d["names"], p["id"]
        assert p["phrases"] == len(d["phrases"]), p["id"]
        assert p["critical"] == sum(1 for x in d["phrases"] if x.get("critical")), p["id"]
        assert p["category"] in {"health", "emergency", "transport", "food", "money", "stay", "culture", "leisure", "general"}


def test_routes_only_name_existing_packs():
    for rid, r in INDEX.get("routes", {}).items():
        assert set(r["packs"]) <= set(PACKS), (rid, set(r["packs"]) - set(PACKS))
        assert len(r["packs"]) == len(set(r["packs"])), rid


# ---- Service Worker ----

def test_sw_and_page_lists_follow_index_minus_pending():
    ids = sync_web.preset_ids()
    assert _list(SW, "PRESET_IDS") == ids
    assert _list(HTML, "PRESET_IDS") == ids


def test_sw_priority_packs_exist_and_come_first():
    prio = _list(SW, "PRIORITY")
    assert {"emergency", "police", "doctor", "hospital", "lostchild", "pharmacy", "food-allergy"} <= set(prio)
    assert set(prio) <= set(_list(SW, "PRESET_IDS")), set(prio) - set(_list(SW, "PRESET_IDS"))
    assert len(prio) == len(set(prio))
    assert "FIRST.concat(PRESET_IDS.filter(id => !FIRST.includes(id)))" in SW
    assert "e.data.priorityOnly === true" in SW and "saveData()" in SW and "MIN_FREE" in SW and "estimate()" in SW


def test_cache_hash_is_current_and_cache_name_keeps_format():
    assert re.search(r"^const CACHE = 'dolmetscher-web-v\d+';$", SW, re.M)
    assert re.search(r"^// content-hash: [0-9a-f]{16}$", SW, re.M)
    assert sync_web.sync(write=False)[0] == []


def test_sync_web_check_detects_drift(tmp_path):
    for f in ("index.html", "sw.js", "presets-index.json", "manifest.webmanifest", "languages.json", "allergens.json"):
        shutil.copy(ROOT / f, tmp_path / f)
    (tmp_path / "tools").mkdir()
    shutil.copy(ROOT / "tools" / "web_pending_presets.txt", tmp_path / "tools" / "web_pending_presets.txt")
    shutil.copytree(ROOT / "presets", tmp_path / "presets")
    sync_web.sync(tmp_path, write=True)                                                        # Ausgangslage: Kopie ohne Icons/i18n, Hash neu
    assert sync_web.sync(tmp_path, write=False)[0] == []
    (tmp_path / "presets" / "doctor.json").write_text('{"changed": true}', encoding="utf-8")   # Inhalt ändert sich: CACHE muss hoch
    probs, new_sw, _ = sync_web.sync(tmp_path, write=False)
    assert any("Hash" in p for p in probs)
    old_v = int(re.search(r"dolmetscher-web-v(\d+)", (tmp_path / "sw.js").read_text(encoding="utf-8")).group(1))
    assert "dolmetscher-web-v%d'" % (old_v + 1) in new_sw
    sw_txt = (tmp_path / "sw.js").read_text(encoding="utf-8").replace("'doctor', ", "", 1)   # Liste weicht ab
    (tmp_path / "sw.js").write_text(sw_txt, encoding="utf-8")
    assert any("PRESET_IDS" in p for p in sync_web.sync(tmp_path, write=False)[0])
    sync_web.sync(tmp_path, write=True)
    assert sync_web.sync(tmp_path, write=False)[0] == []                                      # danach idempotent


@pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
def test_sw_loads_priority_packs_first_and_only_them_in_data_saver(tmp_path):
    js = r"""
const vm = require('vm'), fs = require('fs');
const store = new Map(), fetched = [], handlers = {};
const resp = body => ({ ok: true, status: 200, body, clone() { return resp(body); } });
const cache = { add: async u => { store.set(u.url || u, resp('x')); }, put: async (r, v) => { store.set(r.url || r, v); }, match: async r => store.get(r.url || r) };
const ctx = { URL, Response: function () {}, Request: function (u) { this.url = u; },
  self: { registration: { scope: 'https://x.test/a/' }, location: { origin: 'https://x.test' }, addEventListener: (t, f) => { handlers[t] = f; }, skipWaiting: async () => {}, clients: { claim: async () => {} } },
  caches: { open: async () => cache, keys: async () => [], delete: async () => {}, match: async () => undefined },
  fetch: async r => { fetched.push(String(r.url || r)); return resp('p'); }, setInterval: () => 0, clearInterval: () => {},
  navigator: { connection: { saveData: process.argv[3] === 'save' }, storage: { estimate: async () => ({ quota: 1e9, usage: 0 }) } } };
ctx.globalThis = ctx; vm.createContext(ctx);
vm.runInContext(fs.readFileSync(process.argv[2], 'utf8'), ctx);
(async () => {
  const w = [];
  handlers.message({ data: { type: 'cache-presets', priorityOnly: false }, source: { postMessage() {} }, waitUntil: p => w.push(p) });
  await Promise.all(w);
  console.log(JSON.stringify({ first: fetched.slice(0, 3).map(u => u.split('/').pop()), n: fetched.length, prio: vm.runInContext('FIRST.length', ctx), all: vm.runInContext('PACKS.length', ctx) }));
})();
"""
    f = tmp_path / "h.js"
    f.write_text(js, encoding="utf-8")
    out = {}
    for mode in ("normal", "save"):
        r = subprocess.run(["node", str(f), str(ROOT / "sw.js"), mode], capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stderr
        out[mode] = json.loads(r.stdout.strip().splitlines()[-1])
    first = _list(SW, "PRIORITY")[0]
    assert out["normal"]["first"][0] == first + ".json" and out["normal"]["n"] == out["normal"]["all"]
    assert out["save"]["n"] == out["save"]["prio"] < out["save"]["all"]


def test_page_asks_for_persistence_only_when_installed_and_passes_save_data():
    assert "(display-mode: standalone)" in HTML and "priorityOnly: lite" in HTML


# ---- Manifest ----

def test_manifest_shortcuts_share_target_and_launch_handler():
    assert MANIFEST["share_target"]["method"] == "GET" and set(MANIFEST["share_target"]["params"]) == {"title", "text", "url"}
    assert MANIFEST["launch_handler"]["client_mode"] == "navigate-existing"
    assert MANIFEST["handle_links"] == "preferred"
    urls = [s["url"] for s in MANIFEST["shortcuts"]]
    assert len(urls) == len(set(urls)) and "./#preset=emergency" in urls and "./#preset=pharmacy" in urls
    for s in MANIFEST["shortcuts"]:
        assert s["name"] and s["short_name"] and len(s["short_name"]) <= 12, s
        m = re.fullmatch(r"\./#preset=([\w-]+)", s["url"])
        if m:
            assert m.group(1) in PACKS, s["url"]
        for ic in s["icons"]:
            assert (ROOT / ic["src"]).is_file()


def test_manifest_has_no_dead_files():
    for ic in MANIFEST["icons"] + MANIFEST.get("screenshots", []):
        assert (ROOT / ic["src"]).is_file(), ic["src"]


# ---- Kopfdaten, CSP, tote Verweise ----

def test_head_has_canonical_open_graph_twitter_and_json_ld():
    assert f'<link rel="canonical" href="{CANONICAL}">' in HTML
    for k in ("og:title", "og:description", "og:url", "og:image", "og:type"):
        assert f'property="{k}"' in HTML, k
    for k in ("twitter:card", "twitter:title", "twitter:image"):
        assert f'name="{k}"' in HTML, k
    ld = json.loads(re.search(r'<script type="application/ld\+json">\s*(\{.*?\})\s*</script>', HTML, re.S).group(1))
    assert ld["@type"] == "WebApplication" and ld["url"] == CANONICAL and ld["offers"]["price"] == "0"
    og_image = re.search(r'property="og:image" content="([^"]+)"', HTML).group(1)
    assert og_image.startswith(CANONICAL) and (ROOT / og_image[len(CANONICAL):]).is_file()


def test_crawler_files_agree_with_canonical():
    robots = (ROOT / "robots.txt").read_text(encoding="utf-8")
    assert "User-agent: *" in robots and f"Sitemap: {CANONICAL}sitemap.xml" in robots
    assert f"<loc>{CANONICAL}</loc>" in (ROOT / "sitemap.xml").read_text(encoding="utf-8")
    llms = (ROOT / "llms.txt").read_text(encoding="utf-8")
    assert llms.startswith("# ") and CANONICAL in llms and f"{len(PACKS)} scenario packs" in llms
    assert "not yet checked by native speakers" in llms


def test_csp_is_hardened_without_breaking_inline_app():
    csp = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', HTML).group(1)
    for d in ("default-src 'none'", "frame-src 'none'", "object-src 'none'", "script-src-attr 'none'", "base-uri 'none'", "form-action 'none'"):
        assert d in csp, d
    assert not re.search(r"\son(?:click|change|input|load|error|submit|keydown)=", HTML), "Inline-Handler brechen script-src-attr 'none'"
    assert "unsafe-eval" not in csp


def test_no_dead_local_links():
    srcs = re.findall(r'(?:href|src)="([^"#:]+?)(?:[?#][^"]*)?"', HTML)
    local = [s for s in srcs if not s.startswith(("http", "mailto", "tel", "data", "javascript", "//"))]
    assert local, "keine lokalen Verweise gefunden: Regex prüfen"
    for s in local:
        assert (ROOT / s).exists(), f"toter Verweis in index.html: {s}"
    for f in ("index.html", "sw.js", "manifest.webmanifest", "README.md", "docs/WEB-HOSTING.md", "llms.txt"):
        assert "partner.html" not in (ROOT / f).read_text(encoding="utf-8"), f


def test_tabs_accessible_and_show_card_keeps_screen_awake():
    assert 'role="tablist" aria-orientation="horizontal"' in HTML
    assert "e.key === 'Home' || e.key === 'End'" in HTML and "aria-selected" in HTML
    wake = re.search(r"async function updateWakeLock\(\) \{(.*?)\n\}", HTML, re.S).group(1)
    assert "$('partner').classList.contains('on')" in wake and "wakeLock.request('screen')" in wake
    assert "@media (prefers-contrast: more)" in HTML and "@media (pointer:coarse)" in HTML
    assert "a:focus-visible" in HTML


# ---- Neue Pakete ----

@pytest.mark.parametrize("pid", NEW_R22)
def test_new_r22_pack(pid):
    d = PACKS[pid]
    ix = next(p for p in INDEX["packs"] if p["id"] == pid)
    assert ix["reviewed"] is False and ix["category"] != "general"
    assert d["style"] == "polite" and 12 <= len(d["phrases"]) <= 25
    assert d["note"]["de"].endswith("Thai-Sätze maschinell erstellt, nicht von Muttersprachlern geprüft.")
    assert "ครับ/ค่ะ" in d["note"]["de"] and "krub/ka" in d["note"]["en"]           # Partikel-Hinweis
    flags = [bool(p.get("critical")) for p in d["phrases"]]
    assert flags == sorted(flags, reverse=True)                                    # kritische Sätze zuerst


# ---- Thai-Unicode-Lint ----

ZERO_WIDTH = re.compile("[​‌‍⁠﻿­]")
TONES = "่้๊๋"


def _thai_texts():
    for pid, d in PACKS.items():
        yield pid + " names.th", d["names"]["th"]
        for i, p in enumerate(d["phrases"]):
            yield f"{pid} phrases[{i}]", p["th"]
        for i, g in enumerate(d.get("glossary", [])):
            yield f"{pid} glossary[{i}]", g["th"]
    for lang in ("th",):
        data = json.loads((ROOT / "i18n" / f"{lang}.json").read_text(encoding="utf-8"))
        for k, v in data.items():
            if isinstance(v, str):
                yield f"i18n/th.json {k}", " ".join(v.split())   # Fließtext: Leerraum nicht prüfen


def thai_problems(t, ws=True):
    out = []
    if unicodedata.normalize("NFC", t) != t:
        out.append("nicht NFC")
    if ZERO_WIDTH.search(t):
        out.append("unsichtbares Zeichen")
    if "ํา" in t:
        out.append("Nikhahit + Sara Aa statt Sara Am (ำ)")
    if re.search("[" + TONES + "]{2}", t):
        out.append("zwei Tonzeichen hintereinander")
    if re.search("ะ{2}|า{2}|ำ{2}", t):
        out.append("doppelter Vokal")
    if re.search(r"[ิีึืั][ิีึืั]", t):
        out.append("zwei Obervokale hintereinander")
    if re.match(r"[ะัาำิีึืฺุู็่้๊๋์ํ]", t.lstrip()):
        out.append("beginnt mit Vokal-/Tonzeichen")
    if re.search(r"[เแโใไ]\s", t) or re.search(r"[เแโใไ]$", t):
        out.append("Vorangestellter Vokal ohne Konsonant")
    if re.search(r"[๐-๙]", t) and re.search(r"[0-9]", t):
        out.append("Thai- und arabische Ziffern gemischt")
    if ws and ("  " in t or t != t.strip()):
        out.append("Leerzeichen")
    return out


def test_thai_lint_catches_known_defects():
    assert thai_problems("ก่้า") and thai_problems("ก​ข") and thai_problems("่ก") and thai_problems("กํา")
    assert thai_problems("เ ") and thai_problems("๑2") and thai_problems("ก  ข")
    assert thai_problems("ขอบคุณ") == [] and thai_problems("ช่วยจดความเสียหายลงในสัญญา") == []


def test_all_thai_texts_pass_unicode_lint():
    bad = [(w, thai_problems(t)) for w, t in _thai_texts() if thai_problems(t)]
    assert not bad, bad[:5]
