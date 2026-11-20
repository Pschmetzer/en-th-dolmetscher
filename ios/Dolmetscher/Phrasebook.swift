// Phrasebook.swift – Satzbuch: feste Reise-Sätze (sofort und offline, Thai fest hinterlegt) und eigene Favoriten.
import SwiftUI

struct Phrase: Identifiable, Codable, Hashable, Sendable {
    /// Für `ForEach`: ein Satz kann in mehreren Szenario-Paketen oder für mehrere Sprachpaare vorkommen.
    var id: String { (pack ?? "") + "|" + favoriteKey }
    /// Identität eines Favoriten: Sprachpaar und Quelltext (nicht das Paket, aus dem er stammt).
    var favoriteKey: String { "\(srcLang.rawValue)>\(dstLang.rawValue)|\(en)" }
    var en: String
    /// Thai mit Platzhaltern {p} {q} {i} (siehe Politeness.fill)
    var th: String
    /// ungefähre Aussprache, gleiche Platzhalter
    var roman: String
    var category: String
    /// Nur bei Favoriten aus anderen Sprachpaaren gesetzt; sonst en -> th (eingebautes Satzbuch).
    var src: Lang? = nil
    var dst: Lang? = nil
    /// Deutsche Glosse (eingebautes Satzbuch).
    var de: String? = nil
    /// Sicherheitskritischer Satz aus einem Szenario-Paket. Optional, damit alte favorites.json lesbar bleiben.
    var critical: Bool? = nil
    /// Szenario-Paket (presets/<id>.json), aus dem der Satz stammt.
    var pack: String? = nil

    var srcLang: Lang { src ?? .en }
    var dstLang: Lang { dst ?? .th }
    /// Überschrift in der Oberflächensprache (Deutsch, sonst Englisch).
    var gloss: String { L10n.lang == "de" ? (de ?? en) : en }
    var isCritical: Bool { critical == true }
}

enum Phrasebook {
    static var categories: [(key: String, icon: String)] { PhraseData.categories }

    /// Aus Shared/phrases.json (auch im Widget gebündelt).
    static let builtIn: [Phrase] = PhraseData.all.map {
        Phrase(en: $0.en, th: $0.th, roman: $0.roman, category: $0.category, de: $0.de)
    }

    /// Szenario-Pakete aus presets/*.json (Kulturhinweis, kritische Sätze zuerst).
    static let packs: [ScenarioPack] = ScenarioPack.load(Bundle.main)

    /// Eingebaut + Pakete. Eingebaute zuerst: bei gleichem englischen Satz gewinnt die Fassung mit Höflichkeitsform.
    static let all: [Phrase] = builtIn + packs.flatMap(\.asPhrases)

    /// Sätze einer Kategorie (eingebaut oder „pack.<id>“).
    static func phrases(in category: String, from list: [Phrase] = all) -> [Phrase] {
        list.filter { $0.category == category }
    }

    /// Umschrift zum Anzeigen: die geprüfte, sonst automatisch (Paket-Sätze haben keine eigene).
    static func roman(_ p: Phrase, politeness: Politeness) -> String? {
        if !p.roman.isEmpty { return p.dstLang == .th ? politeness.fillRoman(p.roman) : p.roman }
        return Romanizer.latin(p.th, p.dstLang)
    }

    /// Doppelte englische Sätze entfernen, erste Fassung behalten.
    static func unique(_ list: [Phrase]) -> [Phrase] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.en).inserted }
    }

    /// Klein, ohne Satzzeichen und Füllwörter („please“, „bitte“) – für den Vergleich getippter Sätze.
    static func normalize(_ s: String) -> String {
        let fillers: Set<String> = ["please", "bitte", "a", "the", "ein", "eine"]
        let folded: String = s.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        let cleaned: [Character] = folded.map { (c: Character) -> Character in c.isLetter || c.isNumber ? c : " " }
        let words: [String] = String(cleaned).split(separator: " ").map(String.init)
        return words.filter { !fillers.contains($0) }.joined(separator: " ")
    }

    /// „Satzbuch zuerst“: passt ein englischer (oder deutscher) Satz fast genau auf einen Satz im Satzbuch?
    /// Dann die geprüfte Thai-Fassung statt maschineller Übersetzung.
    static func match(_ text: String, lang: Lang, in list: [Phrase] = all) -> Phrase? {
        guard lang == .en || lang == .de else { return nil }
        let n = normalize(text)
        guard n.count >= 2 else { return nil }
        var best: (Phrase, Double)?
        // Wörter, die das Satzbuch kennt: ein Unterschied in einem bekannten Wort („pill“ ≠ „bill“) ist kein Tippfehler,
        // sondern ein anderer Satz – dann nie unscharf ersetzen (der Nutzer sähe seinen Satz, hörte aber einen anderen).
        let vocab = known(list)
        for p in list {
            let key = lang == .de ? (p.de ?? "") : p.en
            let k = normalize(key)
            guard !k.isEmpty else { continue }
            if k == n { return p }
            // nur bei längeren Sätzen unscharf (Tippfehler), kurze müssen genau passen;
            // sicherheitskritische Sätze nur genau, und nie über eine Verneinung hinweg („not allergic“ ≠ „allergic“).
            guard n.count >= 10, !p.isCritical, negated(k) == negated(n) else { continue }
            guard sameNumbers(k, n), typoOnly(n, against: k, vocab: vocab) else { continue }
            let sim = BackCheck.similarity(k, n)
            if sim >= 0.9, sim > (best?.1 ?? 0) { best = (p, sim) }
        }
        return best?.0
    }

    /// Alle Wörter des Satzbuchs (englisch und deutsch, normalisiert).
    static func known(_ list: [Phrase]) -> Set<String> {
        var out = Set<String>()
        for p in list {
            for key in [p.en, p.de ?? ""] { for w in normalize(key).split(separator: " ") { out.insert(String(w)) } }
        }
        return out
    }

    private static func digits(_ s: String) -> [String] {
        s.split { !$0.isNumber }.map(String.init)
    }

    static func sameNumbers(_ a: String, _ b: String) -> Bool { digits(a) == digits(b) }

    /// Weicht der Satz nur in Wörtern ab, die das Satzbuch gar nicht kennt (echter Tippfehler)?
    static func typoOnly(_ typed: String, against key: String, vocab: Set<String>) -> Bool {
        let keyWords = Set(key.split(separator: " ").map(String.init))
        return typed.split(separator: " ").map(String.init).allSatisfy { keyWords.contains($0) || !vocab.contains($0) }
    }

    /// Enthält der (normalisierte) Satz eine Verneinung?
    static func negated(_ normalized: String) -> Bool {
        let words: Set<String> = ["not", "no", "never", "dont", "don", "t", "cant", "isnt", "doesnt", "nicht", "kein", "keine", "keinen", "nie"]
        return normalized.split(separator: " ").contains { words.contains(String($0)) }
    }

    /// Vorschläge beim Tippen (ab 3 Zeichen): Sätze, die den Text enthalten.
    static func suggestions(_ text: String, in list: [Phrase] = all, limit: Int = 3) -> [Phrase] {
        let n = normalize(text)
        guard n.count >= 3 else { return [] }
        let hits = unique(list).filter { normalize($0.en).contains(n) || normalize($0.de ?? "").contains(n) }
        return Array(hits.prefix(limit))
    }
}

struct PhrasebookView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var category = "favorites"
    @State private var search = ""

    /// Eingebaute Sätze und Pakete sind Englisch -> Thai. Ohne Thai im Paar werden die englischen Sätze automatisch in die
    /// Partnersprache übersetzt (Hinweis „nicht geprüft“); das Satzbuch bleibt so für jedes Paar nutzbar.
    private var available: [Phrase] { Phrasebook.all }

    /// Pakete passend zur Uhrzeit – nur mit Thai im Paar (sonst ist das Satzbuch maschinell übersetzt und bleibt schlicht).
    private var suggested: [ScenarioPack] {
        m.features.thaiExtras ? ScenarioSuggest.packs(hour: Calendar.current.component(.hour, from: Date()), available: Phrasebook.packs) : []
    }

    private var pack: ScenarioPack? { Phrasebook.packs.first { $0.key == category } }

    private var shown: [Phrase] {
        guard search.isEmpty else {
            let all: [Phrase] = Phrasebook.unique(m.favorites + available)
            return all.filter(matches)
        }
        if category == "recent" { return recent }
        return category == "favorites" ? m.favorites : Phrasebook.phrases(in: category, from: available)
    }

    /// Zuletzt gesagte Sätze (aus dem Verlauf; gesperrter Verlauf bleibt außen vor).
    private var recent: [Phrase] { Phrasebook.recent(entries: m.visibleEntries, in: available) }

    /// 662: auch die Umschrift („khop khun“) finden; Round 9: ohne Akzente/Groß-Kleinschreibung, mehrere Wörter in beliebiger Reihenfolge.
    private func matches(_ p: Phrase) -> Bool {
        PhraseSearch.matches(query: search, fields: [p.en, p.th, p.de ?? "", Phrasebook.roman(p, politeness: m.politeness) ?? ""])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chips
                if !m.features.thaiExtras {
                    Text(T("pb_machine_hint")).font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal).padding(.bottom, 6).frame(maxWidth: .infinity, alignment: .leading)
                }
                List {
                    if search.isEmpty, let note = pack?.noteText(L10n.lang) {
                        PackNote(text: note)
                    }
                    if shown.isEmpty {
                        Text(category == "favorites" ? T("fav_empty") : category == "recent" ? T("recent_empty") : T("nothing_found"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown) { p in row(p) }
                }
                .listStyle(.plain)
            }
            .searchable(text: $search, prompt: T("search"))
            .navigationTitle(T("phrasebook"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .toolbar {
                if category == "favorites", !m.favorites.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Phrasebook.shareText(m.favorites, politeness: m.politeness)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(T("share_favorites"))
                    }
                }
            }
            .onAppear(perform: pickStart)
        }
    }

    private func pickStart() {
        if m.favorites.isEmpty { category = recent.isEmpty ? "basics" : "recent" }
        if let c = m.phrasebookStart { category = c; m.phrasebookStart = nil }
        if let q = m.phrasebookQuery { search = q; m.phrasebookQuery = nil }
        #if DEBUG
        if let c = ProcessInfo.processInfo.environment["DOLMETSCHER_PB_CATEGORY"] { category = c }
        #endif
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !recent.isEmpty { chip("recent", title: T("cat_recent"), icon: "clock") }
                    chip("favorites", title: T("cat_favorites"), icon: "star.fill")
                    do {
                        // Zur Tageszeit passende Pakete zuerst (Sortierhilfe, alle bleiben erreichbar).
                        ForEach(suggested) { chip($0.key, title: $0.name(L10n.lang), icon: "sparkles").accessibilityHint(T("sc_now")) }
                        ForEach(Phrasebook.categories, id: \.key) { chip($0.key, title: T("cat_" + $0.key), icon: $0.icon) }
                        ForEach(Phrasebook.packs.filter { p in !suggested.contains { $0.id == p.id } }) { chip($0.key, title: $0.name(L10n.lang), icon: $0.icon) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            // Gewählte Kategorie sichtbar halten (16 Pakete passen nicht in eine Zeile).
            .onChange(of: category) { _, c in withAnimation(Motion.animation(reduce: reduceMotion)) { proxy.scrollTo(c, anchor: .center) } }
            .task { proxy.scrollTo(category, anchor: .center) }
        }
    }

    private func row(_ p: Phrase) -> some View {
        // 590: Sheet bleibt offen – mehrere Sätze nacheinander (Bestellung); Langdruck zeigt groß.
        Button {
            m.say(p)
            Haptics.tap()
        } label: {
            PhraseRow(phrase: p, thai: m.isMachinePhrase(p) ? T("pb_machine_row") : (p.dstLang == .th ? m.politeness.fill(p.th) : p.th),
                      roman: Phrasebook.roman(p, politeness: m.politeness), color: LangStyle.color(p.dstLang, m.pair))
        }
        .buttonStyle(.plain)
        .contextMenu {
            let target = m.isMachinePhrase(p) ? p.en : (p.dstLang == .th ? m.politeness.fill(p.th) : p.th)
            Button { m.copy(target) } label: { Label(T("copy"), systemImage: "doc.on.doc") }
            ShareLink(item: Phrasebook.shareText([p], politeness: m.politeness)) {
                Label(T("share_one"), systemImage: "square.and.arrow.up")
            }
            Button { m.say(p); m.showLastBig(); dismiss() } label: {
                Label(T("show_big"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }
        .listRowBackground(p.isCritical ? StatusColor.error.opacity(0.08) : nil)
        .swipeActions {
            if m.isFavorite(p) {
                Button(role: .destructive) { m.toggleFavorite(p) } label: { Label(T("unfavorite"), systemImage: "star.slash") }
            } else {
                Button { m.toggleFavorite(p) } label: { Label(T("favorite"), systemImage: "star") }.tint(.yellow)
            }
        }
    }

    private func chip(_ key: String, title: String, icon: String) -> some View {
        let on = category == key
        return Button { category = key } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
        .id(key)
    }
}

/// Kulturhinweis eines Pakets über den Sätzen.
private struct PackNote: View {
    let text: String
    var body: some View {
        Label { Text(text).font(.footnote) } icon: { Image(systemName: "info.circle.fill").foregroundStyle(StatusColor.info) }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StatusColor.info.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(T("pack_note") + ": " + text)
    }
}

/// Ein Satz: Glosse, Übersetzung, Umschrift; kritische Sätze rot markiert.
private struct PhraseRow: View {
    let phrase: Phrase
    let thai: String
    let roman: String?
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if phrase.isCritical {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(StatusColor.error)
                    .accessibilityLabel(T("critical"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(phrase.gloss).font(.headline)
                Text(thai).font(.title3).foregroundStyle(color).accessibilityLabel(A11yLabel.spoken(thai, phrase.dstLang))
                if let roman, !roman.isEmpty {
                    Text(roman).font(.caption).foregroundStyle(.secondary).italic()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

