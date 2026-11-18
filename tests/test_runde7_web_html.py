"""Web Lite, Runde 7: Barrierefreiheit, Zurück-Taste, Einwilligungsversion, Doku-gegen-Code (ohne Browser)."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
PRIVACY = (ROOT / "docs" / "DATENSCHUTZ.md").read_text(encoding="utf-8")


def _tokens(block):
    return dict(re.findall(r"--([\w-]+):\s*(#[0-9a-fA-F]{6})", block))


def _lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def _contrast(a, b):
    hi, lo = sorted((_lum(a), _lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def test_text_tokens_have_contrast_in_both_schemes():
    light = _tokens(re.search(r":root \{(.*?)\n  \}", HTML, re.S).group(1))
    dark_re = r"prefers-color-scheme: dark\) \{\s*:root:not\(\[data-theme=\"light\"\]\) \{(.*?)\n    \}"
    dark = _tokens(re.search(dark_re, HTML, re.S).group(1))
    for name, tok in (("hell", light), ("dunkel", dark)):
        for fg in ("fg", "mut", "th-text", "crit", "star"):
            assert _contrast(tok[fg], tok["bg"]) >= 4.5, (name, fg, _contrast(tok[fg], tok["bg"]))
        assert _contrast(tok["fg"], tok["card"]) >= 4.5, name


def test_color_scheme_and_noscript():
    assert '<meta name="color-scheme" content="light dark">' in HTML
    assert "color-scheme:light dark" in HTML
    assert len(re.findall(r'<meta name="theme-color"', HTML)) == 2
    assert "<noscript>" in HTML


def test_touch_action_only_with_ptt():
    assert "body.ptt button.mode { touch-action:none; }" in HTML
    assert re.search(r"(?<!ptt )button\.mode \{[^}]*touch-action", HTML) is None
    assert "classList.toggle('ptt'" in HTML


def test_back_button_closes_big_view_and_hash_removed():
    assert "history.pushState({ big: 1 }" in HTML and "addEventListener('popstate'" in HTML
    assert "history.replaceState(null, ''" in HTML
    assert "history.state.big" in HTML


def test_big_view_keeps_screen_awake():
    m = re.search(r"async function updateWakeLock\(\) \{.*?\n\}", HTML, re.S).group(0)
    assert "$('partner').classList.contains('on')" in m


def test_shared_link_is_marked_unchecked():
    assert 'id="partnerNote"' in HTML and "von der App nicht geprüft" in HTML
    assert "showBig(s.text, s.lang, '', true)" in HTML


def test_consent_version_matches_privacy_doc():
    ver = re.search(r"const CONSENT_VER = '(\d+)'", HTML).group(1)
    assert f"aktuell **{ver}**" in PRIVACY
    assert "=== CONSENT_VER" in HTML and "setItem('micConsent', CONSENT_VER)" in HTML


def test_every_storage_key_is_in_privacy_doc():
    keys = set(re.findall(r"(?:getItem|setItem|removeItem)\('(\w+)'", HTML)) | {"learnV1"}
    keys |= set(re.findall(r"const LEARN_KEY = '(\w+)'", HTML))
    assert {"webSettings", "keysOn", "micConsent", "pbTrans", "learnV1"} <= keys
    for k in keys:
        assert k in PRIVACY, f"localStorage-Schluessel {k} fehlt in docs/DATENSCHUTZ.md"


def test_preset_count_in_docs_matches_files():
    ids = re.search(r"const PRESET_IDS = \[(.*?)\]", HTML, re.S).group(1)
    n = len(re.findall(r"'([\w-]+)'", ids))
    lines = (ROOT / "tools" / "web_pending_presets.txt").read_text(encoding="utf-8").splitlines()
    pend = {x.strip() for x in lines if x.strip() and not x.startswith("#")}
    assert n == len(list((ROOT / "presets").glob("*.json"))) - len(pend)
    assert re.search(r"const PRESET_IDS = \[(.*?)\]", SW, re.S).group(1).count("'") == n * 2
    for f in (ROOT / "presets").glob("*.json"):
        json.loads(f.read_text(encoding="utf-8"))
