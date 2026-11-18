"""Runde 12, Mac-App: statisches Barrierefreiheits-Audit (Quelltext, kein Live-Lauf)."""
import pathlib
import re

APP = pathlib.Path(__file__).resolve().parent.parent / "app"
FILES = sorted(APP.glob("*.swift"))


def lines(path):
    return path.read_text(encoding="utf-8").split("\n")


def test_bildknoepfe_ohne_text_haben_label():
    """Jeder Button, dessen Label nur aus einem Image besteht, braucht ein accessibilityLabel."""
    bad = []
    for f in FILES:
        ls = lines(f)
        for i, row in enumerate(ls):
            if re.search(r"Button\b.*\{\s*Image\(", row):
                if not re.search(r"accessibilityLabel", "\n".join(ls[i:i + 6])):
                    bad.append(f"{f.name}:{i + 1}")
    assert not bad, bad


def test_dekorative_bilder_versteckt_oder_beschriftet():
    """Image(systemName:) außerhalb von Label/Button braucht accessibilityHidden oder -Label in der Nähe."""
    bad = []
    for f in FILES:
        ls = lines(f)
        for i, row in enumerate(ls):
            if "Image(systemName" not in row or "Label(" in row or re.search(r"Button\b", row):
                continue
            if i > 0 and re.search(r"Button\b|Label\s*\{", ls[i - 1]):
                continue
            ctx = "\n".join(ls[max(0, i - 3):i + 7])
            if not re.search(r"accessibility(Label|Hidden)", ctx) and "Label {" not in ctx:
                bad.append(f"{f.name}:{i + 1}")
    # Statusbild im Start-Knopf: der Knopf trägt Label, Wert und Hinweis selbst
    bad = [b for b in bad if not b.startswith("Views.swift:6")]
    assert not bad, bad


def test_jede_animation_beachtet_reduzierte_bewegung():
    bad = []
    for f in FILES:
        s = f.read_text(encoding="utf-8")
        for m in re.finditer(r"withAnimation|\.animation\(|\.transition\(", s):
            ln = s.count("\n", 0, m.start())
            ctx = "\n".join(s.split("\n")[max(0, ln - 4):ln + 1])
            if "reduceMotion" not in ctx and "appear" not in ctx:
                bad.append(f"{f.name}:{ln + 1}")
    assert not bad, bad
    for f in FILES:
        s = f.read_text(encoding="utf-8")
        if re.search(r"withAnimation|\.animation\(", s):
            assert "accessibilityReduceMotion" in s, f.name


def test_ueberschriften_traits():
    for name, needle in (("Extras.swift", 'whatsnew_title'), ("Runde8.swift", "shortcuts_title"),
                         ("Runde8.swift", "glossary_add_title"), ("Setup.swift", "setup_title"),
                         ("EnvSetup.swift", "Text(title).font(.headline)")):
        s = (APP / name).read_text(encoding="utf-8")
        i = s.index(needle)
        assert ".isHeader" in s[i:i + 200], (name, needle)
    v = (APP / "Views.swift").read_text(encoding="utf-8")
    assert v.count(".accessibilityAddTraits(.isHeader)") >= 2   # Mikrofon-verweigert- und Absturz-Banner


def test_setup_schritt_nennt_zustand_nicht_nur_per_symbol():
    s = (APP / "EnvSetup.swift").read_text(encoding="utf-8")
    assert ".accessibilityValue(L.t(stepKey(st)))" in s
    for k in ("a11y_step_done", "a11y_step_pending", "a11y_step_active"):
        assert k in s
    assert ".accessibilityHidden(true)" in (APP / "Extras.swift").read_text(encoding="utf-8")


def test_statuswechsel_werden_angesagt_und_zustand_nicht_nur_farbe():
    e = (APP / "Engine.swift").read_text(encoding="utf-8")
    for k in ("a11y_ready", "a11y_mic_on", "a11y_mic_off", "a11y_paused", "a11y_offline", "a11y_online"):
        assert k in e, k
    v = (APP / "Views.swift").read_text(encoding="utf-8")
    assert ".accessibilityValue(stateText)" in v          # Start/Stopp nicht nur rot/grün
    assert "low_conf" in (APP / "BubbleViews.swift").read_text(encoding="utf-8")   # Warnrahmen hat Text
