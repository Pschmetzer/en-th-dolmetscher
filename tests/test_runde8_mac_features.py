"""Runde 8 (Mac), zweiter Teil: Fehlerhilfe, Großanzeige, Glossar-Schnelleingabe, Kürzel, Verlaufs-Export."""
import pathlib
import re

APP = pathlib.Path(__file__).resolve().parent.parent / "app"
DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"


def _src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_every_advised_error_code_is_a_known_engine_code():
    """Die Fehlerhilfe darf nur Codes behandeln, die die Engine wirklich meldet (docs/PROTOKOLL.md)."""
    r8 = _src("ErrorAdviceLogic.swift")
    body = r8[r8.index("static func advice"):r8.index("static func restartsEngine")]
    codes = set(re.findall(r'"([a-z_]+)"', "\n".join(ln for ln in body.splitlines() if "case" in ln)))
    codes = {c for c in codes if not c.startswith("advice_")}
    protocol = (DOCS / "PROTOKOLL.md").read_text(encoding="utf-8")
    assert codes, "keine Codes gefunden"
    missing = [c for c in sorted(codes) if c not in protocol]
    assert not missing, f"nicht in PROTOKOLL.md: {missing}"


def test_error_banner_replaces_plain_log_banner():
    v = _src("Views.swift")
    assert "ErrorBanner(error: e)" in v
    assert "NetDownBanner()" in v
    assert "lastErrorCode = code" in _src("Engine.swift")


def test_search_hits_can_be_exported_and_empty_result_has_a_way_out():
    v, s = _src("Views.swift"), _src("Support.swift")
    assert "exportConversation(m, only: shown)" in v
    assert "func exportConversation(_ m: EngineModel, only subset" in s
    assert "reset_filter" in v and "no_results" in v


def test_bubble_can_share_and_show_large():
    b = _src("BubbleViews.swift")
    assert "ShareLink(" in b
    assert b.count("showBigText") >= 2     # Kontextmenü und VoiceOver-Aktion


def test_glossary_line_format_is_in_sync_with_engine_format():
    r8 = _src("Runde8.swift")
    assert '" => "' in r8 and "flushGlossary()" in r8      # Format `Wort => Übersetzung` laut PROTOKOLL.md
    assert "Wort => Übersetzung" in (DOCS / "PROTOKOLL.md").read_text(encoding="utf-8")


def test_shortcut_sheet_lists_only_real_shortcuts():
    r8, a = _src("Runde8.swift"), _src("DolmetscherApp.swift")
    for k in ("⌘L", "⌥⌘S", "⌥⌘L", "⇧⌘C", "⌥⌘G", "⌘/"):
        assert k in r8
    assert 'keyboardShortcut("g", modifiers: [.command, .option])' in a
    assert 'keyboardShortcut("c", modifiers: [.command, .shift])' in a
    combos = re.findall(r'keyboardShortcut\(([^)]*)\)', a)
    normal = [c for c in combos if "Character" not in c]
    assert len(normal) == len(set(normal))


def test_settings_search_index_uses_existing_keys_and_tabs():
    st = _src("SettingsView.swift")
    block = st[st.index("static let index"):st.index("static func matches")]
    pairs = re.findall(r'\("([a-z_]+)", (\d)\)', block)
    assert len(pairs) >= 40
    l10n = _src("L10n.swift")
    for key, tab in pairs:
        assert f'"{key}": [' in l10n, key
        assert int(tab) in range(5)   # Runde 21: Reiter 4 = Erweitert & Datenschutz
    assert st.count(".tag(") >= 4


def test_caption_window_and_partner_view_extras():
    e, p = _src("Extras.swift"), _src("PartnerView.swift")
    assert "captionOriginal" in e and "contextMenu" in e and "setFrameAutosaveName" in e
    assert "partner_prev" in p and "partner_next" in p and "back = 0" in p


def test_dock_menu_exists():
    a = _src("DolmetscherApp.swift")
    assert "applicationDockMenu" in a and "dockToggle" in a
