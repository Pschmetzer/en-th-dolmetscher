// R24Views.swift – Fenster der Runde 24: Zahlen & Preise (Umrechnung, Großanzeige, Verhandlungshilfe), Zusammenfassung,
// Lernen, Zeig-Karte (mit Satzbuch-Fallback ohne Übersetzer), Kürzel-Fenster und Szenario-Vorschlag.
// Die Regeln stehen in PriceLogic, SummaryLogic, LearnLogic, OfflineFallback, ShortcutCatalog und ScenarioDetect
// (getestet in swift-tests); hier nur Darstellung und Verdrahtung.
import SwiftUI
import AppKit

extension Utterance {
    var exportItem: ExportItem {
        ExportItem(at: date, lang: lang, to: to, text: text, out: out, translated: translated,
                   speaker: speaker ?? role, dur: dur, readyS: readyS)
    }
}

/// Zustand, den mehrere Fenster teilen (Text der Zeig-Karte, z. B. aus einer Zahl oder einem Kurzbefehl).
@MainActor
final class R24Shared: ObservableObject {
    static let shared = R24Shared()
    @Published var cardText = ""
    @Published var cardIsNumber = false
    func showCard(_ text: String, number: Bool = false) { cardText = text; cardIsNumber = number }
}

enum R24Views {
    /// Beschriftung zu einem Schlüssel: L.t, sonst die Tabelle der Runde 24 (L.t gibt unbekannte Schlüssel unverändert zurück).
    static func label(_ key: String) -> String {
        let t = L.t(key)
        return t == key ? R24T.t(key) : t
    }
}

enum R24Prefs {
    static let rate = "r24RateText"
    static let budget = "r24Budget"
    static let ankiFront = "r24AnkiFront"
}

/// Kommas als Dezimaltrenner in der Oberflächensprache Deutsch (und Thai/Englisch mit Punkt).
private var useComma: Bool { L.lang == .de }

// MARK: Zahl groß zeigen

struct BigNumberSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.system(size: 140, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.1).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .textSelection(.enabled)
                .accessibilityLabel(text)
            Button(L.t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(minWidth: 520, idealWidth: 760, minHeight: 280, idealHeight: 380)
    }
}

// MARK: Zahlen & Preise

struct NumbersView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(R24Prefs.rate) private var rateText = "37"
    @AppStorage(R24Prefs.budget) private var budgetText = ""
    @State private var asking = ""
    @State private var mine = ""
    @State private var big: String?

    private var rate: Double? { PriceLogic.parseRate(rateText) }

    private var recent: [PriceMention] {
        var out: [PriceMention] = []
        for u in m.items.suffix(40).reversed() where !u.pending {
            for p in PriceLogic.mentions(in: u.out) + PriceLogic.mentions(in: u.text)
            where !out.contains(where: { $0.amount == p.amount && $0.currency == p.currency }) { out.append(p) }
            if out.count >= 8 { break }
        }
        return out
    }

    var body: some View {
        Form {
            Section {
                TextField(R24T.t("rate_label"), text: $rateText)
                    .accessibilityLabel(R24T.t("rate_label"))
                if rate == nil { Text(R24T.t("rate_invalid")).font(.caption).foregroundStyle(LangStyle.warning) }
            }
            Section(R24T.t("prices_recent")) {
                if recent.isEmpty { Text(R24T.t("prices_none")).foregroundStyle(.secondary) }
                ForEach(Array(recent.enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(PriceLogic.conversionLine(p, rate: rate, comma: useComma)
                             ?? (p.currency.map { PriceLogic.format(p.amount, $0, comma: useComma) } ?? p.raw))
                            .textSelection(.enabled)
                        Spacer()
                        Button(R24T.t("show_big")) {
                            big = p.currency.map { PriceLogic.format(p.amount, $0, comma: useComma) } ?? p.raw
                        }
                    }
                }
            }
            Section(R24T.t("counter_offers")) {
                TextField(R24T.t("asking"), text: $asking).accessibilityLabel(R24T.t("asking"))
                if let a = PriceLogic.parseAmount(asking) {
                    ForEach(PriceLogic.counterOffers(asking: a), id: \.percent) { o in
                        HStack {
                            Text("\(o.percent) %  →  " + PriceLogic.format(o.amount, .thb, comma: useComma))
                            Spacer()
                            Button(R24T.t("show_big")) { big = PriceLogic.format(o.amount, .thb, comma: useComma) }
                        }
                    }
                    TextField(R24T.t("my_bid"), text: $mine).accessibilityLabel(R24T.t("my_bid"))
                    if let b = PriceLogic.parseAmount(mine) {
                        if let n = PriceLogic.nextBid(mine: b, theirs: a, maxBudget: PriceLogic.parseAmount(budgetText)) {
                            HStack {
                                Text(R24T.f("next_bid", PriceLogic.format(n, .thb, comma: useComma))).bold()
                                Spacer()
                                Button(R24T.t("show_big")) { big = PriceLogic.format(n, .thb, comma: useComma) }
                            }
                        } else {
                            Text(R24T.t("no_room")).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 420)
        .sheet(item: Binding(get: { big.map { BigItem(text: $0) } }, set: { big = $0?.text })) { item in
            BigNumberSheet(text: item.text)
        }
        .background(WindowAccessor { R24Window.prepare($0, name: "Numbers") })
    }

    private struct BigItem: Identifiable { let text: String; var id: String { text } }
}

// MARK: Zusammenfassung

struct SummaryView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(R24Prefs.rate) private var rateText = "37"
    @State private var copied = false

    static var labels: [String: String] {
        ["turns": R24T.t("sum_turns"), "minutes": R24T.t("sum_minutes"), "todos": R24T.t("sum_todos"),
         "questions": R24T.t("sum_questions"), "prices": R24T.t("sum_prices"), "numbers": R24T.t("sum_numbers")]
    }

    private var summary: ConversationSummary { SummaryLogic.summarize(m.items.filter { !$0.pending }.map(\.exportItem)) }

    private func section(_ key: String, _ lines: [String]) -> some View {
        Group {
            if !lines.isEmpty {
                Text(R24T.t(key)).font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in Text("• " + l).textSelection(.enabled) }
            }
        }
    }

    var body: some View {
        let s = summary
        let rate = PriceLogic.parseRate(rateText)
        VStack(alignment: .leading, spacing: 8) {
            if s.turns == 0 {
                Text(R24T.t("sum_empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("\(R24T.t("sum_turns")): \(s.turns) · \(R24T.t("sum_minutes")): \(s.minutes)").foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        section("sum_todos", s.todos)
                        section("sum_questions", s.questions)
                        section("sum_prices", s.prices.map { PriceLogic.conversionLine($0, rate: rate, comma: useComma) ?? $0.raw })
                        section("sum_numbers", s.numbers)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(R24T.t("sum_note")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(copied ? R24T.t("copied") : R24T.t("sum_copy")) {
                        copyToPasteboard(SummaryLogic.plain(s, labels: Self.labels)); copied = true
                    }
                    Button(R24T.t("sum_save")) { save(s, rate: rate) }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 360)
        .background(WindowAccessor { R24Window.prepare($0, name: "Summary") })
    }

    private func save(_ s: ConversationSummary, rate: Double?) {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Dolmetscher-Summary.md"
        p.title = R24T.t("sum_save")
        guard p.runModal() == .OK, let url = p.url else { return }
        let md = SummaryLogic.markdown(s, title: R24T.t("summary_title"), labels: Self.labels, rate: rate, comma: useComma)
        do { try Data(md.utf8).write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
    }
}

// MARK: Lernen

struct LearnView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(R24Prefs.ankiFront) private var ankiFront = ""
    @State private var selected: UUID?
    @State private var clozeIndex: Int?
    @State private var revealed = false

    private var sentences: [Utterance] { m.items.filter { !$0.pending && $0.translated && !$0.out.isEmpty }.suffix(30).reversed() }
    private var current: Utterance? { sentences.first { $0.id == selected } ?? sentences.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sentences.isEmpty {
                Text(R24T.t("learn_empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let u = current {
                Picker(R24T.t("learn_pick"), selection: Binding(get: { u.id }, set: { selected = $0; clozeIndex = nil; revealed = false })) {
                    ForEach(sentences) { s in Text(String(s.text.prefix(60))).tag(s.id) }
                }
                Text(R24T.t("learn_words")).font(.headline).accessibilityAddTraits(.isHeader)
                words(u.out, lang: u.to)
                words(u.text, lang: u.lang)
                Text(R24T.t("learn_cloze")).font(.headline).accessibilityAddTraits(.isHeader)
                cloze(u)
            }
            Divider()
            HStack {
                Picker(R24T.t("learn_front"), selection: $ankiFront) {
                    Text("–").tag("")
                    ForEach(Langs.pair, id: \.self) { Text($0.uppercased()).tag($0) }
                }.fixedSize()
                Text(R24T.f("learn_cards_n", cards.count)).foregroundStyle(.secondary)
                Spacer()
                Button(R24T.t("learn_anki")) { saveAnki() }.disabled(cards.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 420)
        .background(WindowAccessor { R24Window.prepare($0, name: "Learn") })
    }

    private var cards: [LearnLogic.Card] { LearnLogic.cards(m.items.filter { !$0.pending }.map(\.exportItem), frontLang: ankiFront) }

    private func words(_ text: String, lang: String) -> some View {
        let toks = LearnLogic.tokens(text)
        return HStack(spacing: 6) {
            Text(lang.uppercased()).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(toks, id: \.index) { t in
                        Text(t.word).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func cloze(_ u: Utterance) -> some View {
        let idx = clozeIndex ?? LearnLogic.defaultClozeIndex(u.out) ?? 0
        let c = LearnLogic.cloze(u.out, hiding: idx)
        return VStack(alignment: .leading, spacing: 6) {
            if let c {
                Text(c.prompt).font(.title3).textSelection(.enabled)
                HStack {
                    Button(R24T.t("learn_reveal")) { revealed = true }
                    Button(R24T.t("learn_next")) {
                        let n = LearnLogic.words(u.out).count
                        clozeIndex = n > 0 ? (idx + 1) % n : 0; revealed = false
                    }
                    if revealed { Text(c.answer).bold() }
                }
            } else {
                Text(u.out)
            }
        }
    }

    private func saveAnki() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Dolmetscher-Anki.csv"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try Data(LearnLogic.ankiCSV(cards).utf8).write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
    }
}

// MARK: Zeig-Karte (auch ohne Übersetzer: Satzbuch-Fallback)

struct ShowCardView: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var shared = R24Shared.shared
    @State private var query = ""
    @State private var zoom = 1.0

    /// Satzbuch aus den Szenario-Paketen (englisch ↔ Thai).
    private var book: [BookPhrase] {
        PresetCatalog.all.flatMap { $0.phrases.map { BookPhrase(en: $0.en, th: $0.th, critical: $0.critical) } }
    }

    private var match: BookMatch? { OfflineFallback.match(query, in: book) }

    private var shown: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return match?.answer ?? "" }
        if !shared.cardText.isEmpty { return shared.cardText }
        return m.lastReplayable.map { $0.out } ?? ""
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField(R24T.t("card_field"), text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel(R24T.t("card_field"))
                .onChange(of: query) { if !query.isEmpty { shared.cardText = "" } }
            if !query.isEmpty {
                if let mt = match {
                    Text(R24T.f("card_match", mt.inputIsThai ? mt.phrase.th : mt.phrase.en)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(R24T.t("card_nomatch")).font(.caption).foregroundStyle(LangStyle.warning)
                    let sug = OfflineFallback.suggestions(query, in: book)
                    if !sug.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(R24T.t("card_suggest")).font(.caption)
                            ForEach(Array(sug.enumerated()), id: \.offset) { _, s in
                                Button(s.inputIsThai ? s.phrase.th : s.phrase.en) { query = s.inputIsThai ? s.phrase.th : s.phrase.en }
                                    .buttonStyle(.link)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if shared.cardText.isEmpty, m.lastReplayable != nil {
                Text(R24T.t("card_last")).font(.caption).foregroundStyle(.secondary)
            }
            Text(shown)
                .font(.system(size: 64 * zoom, weight: .bold))
                .minimumScaleFactor(0.1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .textSelection(.enabled)
                .accessibilityLabel(shown)
            HStack {
                Text(R24T.t("card_hint")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(R24T.t("card_link")) {
                    if let u = HandoffPayload.sayURL(text: shown, lang: nil) { copyToPasteboard(u.absoluteString) }
                }.disabled(shown.isEmpty)
                Button { zoom = max(0.4, zoom - 0.15) } label: { Image(systemName: "textformat.size.smaller") }
                    .help(L.t("font_smaller")).accessibilityLabel(L.t("font_smaller"))
                Button { zoom = min(2, zoom + 0.15) } label: { Image(systemName: "textformat.size.larger") }
                    .help(L.t("font_bigger")).accessibilityLabel(L.t("font_bigger"))
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowAccessor { R24Window.prepare($0, name: "ShowCard") })
    }
}

// MARK: Kürzel-Fenster

struct ShortcutsWindowView: View {
    @State private var query = ""
    var body: some View {
        let list = ShortcutCatalog.filter(ShortcutCatalog.all, query: query, label: { R24Views.label($0) })
        VStack(alignment: .leading, spacing: 8) {
            TextField(R24T.t("search_shortcuts"), text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel(R24T.t("search_shortcuts"))
            List {
                ForEach(ShortcutCatalog.grouped(list), id: \.group) { g in
                    Section(R24T.t("grp_" + g.group)) {
                        ForEach(g.entries, id: \.keys) { e in
                            HStack {
                                Text(R24Views.label(e.labelKey))
                                Spacer()
                                Text(e.keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 380, minHeight: 360)
        .background(WindowAccessor { R24Window.prepare($0, name: "Shortcuts") })
    }
}

// MARK: Szenario-Vorschlag im Hauptfenster

/// Zustand des Szenario-Vorschlags (geteilt zwischen Prüfung in `R24Hooks` und Hinweiszeile).
@MainActor
final class ScenarioHint: ObservableObject {
    static let shared = ScenarioHint()
    @Published var shown: ScenarioSuggestion?
    private var previous: String?
    private var dismissed: Set<String> = []

    private static let candidates: [ScenarioCandidate] = ScenarioDetect.deriveCandidates(
        packs: PresetCatalog.all.map { (id: $0.id, phrases: $0.phrases.map(\.en)) })

    /// Nach jeder neuen oder fertig gewordenen Äußerung: erst wenn zweimal hintereinander dasselbe Paket passt, zeigen.
    func check(_ m: EngineModel) {
        let recent = m.items.suffix(ScenarioDetect.window).filter { !$0.pending }.flatMap { [$0.text, $0.out] }
        var skip = dismissed
        if !m.preset.isEmpty { skip.insert(m.preset) }
        let cur = ScenarioDetect.suggest(recent: recent, candidates: Self.candidates, exclude: skip)
        shown = ScenarioDetect.stable(previous: previous, current: cur)
        previous = cur?.id
    }

    func dismiss() { if let s = shown { dismissed.insert(s.id) }; shown = nil }
}

/// Hinweiszeile „Das klingt nach … Passende Sätze laden?“.
struct ScenarioSuggestBanner: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var hint = ScenarioHint.shared

    var body: some View {
        if let s = hint.shown, let p = PresetCatalog.all.first(where: { $0.id == s.id }), m.preset != s.id {
            NoticeBanner(icon: "sparkles", tint: .accentColor, text: R24T.f("scn_suggest", p.name),
                         action: (R24T.t("scn_use"), { m.preset = s.id; hint.shown = nil }),
                         onClose: { hint.dismiss() })
        }
    }
}

// MARK: Fenster-Hilfen

enum R24Window {
    /// Gemerkte Fenster, deren Rahmen schon geprüft wurde (WindowAccessor ruft mehrfach auf).
    @MainActor private static var fitted = Set<ObjectIdentifier>()

    /// Speichert den Rahmen unter `name` und holt ein Fenster zurück ins Sichtbare, wenn sein Bildschirm fehlt
    /// (Monitor abgesteckt, Auflösung geändert).
    @MainActor static func prepare(_ w: NSWindow, name: String) {
        if w.frameAutosaveName.isEmpty { w.setFrameAutosaveName("Dolmetscher\(name)Window") }
        guard fitted.insert(ObjectIdentifier(w)).inserted else { return }
        fitOnScreen(w)
    }

    @MainActor static func fitOnScreen(_ w: NSWindow) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let fixed = WindowRestore.fit(WindowFrame(w.frame), screens: screens), fixed.rect != w.frame else { return }
        w.setFrame(fixed.rect, display: true)
    }
}

/// Hauptfenster-Verdrahtung der Runde 24 (eigener Modifier, damit der Körper von ContentView überschaubar bleibt):
/// Mitteilung mit Zusammenfassung nach dem Gespräch, Fenster aus Mitteilung und Kurzbefehl öffnen.
struct R24Hooks: ViewModifier {
    @EnvironmentObject var m: EngineModel
    @Environment(\.openWindow) private var openWindow

    /// Ändert sich bei neuer Äußerung und wenn ein Platzhalter fertig wird (Anzahl bleibt dabei gleich).
    private var lastDoneKey: String {
        guard let u = m.items.last(where: { !$0.pending }) else { return "" }
        return "\(u.id)-\(u.text.count)-\(u.out.count)"
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: m.active) { if !m.active { SummaryNotifier.sessionEnded(m) } }
            .onChange(of: lastDoneKey) { ScenarioHint.shared.check(m) }
            .onReceive(NotificationCenter.default.publisher(for: .openSummary)) { _ in openWindow(id: "summary") }
            .onReceive(NotificationCenter.default.publisher(for: .openCard)) { _ in openWindow(id: "card") }
    }
}
