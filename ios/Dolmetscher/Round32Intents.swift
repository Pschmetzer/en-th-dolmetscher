// Round32Intents.swift – Kurzbefehle mit Rückgabewert: Notrufnummern je Land, Taxi-Satz, Gegenangebote.
// Nicht als App Shortcut (Siri-Phrasen sind begrenzt), aber in der Kurzbefehle-App wählbar und verkettbar.
import AppIntents
import Foundation

/// Notrufnummern eines Landes (Standard: Region des Geräts). Der Text geht zurück, damit Kurzbefehle ihn weiterverwenden.
struct EmergencyNumbersIntent: AppIntent {
    static let title: LocalizedStringResource = "Emergency numbers"
    static let description = IntentDescription("Returns the police, ambulance and fire numbers for a country (default: the device's region).")

    @Parameter(title: "Country", description: "Country name or two-letter code, for example Thailand or TH. Empty uses this device's region.")
    var country: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let region = country.flatMap { EmergencyNumbers.region(matching: $0) } ?? Locale.current.region?.identifier
        let text = EmergencyNumbers.summary(EmergencyNumbers.forRegion(region))
        return .result(value: text, dialog: "\(text)")
    }
}

/// Taxi-Satz auf Thai als Text zurückgeben (zum Einfügen in Nachrichten); `phraseID` wie in der Taxi-Karte.
struct TaxiPhraseIntent: AppIntent {
    static let title: LocalizedStringResource = "Taxi phrase (Thai)"
    static let description = IntentDescription("Returns a common taxi sentence in Thai script, for example \"Please use the meter\".")

    @Parameter(title: "Phrase", description: "airport, donmueang, bts, meter, price, toll, stop, wait, aircon")
    var phraseID: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let item = TaxiCard.item(phraseID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw TranslateIntentError(message: T("sc_no_phrase"))
        }
        let female = UserDefaults.standard.string(forKey: "politeness") == Politeness.female.rawValue
        let thai = TaxiCard.thai(item, female: female)
        return .result(value: thai, dialog: "\(thai)")
    }
}

/// Gegenangebote fürs Handeln (Baht) zu einem verlangten Preis.
struct PriceCounterIntent: AppIntent {
    static let title: LocalizedStringResource = "Counter-offer for a price"
    static let description = IntentDescription("Returns suggested counter-offers in baht for an asking price.")

    @Parameter(title: "Asking price (baht)")
    var asked: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[Int]> & ProvidesDialog {
        let offers = PriceHelper.counters(asked: asked).map(\.amount)
        guard !offers.isEmpty else { throw TranslateIntentError(message: T("err_translate")) }
        return .result(value: offers, dialog: "\(offers.map { "฿\($0)" }.joined(separator: " · "))")
    }
}
