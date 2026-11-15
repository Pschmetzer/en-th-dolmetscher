// Translator.swift – Übersetzung EN⇄TH. Zuerst Apples Translation (auf dem Gerät, offline), sonst – wenn erlaubt –
// derselbe Web-Übersetzer wie die Mac-Engine (Google, Rückfall MyMemory).
import Foundation
import Translation

struct TranslationResult: Sendable {
    var text: String
    var provider: String   // "apple" | "google" | "mymemory"
}

enum TranslateError: LocalizedError {
    case offlineMissing, failed
    var errorDescription: String? {
        switch self {
        case .offlineMissing: return T("err_offline_missing")
        case .failed: return T("err_translate")
        }
    }
}

actor Translator {
    private var sessions: [Lang: TranslationSession] = [:]

    static func language(_ l: Lang) -> Locale.Language { Locale.Language(identifier: l.rawValue) }

    /// Sind die Offline-Sprachpakete für diese Richtung installiert?
    static func offlineInstalled(from: Lang) async -> Bool {
        await LanguageAvailability().status(from: language(from), to: language(from.other)) == .installed
    }

    func translate(_ text: String, from: Lang, allowOnline: Bool) async throws -> TranslationResult {
        if await Self.offlineInstalled(from: from) {
            do {
                let s = sessions[from] ?? TranslationSession(installedSource: Self.language(from),
                                                             target: Self.language(from.other))
                sessions[from] = s
                let out = try await s.translate(text).targetText
                if !out.isEmpty { return TranslationResult(text: out, provider: "apple") }
            } catch {
                sessions[from] = nil
            }
        }
        guard allowOnline else { throw TranslateError.offlineMissing }
        if let out = try? await google(text, from: from), !out.isEmpty {
            return TranslationResult(text: out, provider: "google")
        }
        if let out = try? await myMemory(text, from: from), !out.isEmpty {
            return TranslationResult(text: out, provider: "mymemory")
        }
        throw TranslateError.failed
    }

    private func form(_ items: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }

    private func google(_ text: String, from: Lang) async throws -> String {
        var req = URLRequest(url: URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = form(["sl": from.rawValue, "tl": from.other.rawValue, "q": text])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let parts = root.first as? [[Any]] else { return "" }
        return parts.compactMap { $0.first as? String }.joined()
    }

    private func myMemory(_ text: String, from: Lang) async throws -> String {
        var c = URLComponents(string: "https://api.mymemory.translated.net/get")!
        c.queryItems = [URLQueryItem(name: "q", value: text),
                        URLQueryItem(name: "langpair", value: "\(from.rawValue)|\(from.other.rawValue)")]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 6
        let (data, _) = try await URLSession.shared.data(for: req)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (root?["responseData"] as? [String: Any])?["translatedText"] as? String ?? ""
    }
}
