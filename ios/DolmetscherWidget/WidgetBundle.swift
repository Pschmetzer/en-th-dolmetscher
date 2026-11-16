// WidgetBundle.swift – Erweiterung für Home-Bildschirm, Kontrollzentrum und Live-Aktivität.
import SwiftUI
import WidgetKit

@main
struct DolmetscherWidgets: WidgetBundle {
    var body: some Widget {
        QuickPhrasesWidget()
    }
}

struct QuickPhrasesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickPhrases", provider: Placeholder()) { _ in Text("Dolmetscher") }
    }
}

struct Placeholder: TimelineProvider {
    struct E: TimelineEntry { var date = Date() }
    func placeholder(in context: Context) -> E { E() }
    func getSnapshot(in context: Context, completion: @escaping (E) -> Void) { completion(E()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<E>) -> Void) { completion(Timeline(entries: [E()], policy: .never)) }
}
