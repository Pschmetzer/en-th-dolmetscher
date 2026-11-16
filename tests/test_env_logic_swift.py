"""Unit-Tests für app/EnvLogic.swift (Stempel, Python-Auswahl, Ausgabe von setup-env.sh, Platzbedarf).

Übersetzt EnvLogic.swift zusammen mit einem kleinen Test-Hauptprogramm per swiftc und führt es aus
(übersprungen ohne swiftc, z. B. unter Linux)."""
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

// Stempel
let st = "lock=abc\npython=3.12\narch=arm64\n"
check(EnvLogic.stampMatches(expected: st, actual: st), "gleich")
check(EnvLogic.stampMatches(expected: st, actual: "lock=abc\r\npython=3.12\r\narch=arm64"), "CRLF/Zeilenende egal")
check(!EnvLogic.stampMatches(expected: st, actual: "lock=xyz\npython=3.12\narch=arm64\n"), "anderer Lock")
check(!EnvLogic.stampMatches(expected: st, actual: "lock=abc\npython=3.13\narch=arm64\n"), "andere Python-Version")
check(!EnvLogic.stampMatches(expected: st, actual: nil), "fehlender Stempel in der venv")
check(!EnvLogic.stampMatches(expected: nil, actual: st), "fehlender Stempel im Bundle")
check(!EnvLogic.stampMatches(expected: "", actual: ""), "leer passt nie")

// Python-Auswahl: Dev-Override -> venv (nur mit Stempel) -> keins
let exe: Set<String> = ["/dev/py", "/sup/venv/bin/python"]
let isExe: (String) -> Bool = { exe.contains($0) }
check(EnvLogic.resolvePython(override: "/dev/py", venvPython: "/sup/venv/bin/python", stampOK: true,
                             isExecutable: isExe) == .override("/dev/py"), "Override zuerst")
check(EnvLogic.resolvePython(override: "/gibts/nicht", venvPython: "/sup/venv/bin/python", stampOK: true,
                             isExecutable: isExe) == .venv("/sup/venv/bin/python"), "kaputter Override -> venv")
check(EnvLogic.resolvePython(override: nil, venvPython: "/sup/venv/bin/python", stampOK: false, isExecutable: isExe)
      == .none, "venv ohne passenden Stempel zählt nicht (halb eingerichtet / veraltet)")
check(EnvLogic.resolvePython(override: "  ", venvPython: "/sup/venv/bin/python", stampOK: true, isExecutable: isExe)
      == .venv("/sup/venv/bin/python"), "leerer Override ignoriert")
check(EnvLogic.resolvePython(override: nil, venvPython: "/fehlt/python", stampOK: true, isExecutable: isExe)
      == .none, "Stempel ohne Python -> keins")
let home = NSHomeDirectory()
let tilde = EnvLogic.resolvePython(override: "~/py", venvPython: "/x", stampOK: false,
                                   isExecutable: { $0 == home + "/py" })
check(tilde == .override(home + "/py"), "Tilde im Override")
// Nie /usr/bin/python3 als Ersatz
check(EnvLogic.resolvePython(override: nil, venvPython: "/x", stampOK: false, isExecutable: { _ in true }) == .none,
      "kein System-Python")

// setup-env.sh-Zeilen
check(EnvLogic.parseSetupLine("step packages\n") == .step("packages"), "step")
check(EnvLogic.parseSetupLine("done") == .done, "done")
check(EnvLogic.parseSetupLine("fail offline") == .fail("offline"), "fail")
check(EnvLogic.parseSetupLine("irgendwas") == nil && EnvLogic.parseSetupLine("") == nil, "Rauschen")
check(EnvLogic.stepFraction("python") < EnvLogic.stepFraction("packages")
      && EnvLogic.stepFraction("packages") < EnvLogic.stepFraction("verify"), "Fortschritt steigt")

// Platz
check(abs(EnvLogic.requiredGB(envMissing: true, modelsGB: 3.5) - 4.4 * 1.1) < 1e-9, "Bedarf Umgebung + Modelle")
check(EnvLogic.requiredGB(envMissing: false, modelsGB: 0) == 0, "nichts fehlt")
check(EnvLogic.enoughSpace(freeBytes: 5_000_000_000, requiredGB: 4.84), "genug")
check(!EnvLogic.enoughSpace(freeBytes: 4_000_000_000, requiredGB: 4.84), "zu wenig")
check(EnvLogic.enoughSpace(freeBytes: nil, requiredGB: 99), "unbekannt blockiert nicht")
check(EnvLogic.downloadFraction(done: 50, total: 200) == 0.25, "Anteil")
check(EnvLogic.downloadFraction(done: 300, total: 200) == 1, "gedeckelt")
check(EnvLogic.downloadFraction(done: 5, total: nil) == nil && EnvLogic.downloadFraction(done: 5, total: 0) == nil,
      "ohne Gesamtgröße")

print(failures == 0 ? "OK" : "FEHLER \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
def test_env_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "envlogic_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "EnvLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_envlogic_ohne_ui_abhaengigkeiten():
    """Bleibt testbar: nur Foundation, kein SwiftUI/AppKit."""
    src = (ROOT / "app" / "EnvLogic.swift").read_text(encoding="utf-8")
    imports = [ln for ln in src.splitlines() if ln.startswith("import ")]
    assert imports == ["import Foundation"]
