# ruff: noqa: E501
"""Runde 14 Web: Vorzeigen-Modus, Favoriten-Link (Paket-ID + Index + Pruefsumme), Teilen mit Fallback, Tastatur, Texte."""
import re

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, func, line, prelude, run

SW = (ROOT / "sw.js").read_text(encoding="utf-8")
KEYS = ("showLbl", "showClose", "favShareLbl", "favLinkBad")
PRE = prelude(funcs=("favSum", "favUrl", "parseFav", "showFontVw"), lines=("const PRESET_IDS =",)) if HAVE_NODE else ""
PRE = "const location = { origin: 'https://x.test', pathname: '/app/' };\n" + PRE


def test_texts_in_three_languages():
    from _webhelpers import web_str
    S = web_str()
    for lg in ("de", "en", "th"):
        for k in KEYS:
            assert S[lg][k].strip(), (lg, k)


def test_controls_wired_and_sw_bumped():
    for i in ("btnPartnerShow", "btnPartnerShare"):
        assert f'id="{i}"' in HTML, i
    assert "['btnPartnerShow', 'showLbl']" in SCRIPT and "['btnPartnerShare', 'favShareLbl']" in SCRIPT
    assert "setShow(false)" in func("togglePartner") and "navigator.wakeLock" in SCRIPT
    assert "e.code === 'KeyV'" in SCRIPT and "e.code === 'KeyS'" in SCRIPT
    assert int(re.search(r"dolmetscher-web-v(\d+)'", SW).group(1)) >= 13
    assert "#partner.show" in HTML and "parseDeepLink(location.hash" in SCRIPT and "function openFromHash" in SCRIPT


def test_share_falls_back_to_clipboard_then_prompt():
    body = func("shareOut")
    assert body.index("navigator.share") < body.index("clipboard.writeText") < body.index("window.prompt")


def test_no_conversation_text_in_fav_link():
    body = func("favUrl")
    assert "en)" in body and "text" not in body and "#fav=" in body


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_fav_link_roundtrip_and_validation():
    ok, bad_pack, bad_idx, bad_lang, no_sum = run(PRE, [
        "parseFav(new URL(favUrl('taxi', 3, 'th', 'Please stop here.')).hash, PRESET_IDS)",
        "parseFav('#fav=nope.3&l=th&c=abc', PRESET_IDS)",
        "parseFav('#fav=taxi.x&l=th&c=abc', PRESET_IDS)",
        "parseFav('#fav=taxi.3&l=zz&c=abc', PRESET_IDS)",
        "parseFav('#fav=taxi.3&l=th', PRESET_IDS)"])
    assert ok["pack"] == "taxi" and ok["idx"] == 3 and ok["lang"] == "th" and ok["sum"]
    assert bad_pack is None and bad_idx is None and bad_lang is None and no_sum is None


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_checksum_detects_changed_sentence_and_url_has_no_text():
    a, b, url = run(PRE, ["favSum('Please stop here.')", "favSum('Please stop there.')", "favUrl('taxi', 3, 'th', 'Please stop here.')"])
    assert a != b and re.fullmatch(r"[0-9a-z]{1,8}", a)
    assert url.startswith("https://x.test/app/#fav=taxi.3&l=th&c=") and "stop" not in url.lower()


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_show_font_shrinks_with_length():
    sizes = run(PRE, ["[5, 20, 50, 100, 300].map(showFontVw)"])[0]
    assert sizes == sorted(sizes, reverse=True) and sizes[0] > sizes[-1] >= 6


def test_no_shadowed_t_and_i18n_helpers_present():
    for name in ("setShow", "openFav", "shareFav", "parseFav"):
        body = func(name)
        assert not re.search(r"\b(?:const|let|var) t\b|\(t[,)]", body.split("{", 1)[0] + body), name
    assert line("const PRESET_IDS =")
