"""Runde 8 (Mac): schmale Fenster, Ladefortschritt, Menüleiste, Kürzel – statische Prüfung der Swift-Quellen."""
import pathlib
import re

APP = pathlib.Path(__file__).resolve().parent.parent / "app"


def _src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_toolbar_and_conversation_bar_adapt_to_narrow_windows():
    v = _src("Views.swift")
    assert v.count("ViewThatFits(in: .horizontal)") >= 2          # Werkzeugleiste und Eingabezeile
    assert "private var compactMenu" in v and "L.t(\"more_tools_help\")" in v
    # das Popover der Befehle hängt am Container, nicht an einem Knopf, der im Menü verschwindet
    assert v.index(".popover(isPresented: $showCommands") < v.index("private var compactMenu")


def test_loading_shows_numbers_not_only_a_spinner():
    v = _src("Views.swift")
    assert "struct ModelLoadProgress" in v
    assert "EnvLogic.downloadFraction" in v
    assert v.count("ModelLoadProgress()") >= 1


def test_main_window_remembers_its_frame():
    assert "setFrameAutosaveName" in _src("Views.swift")


def test_menu_bar_extra_offers_direction_speak_and_windows():
    a = _src("DolmetscherApp.swift")
    body = a[a.index("struct MenuBarContent"):a.index("@main")]
    for needle in ('"dir_auto"', '"speak_toggle"', '"partner_view"', '"caption_title"', "showSettingsWindow"):
        assert needle in body, needle


def test_new_shortcuts_do_not_clash():
    a = _src("DolmetscherApp.swift")
    combos = re.findall(r'keyboardShortcut\(([^)]*)\)', a)
    normal = [c for c in combos if "Character" not in c]
    assert len(normal) == len(set(normal)), "doppeltes Tastenkürzel"
    assert 'keyboardShortcut("l", modifiers: .command)' in a
