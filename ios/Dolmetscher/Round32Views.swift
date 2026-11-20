// Round32Views.swift – Oberfläche der Runde 32: Taxi-Karte, Preishilfe, Notfall-Ablauf, Wort-Lexikon zum Antippen,
// Bildschirmschutz und kleine Barrierefreiheits-Bausteine (große Schrift, Transparenz reduzieren, Farbe nicht allein).
import SwiftUI
import UIKit

// MARK: Barrierefreiheit

/// HStack, die ab Bedienungshilfen-Schriftgrößen (AX1…AX5) senkrecht stapelt, damit nichts abgeschnitten wird.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var size
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing, content: content)
        }
    }
}

/// Fläche: Material, bei „Transparenz reduzieren“ deckend.
struct SolidWhenReduced: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduce
    var shape = Rectangle()
    func body(content: Content) -> some View {
        if reduce { content.background(Color(.secondarySystemBackground), in: shape) }
        else { content.background(.regularMaterial, in: shape) }
    }
}

/// „Unterscheiden ohne Farbe“: zusätzlicher Rahmen und Symbol, damit der Zustand nicht nur an der Farbe hängt.
struct DifferentiateMark: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    let color: Color
    func body(content: Content) -> some View {
        if differentiate {
            content.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
        } else { content }
    }
}

extension View {
    func solidWhenReduced() -> some View { modifier(SolidWhenReduced()) }
    func differentiateMark(_ color: Color) -> some View { modifier(DifferentiateMark(color: color)) }
    /// Verdeckt sensible Inhalte während Bildschirmaufnahme oder Spiegelung.
    func screenShield(sensitive: Bool = true) -> some View { modifier(ScreenShield(sensitive: sensitive)) }
}

// MARK: Bildschirmschutz

@Observable
@MainActor
final class CaptureWatcher {
    static let shared = CaptureWatcher()
    private(set) var captured: Bool
    @ObservationIgnored private var token: NSObjectProtocol?

    private static func screen() -> UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    private init() {
        captured = Self.screen()?.isCaptured ?? false
        token = NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.captured = Self.screen()?.isCaptured ?? false }
        }
    }
}

struct ScreenShield: ViewModifier {
    @AppStorage("screenShield") private var enabled = true
    let sensitive: Bool

    func body(content: Content) -> some View {
        let covered = ScreenShieldPolicy.covers(captured: CaptureWatcher.shared.captured, sensitive: sensitive, enabled: enabled)
        content
            .overlay {
                if covered {
                    ZStack {
                        Color(.systemBackground)
                        Label(T("r32_shield"), systemImage: "eye.slash.fill").font(.headline).multilineTextAlignment(.center).padding()
                    }
                    .ignoresSafeArea()
                    .accessibilityElement(children: .combine)
                }
            }
    }
}

// MARK: Wort-Lexikon zum Antippen

/// Fließender Umbruch für Wort-Knöpfe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in r.origins.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var origins: [CGPoint] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), origins)
    }
}

/// Thai-Satz in einzelnen Wörtern; Antippen zeigt Umschrift und Bedeutung (aus dem eingebauten Grundwortschatz).
struct WordTapText: View {
    let text: String
    var font: Font = .title2.weight(.semibold)
    @State private var selected: WordLexicon.Token?

    var body: some View {
        let tokens = WordLexicon.tokens(text)
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(tokens) { t in
                    Button { selected = (selected == t ? nil : t) } label: {
                        Text(t.text).font(font)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .frame(minHeight: 44)
                            .background(t.entry == nil ? Color.clear : Color.accentColor.opacity(selected == t ? 0.3 : 0.12), in: RoundedRectangle(cornerRadius: 8))
                            .differentiateMark(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(t.entry == nil)
                    .accessibilityLabel(t.entry.map { "\(t.text), \($0.roman), \($0.meaning)" } ?? t.text)
                    .accessibilityHint(t.entry == nil ? "" : T("r32_words_hint"))
                }
            }
            if let e = selected?.entry {
                Text("\(e.roman) · \(e.meaning)").font(.callout).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            } else if tokens.contains(where: { $0.entry != nil }) {
                Text(T("r32_words_hint")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Taxi-Karte

struct TaxiCardView: View {
    @ScaledMetric(relativeTo: .headline) private var iconWidth: CGFloat = 28
    @Environment(InterpreterModel.self) private var m
    @State private var shown: TaxiCard.Item?

    var body: some View {
        List {
            Section { } footer: { Text(T("r32_taxi_hint")) }
            if !m.emergency.hotel.isEmpty {
                Section(T("em_hotel")) {
                    Text(m.emergency.hotel).font(.title3.weight(.semibold)).textSelection(.enabled)
                }
            }
            Section {
                ForEach(TaxiCard.items) { item in
                    Button { shown = item } label: {
                        AdaptiveStack {
                            Image(systemName: item.icon).frame(width: iconWidth).foregroundStyle(.tint).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.en).font(.headline)
                                Text(TaxiCard.thai(item, female: m.politeness == .female)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(item.en)
                    .accessibilityInputLabels([item.en, item.id])
                    .accessibilityHint(T("r32_taxi_hint"))
                }
            }
        }
        .navigationTitle(T("r32_taxi"))
        .fullScreenCover(item: $shown) { TaxiBigView(item: $0) }
    }
}

/// Satz bildschirmfüllend in sehr großer Thai-Schrift (Fahrer liest ihn über die Schulter, Handy bleibt in der Hand).
struct TaxiBigView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var scaledBig: CGFloat = 64
    let item: TaxiCard.Item
    @State private var flipped = false

    private var thai: String { m.politeness.fill(item.th) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Text(thai).font(.system(size: scaledBig, weight: .heavy)).minimumScaleFactor(0.4).multilineTextAlignment(.center)
                        .spokenIn(Lang.th.voiceLocale, thai)
                    Text(item.roman).font(.title3).foregroundStyle(.secondary)
                    Text(item.en).font(.title2).foregroundStyle(.secondary)
                    if !m.emergency.hotel.isEmpty && (item.id == "price" || item.id == "stop") {
                        Text(m.emergency.hotel).font(.title.weight(.semibold)).padding(.top, 8)
                    }
                    WordTapText(text: thai).padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .rotationEffect(.degrees(flipped ? 180 : 0))
            }
            Divider()
            HStack(spacing: 28) {
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down").minTapTarget() }.accessibilityLabel(T("flip"))
                Button { m.announce(thai, lang: .th) } label: { Image(systemName: "speaker.wave.2.fill").minTapTarget() }.accessibilityLabel(T("replay"))
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .font(.title2).padding()
        }
        .modifier(FullBrightness())
    }
}

// MARK: Preis- und Verhandlungshilfe

struct PriceHelperView: View {
    @Environment(InterpreterModel.self) private var m
    @AppStorage("fxRate") private var rate = 0.026
    @AppStorage("fxCode") private var code = "EUR"
    @State private var asked = ""
    @State private var showOffer: Int?

    private var amount: Int { Int(asked.filter(\.isNumber)) ?? 0 }

    var body: some View {
        List {
            Section {
                TextField(T("r32_price_asked"), text: $asked)
                    .keyboardType(.numberPad)
                    .font(.title2.monospacedDigit())
                    .accessibilityInputLabels([T("r32_price_asked"), "Price"])
            }
            if amount > 0 {
                Section(T("r32_price_counter")) {
                    ForEach(PriceHelper.counters(asked: amount)) { o in
                        Button { showOffer = o.amount } label: {
                            AdaptiveStack {
                                Text("฿ \(o.amount)").font(.title2.monospacedDigit().bold())
                                Spacer(minLength: 0)
                                Text(PriceSpotter.line(PriceSpotter.amounts(in: "\(o.amount) บาท"), rate: rate, code: code, locale: Locale(identifier: L10n.lang)) ?? "")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("\(T("r32_price_counter")) \(o.amount) baht")
                    }
                }
            }
            Section {
                ForEach(PriceHelper.phrases, id: \.id) { p in
                    let thai = m.politeness.fill(p.th)
                    Button { m.announce(thai, lang: .th) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.en).font(.headline)
                            Text(thai).font(.title3)
                            Text(p.roman).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(p.en), \(thai)")
                    .accessibilityHint(T("replay"))
                }
            }
        }
        .navigationTitle(T("r32_price_help"))
        .fullScreenCover(item: Binding(get: { showOffer.map(IdentInt.init) }, set: { showOffer = $0?.value })) {
            PriceShowView(amount: $0.value, home: nil)
        }
    }

    private struct IdentInt: Identifiable { let value: Int; var id: Int { value } }
}

// MARK: Notfall-Ablauf

struct EmergencyFlowView: View {
    @ScaledMetric(relativeTo: .headline) private var iconWidth: CGFloat = 28
    @Environment(InterpreterModel.self) private var m
    let region: String?

    var body: some View {
        let nums = EmergencyNumbers.forRegion(region)
        List {
            Section {
                step(1, "r32_emflow_1", icon: "figure.walk")
                step(2, "r32_emflow_2", icon: "phone.fill")
                dialRow("Police", nums.police, icon: "shield.fill")
                dialRow("Ambulance", nums.ambulance, icon: "cross.case.fill")
                dialRow("Fire", nums.fire, icon: "flame.fill")
                step(3, "r32_emflow_3", icon: "speaker.wave.3.fill")
                Button { m.sheet = .helpNow } label: { Label(T("help_now"), systemImage: "sos").font(.headline).foregroundStyle(StatusColor.error) }
                step(4, "r32_emflow_4", icon: "location.fill")
                Button { m.sheet = .emergency } label: { Label(T("em_card"), systemImage: "cross.case") }
            } footer: { Text(String(format: T("r32_numbers_for"), Locale(identifier: L10n.lang).localizedString(forRegionCode: nums.region) ?? nums.region)) }
        }
        .navigationTitle(T("r32_emflow"))
    }

    private func step(_ n: Int, _ key: String, icon: String) -> some View {
        AdaptiveStack {
            Image(systemName: icon).frame(width: iconWidth).foregroundStyle(.tint).accessibilityHidden(true)
            Text("\(n). \(T(key))").font(.headline)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func dialRow(_ label: String, _ number: String, icon: String) -> some View {
        DialRow(number: number, en: label, th: "", icon: icon)
    }
}
