// PartnerLogic.swift – reine Logik der Partner-Ansicht (ohne UI): Schriftgröße nach Satzlänge, Zahlen finden.
import Foundation

enum PartnerLogic {
    static let minFont = 28.0, maxFont = 160.0
    static let zoomRange = 0.5...2.0

    /// Schriftgröße (pt) für `length` Zeichen in einer Fläche; je länger der Satz, desto kleiner.
    /// Ergebnis liegt immer zwischen minFont und maxFont (vor dem Zoom), Zoom wird danach angewendet.
    static func fontSize(length: Int, width: Double, height: Double, zoom: Double = 1.0) -> Double {
        let n = Double(max(length, 1))
        let w = max(width - 96, 100), h = max(height * 0.6, 100)
        let byArea = (w * h / (n * 0.9)).squareRoot()
        let base = min(max(byArea, minFont), min(h, maxFont))
        return base * min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }

    private static func isDigit(_ c: Character) -> Bool {
        // lateinische (0-9), Thai- (๐-๙) und arabisch-indische Ziffern
        c.isNumber && c.wholeNumberValue != nil
    }

    /// Bereiche (Zeichen-Offsets) aller Zahlen im Text: Ziffernfolgen inkl. innerer Trenner . , : / zwischen Ziffern.
    static func numberRanges(in text: String) -> [Range<Int>] {
        let chars = Array(text)
        var out: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            guard isDigit(chars[i]) else { i += 1; continue }
            var j = i + 1
            while j < chars.count {
                if isDigit(chars[j]) { j += 1; continue }
                if ".,:/".contains(chars[j]), j + 1 < chars.count, isDigit(chars[j + 1]) { j += 2; continue }
                break
            }
            out.append(i..<j)
            i = j
        }
        return out
    }

    /// Text in Teile zerlegen: (Teil, ist Zahl). Die Teile ergeben zusammengesetzt wieder den Originaltext.
    static func segments(_ text: String) -> [(text: String, isNumber: Bool)] {
        let chars = Array(text)
        var out: [(text: String, isNumber: Bool)] = []
        var pos = 0
        for r in numberRanges(in: text) {
            if r.lowerBound > pos { out.append((String(chars[pos..<r.lowerBound]), false)) }
            out.append((String(chars[r]), true))
            pos = r.upperBound
        }
        if pos < chars.count { out.append((String(chars[pos...]), false)) }
        return out
    }
}
