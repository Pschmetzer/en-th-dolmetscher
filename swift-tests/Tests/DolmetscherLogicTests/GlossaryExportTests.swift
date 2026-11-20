import XCTest
@testable import DolmetscherLogic

final class GlossaryLogicTests: XCTestCase {
    func testEntriesSkipCommentsBlankAndBOM() {
        let text = "\u{FEFF}# Kommentar\nHund => dog\n\nKatze\n  # noch einer\nA => B => C"
        let e = GlossaryLogic.entries(text)
        XCTAssertEqual(e.map(\.term), ["Hund", "Katze", "A"])
        XCTAssertEqual(e[0].translation, "dog")
        XCTAssertEqual(e[1].translation, "")
        XCTAssertEqual(e[2].translation, "B => C")
    }

    func testLineCleansFormatBreakers() {
        XCTAssertEqual(GlossaryLogic.line(term: "a=>b\n c", translation: "x"), "a b c => x")
        XCTAssertEqual(GlossaryLogic.line(term: "  ", translation: "x"), "")
        XCTAssertEqual(GlossaryLogic.line(term: "Name", translation: ""), "Name")
    }

    func testIssuesDetectDuplicateConflictAndTooLong() {
        let long = String(repeating: "x", count: GlossaryLogic.termMax + 1)
        let kinds = GlossaryLogic.issues("a => b\nA => B\na => c\n\(long) => y").map(\.kind)
        XCTAssertEqual(kinds, [.duplicate, .conflict, .tooLong])
    }

    func testEntryLimitMarksOverflow() {
        let text = (0...GlossaryLogic.entryLimit).map { "w\($0) => v" }.joined(separator: "\n")
        XCTAssertEqual(GlossaryLogic.issues(text).last?.kind, .overLimit)
    }

    func testMergeCountsDuplicatesAndConflicts() {
        let imported = [
            GlossaryEntry(term: "Hund", translation: "dog", line: -1),     // Duplikat
            GlossaryEntry(term: "hund", translation: "hound", line: -1),   // Widerspruch
            GlossaryEntry(term: "Katze", translation: "cat", line: -1),    // neu
        ]
        let r = GlossaryLogic.merge(imported, into: "Hund => dog")
        XCTAssertEqual(r.added, 1); XCTAssertEqual(r.duplicates, 1); XCTAssertEqual(r.conflicts, 1)
        XCTAssertTrue(r.text.contains("Katze => cat"))
    }

    func testRemoveKeepsOtherLines() {
        XCTAssertEqual(GlossaryLogic.removing(line: 1, from: "a\nb\nc"), "a\nc")
        XCTAssertEqual(GlossaryLogic.removing(line: 9, from: "a"), "a")
    }

    func testCSVRoundTrip() {
        let list = [GlossaryEntry(term: "Hund", translation: "dog, \"good\"", line: 0)]
        let csv = GlossaryLogic.exportCSV(list)
        let back = GlossaryLogic.importCSV(Data(csv.utf8))
        XCTAssertNil(back.fatal)
        XCTAssertEqual(back.entries.first?.translation, "dog, \"good\"")
    }
}

final class ExportFormatsTests: XCTestCase {
    func testCsvCellNeutralizesFormulas() {
        XCTAssertEqual(ExportFormats.csvCell("=1+1"), "\"'=1+1\"")
        XCTAssertEqual(ExportFormats.csvCell("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(ExportFormats.csvCell("ok"), "\"ok\"")
    }

    func testMarkdownEscape() {
        XCTAssertEqual(ExportFormats.mdEscape("a*b_c"), "a\\*b\\_c")
        XCTAssertEqual(ExportFormats.mdEscape("x\ny"), "x  \ny")
    }

    func testTimestamps() {
        XCTAssertEqual(ExportFormats.timestamp(3661.5, comma: true), "01:01:01,500")
        XCTAssertEqual(ExportFormats.timestamp(1.25, comma: false), "00:00:01.250")
        XCTAssertEqual(ExportFormats.timestamp(-5, comma: true), "00:00:00,000")
    }

    func testCsvFileHasBOM() {
        XCTAssertEqual(Array(ExportFormats.fileData("a", csv: true).prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(ExportFormats.fileData("a", csv: false), Data("a".utf8))
    }
}
