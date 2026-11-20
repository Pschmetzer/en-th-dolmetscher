# ruff: noqa: E501
"""Runde 9 Web: keine festen deutschen Texte in der Logik, Hinweis ohne Spracherkennung, neue Bedienelemente."""
import json
import re

from _webhelpers import HTML, SCRIPT, web_str

STR_M = re.search(r"^const STR = (\{.*?^\});", SCRIPT, re.S | re.M)
STR = web_str()
LOGIC = SCRIPT.replace(STR_M.group(0), "")
# Datentabellen (Ländernamen der Sprachvarianten), keine Meldungen
ALLOWED = {"Brasilien", "Spanien", "Mexiko", "Frankreich", "Kanada", "Mandarin (China)", "Mandarin (Taiwan)", "Kantonesisch (Hongkong)",
           "Saudi-Arabien", "Ägypten", "Emirate", "Deutschland", "Österreich", "Schweiz", "Satz prüfen: "}   # letzteres: Titel des deutschen GitHub-Formulars
GERMAN_WORDS = re.compile(r"\b(nicht|Bitte|Fehler|Verlauf|Karten?|Sätze|Thema|offline\?|wird|oder|und|kopiert|gelöscht|Stimme)\b")


def _strings(code):
    code = re.sub(r"^\s*//.*$", "", code, flags=re.M)
    code = re.sub(r"(?<![:'\"\\])//[^\n]*", "", code)   # Zeilenkommentare (grob)
    return re.findall(r"'((?:[^'\\\n]|\\.)*)'|\"((?:[^\"\\\n]|\\.)*)\"", code)


def test_no_hardcoded_german_in_logic():
    bad = []
    for a, b in _strings(LOGIC):
        s = a or b
        if s in ALLOWED or s.startswith("<") and "data-act" in s and not GERMAN_WORDS.search(s):
            continue
        if re.search(r"[äöüÄÖÜß]", s) and not re.search(r"[\u0e00-\u0e7f]", s) or GERMAN_WORDS.search(s):
            bad.append(s[:70])
    assert not bad, bad


def test_new_keys_in_all_languages():
    for k in ("noSr", "noSrTitle", "toPhrasebook", "logCopied", "cmdPaused", "slowBtn", "themeDark", "fsUp", "topicNext", "recentTopics", "errNotAllowed"):
        assert all(STR[lg][k].strip() for lg in ("de", "en", "th")), k
    assert "Verlauf kopiert" in STR["de"]["logCopied"] and "copied" in STR["en"]["logCopied"]


def test_no_speech_recognition_hint_offers_actions():
    body = LOGIC.split("if (!SR) {", 1)[1].split("\n}", 1)[0]
    assert "t('noSr')" in body and "'btnType'" in body and "'toPhrasebook'" in body
    for lg in ("de", "en", "th"):
        assert "<b>" in STR[lg]["noSr"] and "<b>3.</b>" in STR[lg]["noSr"]
    assert "Edge" in STR["en"]["noSr"] and "type instead" in STR["en"]["noSr"].lower()


def test_hard_errors_are_keys_and_warnings_tagged():
    block = LOGIC.split("const HARD_ERR = {", 1)[1].split("};", 1)[0]
    for code in ("not-allowed", "service-not-allowed", "language-not-supported", "audio-capture"):
        key = re.search(rf"'{code}': '(\w+)'", block).group(1)
        assert all(key in STR[lg] for lg in STR), key
    assert "warnKinds.get(m) === 'rec'" in LOGIC


def test_controls_and_css():
    for i in ("btnTheme", "btnTextDown", "btnTextUp", "topicPrev", "topicNext", "pbRecentRow", "btnPartnerSlow"):
        assert f'id="{i}"' in HTML, i
    assert 'data-theme="light"' in HTML and 'data-theme="dark"' in HTML and "zoom:var(--ui-scale" in HTML
    assert "@page { margin:12mm; }" in HTML
    assert "SLOW_FACTOR" in LOGIC and "sayNow(text, lang, true)" in LOGIC


def test_no_shadowed_t_in_new_code():
    for name in ("renderRecent", "stepTopic", "updateThemeBtn", "setUiScale", "maybeInstallHint"):
        body = re.search(rf"^function {name}\(.*?^\}}", SCRIPT, re.S | re.M).group(0)
        assert not re.search(r"\b(?:const|let|var) t\b|\(t[,)]", body.split("{", 1)[0] + body), name


def test_sw_cache_bumped():
    from _webhelpers import ROOT
    sw = (ROOT / "sw.js").read_text(encoding="utf-8")
    assert int(re.search(r"dolmetscher-web-v(\d+)", sw).group(1)) >= 12
