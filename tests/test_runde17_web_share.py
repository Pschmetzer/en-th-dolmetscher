# ruff: noqa: E501
"""Runde 17 Web: Share-Target behaelt Text bis zum Netz, Text-Teilen in der Grossansicht, Satzbuch-Verknuepfung, SW hochgezaehlt."""
import json
import re

from _webhelpers import HTML, ROOT, SCRIPT, web_str

SW = (ROOT / "sw.js").read_text(encoding="utf-8")
MANIFEST = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
STR = web_str()


def test_texts_in_three_languages():
    for lg in ("de", "en", "th"):
        for k in ("shareTxLbl", "sharedWait"):
            assert STR[lg][k].strip(), (lg, k)


def test_partner_text_share_with_clipboard_fallback():
    assert 'id="btnPartnerShareTx"' in HTML
    body = SCRIPT.split("$('btnPartnerShareTx').onclick", 1)[1].split("$('btnPartnerShare').onclick", 1)[0]
    assert "navigator.share({ text: bigText.text })" in body and "copyText(bigText.text)" in body and "AbortError" in body


def test_shared_text_kept_until_network_returns():
    assert "sharedPending" in SCRIPT and "$('typeIn').value = d.incoming" in SCRIPT
    assert "addEventListener('online', () => { if (sharedPending)" in SCRIPT


def test_manifest_has_phrasebook_shortcut_and_share_target():
    names = [s["name"] for s in MANIFEST["shortcuts"]]
    assert "Satzbuch" in names
    assert MANIFEST["share_target"]["params"]["text"] == "text"


def test_offline_banner_and_install_hint_exist():
    assert 'id="offline"' in HTML and "beforeinstallprompt" in SCRIPT and 'id="installNote"' in HTML


def test_sw_cache_bumped():
    assert int(re.search(r"dolmetscher-web-v(\d+)'", SW).group(1)) >= 16
