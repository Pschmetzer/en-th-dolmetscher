// Round33Platform.swift – dünne Hüllen um Systemdienste für die Runde-33-Logik: Spotlight, Zwei-Geräte-Verbindung
// (MultipeerConnectivity, Prototyp, in der Oberfläche nicht angeboten), WatchConnectivity-Verfügbarkeit, QR-Bild,
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

/// Prototyp: zwei iPhones tauschen Sätze über MultipeerConnectivity. Wird erst nach Info.plist-Einträgen
/// (NSBonjourServices, NSLocalNetworkUsageDescription) und einer Oberfläche angeboten.
final class PeerLink: NSObject, MCSessionDelegate, @unchecked Sendable {
    static let serviceType = "dolm-pair"
    private let me = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
    var onMessage: (@Sendable (PeerMessage) -> Void)?

    override init() { super.init(); session.delegate = self }

    func send(_ m: PeerMessage) {
        guard let d = m.encode(), !session.connectedPeers.isEmpty else { return }
        try? session.send(d, toPeers: session.connectedPeers, with: .reliable)
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let m = PeerMessage.decode(data) { onMessage?(m) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
