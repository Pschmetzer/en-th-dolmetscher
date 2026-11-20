// WindowLogic.swift – Fenster-Wiederherstellung (liegt der gespeicherte Rahmen noch auf einem Bildschirm?) und Einstellungen
// des Live-Untertitel-Overlays (Position, Schrift, klick-durchlässig). Nur Foundation/CoreGraphics; getestet in swift-tests.
import Foundation
import CoreGraphics

struct WindowFrame: Equatable, Codable {
    var x: Double, y: Double, w: Double, h: Double
    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    init(_ r: CGRect) { x = r.origin.x; y = r.origin.y; w = r.size.width; h = r.size.height }
    init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

enum WindowRestore {
    static let minSize = CGSize(width: 240, height: 100)

    /// Gespeicherten Rahmen (JSON) lesen; nil bei Müll.
    static func decode(_ json: String) -> WindowFrame? {
        guard let d = json.data(using: .utf8), let f = try? JSONDecoder().decode(WindowFrame.self, from: d),
              [f.x, f.y, f.w, f.h].allSatisfy({ $0.isFinite }) else { return nil }
        return f
    }

    static func encode(_ f: WindowFrame) -> String {
        (try? String(data: JSONEncoder().encode(f), encoding: .utf8)) ?? ""
    }

    /// Rahmen so anpassen, dass das Fenster sichtbar ist: Größe auf Bildschirm begrenzt, Mindestgröße, und der Rahmen liegt
    /// ganz auf dem Bildschirm mit der größten Überdeckung (bei keiner Überdeckung: auf dem ersten Bildschirm zentriert).
    /// `screens` = sichtbare Bereiche aller Bildschirme.
    static func fit(_ frame: WindowFrame, screens: [CGRect]) -> WindowFrame? {
        guard let first = screens.first else { return nil }
        var r = frame.rect
        r.size.width = max(minSize.width, r.size.width); r.size.height = max(minSize.height, r.size.height)
        let target = screens.max { overlap(r, $0) < overlap(r, $1) }.flatMap { overlap(r, $0) > 0 ? $0 : nil } ?? first
        r.size.width = min(r.size.width, target.width); r.size.height = min(r.size.height, target.height)
        if overlap(r, target) == 0 {
            r.origin = CGPoint(x: target.midX - r.width / 2, y: target.midY - r.height / 2)
        }
        r.origin.x = min(max(r.origin.x, target.minX), target.maxX - r.width)
        r.origin.y = min(max(r.origin.y, target.minY), target.maxY - r.height)
        return WindowFrame(r)
    }

    static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        return i.isNull ? 0 : Double(i.width * i.height)
    }
}

/// Einstellungen des Untertitel-Overlays; alle Werte werden auf sinnvolle Grenzen geklemmt.
struct CaptionStyle: Equatable {
    enum Anchor: String, CaseIterable { case bottom, top, free }
    var anchor: Anchor = .bottom
    var fontSize: Double = 28
    var opacity: Double = 0.9
    var clickThrough = false
    var bold = true

    static let fontRange: ClosedRange<Double> = 14...80
    static let opacityRange: ClosedRange<Double> = 0.3...1

    func clamped() -> CaptionStyle {
        var s = self
        s.fontSize = min(max(fontSize, Self.fontRange.lowerBound), Self.fontRange.upperBound)
        s.opacity = min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        return s
    }
}

enum CaptionOverlay {
    /// Rahmen für einen Anker am Rand des Bildschirms (Breite 70 %, Höhe nach Schriftgröße und Zeilenzahl).
    static func frame(anchor: CaptionStyle.Anchor, screen: CGRect, fontSize: Double, lines: Int, current: CGRect?) -> CGRect {
        let h = max(80, fontSize * 1.5 * Double(max(1, min(lines, 4))) + 36)
        let w = screen.width * 0.7
        let x = screen.midX - w / 2
        switch anchor {
        case .top: return CGRect(x: x, y: screen.maxY - h - 24, width: w, height: h)     // AppKit: y wächst nach oben
        case .bottom: return CGRect(x: x, y: screen.minY + 48, width: w, height: h)
        case .free: return current ?? CGRect(x: x, y: screen.minY + 48, width: w, height: h)
        }
    }

    /// Nächster Anker im Zyklus unten → oben → frei.
    static func next(_ a: CaptionStyle.Anchor) -> CaptionStyle.Anchor {
        let all = CaptionStyle.Anchor.allCases
        return all[(all.firstIndex(of: a)! + 1) % all.count]
    }
}
