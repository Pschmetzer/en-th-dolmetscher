// Speaker.swift – Sprachausgabe mit den Systemstimmen. `speak` kehrt zurück, wenn der Satz zu Ende ist.
import AVFoundation

@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var cont: CheckedContinuation<Void, Never>?
    private var token = 0
    private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synth.delegate = self
    }

    static func voice(_ lang: Lang) -> AVSpeechSynthesisVoice? {
        let prefix = lang == .en ? "en" : "th"
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        let preferred = lang == .en ? "en-US" : "th-TH"
        return all.max { a, b in
            (a.quality.rawValue, a.language == preferred ? 1 : 0) < (b.quality.rawValue, b.language == preferred ? 1 : 0)
        } ?? AVSpeechSynthesisVoice(language: preferred)
    }

    /// `rate`: 1 = normal (0.5 … 1.5), `volume`: 0 … 1.
    func speak(_ text: String, lang: Lang, rate: Double, volume: Double) async {
        finish()
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(lang)
        let d = AVSpeechUtteranceDefaultSpeechRate
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, d * Float(rate)))
        u.volume = Float(min(1, max(0.05, volume)))
        token += 1
        let mine = token
        // Sicherung, falls das System nie „fertig“ meldet (z. B. Stimme fehlt).
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8 + Double(text.count) * 0.25))
            if let self, self.token == mine { self.synth.stopSpeaking(at: .immediate); self.finish() }
        }
        await withCheckedContinuation { c in
            cont = c
            current = u
            synth.speak(u)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        finish()
    }

    /// Rückruf des Systems: nur der gerade laufende Satz zählt (ein verspätetes „abgebrochen“ des vorigen nicht).
    private func ended(_ u: AVSpeechUtterance) {
        if u === current { finish() }
    }

    private func finish() {
        token += 1
        current = nil
        cont?.resume()
        cont = nil
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.ended(u) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.ended(u) }
    }
}
