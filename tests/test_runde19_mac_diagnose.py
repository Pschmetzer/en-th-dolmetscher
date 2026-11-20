"""Runde 19, Mac-App: Diagnose und Selbsttest (DiagnosticsLogic.swift per swiftc getestet, Verdrahtung per Quelltext)."""
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
typealias D = DiagnosticsLogic
let home = "/Users/maxmuster"
let r1 = D.redact("Fehler in /Users/maxmuster/Library/venv/bin/python und /Users/anna/x", home: home, user: "maxmuster")
check(!r1.contains("maxmuster") && !r1.contains("anna"), "Pfade/Nutzer: \(r1)")
check(r1.contains("~/Library/venv/bin/python"), "Home als ~: \(r1)")
let r2 = D.redact("ANTHROPIC_API_KEY=sk-ant-abcdef1234567890 und Bearer abc.def.ghi12345 und hf_abcdefghijkl", home: home, user: "maxmuster")
check(!r2.contains("sk-ant") && !r2.contains("abc.def") && !r2.contains("hf_abc"), "Schlüssel: \(r2)")
let r3 = D.redact("token: " + String(repeating: "A", count: 48) + " ende", home: home, user: "maxmuster")
check(!r3.contains("AAAA") && r3.contains("ende"), "langes Token: \(r3)")
check(D.redact("Modell biodatlab-whisper-th-medium-faster ok", home: home, user: "maxmuster").contains("biodatlab-whisper-th-medium-faster"), "Modellname bleibt")
check(D.redact("MaxMuster sagt", home: "/x", user: "maxmuster") == "<user> sagt", "Nutzername ohne Pfad")
check(D.redact("alles gut", home: "/", user: "") == "alles gut", "leer/Wurzel")
let rows: [D.Row] = [D.Row(id: "mic", status: .ok, detail: "erlaubt"),
                     D.Row(id: "network", status: .fail, detail: "offline /Users/maxmuster/x")]
check(D.overall(rows) == .fail && D.overall([rows[0]]) == .ok && D.overall([]) == .ok, "Gesamt")
check(D.overall([D.Row(id: "speaker", status: .warn, detail: "")]) == .warn, "Warnung")
check(D.suggestionKey(id: "mic", status: .ok) == nil && D.suggestionKey(id: "network", status: .fail) == "diag_fix_network_fail", "Vorschlagsschlüssel")
let rep = D.report(lines: ["Dolmetscher 1.0", "Python: /Users/maxmuster/venv"], rows: rows, lastError: "Mikro maxmuster", home: home, user: "maxmuster")
check(!rep.contains("maxmuster"), "Bericht ohne Nutzername: \(rep)")
check(rep.contains("Self-test: fail") && rep.contains("[fail] network") && rep.contains("Last error"), "Bericht Inhalt: \(rep)")
check(D.report(lines: ["a"], rows: [], lastError: nil, home: home, user: "u").contains("Self-test") == false, "ohne Selbsttest")
check(D.rowIDs.count == 5 && D.helpURL.hasSuffix("docs/FEHLERHILFE.md"), "Zeilen/Link")
print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_diagnostics_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "diag_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "DiagnosticsLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_diagnostics_logic_ohne_ui_abhaengigkeiten():
    src = (ROOT / "app" / "DiagnosticsLogic.swift").read_text(encoding="utf-8")
    assert [ln for ln in src.splitlines() if ln.startswith("import ")] == ["import Foundation"]


def test_diagnose_verdrahtung_und_texte():
    view = (ROOT / "app" / "DiagnosticsView.swift").read_text(encoding="utf-8")
    support = (ROOT / "app" / "Support.swift").read_text(encoding="utf-8")
    app = (ROOT / "app" / "DolmetscherApp.swift").read_text(encoding="utf-8")
    l10n = (ROOT / "app" / "L10n.swift").read_text(encoding="utf-8")
    assert "DiagnosticsLogic.report" in support
    assert "DiagnosticsLogic.suggestionKey" in view and "DiagnosticsLogic.helpURL" in view
    assert ".showSelfTest" in app and "selftest_open" in app
    for row in ("mic", "speaker", "network", "models", "python"):
        assert f'"diag_row_{row}"' in l10n and f'"diag_fix_{row}_fail"' in l10n
    assert '"diag_fix_mic_warn"' in l10n and '"diag_fix_speaker_warn"' in l10n


def test_fehlerhilfe_nennt_selbsttest():
    de = (ROOT / "docs" / "FEHLERHILFE.md").read_text(encoding="utf-8")
    en = (ROOT / "docs" / "en" / "TROUBLESHOOTING.md").read_text(encoding="utf-8")
    assert "Selbsttest" in de and "Self-test" in en
