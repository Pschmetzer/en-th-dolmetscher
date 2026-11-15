"""Tests für Weckwort und Sprachbefehle – ohne Modell, Netz oder Mikrofon.

Der Import von dolmetscher lädt kein Whisper-Modell (nur `from faster_whisper import WhisperModel`).
"""
import pytest

from dolmetscher import WAKE, WAKE_FUZZY, _strip_punct, match_wake, parse_command


def detect(text):
    """Befehl so, wie Engine ihn ausführt: echte Weckwort-Funktion + Satzzeichen weg + parse_command."""
    rest = match_wake(text)
    return None if rest is None else parse_command(_strip_punct(rest))


# echte Verhörer aus Logs
@pytest.mark.parametrize("utterance, expected", [
    ("Translator post.", "pause"),
    ("Translate to a pulse", "pause"),          # nur über WAKE_FUZZY
    ("Translate or pause.", "pause"),            # nur über WAKE_FUZZY
    ("translator, Ty only.", "thai"),
    ("Translator, English off", "en_off"),
    ("Translator, Thai off", "th_off"),
    ("Translator, English on", "en_on"),
    ("Translator, translate both", "both_on"),
    ("Hey translator resume", "resume"),
    ("Translator.", "wake"),
])
def test_wake_commands(utterance, expected):
    assert detect(utterance) == expected


@pytest.mark.parametrize("utterance", [
    "Translate this menu for me",               # unscharfes Weckwort ohne Befehl
    "I need a translator for this.",            # Weckwort nicht am Satzanfang
    "Hello, how are you?",
])
def test_not_a_command(utterance):
    assert detect(utterance) is None


@pytest.mark.parametrize("cmd, expected", [
    ("translate both", "both_on"),
    ("both ways", "both_on"),
    ("pause", "pause"),
    ("post", "pause"),
    ("Ty only", "thai"),
    ("English only", "english"),
    ("English off", "en_off"),
    ("Thai on", "th_on"),
    ("auto", "auto"),
    ("", "wake"),
    ("what is the weather", None),
])
def test_parse_command(cmd, expected):
    assert parse_command(cmd) == expected


def test_fuzzy_needs_a_command():
    assert WAKE_FUZZY.match("Translate this menu for me")
    assert parse_command(WAKE_FUZZY.match("Translate this menu for me").group(1)) is None


@pytest.mark.parametrize("text, rest", [
    ("Translator, pause", "pause"),
    ("Hey translator resume", "resume"),
    ("ok translater, repeat", "repeat"),
    ("Translator.", ""),
])
def test_wake_regex_matches(text, rest):
    m = WAKE.match(text)
    assert m and m.group(1) == rest


@pytest.mark.parametrize("text", [
    "I need a translator for this.",
    "Translate this menu for me",
    "translators are great",
])
def test_wake_regex_rejects(text):
    assert WAKE.match(text) is None


def test_bare_wake_word_is_empty_not_none():
    # "" (bloßes Weckwort) darf nicht mit None (kein Weckwort) verwechselt werden: Engine öffnet sonst
    # kein Befehlsfenster bzw. übersetzt "Translator." als Satz.
    assert match_wake("Translator.") == ""
    assert match_wake("Hey translator") == ""
    assert match_wake("Hello there") is None


def test_fuzzy_wake_without_command_is_none():
    assert match_wake("Translate this menu for me") is None
    assert match_wake("Translate or pause.") == "pause."
