"""Tests für Weckwort und Sprachbefehle – ohne Modell, Netz oder Mikrofon.

Der Import von dolmetscher lädt kein Whisper-Modell (nur `from faster_whisper import WhisperModel`).
"""
import pytest

from dolmetscher import WAKE, WAKE_FUZZY, parse_command


def detect(text):
    """Nachbau der Weckwort-Logik aus Engine (dolmetscher.py, Abschnitt "Sprachbefehle").

    Gibt den erkannten Befehl zurück oder None, wenn kein Weckwort erkannt wurde.
    Muss angepasst werden, falls sich die Logik in Engine ändert.
    """
    m = WAKE.match(text)
    fz = None if m else WAKE_FUZZY.match(text)
    if fz and parse_command(fz.group(1)) not in (None, "wake"):
        m = fz
    if not m:
        return None
    return parse_command(m.group(1).strip(" .,!?"))


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
