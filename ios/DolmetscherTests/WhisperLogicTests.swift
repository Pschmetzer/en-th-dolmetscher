import AVFoundation
import XCTest
@testable import Dolmetscher

/// Reine Whisper-Teile – lädt nie ein Modell.
final class WhisperLogicTests: XCTestCase {
    func testChooseOnlyCountsActivePair() {
        // WhisperKit liefert nur die Log-Wahrscheinlichkeit der erkannten Sprache.
        XCTAssertEqual(WhisperLang.choose(probs: ["en": -0.004], langs: [.en, .th]), .en)
        XCTAssertEqual(WhisperLang.choose(probs: ["th": -0.2], langs: [.en, .th]), .th)
        XCTAssertEqual(WhisperLang.choose(probs: ["en": -2.0, "th": -0.5], langs: [.en, .th]), .th)
        // Lao erkannt: zählt nicht, Entscheidung per Probe-Transkription
        XCTAssertNil(WhisperLang.choose(probs: ["lo": -0.1], langs: [.en, .th]))
        XCTAssertEqual(WhisperLang.best(scores: [(.en, -1.2), (.th, -0.4)]), .th)
    }

    func testSingleLanguageIsForced() {
        XCTAssertEqual(WhisperLang.choose(probs: ["en": -0.01], langs: [.th]), .th)
        XCTAssertEqual(WhisperLang.choose(probs: ["th": -0.01], langs: [.en]), .en)
    }

    func testResolveReportedLanguage() {
        XCTAssertEqual(WhisperLang.resolve(reported: "th", chosen: .en, langs: [.en, .th]), .th)
        XCTAssertEqual(WhisperLang.resolve(reported: "lo", chosen: .th, langs: [.en, .th]), .th)
        XCTAssertEqual(WhisperLang.resolve(reported: "th", chosen: .en, langs: [.en]), .en)
    }

    func testJunkPhrases() {
        XCTAssertTrue(Hallucination.isJunk("Thanks for watching!"))
        XCTAssertTrue(Hallucination.isJunk("Thank you very much for watching, everyone."))
        XCTAssertTrue(Hallucination.isJunk("ขอบคุณที่ติดตามรับชม นะครับ"))
        XCTAssertFalse(Hallucination.isJunk("thanks for watching the kids"))
        XCTAssertFalse(Hallucination.isJunk("Where is the toilet?"))
        XCTAssertFalse(Hallucination.isJunk(""))
    }

    func testJunkIfShortOnlyWhenQuietAndShort() {
        XCTAssertNil(Hallucination.clean("Thank you.", duration: 1.0, rms: 0.005, compressionRatios: []))
        XCTAssertEqual(Hallucination.clean("Thank you.", duration: 1.0, rms: 0.05, compressionRatios: []), "Thank you.")
        XCTAssertEqual(Hallucination.clean("Thank you.", duration: 2.0, rms: 0.005, compressionRatios: []), "Thank you.")
    }

    func testLooksHallucinated() {
        XCTAssertEqual(Hallucination.looksHallucinated("hello", duration: 1, compressionRatios: [3.0]), "repeat")
        XCTAssertEqual(Hallucination.looksHallucinated(String(repeating: "x", count: 40), duration: 1, compressionRatios: []), "too fast")
        XCTAssertNil(Hallucination.looksHallucinated("ห้องน้ำอยู่ที่ไหน", duration: 1.5, compressionRatios: [1.2]))
        // gekürzte Schleife bleibt erhalten
        XCTAssertEqual(Hallucination.clean("ha ha ha ha ha ha", duration: 3, rms: 0.1, compressionRatios: [3.0]), "ha ha ha")
    }

    func testStripMarkers() {
        XCTAssertEqual(Hallucination.stripMarkers("[Music] Hello (laughs) there ♪"), "Hello there")
        XCTAssertNil(Hallucination.clean("[BLANK_AUDIO]", duration: 2, rms: 0.1, compressionRatios: []))
        for junk in [">>", "(", "...", " - "] {
            XCTAssertNil(Hallucination.clean(junk, duration: 2, rms: 0.1, compressionRatios: []), junk)
        }
    }

    func testPreRollKeepsLastSamples() {
        var p = PreRoll(seconds: 0.4)
        XCTAssertEqual(p.capacity, 6400)
        p.append([Float](repeating: 1, count: 5000))
        p.append([Float](repeating: 2, count: 5000))
        let out = p.drain()
        XCTAssertEqual(out.count, 6400)
        XCTAssertEqual(out.last, 2)
        XCTAssertEqual(out.first, 1)
        XCTAssertEqual(p.count, 0)
    }

    func testResampleTo16kMono() {
        let r = Resampler16k()
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        var total = 0
        // 2 s in 100-ms-Stücken
        for _ in 0..<20 {
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4800)!
            b.frameLength = 4800
            for c in 0..<2 { for i in 0..<4800 { b.floatChannelData![c][i] = sin(Float(i) * 0.05) * 0.5 } }
            total += r.convert(b).count
        }
        XCTAssertEqual(Double(total), 32_000, accuracy: 400)   // Rest kann im Konverter stecken
    }

    func testCatalogSkipsEnglishOnly() {
        let sup = ["openai_whisper-tiny", "openai_whisper-tiny.en", "openai_whisper-base", "openai_whisper-base.en",
                   "distil-whisper_distil-large-v3", "openai_whisper-small_216MB"]
        XCTAssertEqual(WhisperCatalog.choices(supported: sup), ["openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small_216MB"])
        XCTAssertEqual(WhisperCatalog.defaultModel(recommended: "openai_whisper-base.en", supported: sup), "openai_whisper-base")
        XCTAssertEqual(WhisperCatalog.sizeMB("openai_whisper-small_216MB"), 216)
        XCTAssertEqual(WhisperCatalog.sizeMB("openai_whisper-base"), 146)
        XCTAssertEqual(WhisperCatalog.label("openai_whisper-base"), "base")
    }
}
