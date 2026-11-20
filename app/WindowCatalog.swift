// WindowCatalog.swift – alle Fenster der App mit ihrer Kennung (`openWindow(id:)`), für Menü, Menüleiste und den
// Fenster-Selbsttest. Die Kennungen müssen zu den `Window(… id:)`-Szenen in DolmetscherApp.swift passen
// (geprüft in tests/test_r25_mac.py). Nur Foundation; getestet in swift-tests.
import Foundation

enum WindowCatalog {
    struct Entry: Equatable { var id: String; var inMenuBar: Bool }

    static let all: [Entry] = [
        Entry(id: "main", inMenuBar: true),
        Entry(id: "partner", inMenuBar: true),
        Entry(id: "history", inMenuBar: true),
        Entry(id: "whatsnew", inMenuBar: false),
        Entry(id: "mini", inMenuBar: true),
        Entry(id: "phrasebook", inMenuBar: true),
        Entry(id: "numbers", inMenuBar: true),
        Entry(id: "summary", inMenuBar: true),
        Entry(id: "learn", inMenuBar: true),
        Entry(id: "card", inMenuBar: true),
        Entry(id: "shortcuts", inMenuBar: false),
        Entry(id: "caption", inMenuBar: true),
    ]

    static var ids: [String] { all.map(\.id) }

    /// Doppelte Kennungen würden zwei Szenen auf dieselbe Taste legen.
    static var hasDuplicates: Bool { Set(ids).count != ids.count }
}
