// Learn.swift – Lernmodus: Sätze aus Favoriten und eigenen Gesprächen als Karteikarten mit Leitner-Wiederholung.
// Logik ohne Oberfläche (LeitnerDeck, unit-getestet), Ablage lokal in learn.json.
import SwiftUI

/// Karteikasten nach Leitner: 5 Fächer, „gewusst“ schiebt eine Karte ein Fach weiter (längerer Abstand),
/// „nochmal“ zurück in Fach 1.
struct LeitnerDeck: Codable, Equatable, Sendable {
    struct Card: Codable, Identifiable, Equatable, Sendable {
        var id: String
        /// Vorderseite: in der eigenen Sprache.
        var front: String
        /// Rückseite: in der Partnersprache (zum Vorlesen).
        var back: String
        var lang: Lang
        var roman: String?
        var box: Int = 1
        var due: Date
        /// Aus einem Gespräch (nicht aus Favoriten): lebt nicht länger als der Verlauf. Optional für alte learn.json.
        var talk: Bool? = nil
        var created: Date? = nil
    }

    /// Eine mögliche Karte aus Favoriten oder Verlauf.
    struct Source: Equatable, Sendable {
        var front: String
        var back: String
        var lang: Lang
        var roman: String?
        var talk = false

        var id: String { lang.rawValue + "|" + Phrasebook.normalize(back) }
    }

    static let boxes = 5
    /// Abstand in Tagen nach dem Wechsel in Fach 1…5.
    static let intervals: [Int] = [0, 1, 3, 7, 14]

    var cards: [Card] = []
    /// Vom Nutzer gelöschte Karten: `sync` legt sie nicht wieder an. Optional für alte learn.json.
    var dismissed: [String]? = nil

    /// Neue Quellen als Karten in Fach 1 aufnehmen (fällig sofort); vorhandene behalten ihren Stand.
    @discardableResult
    mutating func sync(_ sources: [Source], now: Date = Date()) -> Int {
        var known = Set(cards.map(\.id)).union(dismissed ?? [])
        var added = 0
        for s in sources where !s.back.isEmpty && !s.front.isEmpty && known.insert(s.id).inserted {
            cards.append(Card(id: s.id, front: s.front, back: s.back, lang: s.lang, roman: s.roman, due: now,
                              talk: s.talk ? true : nil, created: s.talk ? now : nil))
            added += 1
        }
        return added
    }

    /// Fällige Karten, niedrigstes Fach und älteste Fälligkeit zuerst.
    func due(now: Date = Date()) -> [Card] {
        let open: [Card] = cards.filter { (c: Card) -> Bool in c.due <= now }
        return open.sorted(by: Self.order)
    }

    private static func order(_ a: Card, _ b: Card) -> Bool { a.box != b.box ? a.box < b.box : a.due < b.due }

    /// Nächste Fälligkeit, wenn gerade nichts fällig ist.
    func nextDue(after now: Date = Date()) -> Date? { cards.filter { $0.due > now }.map(\.due).min() }

    mutating func answer(_ id: String, knew: Bool, now: Date = Date(), calendar: Calendar = .current) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        let box = knew ? min(Self.boxes, cards[i].box + 1) : 1
        cards[i].box = box
        cards[i].due = Self.dueDate(box: box, from: now, calendar: calendar)
    }

    /// Fach 1: gleich nochmal (ans Ende der Runde); sonst ab Tagesbeginn + Abstand, damit „morgen“ auch morgen früh heißt.
    static func dueDate(box: Int, from now: Date, calendar: Calendar = .current) -> Date {
        let days = intervals[max(0, min(intervals.count - 1, box - 1))]
        guard days > 0 else { return now }   // gleich wieder dran, hinter den schon fälligen
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: days, to: start) ?? now.addingTimeInterval(Double(days) * 86_400)
    }

    mutating func remove(_ id: String) { cards.removeAll { $0.id == id } }

    /// Karte löschen und merken, dass sie nicht automatisch wiederkommen soll.
    mutating func dismiss(_ id: String) {
        remove(id)
        var d = dismissed ?? []
        if !d.contains(id) { d.append(id) }
        dismissed = d
    }

    /// Karten aus Gesprächen entfernen, die vor `cutoff` entstanden sind (Verlaufseinstellung). Gibt die Anzahl zurück.
    @discardableResult
    mutating func pruneTalk(olderThan cutoff: Date) -> Int {
        let before = cards.count
        cards.removeAll { $0.talk == true && ($0.created ?? .distantPast) < cutoff }
        return before - cards.count
    }

    /// Anzahl Karten je Fach (1…5).
    var counts: [Int] { (1...Self.boxes).map { b in cards.filter { $0.box == b }.count } }
}

extension LeitnerDeck.Source {
    /// Satz aus einem Gespräch: Vorderseite eigene Sprache, Rückseite Partnersprache. Andere Paare: nil.
    static func from(_ e: Entry, pair: LangPair) -> Self? {
        guard e.error == nil, e.photo != true, let t = e.translation, !t.isEmpty, e.text.count <= 160 else { return nil }
        if e.src == pair.mine && e.target == pair.partner {
            return .init(front: e.text, back: t, lang: e.target, roman: e.romanized, talk: true)
        }
        if e.src == pair.partner && e.target == pair.mine {
            return .init(front: t, back: e.text, lang: e.src, roman: Romanizer.latin(e.text, e.src), talk: true)
        }
        return nil
    }

    /// Favorit: Glosse vorn, Übersetzung (mit Höflichkeitsform) hinten.
    static func from(_ p: Phrase, politeness: Politeness) -> Self {
        let back = p.dstLang == .th ? politeness.fill(p.th) : p.th
        return .init(front: p.srcLang == .en ? p.gloss : p.en, back: back, lang: p.dstLang,
                     roman: Phrasebook.roman(p, politeness: politeness))
    }
}

struct LearnView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var now = Date()

    private var card: LeitnerDeck.Card? {
        let open: [LeitnerDeck.Card] = m.learn.due(now: now)
        return open.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if m.learnLocked {
                    lockedState
                } else {
                BoxBar(counts: m.learn.counts)
                if let card {
                    CardFace(card: card, revealed: revealed) { m.announceCard(card) }
                    controls(card)
                } else {
                    emptyState
                }
                }
            }
            .padding()
            .navigationTitle(T("learn"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .toolbar {
                if !m.learnLocked, let card {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) { m.removeCard(card.id); revealed = false } label: { Image(systemName: "trash") }
                            .accessibilityLabel(T("learn_delete"))
                    }
                }
            }
            .onAppear { m.syncLearn(); now = Date() }
            .onChange(of: m.learnLocked) { _, locked in if !locked { m.syncLearn() } }
        }
    }

    @ViewBuilder private func controls(_ card: LeitnerDeck.Card) -> some View {
        if revealed {
            HStack(spacing: 12) {
                Button { grade(card, false) } label: { Label(T("learn_again"), systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(.orange)
                Button { grade(card, true) } label: { Label(T("learn_know"), systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
            .controlSize(.large)
        } else {
            Button { revealed = true; m.announceCard(card) } label: { Text(T("learn_show")).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        Text(String(format: T("learn_due"), m.learn.due(now: now).count))
            .font(.footnote).foregroundStyle(.secondary)
    }

    /// Der Lernkasten enthält Sätze aus Gesprächen: derselbe Schutz wie der Verlauf.
    private var lockedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(T("learn_locked")).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(T("lock_unlock")) { m.unlockHistory() }.buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: m.learn.cards.isEmpty ? "rectangle.stack" : "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(m.learn.cards.isEmpty ? Color.secondary : Color.green)
            Text(T(m.learn.cards.isEmpty ? "learn_empty" : "learn_done"))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Text(T("learn_note")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func grade(_ card: LeitnerDeck.Card, _ knew: Bool) {
        m.answerCard(card.id, knew: knew)
        knew ? Haptics.success() : Haptics.tap()
        revealed = false
        now = Date()
    }
}

/// Fächer 1–5 als kleine Leiste.
private struct BoxBar: View {
    let counts: [Int]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(counts.enumerated()), id: \.offset) { i, n in
                VStack(spacing: 2) {
                    Text("\(n)").font(.headline.monospacedDigit())
                    Text(String(format: T("learn_box"), i + 1)).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Die Karte: vorn eigene Sprache, nach dem Aufdecken Partnersprache mit Umschrift und Vorlesen.
private struct CardFace: View {
    let card: LeitnerDeck.Card
    let revealed: Bool
    let speak: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(card.front).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            if revealed {
                Divider()
                Text(card.back).font(.largeTitle.bold()).foregroundStyle(.orange).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                if let r = card.roman, !r.isEmpty {
                    Text(r).font(.title3).italic().foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button(action: speak) { Image(systemName: "speaker.wave.2.fill").font(.title) }
                    .accessibilityLabel(T("replay"))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
}
