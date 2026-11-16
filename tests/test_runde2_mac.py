"""Runde 2, Mac-App M-Punkte (Quelltext-Prüfungen): Absturz-Mitteilung (351), Auto-Scroll per Scrollposition
(352), Schriftzoom überall (353), Tastatur an Sprechblasen (354), Erststart-Checkliste (355), Modell-Cache-
Hinweis (356), Höflichkeit je Profil in der App (162)."""
import pathlib
import re

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = {f.name: f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift")}


def test_absturz_mitteilung_nur_ohne_fenster_und_mit_neustart():
    n = APP["Notifications.swift"]
    assert "!mainWindowVisible && hasBundle" in n and "UNNotificationAction(identifier: Self.restartAction" in n
    assert "CrashNotifier.shared.onRestart?()" in n
    eng = APP["Engine.swift"]
    ended = eng.split("private func engineEnded", 1)[1].split("\n    }\n", 1)[0]
    # erst nach den automatischen Neustarts (die kehren vorher mit return zurück)
    assert ended.index("CrashNotifier.shared.notifyStopped") > ended.index("return\n        }")
    assert "CrashNotifier.shared.onRestart = { [weak self] in self?.restart() }" in eng


def test_auto_scroll_wertet_inhalt_statt_nur_mausrad():
    v = APP["Views.swift"]
    assert "AutoScroll.userScrolledAway(" in v and "if !bottomVisible, AutoScroll" in v
    assert "onChange(of: g.size.height) { scrollBox.lastContentChange = Date() }" in v   # Band/Fenster schrumpft
    assert ".onChange(of: shown.last) { scrollBox.lastContentChange = Date() }" in v
    rule = v.split("enum AutoScroll", 1)[1].split("\n}\n", 1)[0]
    assert "> contentGrace" in rule


def test_schriftzoom_ueberall():
    v = APP["Views.swift"]
    assert "struct ScaledFont: ViewModifier" in v
    for snippet in ('Text(m.status).scaledFont(13, .semibold)', 'Text(text).scaledFont(12)',
                    '.scaledFont(26, .semibold)'):
        assert snippet in v, snippet
    assert 'Text(m.status).font(.headline)' not in v and 'Text(text).font(.callout)' not in v


def test_sprechblase_per_tastatur():
    b = APP["BubbleViews.swift"]
    assert ".focusable()" in b and ".onKeyPress(.return)" in b and ".onCopyCommand" in b


def test_erststart_checkliste_und_modellhinweis():
    s = APP["Setup.swift"]
    assert "SetupChecklist(model: model, thai: thai)" in APP["Views.swift"]
    assert "ModelCache.hint(model: m.model" in APP["SettingsView.swift"]
    # Repos wie in der Engine (Revisionen gepinnt): sonst zeigt die App „geladen“ für das falsche Modell
    repos = set(re.findall(r'Repo\(id: "([^"]+)"', s))
    assert d.THAI_MODEL in repos
    for name in ("small", "medium", "large-v3-turbo"):
        assert any(r.endswith("faster-whisper-" + name) for r in repos), name
    assert '"small": return [small]' in s                     # small lädt kein Thai-Modell (Engine.__init__)


def test_hoeflichkeit_je_profil_in_der_app():
    p = APP["Profiles.swift"]
    assert 'request: ["polite": [p.name, v]]' in p and 'polite: d["polite"] as? String' in p
    assert 'req.get("polite")' in (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
