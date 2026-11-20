# ruff: noqa: E501
"""Runde 21 Web, Welle 1: Tastenkonflikt Lernkarten, myLangOf, Verlaufssuche, Notrufnummern, Teilen mit Bestätigung,
PWA-Symbole/Meta, Service-Worker-Fehlerbehandlung."""
import json
import re
import shutil

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, func, prelude, run

node = pytest.mark.skipif(not HAVE_NODE or not shutil.which("node"), reason="node nicht installiert")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
KEYS = SCRIPT.split("document.addEventListener('keydown'", 1)[1].split("// ---- Runde 7", 1)[0]


def test_global_shortcuts_respect_learn_card_and_autorepeat():
    assert "e.defaultPrevented || e.repeat" in KEYS                       # Lernkarte hat die Ziffer schon verbraucht; Autorepeat schaltet nichts um
    assert "/^[1-4]$/.test(e.key)) e.preventDefault()" in SCRIPT           # Karte schluckt 1-4 immer (auch ungedeckt)
    assert "closest('button,input,summary,a,[role=button]')" in KEYS      # Leertaste öffnet Bereiche/Links weiter


@node
def test_my_lang_of_uses_the_non_thai_side_of_the_pair():
    pre = prelude(funcs=["scriptShare", "myLangOf"])
    got = run(pre, ["(pair = { a: 'en', b: 'th' }, myLangOf('hotel near the beach'))", "(pair = { a: 'en', b: 'th' }, myLangOf('โรงแรม'))",
                    "(pair = { a: 'de', b: 'th' }, myLangOf('Hotel am Strand'))", "(pair = { a: 'th', b: 'en' }, myLangOf('hotel'))"])
    assert got == ["en", "th", "de", "en"]


def test_log_search_ignores_button_texts_and_new_entries_are_filtered():
    assert "function logSearchText(" in SCRIPT and "querySelectorAll('.orig,.trans')" in func("logSearchText")
    assert "logSearchText(e)" in func("applyLogFilter") and "e.textContent" not in func("applyLogFilter")
    assert "if ($('logQ').value.trim()) applyLogFilter();" in func("addEntry")


def test_learn_timer_and_autospeak_only_with_open_learn_box():
    assert "$('learnBox').open) learnRender()" in SCRIPT
    assert "!document.hidden && $('learnBox').open) sayNow(" in func("learnRender")


@node
def test_every_pack_in_a_group_has_emergency_numbers():
    m = re.search(r"^const EMERGENCY = \{.*?^\};\n\{.*?^\}\n", SCRIPT, re.S | re.M)
    assert m
    import subprocess
    r = subprocess.run(["node", "-"], input=m.group(0) + "\nprocess.stdout.write(JSON.stringify(EMERGENCY));", capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    em = json.loads(r.stdout)
    for pid in ("emergency", "hospital", "motorbike-accident", "animal-bite-rabies", "lost-passport", "diving", "snorkel-boat-tour", "doctor"):
        assert pid in em, pid
    assert {n for v in em.values() for _, n in v} <= {"1669", "1155", "191", "199"}
    ids = {p["id"] for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
    assert set(em) <= ids and len(em) >= 40
    assert ["emRescue", "1669"] in em["emergency"] and ["emFire", "199"] in em["emergency"]


def test_shared_text_is_only_sent_after_confirmation():
    block = SCRIPT.split("if (d.incoming) {", 1)[1].split("return true;", 1)[0]
    assert "sharedGo = () =>" in block and "showWarn(t('shareAsk')" in block
    assert block.index("sharedGo = () =>") < block.index("showWarn(")
    assert "translate(" not in block.split("sharedGo = () =>", 1)[0]       # nichts wird vor der Bestätigung gesendet
    assert "act === 'sharego'" in SCRIPT


def test_pwa_icons_meta_and_manifest():
    for m in ('name="apple-mobile-web-app-capable"', 'name="apple-mobile-web-app-title"', 'name="apple-mobile-web-app-status-bar-style"', 'href="apple-touch-icon-180.png"'):
        assert m in HTML, m
    man = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
    assert "EN" in man["name"] and "TH" in man["name"]
    for f in ("icon-maskable-192.png", "icon-maskable-512.png", "apple-touch-icon-180.png"):
        assert f in SW and (ROOT / f).is_file(), f


def test_sw_install_fails_without_page_and_language_table():
    assert "const MUST = ['index.html', 'languages.json']" in SW and "if (MUST.includes(u)) throw err" in SW
    assert "cache: 'reload'" in SW and "cache: 'no-cache'" in SW


def test_registration_updates_hourly_and_reports_failure():
    assert "register('sw.js', { updateViaCache: 'none' })" in HTML and "3600000" in HTML
    assert "$('swState').textContent = t('noSw'); });" in HTML


def test_skip_links_theme_color_and_bad_packs():
    assert 'id="skipMain" href="#main"' in HTML and 'id="main" tabindex="-1"' in HTML
    assert '<span aria-hidden="true">🌐</span>' in HTML
    assert "meta[name=\"theme-color\"]" in func("applyTheme")
    assert "Array.isArray(d.phrases)" in func("loadPreset")
    assert "#partnerText.crit" in HTML
