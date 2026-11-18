"""Runde 17, Mac-App: Menüleiste und Dock (MenuBarLogic.swift per swiftc getestet, Verdrahtung per Quelltext)."""
# ruff: noqa: E501  (Swift-Testprogramm als Zeichenkette)
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent

MAIN = r'''
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL \(line): \(what)") }
}
func st(_ f: (inout MenuBarInput) -> Void) -> MenuBarStatus { var i = MenuBarInput(); f(&i); return MenuBarLogic.status(i) }
check(st { _ in } == .stopped, "aus")
check(st { $0.active = true } == .listening, "hört")
check(st { $0.active = true; $0.speaking = true } == .speaking, "spricht")
check(st { $0.active = true; $0.paused = true; $0.speaking = true } == .paused, "Pause vor Sprechen")
check(st { $0.active = true; $0.offline = true } == .offline, "offline")
check(st { $0.active = true; $0.loading = true; $0.offline = true } == .loading, "laden vor offline")
check(st { $0.hasError = true; $0.loading = true; $0.active = true } == .error, "Fehler zuerst")
let all: [MenuBarStatus] = [.error, .loading, .offline, .stopped, .paused, .listening, .speaking]
check(Set(all.map { MenuBarLogic.symbol($0) }).count == all.count, "Symbole verschieden")
check(Set(all.map { MenuBarLogic.labelKey($0) }).count == all.count, "Texte verschieden")
check(!MenuBarLogic.canToggle(.loading) && MenuBarLogic.canToggle(.error), "Toggle beim Laden aus")
var i = MenuBarInput(); i.running = true
check(!MenuBarLogic.canPause(i), "Pause nur aktiv")
i.active = true
check(MenuBarLogic.canPause(i) && !MenuBarLogic.canCopyLast(i), "Pause ja, Kopieren nein")
i.hasLast = true
check(MenuBarLogic.canCopyLast(i), "Kopieren")
let sw = MenuBarLogic.swapped(mine: "en", partner: "th")
check(sw.mine == "th" && sw.partner == "en", "Tausch")
check(MenuBarLogic.preview("a\nb") == "a b", "einzeilig")
check(MenuBarLogic.preview(String(repeating: "x", count: 100)).count == 60, "gekürzt")
print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_menubar_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "menubar_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "MenuBarLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_menubar_logic_ohne_ui_abhaengigkeiten():
    src = (ROOT / "app" / "MenuBarLogic.swift").read_text(encoding="utf-8")
    assert [ln for ln in src.splitlines() if ln.startswith("import ")] == ["import Foundation"]


def test_menubar_verdrahtung_und_texte():
    app = (ROOT / "app" / "DolmetscherApp.swift").read_text(encoding="utf-8")
    l10n = (ROOT / "app" / "L10n.swift").read_text(encoding="utf-8")
    assert "MenuBarLogic.symbol" in app and "MenuBarLogic.labelKey" in app
    assert "dockSwap" in app and "dockCopy" in app
    assert 'keyboardShortcut("k", modifiers: [.command, .option])' in app
    assert app.count("menu_swap_vo") >= 2 and app.count("menu_copy_last_vo") >= 2
    for k in ("menu_state_speaking", "menu_state_offline_only", "menu_swap_pair", "menu_engine_status",
              "menu_copy_last_vo", "menu_swap_vo"):
        assert f'"{k}"' in l10n


def test_changelog_runde17_menubar():
    assert "### Mac app (round 17)" in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
