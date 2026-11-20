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
    case offlineMissing, failed, noNetwork, cooldown, rateLimited, appleFailed
    var errorDescription: String? {
        switch self {
        case .offlineMissing: return T("err_offline_missing")
        case .failed: return T("err_translate")
        case .noNetwork: return T("err_no_network")
        case .cooldown: return T("err_online_cooldown")
        case .rateLimited: return T("err_online_limit")
        case .appleFailed: return T("err_apple_failed")
        }
    }
}

/// Netzzustand (NWPathMonitor). Ohne Netz gar nicht erst auf Google/MyMemory warten.
final class NetStatus: @unchecked Sendable {
    static let shared = NetStatus()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var path: NWPath?
    private var reconnectHandlers: [@Sendable () -> Void] = []
    private var changeHandlers: [@Sendable (Bool) -> Void] = []

    /// Bei jedem Wechsel zwischen online und offline (auch beim ersten Pfad). Mehrere Abonnenten möglich.
    func onChange(_ handler: @escaping @Sendable (Bool) -> Void) {
        lock.lock(); changeHandlers.append(handler); lock.unlock()
    }

    /// Wird aufgerufen, wenn das Netz nach einem Ausfall wieder da ist (Tunnel, Flugmodus, Funkloch). Mehrere Abonnenten möglich.
    func onReconnect(_ handler: @escaping @Sendable () -> Void) {
        lock.lock(); reconnectHandlers.append(handler); lock.unlock()
    }

    /// Für Tests: Pfadwechsel von Hand melden (gleiche Verteilung wie der echte Monitor).
    func deliver(was: Bool?, now: Bool) {
        lock.lock()
        let change = changeHandlers, reconnect = reconnectHandlers
        lock.unlock()
        if was != now { change.forEach { $0(now) } }
        if ReconnectRetry.cameBack(was: was, now: now) { reconnect.forEach { $0() } }
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] p in
            guard let self else { return }
            self.lock.lock()
            let was = self.path.map { $0.status == .satisfied }
            self.path = p
            self.lock.unlock()
            self.deliver(was: was, now: p.status == .satisfied)
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
    /// Nach „Limit erreicht“ (HTTP 429) deutlich länger pausieren.
    var rateLimitCooldown: TimeInterval = 300
    private(set) var openUntil: Date = .distantPast

    func allows(at now: Date) -> Bool { now >= openUntil }
    mutating func failed(at now: Date, rateLimited: Bool = false) {
        openUntil = now.addingTimeInterval(rateLimited ? rateLimitCooldown : cooldown)
    }
    mutating func succeeded() { openUntil = .distantPast }
}

/// Zeitlimit für eine Operation. Ohne Ergebnis nach `seconds` kommt `nil` zurück (die Operation wird abgebrochen).
/// Verhindert, dass eine hängende Übersetzung die ganze Sprachausgabe blockiert.
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async rethrows -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await operation() }
        group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
    }
}

/// HTTP-Antwort der Online-Übersetzer: 429 (Limit) und 5xx sind Fehler, auch wenn ein JSON-Text mitkommt.
enum OnlineStatus: Equatable {
    case ok, rateLimited, failed

    static func of(_ response: URLResponse?) -> OnlineStatus {
        guard let code = (response as? HTTPURLResponse)?.statusCode else { return .ok }
        if code == 429 { return .rateLimited }
        return (200..<300).contains(code) ? .ok : .failed
    }
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
    init(http: URLSession = Translator.privateSession, isOnline: @escaping @Sendable () -> Bool = { NetStatus.shared.online }, useApple: Bool = true) {
        self.http = http
        self.isOnline = isOnline
        self.useApple = useApple
    }

    /// Der Gesprächstext geht an Google/MyMemory (im Body, nie in der URL): nie in den Festplatten-Cache (URLCache) oder Cookies schreiben.
    static let privateSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.waitsForConnectivity = false          // kein Netz: sofort scheitern, nicht auf Verbindung warten
        c.timeoutIntervalForResource = OnlineTiming.resourceTimeout   // Obergrenze je Anfrage, auch bei tröpfelnder Antwort
        return URLSession(configuration: c)
    }()

    /// Längstens so lange auf die Apple-Übersetzung eines Satzes warten.
    static let appleTimeout = 8.0

    static func language(_ l: Lang) -> Locale.Language { Locale.Language(identifier: l.translationCode) }

    /// So lange gilt der gemerkte Paketstatus.
    static let installedTTL = 30.0
    private var installedCache: [String: (Bool, Date)] = [:]

    /// Paketstatus je Richtung 30 s merken: `LanguageAvailability` je Satz zu fragen kostet Latenz.
    private func installed(from: Lang, to: Lang) async -> Bool {
        let key = "\(from.rawValue)>\(to.rawValue)"
        if let (v, t) = installedCache[key], Date().timeIntervalSince(t) < Self.installedTTL { return v }
        let v = await Self.offlineInstalled(from: from, to: to)
        installedCache[key] = (v, Date())
        return v
    }

    /// Nach einem Paket-Download den Merker verwerfen.
    func invalidateInstalled() { installedCache = [:] }

    /// Sind die Offline-Sprachpakete für diese Richtung installiert?
    static func offlineInstalled(from: Lang, to: Lang) async -> Bool {
        await LanguageAvailability().status(from: language(from), to: language(to)) == .installed
    }

    func translate(_ text: String, from: Lang, to: Lang, allowOnline: Bool) async throws -> TranslationResult {
        let key = "\(from.rawValue)>\(to.rawValue)"
        var appleFailed = false
        try Task.checkCancellation()   // abgebrochen (gelöscht, neu übersetzt): nichts mehr tun, schon gar nichts ins Netz schicken
        if useApple, await installed(from: from, to: to) {
            do {
                let s = sessions[key] ?? TranslationSession(installedSource: Self.language(from), target: Self.language(to))
                sessions[key] = s
                // Zeitlimit: hängt die Apple-Übersetzung, soll nicht die ganze Sprachausgabe stehen.
                if let out = try await withTimeout(seconds: Self.appleTimeout, { try await s.translate(text).targetText }) {
                    if !out.isEmpty { return TranslationResult(text: out, provider: "apple") }
                } else {
                    sessions[key] = nil
                    appleFailed = true
                }
            } catch {
                sessions[key] = nil
                appleFailed = true
            }
            // Der Abbruch lässt den Zeitgeber der Gruppe sofort „ablaufen“: das ist kein Apple-Fehler und darf nicht online weitergehen.
            try Task.checkCancellation()
        }
        // Das Paket ist da, die Übersetzung hat aber nicht geantwortet: nicht „Paket fehlt“ melden.
        guard allowOnline else { throw appleFailed ? TranslateError.appleFailed : TranslateError.offlineMissing }
        guard isOnline() else { throw TranslateError.noNetwork }
        guard breaker.allows(at: Date()) else { throw TranslateError.cooldown }
        let (result, limited) = await onlineAttempt(text, from: from, to: to)
        try Task.checkCancellation()
        if let result {
            breaker.succeeded()
            return result
        }
        breaker.failed(at: Date(), rateLimited: limited)
        throw limited ? TranslateError.rateLimited : TranslateError.failed
    }

    /// Zeiten der Online-Übersetzer (kurz: wer am Markt kein Netz hat, soll nicht lange auf einen Satz warten).
    enum OnlineTiming {
        static let googleTimeout = 3.0
        static let myMemoryTimeout = 3.5
        /// Antwortet Google nach so vielen Sekunden noch nicht, startet MyMemory parallel (der schnellere gewinnt).
        static let hedgeDelay = 1.2
        /// Gesamtdauer einer Anfrage (URLSession), unabhängig vom Leerlauf-Zeitlimit.
        static let resourceTimeout = 8.0
    }

    private enum Attempt: Sendable {
        case answer(provider: String, text: String?, limited: Bool)
        case tick
    }

    /// Google zuerst; MyMemory startet sofort, wenn Google scheitert, sonst nach `hedgeDelay` parallel dazu.
    /// Das erste brauchbare Ergebnis gewinnt, der Rest wird abgebrochen. `limited`: ein Dienst meldete „Limit erreicht“.
    private func onlineAttempt(_ text: String, from: Lang, to: Lang) async -> (TranslationResult?, Bool) {
        let useMyMemory = MyMemory.fits(text)
        return await withTaskGroup(of: Attempt.self) { group in
            group.addTask { await self.run("google") { try await self.google(text, from: from, to: to) } }
            if useMyMemory {
                group.addTask {
                    try? await Task.sleep(for: .seconds(OnlineTiming.hedgeDelay))
                    return .tick
                }
            }
            var secondStarted = false
            var limited = false
            func startSecond() {
                guard useMyMemory, !secondStarted else { return }
                secondStarted = true
                group.addTask { await self.run("mymemory") { try await self.myMemory(text, from: from, to: to) } }
            }
            while let next = await group.next() {
                switch next {
                case .tick:
                    startSecond()
                case .answer(let provider, let out, let lim):
                    if lim { limited = true }
                    if let out, !out.isEmpty {
                        group.cancelAll()
                        return (TranslationResult(text: out, provider: provider), false)
                    }
                    if provider == "google" { startSecond() }
                }
            }
            return (nil, limited)
        }
    }

    private func run(_ provider: String, _ op: () async throws -> String?) async -> Attempt {
        do {
            return .answer(provider: provider, text: try await op(), limited: false)
        } catch OnlineError.rateLimited {
            return .answer(provider: provider, text: nil, limited: true)
        } catch {
            return .answer(provider: provider, text: nil, limited: false)   // Abbruch/Netzfehler: kein Ergebnis
        }
    }

    /// Formular-Kodierung: „+“ muss als %2B raus, sonst wird es beim Server zum Leerzeichen.
    static func form(_ items: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }

    private enum OnlineError: Error { case rateLimited, http }

    private static func check(_ response: URLResponse) throws {
        switch OnlineStatus.of(response) {
        case .ok: return
        case .rateLimited: throw OnlineError.rateLimited
        case .failed: throw OnlineError.http
        }
    }

    private func google(_ text: String, from: Lang, to: Lang) async throws -> String {
        var req = URLRequest(url: URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t")!)
        req.httpMethod = "POST"
        req.timeoutInterval = OnlineTiming.googleTimeout
        req.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form(["sl": from.mtCode, "tl": to.mtCode, "q": text])
        let (data, response) = try await http.data(for: req)
        try Self.check(response)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let parts = root.first as? [[Any]] else { return "" }
        return parts.compactMap { $0.first as? String }.joined()
    }

    /// POST statt GET: der Gesprächstext steht nicht in der URL (Proxy-/Server-Logs, Verlauf).
    private func myMemory(_ text: String, from: Lang, to: Lang) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://api.mymemory.translated.net/get")!)
        req.httpMethod = "POST"
        req.timeoutInterval = OnlineTiming.myMemoryTimeout
        req.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form(["q": text, "langpair": "\(from.mtCode)|\(to.mtCode)"])
        let (data, response) = try await http.data(for: req)
        try Self.check(response)
        return MyMemory.parse(data)
    }
}
