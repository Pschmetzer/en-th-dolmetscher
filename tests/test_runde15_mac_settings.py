"""Runde 15, Mac-App: Einstellungen sichern/einspielen (SettingsLogic.swift per swiftc getestet, Verdrahtung per Quelltext)."""
# ruff: noqa: E501  (Swift-Testprogramm als Zeichenkette)
import pathlib
import re
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
let langs: Set<String> = ["en", "th", "de"]
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func file(_ settings: String, profile: String = "{}", version: String = "1", format: String = "dolmetscher-settings") -> Data {
    "{\"format\": \"\(format)\", \"version\": \(version), \"settings\": \(settings), \"profile\": \(profile)}".data(using: .utf8)!
}

// Export: alle Felder, Version, kein Schlüssel, Profil
let exp = SettingsLogic.export(values: ["rate": .number(10), "speak": .bool(false)],
                               profile: SettingsProfile(quickPhrases: "Hallo\nDanke", glossary: "Anna => Anna"), exportedAt: t0)
let text = String(data: exp, encoding: .utf8)!
check(text.contains("\"version\" : 1") && text.contains("dolmetscher-settings"), "Version und Format")
let back = SettingsLogic.parse(exp, languages: langs)
check(back.issues.isEmpty && back.fatal == nil, "eigene Datei ohne Befund: \(back.issues)")
check(back.settings.count == SettingsLogic.specs.count, "alle Felder zurück: \(back.settings.count)")
check(back.settings["rate"] == .number(10) && back.settings["speak"] == .bool(false), "Werte")
check(back.settings["llmModel"] == .text("claude-haiku-5-5"), "Vorgabe wird mitgeschrieben")
check(back.profile.quickPhrases == "Hallo\nDanke" && back.profile.glossary == "Anna => Anna", "Profil")
for banned in ["apiKey", "api_key", "ANTHROPIC", "history", "logText", "mic", "outputDevice", "voiceEN"] {
    check(!text.contains(banned), "nicht in der Datei: \(banned)")
}
check(Set(SettingsLogic.specs.map { $0.key }).count == SettingsLogic.specs.count, "Schlüssel eindeutig")

// Datei-Ebene
check(SettingsLogic.parse(Data("kaputt".utf8), languages: langs).fatal?.kind == .notJSON, "kein JSON")
check(SettingsLogic.parse(Data("[1]".utf8), languages: langs).fatal?.kind == .notJSON, "kein Objekt")
check(SettingsLogic.parse(file("{}", format: "x"), languages: langs).fatal?.kind == .wrongFormat, "falsches Format")
check(SettingsLogic.parse(file("{}", version: "\"1\""), languages: langs).fatal?.kind == .badVersion, "Version als Text")
check(SettingsLogic.parse(file("{}", version: "0"), languages: langs).fatal?.kind == .badVersion, "Version 0")
check(SettingsLogic.parse(file("{}", version: "1.5"), languages: langs).fatal?.kind == .badVersion, "Version 1.5")
check(SettingsLogic.parse(file("{}", version: "2"), languages: langs).fatal?.kind == .newerVersion(2), "neuere Version")
check(SettingsLogic.parse(Data(count: SettingsLogic.maxFileBytes + 1), languages: langs).fatal?.kind == .notJSON, "zu groß")
check(SettingsLogic.parse(file("{}"), languages: langs).issues.isEmpty, "leere Einstellungen sind gültig")

// Feldprüfung
func one(_ k: String, _ v: String) -> SettingsImport { SettingsLogic.parse(file("{\"\(k)\": \(v)}"), languages: langs) }
check(one("rate", "20").settings["rate"] == .number(20), "Int ok")
check(one("rate", "20.5").settings.isEmpty, "Int mit Nachkomma abgelehnt")
check(one("rate", "51").settings.isEmpty && one("rate", "-51").settings.isEmpty, "Int außerhalb")
check(one("rate", "true").settings.isEmpty, "Bool ist keine Zahl")
check(one("rate", "\"5\"").settings.isEmpty, "Text ist keine Zahl")
check(one("rate", "1e30").settings.isEmpty, "riesige Zahl")
check(one("speak", "1").settings.isEmpty && one("speak", "\"true\"").settings.isEmpty, "Zahl/Text ist kein Bool")
check(one("speak", "true").settings["speak"] == .bool(true), "Bool ok")
check(one("volume", "2.0").settings["volume"] == .number(2) && one("volume", "2.1").settings.isEmpty, "Double-Bereich")
check(one("fontScale", "0.5").settings.isEmpty && one("fontScale", "2.5").settings["fontScale"] == .number(2.5), "Schriftzoom")
check(one("sensitivity", "\"high\"").settings["sensitivity"] == .text("high") && one("sensitivity", "\"x\"").settings.isEmpty, "Auswahl")
check(one("lang", "\"auto\"").settings["lang"] == .text("auto") && one("lang", "\"fr\"").settings.isEmpty, "Erkennungssprache")
check(one("mineLang", "\"auto\"").settings.isEmpty && one("mineLang", "\"de\"").settings["mineLang"] == .text("de"), "Paarsprache ohne auto")
check(one("llmModel", "\"claude-opus-5\"").settings["llmModel"] == .text("claude-opus-5"), "Modellname")
check(one("llmModel", "\"a b; rm\"").settings.isEmpty && one("llmModel", "\"\"").settings.isEmpty, "Modellname streng")
check(one("preset", "\"\"").settings["preset"] == .text("") && one("preset", "\"Arzt!\"").settings.isEmpty, "Preset-Kennung")
check(one("llmBudget", "-1").settings.isEmpty && one("llmBudget", "5.5").settings["llmBudget"] == .number(5.5), "Budget")
let bad = one("rate", "999")
check(bad.issues == [SettingsIssue(key: "rate", kind: .invalidValue)] && bad.fatal == nil, "ungültig ist nicht fatal")

// unbekannt / sensibel
let odd = SettingsLogic.parse(file("{\"zzz\": 1, \"apiKey\": \"sk-geheim\", \"history\": true, \"speak\": false}",
                                   profile: "{\"token\": \"x\", \"neu\": 1}"), languages: langs)
check(odd.settings.count == 1 && odd.settings["speak"] == .bool(false), "Rest wird übernommen")
check(odd.issues.contains(SettingsIssue(key: "zzz", kind: .unknownKey)), "unbekannt gemeldet")
check(odd.issues.contains(SettingsIssue(key: "apiKey", kind: .sensitiveKey)), "Schlüssel gemeldet, nicht übernommen")
check(odd.issues.contains(SettingsIssue(key: "history", kind: .sensitiveKey)), "Verlauf nie einspielbar")
check(odd.issues.contains(SettingsIssue(key: "profile.token", kind: .sensitiveKey)) && odd.issues.contains(SettingsIssue(key: "profile.neu", kind: .unknownKey)), "Profil-Zusätze")
check(!String(describing: odd.settings).contains("sk-geheim"), "Geheimnis nirgends im Ergebnis")

// gleiche Sprachen
let same = SettingsLogic.parse(file("{\"mineLang\": \"de\", \"partnerLang\": \"de\"}"), languages: langs)
check(same.settings["mineLang"] == .text("de") && same.settings["partnerLang"] == nil
      && same.issues == [SettingsIssue(key: "partnerLang", kind: .sameLanguages)], "gleiche Paarsprachen")

// Profil
let big = String(repeating: "a", count: SettingsLogic.maxGlossaryLength + 1)
let pr = SettingsLogic.parse(file("{}", profile: "{\"glossary\": \"\(big)\", \"quickPhrases\": 5}"), languages: langs)
check(pr.profile.glossary == nil && pr.profile.quickPhrases == nil && pr.issues.count == 2, "Profil zu lang / falscher Typ")
check(SettingsLogic.lineCount("a\n\n  \nb\r\nc") == 3 && SettingsLogic.lineCount("") == 0, "Zeilen zählen")

// Vorschau (Diff)
let cur: [String: SettingValue] = ["rate": .number(10), "speak": .bool(true)]
let imp = SettingsLogic.parse(file("{\"rate\": 10, \"speak\": false, \"volume\": 1.0, \"beam\": 3}",
                                   profile: "{\"quickPhrases\": \"A\", \"glossary\": \"G\"}"), languages: langs)
let ch = SettingsLogic.diff(current: cur, currentProfile: SettingsProfile(quickPhrases: "A", glossary: "alt"), imported: imp)
check(ch.map { $0.key } == ["beam", "speak", "profile.glossary"] || ch.map { $0.key }.sorted() == ["beam", "profile.glossary", "speak"], "nur Änderungen: \(ch.map { $0.key })")
check(ch.first { $0.key == "speak" }?.old == .bool(true) && ch.first { $0.key == "speak" }?.new == .bool(false), "alt und neu")
check(ch.first { $0.key == "beam" }?.old == .number(0), "fehlender Ist-Wert = Vorgabe")
check(ch.first { $0.key == "profile.glossary" }?.old == .text("alt"), "Profil-Änderung")
check(SettingsLogic.diff(current: [:], currentProfile: SettingsProfile(), imported: SettingsLogic.parse(file("{}"), languages: langs)).isEmpty, "leer: keine Änderung")
let order = SettingsLogic.diff(current: [:], currentProfile: SettingsProfile(), imported: SettingsLogic.parse(file("{\"fontScale\": 2, \"mineLang\": \"de\"}"), languages: langs)).map { $0.key }
check(order == ["mineLang", "fontScale"], "Reihenfolge wie im Fenster: \(order)")

// Zuletzt geändert
let a: [String: SettingValue] = ["rate": .number(0), "speak": .bool(true)]
let b: [String: SettingValue] = ["rate": .number(5), "speak": .bool(true), "beam": .number(1)]
check(SettingsLogic.noteChanges(old: nil, new: b, log: [:], now: t0).isEmpty, "erster Stand stempelt nichts")
let l1 = SettingsLogic.noteChanges(old: a, new: b, log: [:], now: t0)
check(l1["rate"] == t0 && l1["beam"] == t0 && l1["speak"] == nil, "geänderte gestempelt: \(l1)")
let l2 = SettingsLogic.noteChanges(old: b, new: b, log: l1, now: t0.addingTimeInterval(60))
check(l2 == l1, "ohne Änderung bleibt es")
let l3 = SettingsLogic.noteChanges(old: b, new: ["rate": .number(5), "speak": .bool(false), "beam": .number(1)], log: l1, now: t0.addingTimeInterval(60))
check(l3["speak"] == t0.addingTimeInterval(60) && l3["rate"] == t0, "nur das Geänderte neu")
let rec = SettingsLogic.recent(["rate": t0, "speak": t0.addingTimeInterval(9), "gone": t0.addingTimeInterval(99), "profile.glossary": t0.addingTimeInterval(5)], limit: 2)
check(rec.map { $0.key } == ["speak", "profile.glossary"], "neueste zuerst, Unbekanntes weg: \(rec.map { $0.key })")

// SettingValue Codable (Stand zwischen Sitzungen)
let enc = try! JSONEncoder().encode(["a": SettingValue.bool(true), "b": .number(1), "c": .text("x")])
let dec = try! JSONDecoder().decode([String: SettingValue].self, from: enc)
check(dec["a"] == .bool(true) && dec["b"] == .number(1) && dec["c"] == .text("x"), "Codable")

print(failures == 0 ? "OK" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.macos
@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_settings_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "settings_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(ROOT / "app" / "SettingsLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-3000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and r.stdout.strip().endswith("OK"), r.stdout


def _l10n_keys():
    src = (ROOT / "app" / "L10n.swift").read_text(encoding="utf-8")
    return set(re.findall(r'^\s*"([A-Za-z0-9_]+)": \[', src, re.M))


def _specs():
    src = (ROOT / "app" / "SettingsLogic.swift").read_text(encoding="utf-8")
    return re.findall(r'\bs\("(\w+)", .*?, \.(?:general|voice|translation|display), "(\w+)", "(\w+)"\)', src, re.S)


def test_settings_logic_ohne_ui_abhaengigkeiten():
    src = (ROOT / "app" / "SettingsLogic.swift").read_text(encoding="utf-8")
    assert [ln for ln in src.splitlines() if ln.startswith("import ")] == ["import Foundation"]


def test_jede_einstellung_hat_beschriftung_und_erklaertext():
    specs = _specs()
    assert len(specs) >= 40
    keys = _l10n_keys()
    for key, label, helptext in specs:
        assert label in keys, f"{key}: Beschriftung {label}"
        assert helptext in keys, f"{key}: Erklärtext {helptext}"


def test_erklaertexte_sind_im_fenster_verdrahtet():
    ui = "".join((ROOT / "app" / f).read_text(encoding="utf-8") for f in ("SettingsView.swift", "SettingsAudioSections.swift", "SettingsQuickPhrases.swift", "Views.swift", "Profiles.swift"))
    for _key, _label, helptext in _specs():
        assert f'"{helptext}"' in ui, helptext


def test_keine_geheimnisse_oder_inhalte_im_schema():
    keys = {k for k, _, _ in _specs()}
    for banned in ("history", "logText", "mic", "micName", "outputDevice", "voiceEN", "voiceTH", "apiKey"):
        assert banned not in keys
    src = (ROOT / "app" / "SettingsTransfer.swift").read_text(encoding="utf-8")
    assert "APIKeyStore" not in src and "Keychain" not in src


def test_settings_verdrahtung_und_texte():
    view = (ROOT / "app" / "SettingsView.swift").read_text(encoding="utf-8")
    app = (ROOT / "app" / "DolmetscherApp.swift").read_text(encoding="utf-8")
    transfer = (ROOT / "app" / "SettingsTransfer.swift").read_text(encoding="utf-8")
    l10n = _l10n_keys()
    assert "SettingsTransferSection()" in view and "SettingsTracker.shared.start()" in app
    assert "SettingsLogic.diff" in transfer and "NSOpenPanel" in transfer and "NSSavePanel" in transfer
    assert transfer.index("SettingsLogic.diff") < transfer.index("m.applyImported(imp)")  # erst Vorschau, dann Übernahme
    used = set(re.findall(r'L\.[tf]\("(sx_\w+)"', transfer))
    assert len(used) >= 15 and used <= l10n
    assert "sx_err_json" in l10n and "sx_recent" in l10n


def test_changelog_runde15_einstellungen():
    assert "### Mac app (round 15)" in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
