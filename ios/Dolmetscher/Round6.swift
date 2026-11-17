// Round6.swift – Runde 6: kleine, testbare Helfer und Ansichten (Zusammenfassung, Kulturhinweis, Sichtschutz,
// Export, Foto verkleinern, Sprachprüfung beim Tippen, Lautstärke-Hinweis).
import FoundationModels
import ImageIO
import NaturalLanguage
import SwiftUI
import UniformTypeIdentifiers

/// 593: Ab hier ist die Ausgabe auf der Straße kaum zu hören.
enum VolumeHint {
    static func tooQuiet(_ volume: Float) -> Bool { volume < 0.15 }
}

/// 592: Getippter Text in einer dritten Sprache (z. B. Deutsch bei Englisch ⇄ Thai) würde Unsinn ergeben.
enum TypedLanguageCheck {
    /// Sprachcode, wenn der Text sicher in einer Sprache außerhalb des Paars geschrieben ist, sonst nil.
    /// Kurze Texte (ein, zwei Wörter) werden nie beanstandet – dort rät die Erkennung zu oft.
    static func foreign(_ text: String, pair: LangPair) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.split(separator: " ").count >= 3, t.count >= 12 else { return nil }
        let r = NLLanguageRecognizer()
        r.processString(t)
        guard let (lang, p) = r.languageHypotheses(withMaximum: 1).first, p >= 0.85 else { return nil }
        let code = base(lang.rawValue)
        return pair.langs.contains { base($0.rawValue) == code } ? nil : code
    }

    /// "zh-Hans" -> "zh", "pt-BR" -> "pt"
    static func base(_ code: String) -> String { String(code.split(separator: "-").first ?? Substring(code)) }
}

/// 582: Fotos vor der Texterkennung verkleinern (12–48 MP kosten Speicher, Zeit und Wärme).
enum PhotoDownsample {
    static let maxPixels = 2000

    static func image(from data: Data, maxPixels: Int = maxPixels) -> UIImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        let thumb = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                     kCGImageSourceCreateThumbnailWithTransform: true,
                     kCGImageSourceShouldCacheImmediately: true,
                     kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumb) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 581/647: Verlauf zum Teilen – erst beim Teilen gebaut, Datum in der Sprache der App.
struct TranscriptExport: Transferable {
    let entries: [Entry]
    let lang: String

    static func text(_ entries: [Entry], lang: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang)
        f.dateStyle = .short; f.timeStyle = .short
        return entries.map {
            "[\(f.string(from: $0.date))] \($0.src.rawValue.uppercased())→\($0.target.rawValue.uppercased()): \($0.text)\n→ \($0.translation ?? "–")"
        }.joined(separator: "\n\n")
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (e: TranscriptExport) in TranscriptExport.text(e.entries, lang: e.lang) }
    }
}

/// Kulturhinweis passend zur Situation (846/894): Stichwörter im Gespräch -> Szenario-Paket mit Hinweis.
/// Die Hinweise selbst stammen aus presets/*.json (`note`) – hier stehen nur die Stichwörter.
enum CultureHint {
    static let keywords: [String: [String]] = [
        "temple": ["temple", "monk", "buddha", "shrine", "tempel", "mönch", "วัด", "พระ"],
        "doctor": ["doctor", "hospital", "clinic", "fever", "arzt", "krankenhaus", "fieber", "หมอ", "โรงพยาบาล", "คลินิก"],
        "pharmacy": ["pharmacy", "pharmacist", "apotheke", "ร้านขายยา", "เภสัช"],
        "taxi": ["taxi", "meter", "taxameter", "แท็กซี่", "มิเตอร์"],
        "restaurant": ["restaurant", "menu", "spicy", "speisekarte", "scharf", "ร้านอาหาร", "เมนู", "เผ็ด"],
        "shopping": ["discount", "bargain", "cheaper", "rabatt", "billiger", "ลดราคา", "ลดได้", "ถูกกว่า"],
        "spa": ["massage", "spa", "นวด"],
        "police": ["police", "stolen", "polizei", "gestohlen", "ตำรวจ", "ขโมย"],
        "bank": ["atm", "geldautomat", "exchange rate", "wechselkurs", "ตู้เอทีเอ็ม", "แลกเงิน"],
        "scooter": ["scooter", "motorbike", "roller", "มอเตอร์ไซค์", "เช่ารถ"],
        "transport": ["ferry", "train", "fähre", "zug", "เรือ", "รถไฟ"],
        "office": ["meeting", "business card", "visitenkarte", "ประชุม", "นามบัตร"],
        "rental": ["deposit", "lease", "kaution", "mietvertrag", "เงินมัดจำ", "สัญญาเช่า"],
        "lostchild": ["lost my child", "kind verloren", "ลูกหาย", "เด็กหลง"],
    ]

    /// Erstes passende Paket mit Hinweis, das noch nicht gezeigt wurde.
    static func pack(for text: String, packs: [ScenarioPack], skip: Set<String> = []) -> ScenarioPack? {
        let t = text.lowercased()
        guard !t.isEmpty else { return nil }
        let words = Set(t.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return packs.first { p in
            guard !skip.contains(p.id), p.noteText("en") != nil, let keys = keywords[p.id] else { return false }
            return keys.contains { k in
                // Latein: ganzes Wort (sonst „meter“ in „thermometer“); Thai hat keine Wortgrenzen.
                k.unicodeScalars.allSatisfy(\.isASCII) && !k.contains(" ") ? words.contains(k) : t.contains(k)
            }
        }
    }
}

/// Banner über dem Gespräch: Kulturhinweis mit Sprung ins passende Satzbuch-Paket.
struct CultureHintBanner: View {
    let pack: ScenarioPack
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pack.icon).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(T("pack_note") + " · " + pack.name(L10n.lang)).font(.caption.bold())
                Text(pack.noteText(L10n.lang) ?? "").font(.caption).fixedSize(horizontal: false, vertical: true)
                Button(T("culture_open"), action: open).font(.caption.bold())
            }
            Spacer(minLength: 0)
            Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .accessibilityLabel(T("close"))
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

/// 567: Sichtschutz für den App-Umschalter.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: Gesprächszusammenfassung (Apple Intelligence, auf dem Gerät)

enum ConversationSummary {
    /// Was zusammengefasst wird: sichtbare Sätze in meiner Sprache – was ich sagte und was das Gegenüber
    /// (übersetzt) sagte. Gesperrter Verlauf ist schon in `visibleEntries` herausgefiltert.
    static func lines(_ entries: [Entry], mine: Lang, limit: Int = 80) -> [String] {
        entries.suffix(limit).compactMap { e in
            if e.src == mine { return "A: " + e.text }
            if e.target == mine, let t = e.translation, !t.isEmpty { return "B: " + t }
            return nil
        }
    }

    static func instructions(language: String) -> String {
        "You summarize a conversation between person A (the user) and person B (a local). "
            + "Write the summary in \(language). Use 3 to 6 short bullet points: agreed prices, times, places, names, "
            + "open questions and next steps. Only use facts from the conversation. Do not invent anything."
    }

    static func prompt(_ lines: [String]) -> String {
        "Conversation:\n" + lines.joined(separator: "\n")
    }

    /// Kann dieses Gerät zusammenfassen (Apple Intelligence an, Modell bereit, Sprache unterstützt)?
    static func available(for lang: Lang) -> Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale(Locale(identifier: lang.rawValue))
    }

    /// Kurzer Grund, warum es nicht geht (für die Einstellungen).
    static func unavailableReason(for lang: Lang) -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return SystemLanguageModel.default.supportsLocale(Locale(identifier: lang.rawValue)) ? nil : T("summary_no_lang")
        case .unavailable(.appleIntelligenceNotEnabled): return T("summary_ai_off")
        case .unavailable(.modelNotReady): return T("summary_not_ready")
        default: return T("summary_device")
        }
    }

    static func summarize(_ lines: [String], language: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions(language: language))
        return try await session.respond(to: prompt(lines)).content
    }
}

struct SummaryView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var failed: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let text {
                        Text(text).textSelection(.enabled)
                    } else if let failed {
                        Label(failed, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else {
                        ProgressView(T("summary_busy"))
                    }
                    Text(T("summary_note")).font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(T("summary"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("done")) { dismiss() } }
                if let text {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .task { await run() }
        }
    }

    private func run() async {
        let lines = ConversationSummary.lines(m.visibleEntries, mine: m.pair.mine)
        guard lines.count >= 2 else { failed = T("summary_short"); return }
        let language = Locale(identifier: "en").localizedString(forLanguageCode: m.pair.mine.rawValue) ?? "English"
        do {
            text = try await ConversationSummary.summarize(lines, language: language)
        } catch {
            failed = T("summary_failed")
        }
    }
}
