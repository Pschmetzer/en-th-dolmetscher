import XCTest
@testable import Dolmetscher

/// Oberflächen- und App-Store-Texte: vollständig in allen Sprachen, Platzhalter gleich, Längen eingehalten.
final class L10nTests: XCTestCase {
    private let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func placeholders(_ s: String) -> [String] {
        let rx = try! NSRegularExpression(pattern: #"%(?:\d\$)?[@df]|%\.\d+f"#)
        return rx.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { String(s[Range($0.range, in: s)!]) }.sorted()
    }

    func testEveryKeyInEveryLanguage() {
        XCTAssertEqual(L10n.languages.count, 10)
        for lang in L10n.languages {
            for (key, row) in L10n.table {
                guard let text = L10n.text(key, lang: lang) else { XCTFail("\(lang): \(key) fehlt"); continue }
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang): \(key) leer")
                XCTAssertEqual(placeholders(text), placeholders(row["en"]!), "\(lang): \(key) Platzhalter")
            }
            if let extra = L10n.extra[lang] {
                XCTAssertEqual(Set(extra.keys), Set(L10n.table.keys), "\(lang): überzählige/fehlende Schlüssel")
            }
        }
    }

    /// Jedes `T("…")` im Code muss es in der Tabelle geben – sonst sieht man den rohen Schlüssel.
    func testEveryUsedKeyExists() throws {
        let dir = ios.appendingPathComponent("Dolmetscher")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && !$0.lastPathComponent.hasPrefix("L10n") }
        XCTAssertGreaterThan(files.count, 10)
        let direct = try NSRegularExpression(pattern: #"\bT\("([^"\\]+)"\)"#)
        let ternary = try NSRegularExpression(pattern: #"\bT\([^()"]*\?\s*"([^"]+)"\s*:\s*"([^"]+)"\s*\)"#)
        var used = Set<String>()
        for f in files {
            let s = try String(contentsOf: f, encoding: .utf8)
            let r = NSRange(s.startIndex..., in: s)
            for m in direct.matches(in: s, range: r) { used.insert(String(s[Range(m.range(at: 1), in: s)!])) }
            for m in ternary.matches(in: s, range: r) {
                used.insert(String(s[Range(m.range(at: 1), in: s)!])); used.insert(String(s[Range(m.range(at: 2), in: s)!]))
            }
        }
        XCTAssertGreaterThan(used.count, 100)
        for k in used.sorted() { XCTAssertNotNil(L10n.table[k], "T(\"\(k)\") fehlt in L10n.table") }
    }

    func testSystemLanguageMatch() {
        XCTAssertEqual(L10n.match(["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(L10n.match(["zh-Hant-TW", "ja-JP"]), "ja")
        XCTAssertEqual(L10n.match(["de-AT"]), "de")
        XCTAssertEqual(L10n.match(["pt-BR", "fr-FR"]), "fr")
        XCTAssertEqual(L10n.match(["sv"]), "en")
        XCTAssertEqual(L10n.match(["id-ID"]), "id")
    }

    func testInfoPlistStringsInEveryLanguage() throws {
        let keys: Set = ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
                         "NSCameraUsageDescription", "NSPhotoLibraryUsageDescription",
                         "NSFaceIDUsageDescription"]
        for lang in L10n.languages where lang != "en" {   // Englisch steht in den Build-Einstellungen
            let url = ios.appendingPathComponent("Dolmetscher/\(lang).lproj/InfoPlist.strings")
            let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], lang)
            XCTAssertEqual(Set(dict.keys), keys, lang)
        }
    }

    func testAppStoreTexts() throws {
        let locales = ["en-US", "de-DE", "th", "es-ES", "fr-FR", "ja", "ko", "zh-Hans", "vi", "id"]
        let limits = ["name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000]
        for loc in locales {
            for (file, max) in limits {
                let url = ios.appendingPathComponent("AppStore/\(loc)/\(file).txt")
                let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertFalse(text.isEmpty, "\(loc)/\(file)")
                XCTAssertLessThanOrEqual(text.count, max, "\(loc)/\(file): \(text.count) Zeichen")
            }
            let name = try String(contentsOf: ios.appendingPathComponent("AppStore/\(loc)/name.txt"), encoding: .utf8)
            XCTAssertTrue(name.hasPrefix("Dolmetscher"), loc)
        }
    }
}
