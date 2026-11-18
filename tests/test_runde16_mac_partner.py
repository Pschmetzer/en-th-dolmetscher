"""Runde 16, Mac-App: Partner-Ansicht (PartnerLogic.swift per swiftc getestet, Verdrahtung per Quelltext)."""
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
let short = PartnerLogic.fontSize(length: 5, width: 1200, height: 800)
let long = PartnerLogic.fontSize(length: 400, width: 1200, height: 800)
check(short > long, "kurzer Satz größer: \(short) \(long)")
check(short <= PartnerLogic.maxFont && long >= PartnerLogic.minFont, "Grenzen")
check(PartnerLogic.fontSize(length: 0, width: 10, height: 10) >= PartnerLogic.minFont, "leer/winzig")
check(abs(PartnerLogic.fontSize(length: 50, width: 1000, height: 700, zoom: 2) - 2 * PartnerLogic.fontSize(length: 50, width: 1000, height: 700)) < 0.001, "Zoom")
check(PartnerLogic.fontSize(length: 50, width: 1000, height: 700, zoom: 9) == PartnerLogic.fontSize(length: 50, width: 1000, height: 700, zoom: 2), "Zoom begrenzt")
func nums(_ t: String) -> [String] { PartnerLogic.segments(t).filter { $0.isNumber }.map { $0.text } }
check(nums("Das kostet 1,250.50 Baht um 14:30") == ["1,250.50", "14:30"], "Preis/Uhrzeit: \(nums("Das kostet 1,250.50 Baht um 14:30"))")
check(nums("ราคา ๓๐๐ บาท") == ["๓๐๐"], "Thai-Ziffern")
check(nums("Ende. Und 5, dann") == ["5"], "Satzzeichen nicht dabei: \(nums("Ende. Und 5, dann"))")
check(nums("keine Zahl").isEmpty && nums("").isEmpty, "keine Zahlen")
for t in ["a 12 b 3.4", "99", "x", "", "ราคา ๓๐๐ บาท 5/6"] {
    check(PartnerLogic.segments(t).map { $0.text }.joined() == t, "Teile ergeben Original: \(t)")
}
print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_partner_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "partner_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "PartnerLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_partner_logic_ohne_ui_abhaengigkeiten():
    src = (ROOT / "app" / "PartnerLogic.swift").read_text(encoding="utf-8")
    assert [ln for ln in src.splitlines() if ln.startswith("import ")] == ["import Foundation"]


def test_partner_verdrahtung_und_texte():
    view = (ROOT / "app" / "PartnerView.swift").read_text(encoding="utf-8")
    l10n = (ROOT / "app" / "L10n.swift").read_text(encoding="utf-8")
    assert "PartnerLogic.fontSize" in view and "PartnerLogic.segments" in view
    assert 'shortcut: "r"' in view and 'shortcut: "s"' in view
    assert "setFrameAutosaveName" in view and "partnerFullscreen" in view and "partnerContrast" in view
    assert "m.partnerVisible = true" in view  # Bildschirm wachhalten
    assert view.count("accessibilityLabel") >= 12
    for k in ("partner_contrast", "partner_presentation", "partner_presentation_end"):
        assert f'"{k}"' in l10n and f'"{k}"' in view


def test_changelog_runde16_partner():
    assert "### Mac app (round 16)" in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
