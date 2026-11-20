# ruff: noqa: E501
"""Runde 23 (Web/PWA): Service Worker (Preload, Backoff, Bytefortschritt), Datenschutz, Notfall-Schnellzugriff, Zielkarte, Barrierefreiheit."""
import json
import pathlib
import re

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, func, line, prelude, run, web_str

SW = (ROOT / "sw.js").read_text(encoding="utf-8")
node = pytest.mark.skipif(not HAVE_NODE, reason="node nicht installiert")
R23_KEYS = ["sosBtn", "sosLbl", "sosTitle", "sosIntro", "sosPolice", "sosAmb", "sosFire", "sosTourist", "sosHighway", "sosIntl", "sosShowAmb", "sosShowPol", "sosClose",
            "destSum", "destHint", "destKindTaxi", "destKindHotel", "destKind", "destName", "destAddr", "destPick", "destShow", "destSay", "destSave", "destSaved", "destEmpty",
            "privSum", "privOnlineOff", "privOnlineNote", "privSens", "onlineOffNow", "sensWarn", "sensDeclined", "privRetain", "privRetainOff", "privDays", "privUsage",
            "privSwept", "privExport", "privImport", "privFile", "privExported", "privImported", "privBadFile", "privBigFile", "privEmptyFile", "privConfirmImport", "privIos", "swUpdating", "swMb"]


# ---- Service Worker ----
def test_sw_navigation_preload_enabled_and_used():
    assert "navigationPreload.enable()" in SW
    assert "e.preloadResponse" in SW


def test_sw_pack_loading_retries_with_backoff_and_counts_bytes():
    assert "RETRIES = 3" in SW and "BACKOFF_MS * 2 ** n" in SW
    assert "bytes: packBytes" in SW


def test_sw_announces_version_to_pages():
    assert "type: 'sw-version'" in SW


@node
def test_sw_fetch_pack_retries_then_gives_up():
    import subprocess
    src = "\n".join([
        "let calls = 0; const abs = u => u; const sleep = () => Promise.resolve();",
        re.search(r"^const RETRIES = 3.*$", SW, re.M).group(0),
        re.search(r"^const sizeOf = .*$", SW, re.M).group(0),
        re.search(r"^function fetchPack\(u, n\) \{.*?^\}", SW, re.S | re.M).group(0),
        "const ok = { ok: true, status: 200 }, bad = { ok: false, status: 503 }, nf = { ok: false, status: 404 };",
        "(async () => {",
        "  const o = {};",
        "  globalThis.fetch = async () => { calls++; if (calls < 3) throw new Error('net'); return ok; }; o.a = [!!(await fetchPack('x', 0)), calls];",
        "  calls = 0; globalThis.fetch = async () => { calls++; return bad; }; o.b = [await fetchPack('x', 0), calls];",
        "  calls = 0; globalThis.fetch = async () => { calls++; return nf; }; o.c = [await fetchPack('x', 0), calls];",
        "  o.d = await sizeOf({ clone: () => ({ arrayBuffer: async () => new ArrayBuffer(7) }) }); o.e = await sizeOf({});",
        "  process.stdout.write(JSON.stringify(o));",
        "})();",
    ])
    r = subprocess.run(["node", "-"], input=src, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    o = json.loads(r.stdout)
    assert o["a"] == [True, 3]          # zwei Netzfehler, dritter Versuch klappt
    assert o["b"] == [None, 4]          # 5xx: 1 + 3 Wiederholungen, dann aufgeben
    assert o["c"] == [None, 1]          # 404: sofort aufgeben
    assert o["d"] == 7 and o["e"] == 0


# ---- Datenschutz ----
@node
def test_backup_parse_accepts_only_known_keys_and_valid_json():
    pre = prelude(lines=["const R23_KEYS", "const R23_ERR", "const R23_FLAGS", "const R23_MAX_VALUE"], funcs=["backupParse"])
    good = json.dumps({"app": "dolmetscher-web", "v": 1, "data": {"webSettings": "{\"ui\":\"en\"}", "micConsent": "1", "installHint": "1", "evil": "x"}})
    exprs = [
        f"backupParse({json.dumps(good)})",
        "backupParse('nope')",
        "backupParse(JSON.stringify({app:'other',v:1,data:{}}))",
        "backupParse(JSON.stringify({app:'dolmetscher-web',v:1,data:{evil:'1'}}))",
        "backupParse(JSON.stringify({app:'dolmetscher-web',v:1,data:{webSettings:'{kaputt'}}))",
        "backupParse(JSON.stringify({app:'dolmetscher-web',v:1,data:{webSettings:5}}))",
        "backupParse(JSON.stringify({app:'dolmetscher-web',v:1,data:{pbTrans:'x'.repeat(1500001)}}))",
    ]
    ok, bad, other, empty, broken, notstr, big = run(pre, exprs)
    assert ok == {"data": {"webSettings": "{\"ui\":\"en\"}", "installHint": "1"}}   # micConsent und Unbekanntes bleiben draußen
    assert bad == {"error": "format"} and other == {"error": "format"}
    assert empty == {"error": "empty"} and broken == {"error": "format"} and notstr == {"error": "size"} and big == {"error": "size"}


@node
def test_backup_roundtrip_and_stale_sweep():
    pre = prelude(lines=["const R23_KEYS", "const R23_ERR", "const R23_FLAGS", "const R23_MAX_VALUE"], funcs=["backupBuild", "backupParse", "staleKeys", "staleDays", "fmtBytes"])
    now = 1_800_000_000_000
    exprs = [
        "(() => { const st = { webSettings: '{\"a\":1}', learnV1: '[]', micConsent: '1' }; return backupParse(backupBuild(k => st[k] ?? null)); })()",
        f"staleKeys({{ a: {{ ts: {now - 100 * 864e5} }}, b: {{ ts: {now - 5 * 864e5} }}, c: 'x' }}, {now}, 90)",
        f"staleKeys({{ a: {{ ts: 1 }} }}, {now}, 0)",
        f"staleDays({{ '2020-01-01': 1, '{(__import__('datetime').date.fromtimestamp(now / 1000)).isoformat()}': 1, 'kaputt': 1 }}, {now}, 30)",
        "fmtBytes(512)", "fmtBytes(2048)", "fmtBytes(5 * 1048576)",
    ]
    rt, stale, off, days, b1, b2, b3 = run(pre, exprs)
    assert rt["data"] == {"webSettings": "{\"a\":1}", "learnV1": "[]"}
    assert stale == ["a"] and off == [] and days == ["2020-01-01"]
    assert (b1, b2, b3) == ("512 B", "2.0 KB", "5.0 MB")


def test_online_gate_is_called_by_translate_and_respects_switch():
    assert "await onlineGate();" in func("translate")
    gate = func("onlineGate")
    assert "settings.onlineOff" in gate and "window.confirm(t('sensWarn'))" in gate and "sensAsked" in gate
    assert "'doctor'" in SCRIPT and "'sexual-health-clinic'" in SCRIPT


def test_sensitive_packs_exist_in_index():
    ids = {p["id"] for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
    packs = set(re.findall(r"'([a-z0-9-]+)'", line("const SENSITIVE_PACKS")))
    assert packs and packs <= ids, sorted(packs - ids)


def test_privacy_box_controls_present_and_stored_keys_documented():
    for i in ("onlineOff", "sensWarn", "retainSel", "privExport", "privImport", "privFile", "privUsage", "privIos"):
        assert f'id="{i}"' in HTML, i
    doc = (ROOT / "docs" / "DATENSCHUTZ.md").read_text(encoding="utf-8")
    assert "destV1" in doc and "exportieren" in doc


# ---- UI-Sprache ----
@node
def test_pick_ui_uses_browser_language_list():
    src = "\n".join(["const UI_LANGS = ['de', 'en', 'th'];", "let nav = {};", "const navigator = new Proxy({}, { get: (_, k) => nav[k] });",
                     "const localStorage = { getItem: () => '{}' };", func("pickUi"),
                     "const o = {}; nav = { languages: ['fr-FR', 'th-TH', 'en'], language: 'fr-FR' }; o.a = pickUi();",
                     "nav = { languages: ['fr', 'es'], language: 'fr' }; o.b = pickUi(); nav = {}; o.c = pickUi(); nav = { language: 'de-AT' }; o.d = pickUi();",
                     "process.stdout.write(JSON.stringify(o));"])
    import subprocess
    r = subprocess.run(["node", "-"], input=src, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout) == {"a": "th", "b": "en", "c": "de", "d": "de"}


# ---- Notfall und Zielkarte ----
def test_sos_dialog_numbers_and_accessibility():
    dlg = re.search(r'<dialog id="sosDlg".*?</dialog>', HTML, re.S).group(0)
    assert 'aria-labelledby="sosTitle"' in dlg
    for n in ("191", "1669", "199", "1155", "1193", "112"):
        assert f'href="tel:{n}"' in dlg, n
    assert 'id="btnSos"' in HTML and 'aria-haspopup="dialog"' in HTML
    assert "sosOpener" in SCRIPT and "o.focus()" in SCRIPT      # Fokus kehrt zum Auslöser zurück


@node
def test_dest_text_for_taxi_and_hotel():
    pre = prelude(funcs=["destText"])
    taxi, hotel, empty, long = run(pre, ["destText('taxi', ' สนามบินดอนเมือง ', '')", "destText('hotel', 'X Hotel', 'Soi 4')", "destText('taxi', '  ', '')", "destText('taxi', 'a'.repeat(200), '').th.length"])
    assert taxi["th"] == "กรุณาไปส่งที่ สนามบินดอนเมือง ด้วย กรุณาเปิดมิเตอร์ด้วย" and "meter" in taxi["en"]
    assert hotel["th"].startswith("ช่วยพาไปส่งที่โรงแรม X Hotel") and "ที่อยู่: Soi 4" in hotel["th"] and "Soi 4" in hotel["en"]
    assert empty is None and long < 200


def test_popular_destinations_have_thai():
    pairs = re.findall(r"\['([^']+)', '([^']+)'\]", line("const DEST_POPULAR"))
    assert len(pairs) >= 10 and all(re.search("[฀-๿]", th) for _, th in pairs)


# ---- Texte, Allergene, Kontrast ----
def test_r23_keys_in_all_languages_and_placeholders_match():
    s = web_str()
    for k in R23_KEYS:
        for lg in ("de", "en", "th"):
            assert s[lg].get(k), (lg, k)
        for ph in re.findall(r"\{(\w+)\}", s["de"][k]):
            assert "{" + ph + "}" in s["en"][k] and "{" + ph + "}" in s["th"][k], (k, ph)


def test_allergens_extended_with_unique_ids():
    d = json.loads((ROOT / "allergens.json").read_text(encoding="utf-8"))
    ids = [a["id"] for a in d["allergies"]]
    assert len(ids) == len(set(ids)) and {"ibuprofen", "iodine", "kiwi", "buckwheat"} <= set(ids)
    assert all(a["en"] and a["de"] and re.search("[฀-๿]", a["th"]) for a in d["allergies"])


def _lum(hexc):
    c = [int(hexc[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def test_sos_button_contrast_at_least_aa():
    m = re.search(r"\.sos \{ background:(#[0-9a-f]{6}); color:#fff;", HTML)
    a, b = sorted((_lum(m.group(1)), _lum("#ffffff")), reverse=True)
    assert (a + 0.05) / (b + 0.05) >= 4.5
    h = re.search(r"\.sos:hover \{ background:(#[0-9a-f]{6})", HTML).group(1)
    a, b = sorted((_lum(h), _lum("#ffffff")), reverse=True)
    assert (a + 0.05) / (b + 0.05) >= 4.5


def test_focus_styles_and_forced_colors_present():
    assert "#sosDlg a.num:focus-visible" in HTML and "forced-colors: active" in HTML and "[role=tab]:focus-visible" in HTML


def test_page_registers_update_hint_and_byte_progress():
    assert "'updatefound'" in HTML and "t('swUpdating')" in HTML
    assert "t('swMb'" in HTML and "d.type === 'sw-version'" in HTML


def test_csp_stays_strict():
    csp = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', HTML).group(1)
    assert "default-src 'none'" in csp and "frame-src 'none'" in csp and "object-src 'none'" in csp and "script-src-attr 'none'" in csp
    assert pathlib.Path(ROOT / "manifest.webmanifest").is_file()
