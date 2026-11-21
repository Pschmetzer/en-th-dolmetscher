// BubbleTrimLogic.swift – welche Sprechblasen fallen bei Überschreiten der Obergrenze weg (aus Engine.trimItems
// herausgelöst, Runde 27, ohne Verhaltensänderung). Die ältesten fertigen Einträge gehen zuerst; Platzhalter und die
// gerade vorgelesene Blase bleiben (die Liste kann dann kurz über der Grenze liegen). Ein Durchlauf: O(n).
import Foundation

enum BubbleTrimLogic {
    /// Indizes (aufsteigend), die entfernt werden. `keep(i)` = Eintrag i bleibt (Platzhalter/aktive Wiedergabe).
    static func indicesToDrop(count: Int, max: Int, keep: (Int) -> Bool) -> [Int] {
        let excess = count - max
        guard excess > 0 else { return [] }
        var out: [Int] = []
        out.reserveCapacity(excess)
        var i = 0
        while i < count, out.count < excess {
            if !keep(i) { out.append(i) }
            i += 1
        }
        return out
    }
}
