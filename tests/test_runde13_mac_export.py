"""Runde 13, Mac-App: Export (app/ExportFormats.swift per swiftc getestet, Verdrahtung und Texte per Quelltext)."""
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
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func item(_ at: Double, _ text: String, _ out: String = "Hallo", tr: Bool = true, sp: String? = nil,
          dur: Double? = nil, ready: Double? = nil) -> ExportItem {
    ExportItem(at: t0.addingTimeInterval(at), lang: "th", to: "de", text: text, out: out, translated: tr,
               speaker: sp, dur: dur, readyS: ready)
}

check(ExportFormats.mdEscape("a*b_c#d|e<f>") == "a\\*b\\_c\\#d\\|e\\<f\\>", "Markdown maskiert")
check(ExportFormats.mdEscape("x\ny") == "x  \ny", "Umbruch hart")
check(ExportFormats.csvCell("=1+1") == "\"'=1+1\"", "Formel entschärft")
check(ExportFormats.csvCell("@SUM") == "\"'@SUM\"" && ExportFormats.csvCell("-1") == "\"'-1\"", "@ und -")
check(ExportFormats.csvCell("a\"b") == "\"a\"\"b\"", "Anführungszeichen")
check(ExportFormats.csvCell("สวัสดี") == "\"สวัสดี\"", "Thai unverändert")

check(ExportFormats.timestamp(3661.5, comma: true) == "01:01:01,500", "SRT-Zeit")
check(ExportFormats.timestamp(-3, comma: false) == "00:00:00.000", "VTT-Zeit, nie negativ")

let a = [item(0, "จุด", "Punkt"), item(10, "สวัสดี", sp: "me", dur: 2, ready: 1), item(14, "สอง", tr: false)]
let c = ExportFormats.cues(a)
check(abs(c[1].start - 7) < 0.001 && abs(c[1].end - 9) < 0.001, "Beginn = Ankunft - Bereit - Länge (\(c[1]))")
check(c[2].start == 14, "Ohne dur: Ankunft")
let srt = ExportFormats.srt(a)
check(srt.contains("2\n00:00:07,000 --> 00:00:09,000\n[me] สวัสดี\nHallo\n\n3\n"), "SRT: \(srt)")
check(srt.hasSuffix("สอง\n\n"), "Nicht übersetzt ohne Zeile")
let vtt = ExportFormats.webvtt(a)
check(vtt.contains("\n\n00:00:07.000 --> 00:00:09.000\n") && vtt.hasPrefix("WEBVTT\n\n"), "VTT-Kopf und Punkt: \(vtt)")
check(!vtt.contains("\n1\n"), "VTT ohne Nummern")
check(ExportFormats.srt([]) == "" && ExportFormats.webvtt([]) == "", "leer")

let evil = ExportFormats.webvtt([item(0, "a --> b\n\nc <b>&", "x")])
check(evil.contains("a –> b\nc &lt;b>&amp;"), "Einschleusung entschärft: \(evil)")
check(!ExportFormats.srt([item(0, "\n\n", "ok")]).contains("\n\n\n"), "leere Zeilen im Block")

let f = ExportFormats.filter([item(0, "a"), item(60, "b"), item(120, "c")], from: t0.addingTimeInterval(30), to: nil)
check(f.count == 2 && f[0].text == "b", "Zeitraum von")
check(ExportFormats.filter(a, from: nil, to: t0.addingTimeInterval(11)).count == 2, "Zeitraum bis")

let n = ExportFormats.fileName(base: "Gespräch/ได้:x", date: t0, ext: "vtt")
check(n.hasSuffix(".vtt") && !n.contains("/") && !n.contains(":") && n.contains("-"), "Dateiname: \(n)")
check(ExportFormats.fileName(base: "  ", date: t0, ext: "md").hasPrefix("export "), "leerer Name")

let d = ExportFormats.fileData("สวัสดี ä", csv: true)
check(Array(d.prefix(3)) == [0xEF, 0xBB, 0xBF], "BOM bei CSV")
check(String(decoding: d.dropFirst(3), as: UTF8.self) == "สวัสดี ä", "Thai/Umlaut UTF-8")
check(ExportFormats.fileData("x", csv: false).count == 1, "kein BOM sonst")

print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_export_formats_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "export_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "ExportFormats.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_export_formats_ohne_ui_abhaengigkeiten():
    src = (ROOT / "app" / "ExportFormats.swift").read_text(encoding="utf-8")
    assert [ln for ln in src.splitlines() if ln.startswith("import ")] == ["import Foundation"]


def test_export_verdrahtung_und_texte():
    sup = (ROOT / "app" / "Support.swift").read_text(encoding="utf-8")
    l10n = (ROOT / "app" / "L10n.swift").read_text(encoding="utf-8")
    assert 'vtt = "vtt"' in sup and "ExportFormats.webvtt" in sup and "ExportFormats.csvCell" in sup
    assert "accessoryView" in sup and "export_privacy" in sup
    for fmt in ("md", "txt", "json", "csv", "srt", "vtt"):
        assert f'"export_fmt_{fmt}"' in l10n
    for k in ("export_format", "export_range", "export_range_all", "export_range_hour", "export_range_today",
              "export_privacy"):
        assert f'"{k}"' in l10n


def test_changelog_runde13_export():
    assert "### Mac app (round 13)" in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
