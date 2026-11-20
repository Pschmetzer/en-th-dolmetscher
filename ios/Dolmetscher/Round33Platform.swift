// Round33Platform.swift – dünne Hüllen um Systemdienste für die Runde-33-Logik: Spotlight, Zwei-Geräte-Verbindung
// (MultipeerConnectivity: Suche, Einladung, Nachrichten; Oberfläche in Round34Views.swift), WatchConnectivity-Verfügbarkeit, QR-Bild,
// Stimmenqualität, Datei-Schutz. Die Entscheidungen stehen in Round33.swift und sind dort getestet.
import AVFoundation
import CoreImage.CIFilterBuiltins
import CoreSpotlight
import MultipeerConnectivity
import UIKit
import WatchConnectivity

enum HistorySpotlight {
    static let enabledKey = "spotlightHistory"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }   // Standard: aus

    /// Index neu aufbauen (oder leeren, wenn nicht erlaubt).
    static func sync(_ entries: [Entry], locked: Bool) {
        let index = CSSearchableIndex.default()
        let allowed = SpotlightPlan.shouldIndex(enabled: enabled, locked: locked)
        let items = allowed ? SpotlightPlan.items(entries).map { i -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = i.title
            a.contentDescription = i.content
            a.contentModificationDate = i.date
            let item = CSSearchableItem(uniqueIdentifier: i.id, domainIdentifier: SpotlightPlan.domain, attributeSet: a)
            item.expirationDate = Date().addingTimeInterval(30 * 86_400)
            return item
        } : []
        index.deleteSearchableItems(withDomainIdentifiers: [SpotlightPlan.domain]) { _ in
            if !items.isEmpty { index.indexSearchableItems(items) { _ in } }
        }
    }

    static func clear() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [SpotlightPlan.domain]) { _ in }
    }
}

enum QRImage {
    /// QR-Bild aus Text; nil bei leerem Text oder Fehler.
    static func make(_ text: String, scale: CGFloat = 8) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum VoiceCheck {
    /// Beste installierte Stimme für die Sprache.
    static func quality(for lang: Lang) -> VoiceQuality {
        let code = lang.voiceLocale
        var best = VoiceQuality.none
        for v in AVSpeechSynthesisVoice.speechVoices() where v.language == code || v.language.hasPrefix(lang.rawValue) {
            let q: VoiceQuality
            switch v.quality {
            case .premium: q = .premium
            case .enhanced: q = .enhanced
            default: q = .compact
            }
            best = max(best, q)
        }
        return best
    }
}

enum WatchBridge {
    /// Gibt es eine gekoppelte Uhr mit installierter App? Ohne Watch-Target immer false.
    static var available: Bool {
        guard WCSession.isSupported() else { return false }
        let s = WCSession.default
        return s.isPaired && s.isWatchAppInstalled
    }
}

enum FileGuardApply {
    /// Setzt Backup-Ausschluss und Dateischutz nach `FileGuard.policy`.
    @discardableResult
    static func apply(_ url: URL) -> Bool {
        let p = FileGuard.policy(forFileNamed: url.lastPathComponent)
        var ok = true
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = p.excludeFromBackup
        var u = url
        do { try u.setResourceValues(rv) } catch { ok = false }
        let key: FileProtectionType? = {
            switch p.protection {
            case .complete: return .complete
            case .untilFirstUnlock: return .completeUntilFirstUserAuthentication
            case .none: return nil
            }
        }()
        if let key { do { try FileManager.default.setAttributes([.protectionKey: key], ofItemAtPath: url.path) } catch { ok = false } }
        return ok
    }
}

/// Zwei iPhones tauschen Sätze über MultipeerConnectivity (Runde 34: Suche, Einladung mit Rückfrage, Oberfläche in Round34Views).
/// Verschlüsselt (`.required`); eine Einladung wird nie ohne Rückfrage angenommen. Es geht nichts ins Internet.
final class PeerLink: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, @unchecked Sendable {
    static let serviceType = "dolm-pair"

    enum Event: Sendable {
        case found(String), lost(String)
        /// Einladung von `from`; `answer(true)` nimmt an.
        case invitation(from: String, answer: @Sendable (Bool) -> Void)
        case connected(String), disconnected(String)
        case message(PeerMessage)
    }

    private let me = MCPeerID(displayName: PeerLink.displayName())
    private lazy var session: MCSession = {
        let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    private lazy var advertiser: MCNearbyServiceAdvertiser = {
        let a = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: Self.serviceType)
        a.delegate = self
        return a
    }()
    private lazy var browser: MCNearbyServiceBrowser = {
        let b = MCNearbyServiceBrowser(peer: me, serviceType: Self.serviceType)
        b.delegate = self
        return b
    }()
    private let lock = NSLock()
    private var found: [String: MCPeerID] = [:]
    var onEvent: (@Sendable (Event) -> Void)?

    /// „iPhone · ab12“: kurz (MultipeerConnectivity erlaubt höchstens 63 Bytes) und unterscheidbar.
    static func displayName(device: String = UIDevice.current.name, suffix: String = String(UUID().uuidString.prefix(4)).lowercased()) -> String {
        let tail = " · " + suffix
        var head = String(device.prefix(40))
        while (head + tail).utf8.count > 63, !head.isEmpty { head.removeLast() }
        return head + tail
    }

    var myName: String { me.displayName }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        lock.withLock { found = [:] }
    }

    func invite(_ name: String) {
        guard let id = lock.withLock({ found[name] }) else { return }
        browser.invitePeer(id, to: session, withContext: nil, timeout: 30)
    }

    func send(_ m: PeerMessage) {
        guard let d = m.encode(), !session.connectedPeers.isEmpty else { return }
        try? session.send(d, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: MCSessionDelegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: onEvent?(.connected(peerID.displayName))
        case .notConnected: onEvent?(.disconnected(peerID.displayName))
        default: break
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let m = PeerMessage.decode(data) { onEvent?(.message(m)) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: Suche
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        lock.withLock { found[peerID.displayName] = peerID }
        onEvent?(.found(peerID.displayName))
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        lock.withLock { _ = found.removeValue(forKey: peerID.displayName) }
        onEvent?(.lost(peerID.displayName))
    }

    // MARK: Einladungen
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let s = session
        onEvent?(.invitation(from: peerID.displayName, answer: { ok in invitationHandler(ok, ok ? s : nil) }))
    }
}
