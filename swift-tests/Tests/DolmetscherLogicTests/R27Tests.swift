import XCTest
@testable import DolmetscherLogic

final class R27Tests: XCTestCase {
    // MARK: StaleGuard (Schlüsseltest, Selbsttest)
    func testStaleGuardNewRunInvalidatesOld() {
        var g = StaleGuard()
        let a = g.begin()
        XCTAssertTrue(g.isCurrent(a))
        let b = g.begin()
        XCTAssertFalse(g.isCurrent(a))
        XCTAssertTrue(g.isCurrent(b))
    }

    func testStaleGuardCancelInvalidatesRunning() {
        var g = StaleGuard()
        let a = g.begin()
        g.cancel()
        XCTAssertFalse(g.isCurrent(a))
        let b = g.begin()               // nach dem Abbruch ist ein neuer Lauf wieder gültig
        XCTAssertTrue(g.isCurrent(b))
    }

    func testStaleGuardCancelWithoutRunIsHarmless() {
        var g = StaleGuard()
        g.cancel(); g.cancel()
        let t = g.begin()
        XCTAssertTrue(g.isCurrent(t))
    }

    // MARK: Cmd-A
    func testSelectAllShortcutYieldsToTextField() {
        XCTAssertTrue(SelectAllShortcut.shouldSelectBubbles(selecting: true, textEditing: false))
        XCTAssertFalse(SelectAllShortcut.shouldSelectBubbles(selecting: true, textEditing: true))
        XCTAssertFalse(SelectAllShortcut.shouldSelectBubbles(selecting: false, textEditing: false))
    }

    // MARK: Diagramm-Sprechtexte
    func testChartValuesEmptyAndLimit() {
        XCTAssertEqual(ChartA11y.values([]), "–")
        XCTAssertEqual(ChartA11y.values([("a", 3), ("b", 5)]), "a 3, b 5")
        let many = (1...15).map { ("d\($0)", $0) }
        let v = ChartA11y.values(many, limit: 12)
        XCTAssertTrue(v.hasSuffix(", … +3"), v)
        XCTAssertTrue(v.hasPrefix("d1 1, d2 2"))
        XCTAssertEqual(ChartA11y.summary(title: "Pro Tag", pairs: [("05-01", 2)]), "Pro Tag: 05-01 2")
    }

    func testChartHourPairsSkipEmptyHours() {
        var h = [Int](repeating: 0, count: 24)
        h[9] = 4; h[17] = 1
        XCTAssertEqual(ChartA11y.hourPairs(h).map { $0.0 }, ["9 h", "17 h"])
        XCTAssertEqual(ChartA11y.hourPairs(h).map { $0.1 }, [4, 1])
        XCTAssertTrue(ChartA11y.hourPairs([Int](repeating: 0, count: 24)).isEmpty)
    }

    // MARK: Fehler- und Drop-Codes (PROTOKOLL.md <-> App-Tabellen)
    private func protocolDoc() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/PROTOKOLL.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Codes aus der ersten Spalte der Tabelle unter `heading` (backticked, Kleinbuchstaben/Unterstrich).
    private func docCodes(_ doc: String, heading: String) -> Set<String> {
        guard let r = doc.range(of: heading) else { return [] }
        var section = String(doc[r.upperBound...])
        if let n = section.range(of: "\n### ") { section = String(section[..<n.lowerBound]) }
        var out = Set<String>()
        for line in section.split(separator: "\n") where line.hasPrefix("| `") && !line.hasPrefix("| `code`") {
            let first = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
            var rest = Substring(first)
            while let a = rest.firstIndex(of: "`") {
                let after = rest.index(after: a)
                guard let b = rest[after...].firstIndex(of: "`") else { break }
                let code = String(rest[after..<b])
                if !code.isEmpty, code.allSatisfy({ $0.isLowercase || $0 == "_" }) { out.insert(code) }
                rest = rest[rest.index(after: b)...]
            }
        }
        return out
    }

    func testEveryDocumentedErrorCodeHasAppText() throws {
        let codes = docCodes(try protocolDoc(), heading: "### `error.code`")
        XCTAssertGreaterThan(codes.count, 30)
        let missing = codes.subtracting(EngineProtocolTexts.errorKeys.keys)
        XCTAssertTrue(missing.isEmpty, "Fehlercodes ohne App-Text: \(missing.sorted())")
    }

    func testEveryDocumentedDroppedCodeHasAppTextOrRule() throws {
        let codes = docCodes(try protocolDoc(), heading: "### `dropped.code`")
        XCTAssertGreaterThan(codes.count, 5)
        let missing = codes.subtracting(EngineProtocolTexts.droppedKeys.keys).subtracting(EngineProtocolTexts.silentDroppedCodes)
        XCTAssertTrue(missing.isEmpty, "Drop-Codes ohne App-Text: \(missing.sorted())")
    }

    func testProtocolTextTablesAreConsistent() {
        for (code, key) in EngineProtocolTexts.errorKeys {
            XCTAssertFalse(key.isEmpty, code)
            XCTAssertTrue(key.hasPrefix("err_") || key == "crash_env", "\(code) -> \(key)")
        }
        XCTAssertTrue(EngineProtocolTexts.errorDetailCodes.isSubset(of: Set(EngineProtocolTexts.errorKeys.keys)))
        XCTAssertTrue(EngineProtocolTexts.silentDroppedCodes.isDisjoint(with: Set(EngineProtocolTexts.droppedKeys.keys)))
        // jeder Code mit Beratungstext (Hinweisband) hat auch einen Fehlertext
        for code in EngineProtocolTexts.errorKeys.keys {
            if let adv = ErrorAdviceLogic.advice(for: code) { XCTAssertFalse(adv.hintKey.isEmpty, code) }
        }
    }

    // MARK: EngineLineFramer
    private func lines(_ o: EngineLineFramer.Output) -> [String] { o.lines.map { String(decoding: $0, as: UTF8.self) } }

    func testFramerSplitsLinesAcrossChunks() {
        var f = EngineLineFramer()
        XCTAssertEqual(lines(f.feed(Data("{\"event\":\"a\"}\n{\"ev".utf8))), ["{\"event\":\"a\"}"])
        XCTAssertEqual(lines(f.feed(Data("ent\":\"b\"}\n".utf8))), ["{\"event\":\"b\"}"])
        XCTAssertTrue(f.buffer.isEmpty)
    }

    func testFramerToleratesCRLFAndBOM() {
        var f = EngineLineFramer()
        var d = Data([0xEF, 0xBB, 0xBF]); d.append(Data("{\"event\":\"a\"}\r\n".utf8))
        XCTAssertEqual(lines(f.feed(d)), ["{\"event\":\"a\"}"])
    }

    func testFramerKeepsEmptyLinesForCaller() {
        var f = EngineLineFramer()
        XCTAssertEqual(lines(f.feed(Data("\n\nx\n".utf8))), ["", "", "x"])
    }

    func testFramerDropsOverlongLineAndSkipsItsRest() {
        var f = EngineLineFramer()
        let o = f.feed(Data(repeating: 0x61, count: 50), limit: 10)
        XCTAssertEqual(o.overflowBytes, 50)
        XCTAssertTrue(o.lines.isEmpty)
        XCTAssertTrue(f.discarding)
        XCTAssertTrue(f.buffer.isEmpty)
        // weitere Bytes ohne Zeilenende gehören noch zur verworfenen Zeile
        XCTAssertTrue(f.feed(Data("bbbb".utf8), limit: 10).lines.isEmpty)
        XCTAssertTrue(f.discarding)
        // Zeilenende beendet das Verwerfen; der Rest ist wieder ein normales Ereignis
        let o2 = f.feed(Data("zz\n{\"event\":\"ok\"}\n".utf8), limit: 10)
        XCTAssertEqual(lines(o2), ["{\"event\":\"ok\"}"])
        XCTAssertFalse(f.discarding)
    }

    func testFramerResetClearsState() {
        var f = EngineLineFramer()
        _ = f.feed(Data("halb".utf8))
        XCTAssertFalse(f.buffer.isEmpty)
        f.reset()
        XCTAssertTrue(f.buffer.isEmpty)
        XCTAssertFalse(f.discarding)
    }

    // MARK: BubbleTrimLogic
    func testTrimNothingBelowLimit() {
        XCTAssertTrue(BubbleTrimLogic.indicesToDrop(count: 500, max: 500) { _ in false }.isEmpty)
        XCTAssertTrue(BubbleTrimLogic.indicesToDrop(count: 3, max: 500) { _ in false }.isEmpty)
    }

    func testTrimDropsOldestFirst() {
        XCTAssertEqual(BubbleTrimLogic.indicesToDrop(count: 505, max: 500) { _ in false }, [0, 1, 2, 3, 4])
    }

    func testTrimSkipsPendingAndPlaying() {
        let keep: Set<Int> = [0, 2]
        let drop = BubbleTrimLogic.indicesToDrop(count: 8, max: 5) { keep.contains($0) }
        XCTAssertEqual(drop, [1, 3, 4])        // 0 und 2 bleiben, älteste übrige gehen
    }

    func testTrimMayDropFewerWhenEverythingIsProtected() {
        XCTAssertTrue(BubbleTrimLogic.indicesToDrop(count: 10, max: 5) { _ in true }.isEmpty)
        XCTAssertEqual(BubbleTrimLogic.indicesToDrop(count: 10, max: 5) { $0 < 8 }, [8, 9])
    }

    func testTrimStaysBoundedOverLongSession() {
        // 5000 neue Blasen nacheinander: die Liste überschreitet 500 nie (Speicher bleibt begrenzt)
        var items = [Int]()
        for n in 0..<5000 {
            items.append(n)
            let gone = Set(BubbleTrimLogic.indicesToDrop(count: items.count, max: 500) { _ in false })
            var i = -1
            items.removeAll { _ in i += 1; return gone.contains(i) }
            XCTAssertLessThanOrEqual(items.count, 500)
        }
        XCTAssertEqual(items.first, 4500)
        XCTAssertEqual(items.last, 4999)
    }

    func testTrimPerformanceAt500Items() {
        // Messung der Kürzung bei voller Liste (Obergrenze 500): ein Durchlauf, keine quadratische Suche
        let t0 = Date()
        for _ in 0..<2000 { _ = BubbleTrimLogic.indicesToDrop(count: 501, max: 500) { _ in false } }
        let perCall = Date().timeIntervalSince(t0) / 2000
        XCTAssertLessThan(perCall, 0.001, "Kürzung bei 500 Blasen dauert \(perCall * 1000) ms")
        measure { for _ in 0..<500 { _ = BubbleTrimLogic.indicesToDrop(count: 700, max: 500) { $0 % 97 == 0 } } }
    }

    // MARK: LogTailLogic
    func testLogTailStartsAfterLastMarker() {
        let log = "alt1\n=== Dolmetscher-Engine gestartet 10:00 ===\nalt2\n=== Dolmetscher-Engine gestartet 11:00 ===\nneu1\nneu2\n"
        XCTAssertEqual(LogTailLogic.tail(log, marker: "=== Dolmetscher-Engine gestartet", n: 25), "neu1\nneu2")
    }

    func testLogTailFiltersMpsWarningAndLimits() {
        let log = (1...10).map { "z\($0)" }.joined(separator: "\n") + "\nUserWarning: experimental feature\n"
        let t = LogTailLogic.tail(log, marker: "MARK", n: 4)   // 4 = letzte Zeile (leer, nach dem Zeilenende) zählt mit
        XCTAssertEqual(t, "z8\nz9\nz10")
    }

    func testLogTailEmptyIsNil() {
        XCTAssertNil(LogTailLogic.tail("", marker: "M", n: 5))
        XCTAssertNil(LogTailLogic.tail("M kopf\n\n  \n", marker: "M", n: 5))
        XCTAssertNil(LogTailLogic.tail("nur experimental\n", marker: "M", n: 5))
    }

    // MARK: Ausgabegerät je Richtung (Engine kennt die Felder noch nicht: nur additiv, leer = nichts senden)
    func testRouteFieldsOnlyForChosenDevices() {
        XCTAssertTrue(AudioRouteLogic.protocolFields(AudioRoute()).isEmpty)
        XCTAssertEqual(AudioRouteLogic.protocolFields(AudioRoute(mine: "A", partner: "")), ["output_device_me": "A"])
        XCTAssertEqual(AudioRouteLogic.protocolFields(AudioRoute(mine: "", partner: "B")), ["output_device_other": "B"])
    }
}
