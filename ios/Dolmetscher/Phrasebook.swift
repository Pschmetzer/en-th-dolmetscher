// Phrasebook.swift – Satzbuch: feste Reise-Sätze (sofort und offline, Thai fest hinterlegt) und eigene Favoriten.
import SwiftUI

struct Phrase: Identifiable, Codable, Hashable, Sendable {
    var id: String { en }
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

    var srcLang: Lang { src ?? .en }
    var dstLang: Lang { dst ?? .th }
    /// Überschrift in der Oberflächensprache (Deutsch, sonst Englisch).
    var gloss: String { L10n.lang == "de" ? (de ?? en) : en }
}

enum Phrasebook {
    static var categories: [(key: String, icon: String)] { PhraseData.categories }

    /// Aus Shared/phrases.json (auch im Widget gebündelt).
    static let builtIn: [Phrase] = PhraseData.all.map {
        Phrase(en: $0.en, th: $0.th, roman: $0.roman, category: $0.category, de: $0.de)
    }

    /// Klein, ohne Satzzeichen und Füllwörter („please“, „bitte“) – für den Vergleich getippter Sätze.
    static func normalize(_ s: String) -> String {
        let fillers: Set<String> = ["please", "bitte", "a", "the", "ein", "eine"]
        let words = s.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(words).split(separator: " ").map(String.init).filter { !fillers.contains($0) }.joined(separator: " ")
    }

    /// „Satzbuch zuerst“: passt ein englischer (oder deutscher) Satz fast genau auf einen Satz im Satzbuch?
    /// Dann die geprüfte Thai-Fassung statt maschineller Übersetzung.
    static func match(_ text: String, lang: Lang, in list: [Phrase] = builtIn) -> Phrase? {
        guard lang == .en || lang == .de else { return nil }
        let n = normalize(text)
        guard n.count >= 2 else { return nil }
        var best: (Phrase, Double)?
        for p in list {
            let key = lang == .de ? (p.de ?? "") : p.en
            let k = normalize(key)
            guard !k.isEmpty else { continue }
            if k == n { return p }
            // nur bei längeren Sätzen unscharf (Tippfehler), kurze müssen genau passen
            guard n.count >= 10 else { continue }
            let sim = BackCheck.similarity(k, n)
            if sim >= 0.9, sim > (best?.1 ?? 0) { best = (p, sim) }
        }
        return best?.0
    }

    /// Vorschläge beim Tippen (ab 3 Zeichen): Sätze, die den Text enthalten.
    static func suggestions(_ text: String, in list: [Phrase] = builtIn, limit: Int = 3) -> [Phrase] {
        let n = normalize(text)
        guard n.count >= 3 else { return [] }
        let hits = list.filter { normalize($0.en).contains(n) || normalize($0.de ?? "").contains(n) }
        return Array(hits.prefix(limit))
    }
}

struct PhrasebookView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var category = "favorites"
    @State private var search = ""

    /// Eingebaute Sätze sind Englisch -> Thai: nur mit Thai im Paar.
    private var builtIn: [Phrase] { m.features.thaiExtras ? Phrasebook.builtIn : [] }

    private var shown: [Phrase] {
        let base = category == "favorites" ? m.favorites : builtIn.filter { $0.category == category }
        guard !search.isEmpty else { return base }
        var seen = Set<String>()
        let all = (m.favorites + builtIn).filter { seen.insert($0.en).inserted }
        return all.filter {
            $0.en.localizedCaseInsensitiveContains(search) || $0.th.contains(search) || ($0.de ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("favorites", icon: "star.fill")
                        if m.features.thaiExtras {
                            ForEach(Phrasebook.categories, id: \.key) { chip($0.key, icon: $0.icon) }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                List {
                    if shown.isEmpty {
                        Text(category == "favorites" ? T("fav_empty") : T("nothing_found"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown) { p in
                        Button {
                            m.say(p)
                            Haptics.tap()
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.gloss).font(.headline)
                                Text(p.dstLang == .th ? m.politeness.fill(p.th) : p.th).font(.title3)
                                    .foregroundStyle(LangStyle.color(p.dstLang, m.pair))
                                if !p.roman.isEmpty {
                                    Text(p.dstLang == .th ? m.politeness.fillRoman(p.roman) : p.roman)
                                        .font(.caption).foregroundStyle(.secondary).italic()
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if m.isFavorite(p) {
                                Button(role: .destructive) { m.toggleFavorite(p) } label: { Label(T("unfavorite"), systemImage: "star.slash") }
                            } else {
                                Button { m.toggleFavorite(p) } label: { Label(T("favorite"), systemImage: "star") }.tint(.yellow)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $search, prompt: T("search"))
            .navigationTitle(T("phrasebook"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .onAppear { if m.favorites.isEmpty && m.features.thaiExtras { category = "basics" } }
        }
    }

    private func chip(_ key: String, icon: String) -> some View {
        Button { category = key } label: {
            Label(T("cat_" + key), systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(category == key ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(category == key ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
