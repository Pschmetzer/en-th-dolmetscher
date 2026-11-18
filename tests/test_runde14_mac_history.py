"""Runde 14, Mac-App: Verlauf-Fenster (HistoryLogic.swift per swiftc getestet, Verdrahtung per Quelltext)."""
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
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let t0 = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13 UTC
func row(_ at: Double, _ s: String, _ text: String, _ out: String = "Hallo", lang: String = "th",
         role: String? = nil, prov: String? = nil) -> HistoryRow {
    HistoryRow(time: t0.addingTimeInterval(at), session: s, lang: lang, text: text, translation: out, translit: "",
               confidence: nil, provider: prov, role: role, speaker: nil)
}

let json = """
[{"time": "2023-11-14T22:13:20.500+00:00", "session": "a", "lang": "th", "text": "สวัสดี", "translation": "Hallo",
  "translit": "sawatdee", "confidence": 0.9, "provider": "claude", "role": "me"},
 {"time": "2023-11-14T22:14:00+00:00", "session": "a", "lang": "de", "text": "Wie geht's", "translation": "",
  "translit": null, "confidence": null, "provider": null, "role": "boss"},
 {"time": "kaputt", "session": "x", "lang": "th", "text": "?"},
 {"session": "y"}]
""".data(using: .utf8)!
let parsed = HistoryLogic.parse(json)
check(parsed.count == 2, "ungültige Einträge übersprungen: \(parsed.count)")
check(parsed[0].role == "me" && parsed[1].role == nil, "Rolle nur me/other")
check(parsed[0].translit == "sawatdee" && parsed[1].translit == "" && parsed[1].translation == "", "Felder")
check(abs(parsed[0].time.timeIntervalSince1970 - 1_700_000_000.5) < 0.01, "Zeit mit Bruchteil")
check(HistoryLogic.parse(Data("{}".utf8)).isEmpty && HistoryLogic.parse(Data()).isEmpty, "kein Array: leer")

let rows = [row(0, "b", "zwei"), row(10, "a", "eins"), row(5, "a", "null"), row(86_400 * 2, "c", "drei")]
let ss = HistoryLogic.sessions(rows)
check(ss.map { $0.id } == ["c", "a", "b"], "neueste zuerst: \(ss.map { $0.id })")
check(ss[1].rows.map { $0.text } == ["null", "eins"] && ss[1].start == t0.addingTimeInterval(5), "Zeilen nach Zeit")
let days = HistoryLogic.days(ss, calendar: cal)
check(days.count == 2 && days[0].sessions.count == 1 && days[1].sessions.count == 2, "Tage: \(days.map { $0.sessions.count })")
check(days[0].day > days[1].day, "Tage absteigend")

check(HistoryLogic.hasNumberWarning(row(0, "a", "ราคา 150 บาท", "Preis 105 Euro")), "Zahl weicht ab")
check(!HistoryLogic.hasNumberWarning(row(0, "a", "ราคา 150 บาท", "Preis 150 Euro")), "Zahl gleich")
check(!HistoryLogic.hasNumberWarning(row(0, "a", "สวัสดี", "Hallo")), "keine Zahlen")
check(!HistoryLogic.hasNumberWarning(row(0, "a", "ราคา 150", "")), "ohne Übersetzung")
check(!HistoryLogic.hasNumberWarning(row(0, "a", "๑๕๐ บาท", "150 Baht")), "Thai-Ziffern = ASCII")
check(HistoryLogic.hasNumberWarning(row(0, "a", "ไม่มี", "Nur 5")), "Zahl nur in Übersetzung")
check(HistoryLogic.isWeak(row(0, "a", "x", prov: "mymemory")) && !HistoryLogic.isWeak(row(0, "a", "x", prov: "claude")), "schwach")

let mix = [row(0, "s1", "Hund", "dog", lang: "th", role: "me"), row(1, "s1", "Katze 3", "cat 4", lang: "en", role: "other"),
           row(2, "s2", "Vogel", "bird", lang: "th", prov: "mymemory"), row(3, "s3", "Fisch", "fish", lang: "th")]
let all = HistoryLogic.sessions(mix)
var f = HistoryFilter()
check(!f.isActive, "leerer Filter inaktiv")
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).hits == 4, "ohne Filter alles")
f.query = "KATZE"
var r = HistoryLogic.apply(all, filter: f, meta: HistoryMeta())
check(r.hits == 1 && r.sessions.count == 1 && r.sessions[0].id == "s1", "Suche ohne Groß/Klein, Trefferzahl")
f = HistoryFilter(); f.query = "dog"
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).hits == 1, "Suche in Übersetzung")
f = HistoryFilter(); f.lang = "en"
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).hits == 1, "Sprache")
f = HistoryFilter(); f.role = "me"
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).hits == 1, "Richtung")
f = HistoryFilter(); f.numberWarning = true
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).sessions.map { $0.id } == ["s1"], "Zahlenwarnung")
f = HistoryFilter(); f.weakTranslation = true
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).sessions.map { $0.id } == ["s2"], "schwache Übersetzung")
f = HistoryFilter(); f.lang = "th"; f.weakTranslation = true
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).hits == 1, "Filter kombiniert (UND)")
f = HistoryFilter(); f.query = "zzz"
check(HistoryLogic.apply(all, filter: f, meta: HistoryMeta()).sessions.isEmpty, "keine Treffer")
check(HistoryLogic.languages(all) == ["en", "th"], "Sprachen")

var meta = HistoryMeta()
meta = HistoryLogic.toggledFavorite(meta, id: "s2")
f = HistoryFilter(); f.favoritesOnly = true
check(HistoryLogic.apply(all, filter: f, meta: meta).sessions.map { $0.id } == ["s2"], "nur Favoriten")
meta = HistoryLogic.toggledFavorite(meta, id: "s2")
check(meta.favorites.isEmpty, "Favorit wieder weg")
meta = HistoryLogic.renamed(meta, id: "s1", to: "  Arzt  ")
check(HistoryLogic.name(all.first { $0.id == "s1" }!, meta) == "Arzt", "Name getrimmt")
meta = HistoryLogic.renamed(meta, id: "s1", to: String(repeating: "x", count: 200))
check(meta.names["s1"]!.count == 80, "Name begrenzt")
meta = HistoryLogic.renamed(meta, id: "s1", to: "   ")
check(meta.names["s1"] == nil, "leerer Name entfernt")

meta = HistoryLogic.hiding(HistoryMeta(), id: "s3")
check(HistoryLogic.apply(all, filter: HistoryFilter(), meta: meta).sessions.map { $0.id } == ["s2", "s1"], "entfernt blendet aus")
check(HistoryLogic.apply(all, filter: HistoryFilter(), meta: HistoryLogic.restoring(meta, id: "s3")).hits == 4, "Rückgängig")
let pr = HistoryLogic.pruned(HistoryMeta(names: ["gone": "x", "s1": "y"], favorites: ["gone"], hidden: ["gone", "s2"]), keeping: ["s1", "s2"])
check(pr.names.keys.sorted() == ["s1"] && pr.favorites.isEmpty && pr.hidden == ["s2"], "veraltete Angaben entfernt")
let coded = try! JSONDecoder().decode(HistoryMeta.self, from: JSONEncoder().encode(HistoryMeta(names: ["a": "b"], favorites: ["a"], hidden: [])))
check(coded.names["a"] == "b" && coded.favorites == ["a"], "Meta Codable")

let long = HistorySession(id: "p", start: t0, rows: [row(0, "p", "  "), row(1, "p", String(repeating: "ก", count: 100) + "\nx")])
check(HistoryLogic.preview(long).count == 81 && HistoryLogic.preview(long).hasSuffix("…"), "Vorschau gekürzt, erste nicht-leere Zeile")
check(HistoryLogic.preview(HistorySession(id: "q", start: t0, rows: [])) == "", "Vorschau leer")

let ids = ["a", "b", "c"]
check(HistoryLogic.moved(ids, from: nil, by: 1) == "a" && HistoryLogic.moved(ids, from: nil, by: -1) == "c", "Pfeil ohne Auswahl")
check(HistoryLogic.moved(ids, from: "b", by: 1) == "c" && HistoryLogic.moved(ids, from: "c", by: 1) == "c", "Pfeil begrenzt")
check(HistoryLogic.moved([], from: "a", by: 1) == nil, "leere Liste")
check(HistoryLogic.neighbor(ids, of: "b") == "c" && HistoryLogic.neighbor(ids, of: "c") == "b", "Nachbar nach Entfernen")
check(HistoryLogic.neighbor(["a"], of: "a") == nil && HistoryLogic.neighbor(ids, of: "z") == nil, "kein Nachbar")

print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_history_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "history_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "HistoryLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def test_history_logic_ohne_ui_abhaengigkeiten():
    src = (ROOT / "app" / "HistoryLogic.swift").read_text(encoding="utf-8")
    assert [ln for ln in src.splitlines() if ln.startswith("import ")] == ["import Foundation"]


def test_history_verdrahtung_und_texte():
    view = (ROOT / "app" / "HistoryView.swift").read_text(encoding="utf-8")
    app = (ROOT / "app" / "DolmetscherApp.swift").read_text(encoding="utf-8")
    views = (ROOT / "app" / "Views.swift").read_text(encoding="utf-8")
    l10n = (ROOT / "app" / "L10n.swift").read_text(encoding="utf-8")
    # nur Engine-Befehle aus docs/PROTOKOLL.md, keine erfundenen
    assert '"--history-export", "json"' in view and "--history-delete" not in view
    assert 'id: "history"' in app and "viewingSession" in views
    assert "onDeleteCommand" in view and "onKeyPress(.return)" in view and "confirmationDialog" in view
    assert view.count("accessibilityLabel") >= 8 and "accessibilityAddTraits(.isHeader)" in view
    for k in ("hist_title", "hist_search", "hist_hits", "hist_filter", "hist_f_lang", "hist_f_dir", "hist_f_num",
              "hist_f_weak", "hist_f_fav", "hist_open", "hist_favorite", "hist_rename", "hist_remove",
              "hist_remove_note", "hist_removed", "hist_undo", "hist_viewing", "hist_back_live"):
        assert f'"{k}"' in l10n and f'"{k}"' in view + app + views


def test_engine_dateien_unveraendert_im_commit():
    # Runde 14 fasst weder dolmetscher.py noch history_store.py an (Diff gegen origin/main, wenn vorhanden)
    r = subprocess.run(["git", "diff", "--name-only", "origin/main", "--", "dolmetscher.py", "history_store.py"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode == 0:
        assert r.stdout.strip() == ""


def test_changelog_runde14_verlauf():
    assert "### Mac app (round 14)" in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
