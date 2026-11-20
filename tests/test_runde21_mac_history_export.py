"""Runde 21, Mac-App: Verlaufs-Export als Text, JSON und WebVTT (HistoryExport.swift per swiftc getestet)."""
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
func row(_ at: Double, _ text: String, _ out: String) -> HistoryRow {
    HistoryRow(time: t0.addingTimeInterval(at), session: "a", lang: "th", text: text, translation: out, translit: "",
               confidence: nil, provider: "claude", role: nil, speaker: nil)
}
let s = HistorySession(id: "a", start: t0, rows: [row(0, "สวัสดี", "Hallo"), row(3, "ขอบคุณ", "Danke")])
let utc = TimeZone(identifier: "UTC")!
let txt = HistoryLogic.text(s, title: "T", timeZone: utc)
check(txt.hasPrefix("T\n\n[22:13:20] TH: สวัสดี\n  → Hallo\n"), "Text: \(txt)")
let vtt = HistoryLogic.vtt(s)
check(vtt.hasPrefix("WEBVTT\n\n1\n00:00:00.000 --> 00:00:03.000\n"), "VTT: \(vtt)")
check(!vtt.contains(","), "VTT ohne Komma")
check(HistoryLogic.vtt(HistorySession(id: "e", start: t0, rows: [])) == "", "VTT leer")
let js = HistoryLogic.json(s, title: "T")
let obj = try! JSONSerialization.jsonObject(with: Data(js.utf8)) as! [String: Any]
let items = obj["items"] as! [[String: Any]]
check(obj["title"] as? String == "T" && items.count == 2 && items[1]["translation"] as? String == "Danke", "JSON")
check(items[0]["provider"] as? String == "claude" && items[0]["translit"] == nil, "JSON Felder")
print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_history_export_formate(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "t"
    srcs = [str(ROOT / "app" / f) for f in ("HistoryLogic.swift", "ExportFormats.swift", "HistoryExport.swift")]
    b = subprocess.run(["swiftc", "-o", str(exe), *srcs, str(main)], capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_history_view_bietet_alle_formate():
    view = (ROOT / "app" / "HistoryView.swift").read_text(encoding="utf-8")
    for fmt in (".markdown", ".csv", ".srt", ".vtt", ".text", ".json"):
        assert f"exportSession(s, {fmt})" in view
