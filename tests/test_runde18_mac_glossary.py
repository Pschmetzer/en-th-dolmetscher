"""Runde 18, Mac-App: Glossar-Editor (GlossaryLogic.swift per swiftc getestet, Verdrahtung per Quelltext)."""
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
typealias G = GlossaryLogic
let text = "# Kommentar\nNok => Nok\nSomchai\n\nBaan => Haus\nbaan => Zuhause\nBaan => haus\n"
let es = G.entries(text)
check(es.map { $0.term } == ["Nok", "Somchai", "Baan", "baan", "Baan"], "Einträge: \(es.map { $0.term })")
check(es[1].translation == "" && es[0].translation == "Nok", "Übersetzung/leer")
let kinds = G.issues(text)
check(kinds.map { $0.kind } == [.conflict, .duplicate], "Konflikt+Doppelt: \(kinds)")
check(G.issues("a => " + String(repeating: "x", count: 121)).first?.kind == .tooLong, "zu lang")
let many = (1...205).map { "w\($0)" }.joined(separator: "\n")
check(G.issues(many).filter { $0.kind == .overLimit }.count == 5, "Limit 200")
check(G.clean("a => b\nc") == "a b c", "clean")
check(G.line(term: "  Nok ", translation: "") == "Nok" && G.line(term: "", translation: "x") == "", "line")
check(G.appending(term: "X", translation: "Y", to: "a") == "a\nX => Y\n", "append")
check(G.removing(line: 1, from: "a\nb\nc") == "a\nc", "remove")
check(G.inserting("b", at: 1, into: "a\nc") == "a\nb\nc", "undo-insert")
check(G.replacing(line: 0, term: "n", translation: "m", in: "a\nc") == "n => m\nc", "replace")
check(G.replacing(line: 9, term: "n", translation: "m", in: "a") == "a", "replace außerhalb")
check(G.filter(es, query: "HAUS").count == 3 && G.filter(es, query: "").count == es.count, "Suche")
check(G.filter(G.entries("Éric => Eric"), query: "eric").count == 1, "Akzent egal")
// CSV
let exp = G.exportCSV([GlossaryEntry(term: "=SUM(A1)", translation: "a,\"b\"", line: 0), GlossaryEntry(term: "Nok", translation: "", line: 1)])
check(exp.contains("\"'=SUM(A1)\"") && exp.contains("\"a,\"\"b\"\"\""), "Export Formelschutz/Quote: \(exp)")
let back = G.importCSV(Data(exp.utf8))
check(back.entries.map { $0.term } == ["=SUM(A1)", "Nok"] && back.entries[0].translation == "a,\"b\"", "Roundtrip: \(back.entries)")
let imp = G.importCSV(Data("\u{FEFF}Wort;Übersetzung\n=cmd|x;a\nHallo;Sawadee\n@x;\n+66;t\n\"Mehr\nzeilig\";x\n;leer\n#c;x\na;b;c\n".utf8))
check(imp.entries.map { $0.term } == ["Hallo", "Mehr zeilig"], "Import gefiltert: \(imp.entries.map { $0.term })")
check(imp.skipped.map { $0.reason } == ["formula", "formula", "formula", "empty", "comment", "columns"], "Gründe: \(imp.skipped.map { $0.reason })")
check(G.importCSV(Data(count: 300_000)).fatal == "size", "Größe")
check(G.importCSV(Data([0xFF, 0xFE, 0x00])).fatal == "encoding", "UTF-8")
check(G.importCSV(Data("a\u{0}b,c".utf8)).fatal == "binary", "binär")
check(G.importCSV(Data((0..<1002).map { "w\($0),x" }.joined(separator: "\n").utf8)).fatal == "rows", "Zeilenlimit")
check(G.importCSV(Data("term,translation\nA,b\n".utf8)).entries.count == 1, "Kopfzeile")
check(G.importCSV(Data(("a," + String(repeating: "x", count: 130) + "\n").utf8)).skipped.first?.reason == "long", "lang")
// Zusammenführen
let mg = G.merge([GlossaryEntry(term: "nok", translation: "Nok", line: -1), GlossaryEntry(term: "Baan", translation: "Heim", line: -1),
                  GlossaryEntry(term: "Neu", translation: "New", line: -1), GlossaryEntry(term: "NEU", translation: "Nova", line: -1)], into: "Nok => Nok\nBaan => Haus\n")
check(mg.added == 1 && mg.duplicates == 1 && mg.conflicts == 2 && mg.text.hasSuffix("Neu => New\n"), "merge: \(mg)")
let full = (1...200).map { "w\($0)" }.joined(separator: "\n") + "\n"
check(G.merge([GlossaryEntry(term: "z", translation: "", line: -1)], into: full).rejected == 1, "merge Limit")
// Vorschau
let list = G.entries("Pat => Patrick\nบ้าน => house\nNok\nSom => Sam")
check(G.preview(list, sample: "path to Pat").map { $0.term } == ["Pat"], "Ganzwort")
check(G.preview(list, sample: "ฉันอยู่บ้านนี้").map { $0.result } == ["house"], "Thai Teilstring")
let kept = G.preview(list, sample: "hello NOK!")
check(kept.count == 1 && kept[0].kept && kept[0].result == "Nok", "unverändert")
check(G.preview(list, sample: "nichts").isEmpty && G.preview(list, sample: "").isEmpty, "keine Treffer")
print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_glossary_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "glossary_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "GlossaryLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_glossary_logic_ohne_ui_abhaengigkeiten():
    src = (ROOT / "app" / "GlossaryLogic.swift").read_text(encoding="utf-8")
    assert [ln for ln in src.splitlines() if ln.startswith("import ")] == ["import Foundation"]


def test_glossary_grenzen_wie_engine():
    py = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    sw = (ROOT / "app" / "GlossaryLogic.swift").read_text(encoding="utf-8")
    for name, swift in (("TERM_MAX", "termMax"), ("GLOSSARY_LIMIT", "entryLimit")):
        val = next(ln for ln in py.splitlines() if ln.startswith(name + " =")).split("=")[1].split("#")[0].strip()
        assert f"static let {swift} = {val}" in sw, name


def test_glossary_verdrahtung_und_texte():
    view = (ROOT / "app" / "GlossaryView.swift").read_text(encoding="utf-8")
    settings = (ROOT / "app" / "SettingsView.swift").read_text(encoding="utf-8")
    assert "GlossaryEditorSheet()" in settings and "GlossaryLogic.importCSV" in view and "GlossaryLogic.exportCSV" in view
    assert "GlossaryLogic.preview" in view and "undo()" in view and "gl_issue_conflict" in view
    assert view.count(".accessibilityLabel(") >= 8
