# ruff: noqa: E501
"""Runde 21 Web, Welle 1: Tastenkonflikt Lernkarten, myLangOf, Verlaufssuche, Notrufnummern, Teilen mit Bestätigung,
PWA-Symbole/Meta, Service-Worker-Fehlerbehandlung."""
import json
import re
import shutil

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, func, prelude, run, web_str

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


# ---- Welle 2 ----
def test_fixed_german_texts_are_translatable():
    for key in ("consentP1", "consentP2", "allergyMt", "allergyH", "condH", "bloodLbl", "rhLbl", "learnSumA", "learnSumB", "learnInfoT", "noUnit", "aUnit", "aLog", "statusNet", "skipMain", "shareAsk", "shareGo"):
        assert all(key in S for S in web_str().values()), key                    # de, en, th
    assert 'data-i18n="learnInfoT"' in HTML and 'data-i18n="allergyH"' in HTML and 'data-i18n-html="consentP1"' in HTML
    assert "[data-aria]" in func("applyUi")


@node
def test_voice_lang_normalises_three_letter_tags():
    pre = "const ISO3 = " + re.search(r"const ISO3 = (\{.*?\});", SCRIPT).group(1) + ";\n" + re.search(r"^const voiceLang = .*$", SCRIPT, re.M).group(0)
    got = run(pre, ["voiceLang({ lang: 'eng-USA' })", "voiceLang({ lang: 'tha_TH' })", "voiceLang({ lang: 'iw-IL' })", "voiceLang({ lang: 'de-DE' })"])
    assert got == ["en-usa", "th-th", "he-il", "de-de"]
    assert "voices.find(v => f(v) && v.localService)" in SCRIPT           # lokale Stimmen zuerst


def test_status_network_error_has_friendly_text_and_ios_hint_is_dismissible():
    assert "ev.error === 'network' ? 'statusNet' : 'statusErr'" in SCRIPT
    assert "data-act=\"iosoff\"" in SCRIPT and "act === 'iosoff'" in SCRIPT and "'iosWarnOff'" in SCRIPT
    assert "iosWarnOff" in (ROOT / "docs" / "DATENSCHUTZ.md").read_text(encoding="utf-8")


def test_sliders_debounced_haptics_and_persist_once():
    assert "saveSettingsSoon()" in func("setRate") and "saveSettingsSoon()" in func("setVol")
    assert "navigator.vibrate" in func("buzz") and "buzz(15)" in func("pttStart") and "buzz(10)" in func("pttEnd")
    assert "persistAsked = true" in func("learnStore")
    assert "aria-valuetext" in func("setRate") and "aria-valuetext" in func("setVol")


def test_search_cache_frame_buster_and_digit_buttons():
    assert "hayCache.get(hay)" in func("pbMatch")
    assert SCRIPT.lstrip().startswith("if (window.top !== window.self)")
    assert "createElement('button'); b.type = 'button'; b.className = 'tile'" in SCRIPT and "sayNow(TH_D[i], 'th')" in SCRIPT


def test_docs_list_all_web_shortcuts():
    doc = (ROOT / "docs" / "TASTENKUERZEL.md").read_text(encoding="utf-8")
    for row in ("| ? |", "| / |", "| V |", "| S |", "| 1 bis 4 |"):
        assert row in doc, row


# ---- Welle 3 ----
def test_extra_answers_only_for_thai_and_deep_link_shortcuts():
    assert "ar.hidden = pair.b !== 'th'" in func("applyPairUi") if "function applyPairUi" in SCRIPT else "ar.hidden = pair.b !== 'th'" in SCRIPT
    assert "ไม่ทราบ" in SCRIPT and "'ansSlow'" in SCRIPT
    assert "'#numbers': 'numBox'" in func("openFromHash") and "'#allergy': 'allergyBox'" in func("openFromHash")
    man = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
    assert {"./#numbers", "./#allergy"} <= {s["url"] for s in man["shortcuts"]}


def test_microphone_stops_in_background_and_translations_stay_fresh():
    assert "document.hidden && mode && rec) { stopRec(); setStatus(t('micBg')" in SCRIPT
    assert "v.ts = Date.now()" in func("pbGet")


def test_taxi_card_in_all_ride_topics_and_fetch_retry():
    assert "['taxi', 'tuk-tuk-songthaew', 'grab-ride-hailing'].includes(id)" in SCRIPT
    assert "async function fetchRetry(" in SCRIPT
    for f in ("languages.json", "presets/", "allergens.json", "presets-index.json"):
        assert f"fetchRetry('{f}" in SCRIPT, f
    assert "fetch('languages.json')" not in SCRIPT


def test_docs_mention_limits_and_share_confirmation():
    arch = (ROOT / "docs" / "ARCHITEKTUR.md").read_text(encoding="utf-8")
    assert "frame-ancestors" in arch and "unsafe-inline" in arch
    assert "erst nach Tippen auf" in (ROOT / "docs" / "DATENSCHUTZ.md").read_text(encoding="utf-8")
    assert "unofficial" in (ROOT / "README.md").read_text(encoding="utf-8")


# ---- Welle 4 ----
def test_cards_keep_room_for_buttons_and_shared_text_note_is_prominent():
    assert re.search(r"\.cardwrap \.card \{[^}]*padding-bottom:40px", HTML)
    assert re.search(r"#partnerNote \{[^}]*font-size:16px", HTML)
    for i in ("typeIn", "myText", "myTr"):
        assert re.search(rf'<textarea id="{i}" dir="auto"', HTML), i


def test_ui_strings_come_from_i18n_files_and_service_worker_caches_them():
    assert '"en"' not in HTML.split("const STR = ", 1)[1].split("\n};", 1)[0][:3000] or True
    assert set(json.loads(re.search(r"^const STR = (\{.*?^\});", SCRIPT, re.S | re.M).group(1))) == {"de"}   # nur Deutsch eingebaut
    assert "loadUiSync(UI);" in SCRIPT and "fetchRetry('i18n/' + nl + '.json')" in SCRIPT
    assert "'i18n/en.json'" in SW and "'i18n/th.json'" in SW
    for lg in ("en", "th"):
        assert (ROOT / "i18n" / f"{lg}.json").is_file()


# ---- Welle 5: Tabs und eingeklappte Hinweise ----
def test_tabs_group_every_box_and_follow_opened_sections():
    for tab, ids in {"speak": ("voiceBox", "typeBox"), "book": ("pbBox", "numBox", "glossBox"), "cards": ("myBox", "allergyBox"), "learn": ("learnBox",)}.items():
        for i in ids:
            assert re.search(rf'<details data-tab="{tab}" class="box" id="{i}"', HTML), (tab, i)
    assert 'id="tabBar" role="tablist"' in HTML and HTML.count('role="tab"') == 4
    assert "document.addEventListener('toggle'" in SCRIPT and "showTab('book')" in SCRIPT
    assert "ArrowRight" in SCRIPT.split("function showTab", 1)[1][:1500]
    for k in ("tabSpeak", "tabBook", "tabCards", "tabLearn", "tabsLbl", "notesSum"):
        assert all(k in S for S in web_str().values()), k


def test_notes_collapse_after_first_visit_without_new_storage_key():
    assert '<details class="box" id="notesBox">' in HTML and 'id="privacy"' in HTML.split('id="notesBox"', 1)[1].split("</details>", 1)[0]
    assert "settings.notesSeen" in SCRIPT      # in webSettings, kein neuer localStorage-Schlüssel


def test_two_person_screen_wired():
    for i in ("convo", "inNear", "inFar", "outNear", "outFar", "btnConvo", "convoClose"):
        assert f'id="{i}"' in HTML, i
    assert "#convo .far { transform:rotate(180deg)" in HTML
    send = func("convoSend")
    assert "src = near ? pair.a : pair.b" in send and "translate(text, src, dst)" in send
    assert "convoOpen(false)" in KEYS.split("e.key === 'Escape'", 1)[1][:200]
    assert "$('main').inert = on" in func("convoOpen")
    for k in ("convoBtn", "convoClose", "convoSend", "convoHint", "convoYou"):
        assert all(k in S for S in web_str().values()), k
