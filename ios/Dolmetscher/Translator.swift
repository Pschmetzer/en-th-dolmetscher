// Translator.swift – Übersetzung zwischen den Sprachen des Paars. Zuerst Apples Translation (auf dem Gerät,
// offline), sonst – wenn erlaubt – derselbe Web-Übersetzer wie die Mac-Engine (Google, Rückfall MyMemory).
import Foundation
import Network
import Translation

struct TranslationResult: Sendable {
    var text: String
    var provider: String   // "apple" | "google" | "mymemory"
}

enum TranslateError: LocalizedError, Equatable {
    case offlineMissing, failed, noNetwork, cooldown
    var errorDescription: String? {
        switch self {
        case .offlineMissing: return T("err_offline_missing")
        case .failed: return T("err_translate")
        case .noNetwork: return T("err_no_network")
        case .cooldown: return T("err_online_cooldown")
        }
    }
}

/// Netzzustand (NWPathMonitor). Ohne Netz gar nicht erst auf Google/MyMemory warten.
final class NetStatus: @unchecked Sendable {
    static let shared = NetStatus()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var path: NWPath?

    private init() {
        monitor.pathUpdateHandler = { [weak self] p in
            guard let self else { return }
            self.lock.lock(); self.path = p; self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "dolmetscher.net"))
    }

    /// Noch unbekannt (gerade gestartet) zählt als online – lieber einmal versuchen.
    var online: Bool { lock.lock(); defer { lock.unlock() }; return path.map { $0.status == .satisfied } ?? true }
    /// Mobilfunk/Roaming oder persönlicher Hotspot.
    var expensive: Bool { lock.lock(); defer { lock.unlock() }; return path?.isExpensive ?? false }
}

/// Nach einem Fehlschlag der Online-Übersetzung eine Weile nicht mehr versuchen – sonst wartet ohne
/// brauchbares Netz (Markt, Insel) jeder Satz erneut auf die Zeitüberschreitung.
struct CircuitBreaker: Sendable {
    var cooldown: TimeInterval = 20
    private(set) var openUntil: Date = .distantPast

    func allows(at now: Date) -> Bool { now >= openUntil }
    mutating func failed(at now: Date) { openUntil = now.addingTimeInterval(cooldown) }
    mutating func succeeded() { openUntil = .distantPast }
}

/// Antwort von MyMemory auswerten. Bei Fehlern (zu lang, Tageslimit) steht der Fehlertext in
/// `translatedText` – mit `responseStatus` 403/429 (mal Zahl, mal Text). Nur Status 200 zählt.
enum MyMemory {
    /// MyMemory nimmt höchstens 500 Byte (UTF-8; Thai = 3 Byte je Zeichen).
    static let maxBytes = 500

    static func fits(_ text: String) -> Bool { text.utf8.count <= maxBytes }

    static func parse(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let status: Int? = (root["responseStatus"] as? Int) ?? (root["responseStatus"] as? String).flatMap { Int($0) }
        guard status == 200 else { return nil }
        let t = (root["responseData"] as? [String: Any])?["translatedText"] as? String
        guard let t, !t.isEmpty else { return nil }
        return t
    }
}

actor Translator {
    private var sessions: [String: TranslationSession] = [:]
    private var breaker = CircuitBreaker()
    private let http: URLSession
    private let isOnline: @Sendable () -> Bool
    private let useApple: Bool

    /// Für Tests: eigene URLSession (URLProtocol-Stub), Netzstatus und ohne Apple-Übersetzung.
    init(http: URLSession = .shared, isOnline: @escaping @Sendable () -> Bool = { NetStatus.shared.online }, useApple: Bool = true) {
        self.http = http
        self.isOnline = isOnline
        self.useApple = useApple
    }

    static func language(_ l: Lang) -> Locale.Language { Locale.Language(identifier: l.translationCode) }

    /// Sind die Offline-Sprachpakete für diese Richtung installiert?
    static func offlineInstalled(from: Lang, to: Lang) async -> Bool {
        await LanguageAvailability().status(from: language(from), to: language(to)) == .installed
    }

    func translate(_ text: String, from: Lang, to: Lang, allowOnline: Bool) async throws -> TranslationResult {
        let key = "\(from.rawValue)>\(to.rawValue)"
        if useApple, await Self.offlineInstalled(from: from, to: to) {
            do {
                let s = sessions[key] ?? TranslationSession(installedSource: Self.language(from), target: Self.language(to))
                sessions[key] = s
                let out = try await s.translate(text).targetText
                if !out.isEmpty { return TranslationResult(text: out, provider: "apple") }
            } catch {
                sessions[key] = nil
            }
        }
        guard allowOnline else { throw TranslateError.offlineMissing }
        guard isOnline() else { throw TranslateError.noNetwork }
        guard breaker.allows(at: Date()) else { throw TranslateError.cooldown }
        if let out = try? await google(text, from: from, to: to), !out.isEmpty {
            breaker.succeeded()
            return TranslationResult(text: out, provider: "google")
        }
        if MyMemory.fits(text), let out = try? await myMemory(text, from: from, to: to) {
            breaker.succeeded()
            return TranslationResult(text: out, provider: "mymemory")
        }
        breaker.failed(at: Date())
        throw TranslateError.failed
    }

    /// Formular-Kodierung: „+“ muss als %2B raus, sonst wird es beim Server zum Leerzeichen.
    static func form(_ items: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }

    private func google(_ text: String, from: Lang, to: Lang) async throws -> String {
        var req = URLRequest(url: URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        req.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form(["sl": from.mtCode, "tl": to.mtCode, "q": text])
        let (data, _) = try await http.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let parts = root.first as? [[Any]] else { return "" }
        return parts.compactMap { $0.first as? String }.joined()
    }

    private func myMemory(_ text: String, from: Lang, to: Lang) async throws -> String? {
        var c = URLComponents(string: "https://api.mymemory.translated.net/get")!
        c.queryItems = [URLQueryItem(name: "q", value: text),
                        URLQueryItem(name: "langpair", value: "\(from.mtCode)|\(to.mtCode)")]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 4
        let (data, _) = try await http.data(for: req)
        return MyMemory.parse(data)
    }
}
