import XCTest
@testable import Dolmetscher

final class Round28Tests: XCTestCase {
    /// Ein abgebrochener Auftrag darf nichts mehr ins Netz schicken (gelöschter Satz, Verlauf geleert).
    func testCancelledTranslationSendsNothing() async {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        StubProtocol.handler = { _ in (200, Data("[[[\"x\"]]]".utf8)) }
        let t = Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
        let job = Task { () -> Bool in
            do { _ = try await t.translate("Hello there", from: .en, to: .th, allowOnline: true); return false }
            catch is CancellationError { return true } catch { return false }
        }
        job.cancel()
        let cancelled = await job.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(StubProtocol.requests.count, 0)
        StubProtocol.handler = nil
    }
}
