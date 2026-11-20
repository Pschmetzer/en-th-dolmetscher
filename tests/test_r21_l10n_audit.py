# ruff: noqa: E501
"""Runde 21, Lokalisierungs-Audit: alle iPhone-Tabellen (auch Runde 13 bis 25), Begriffe, Schreibweise, Plural-Formen.

Ergänzt tests/test_runde13_l10n.py (das nur Runde 4 bis 9 prüft) und tests/test_l10n_keys.py (Mac)."""
import json
import pathlib
import re
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _webhelpers import web_str  # noqa: E402
from test_runde13_l10n import IOS_LANGS, LETTER, ph, swift_dict  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "ios" / "Dolmetscher"
TABLE_RX = re.compile(r"static let (\w+): \[String: \[String: String\]\]")


def _tables():
    """Alle `static let X: [String: [String: String]]` in ios/Dolmetscher/L10n*.swift (ohne packNames)."""
    out = {}
    for f in sorted(IOS.glob("L10n*.swift")):
        src = f.read_text(encoding="utf-8")
        for name in TABLE_RX.findall(src):
            if name != "packNames":
                out[name] = swift_dict(src, name)
    return out


TABLES = _tables()
EXTRA = TABLES.pop("extra")
MAC = swift_dict((ROOT / "app" / "L10n.swift").read_text(encoding="utf-8"), "table")
WEB = web_str()


def _row(name, key):
    row = dict(TABLES[name][key])
    if name == "table":
        for lg in IOS_LANGS:
            row.setdefault(lg, EXTRA.get(lg, {}).get(key, ""))
    return row


def all_ios():
    return {k: _row(n, k) for n in TABLES for k in TABLES[n]}


def test_every_round_table_is_found_and_registered_in_lookup():
    rounds = {n for n in TABLES if n.startswith("round")}
    assert {"round13", "round14", "round21", "round25"} <= rounds
    src = (IOS / "L10n.swift").read_text(encoding="utf-8")
    lookup = src[src.index("static func text("):]
    for n in rounds:
        assert len(re.findall(rf"\b{n}\b", lookup)) >= 2, f"{n} fehlt in L10n.text() oder L10n.allKeys"


@pytest.mark.parametrize("name", sorted(TABLES))
def test_each_ios_table_is_complete_nonempty_with_same_placeholders(name):
    problems = []
    for key in TABLES[name]:
        row = _row(name, key)
        for lg in IOS_LANGS:
            text = row.get(lg, "")
            if not text.strip():
                problems.append(f"{key}.{lg} fehlt/leer")
            elif ph(text) != ph(row["en"]):
                problems.append(f"{key}.{lg}: {ph(text)} != {ph(row['en'])}")
            elif re.search(r" {2,}", text):
                problems.append(f"{key}.{lg}: doppelte Leerzeichen")
            elif text != text.strip():
                problems.append(f"{key}.{lg}: Leerraum am Rand")
        for lg in set(row) - set(IOS_LANGS):
            problems.append(f"{key}: unbekannte Sprache {lg}")
    assert not problems, problems[:20]


def test_ios_keys_unique_across_all_tables():
    seen = {}
    for name, rows in TABLES.items():
        for key in rows:
            assert key not in seen, f"{key} steht in {seen[key]} und {name}; text() nimmt nur den ersten Treffer"
            seen[key] = name


def test_ios_script_languages_use_their_script_in_all_tables():
    bad = []
    for key, row in all_ios().items():
        for lg in ("th", "ja", "ko", "zh-Hans"):
            if row[lg] != row["en"] and not re.search(f"[{LETTER[lg]}]", row[lg]):
                bad.append(f"{key}.{lg}")
    assert not bad, bad[:20]


def test_web_and_mac_texts_have_no_stray_whitespace():
    bad = [f"mac {k}.{lg}" for k, r in MAC.items() for lg, v in r.items() if v != v.strip() or re.search(r"[^\n] {2,}[^\n]", v)]
    bad += [f"web {lg}.{k}" for lg in ("en", "th") for k, v in WEB[lg].items() if re.search(r"[^\s] {2,}\S", v)]
    assert not bad, bad[:20]


# --- Begriffe (docs/GLOSSAR-UI.md) -----------------------------------------------------------------------

def _all_texts():
    for k, r in MAC.items():
        for lg in ("de", "en", "th"):
            yield f"mac {k}.{lg}", lg, r[lg]
    for k, r in all_ios().items():
        for lg in IOS_LANGS:
            yield f"ios {k}.{lg}", lg, r[lg]
    for lg in ("de", "en", "th"):
        for k, v in WEB[lg].items():
            yield f"web {k}.{lg}", lg, v


FORBIDDEN = [   # (Sprache, Muster, Grund) – siehe docs/GLOSSAR-UI.md
    ("en", r"favourite|recognis|colour|Practise|[Cc]ancelled|study card|Partner's language", "amerikanische Schreibweise, ein Wort für Lernkarten"),
    ("de", r"Karteikarte|Lernkasten", "Lernkarte(n)"),
    ("th", r"กรุณา|ไมค์", "โปรด / ไมโครโฟน"),
    ("es", r"\bpareja\b", "Gegenüber heißt interlocutor, nicht pareja"),
    ("fr", r"partenaire", "Gegenüber heißt interlocuteur"),
    ("vi", r"đối tác", "Gegenüber heißt đối phương"),
    ("id", r"\bmitra\b", "Gegenüber heißt lawan bicara"),
    ("zh-Hans", r"嗓音", "声音 statt 嗓音 (Stimmqualität)"),
]


@pytest.mark.parametrize("lang,pattern,reason", FORBIDDEN)
def test_glossary_forbidden_variants_do_not_occur(lang, pattern, reason):
    hits = [where for where, lg, text in _all_texts() if lg == lang and re.search(pattern, text)]
    assert not hits, f"{reason}: {hits[:10]}"


def test_glossary_doc_lists_every_forbidden_term_group():
    doc = (ROOT / "docs" / "GLOSSAR-UI.md").read_text(encoding="utf-8")
    for needle in ("Karteikarte", "Lernkasten", "favourites", "study card", "กรุณา", "pareja", "partenaire", "đối tác", "mitra"):
        assert needle in doc, needle
    for key in ("hs_title", "settings", "phrasebook"):
        row = all_ios()[key]
        for lg in ("es", "fr", "ja", "ko", "zh-Hans", "vi", "id"):
            assert row[lg] in doc, f"{key}.{lg}={row[lg]!r} steht nicht im Glossar"


def test_shared_mac_ios_keys_keep_same_placeholders_and_terms():
    ios = all_ios()
    both = set(MAC) & set(ios)
    assert len(both) > 20
    bad = [f"{k}.{lg}" for k in both for lg in ("de", "en", "th") if ph(MAC[k][lg]) != ph(ios[k][lg])]
    assert not bad, bad
    for k in ("retry", "stop_speaking", "lang_partner"):
        assert {MAC[k][lg] == ios[k][lg] for lg in ("de", "en", "th")} == {True}, k


# --- Plural: Mengen als Beschriftung, nie „1 matches“ -----------------------------------------------------

PLURAL_EN = re.compile(r"(?<!of )(?:%\d*\$?l?l?d|\{[nm]\})\s+(?!of\b|in\b|older\b|min\b|s\b)[a-z]+s\b")
LABEL_FORM = ("mac results_count", "mac hist_hits", "mac hist_count", "mac delete_all_done", "mac gl_exported", "mac sx_preview",
              "mac sx_lines", "ios learn_streak", "ios learn_box_a11y", "web learnMissing", "web printMissing", "web learnAdded",
              "web mcExported", "web mcImported", "web topicCount", "web learnClearConfirm", "web learnResetConfirm")


def test_counts_that_can_be_one_use_label_form_not_plural_nouns():
    """„Matches: %d“ statt „%d matches“. Neue Zähltexte bitte ebenso schreiben (nicht erzwungen, damit parallele Arbeit nicht bricht)."""
    en = {w.rsplit(".", 1)[0]: t for w, lg, t in _all_texts() if lg == "en"}
    for key in LABEL_FORM:
        assert key in en, key
        assert not PLURAL_EN.search(en[key]), f"{key}: {en[key]!r}"


def test_web_json_is_formatted_like_the_exporter_writes_it():
    for lg in ("en", "th"):
        text = (ROOT / "i18n" / f"{lg}.json").read_text(encoding="utf-8")
        assert text == json.dumps(json.loads(text), ensure_ascii=False, indent=1) + "\n"


# --- Einheiten und Datumsformate im Code -----------------------------------------------------------------

def test_ios_settings_units_come_from_foundation_not_fixed_text():
    src = (IOS / "SettingsView.swift").read_text(encoding="utf-8")
    assert not re.search(r'Text\("\d+ min"\)', src), "feste Minuten-Texte"
    assert '"%.1f s"' not in src and '%%"' not in src, "feste Sekunden-/Prozenttexte (Dezimalzeichen, Leerzeichen vor %)"
    for needle in ("UnitDuration.seconds", "UnitDuration.minutes", ".percent", "Locale(identifier: L10n.lang)"):
        assert needle in src, needle


def test_mac_transcript_export_uses_gregorian_calendar_and_posix_locale():
    src = (ROOT / "app" / "Support.swift").read_text(encoding="utf-8")
    block = src[src.index("func transcript("):src.index("func who(")]
    assert 'df.locale = Locale(identifier: "en_US_POSIX")' in block
    assert "df.calendar = Calendar(identifier: .gregorian)" in block   # Thai-Systemsprache: sonst Jahr 2569


def test_fixed_format_date_formatters_set_a_posix_locale():
    """`dateFormat = "yyyy…"` ohne feste Locale liefert je nach Systemsprache andere Ziffern oder Kalender."""
    bad = []
    for f in [*(ROOT / "app").glob("*.swift"), *IOS.glob("*.swift")]:
        src = f.read_text(encoding="utf-8")
        for m in re.finditer(r'\.dateFormat = [^\n]*', src):
            window = src[max(0, m.start() - 300):m.end() + 300]
            if "en_US_POSIX" not in window:
                bad.append(f"{f.relative_to(ROOT)}: {m.group(0)[:50]}")
    assert not bad, bad


def test_web_rate_display_uses_the_decimal_sign_of_the_interface_language():
    html = (ROOT / "index.html").read_text(encoding="utf-8")
    assert "rateOut').textContent = r.toFixed(2)" not in html and "rate.toFixed(2)); $('rate')" not in html
    assert "toLocaleString(UI, { minimumFractionDigits: 2" in html
    assert "t('cmdTempo', { n: fmt2(rate) })" in html
    assert "showRate();" in html[html.index("function applyUi()"):html.index("// ---- Sprachtabelle")]   # Sprachwechsel
