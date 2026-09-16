/// The fixed list of categories, income first. The keys are what
/// `buchungen.kategorie` stores and they never change; a booking with an
/// unknown schluessel keeps it and is shown with the raw schluessel.
public struct Kategorie: Hashable, Sendable, Identifiable {
    public let schluessel: String
    public let name: String
    public let richtung: Richtung
    /// The line of the Anlage EÜR this category is typed into.
    ///
    /// **Ungeprüft**: the line numbers come from the 2023/2024 layout of the
    /// form; the official Anlage EÜR 2026 was not available when they were
    /// written and the numbering is likely to have moved. They are a starting
    /// point for the user, not a checked mapping. The lines
    /// `EUeR.zeileVereinnahmteUmsatzsteuer` and `EUeR.zeileGezahlteVorsteuer`
    /// belong to the two computed VAT lines and no category takes them.
    public let euerZeile: Int
    public let beschreibung: String
    /// The SF Symbol the ledger shows in front of the booking.
    public let symbol: String

    public var id: String {
        schluessel
    }

    /// The categories of one direction, in the order of the list.
    public static func fuer(_ richtung: Richtung) -> [Kategorie] {
        alle.filter { $0.richtung == richtung }
    }

    /// The display name of a schluessel, or the schluessel itself when it is not in the list.
    public static func name(_ schluessel: String) -> String {
        alle.first { $0.schluessel == schluessel }?.name ?? schluessel
    }

    /// The symbol of a schluessel, or a neutral document symbol when it is not in the list.
    public static func symbol(_ schluessel: String?) -> String {
        guard let schluessel else { return "doc.text" }
        return alle.first { $0.schluessel == schluessel }?.symbol ?? "doc.text"
    }

    public static func bekannt(_ schluessel: String) -> Bool {
        alle.contains { $0.schluessel == schluessel }
    }

    public static let alle: [Kategorie] = [
        Kategorie(
            schluessel: "umsatz_dienstleistung", name: "Umsatz Dienstleistung", richtung: .einnahme,
            euerZeile: 11,
            beschreibung: "Honorare für eigene Arbeit, Projekte, Beratung, Entwicklung.",
            symbol: "briefcase"
        ),
        Kategorie(
            schluessel: "umsatz_waren", name: "Umsatz Waren", richtung: .einnahme,
            euerZeile: 14,
            beschreibung: "Verkauf von Gegenständen oder Handelsware.",
            symbol: "shippingbox"
        ),
        Kategorie(
            schluessel: "umsatz_lizenzen", name: "Umsatz Lizenzen", richtung: .einnahme,
            euerZeile: 15,
            beschreibung: "Lizenzen, Nutzungsrechte, Tantiemen, Abo-Erlöse aus eigenen Produkten.",
            symbol: "key"
        ),
        Kategorie(
            schluessel: "sonstige_einnahme", name: "Sonstige Einnahme", richtung: .einnahme,
            euerZeile: 17,
            beschreibung: "Einnahme, die in keine andere Einnahmekategorie passt.",
            symbol: "doc.text"
        ),
        Kategorie(
            schluessel: "ust_erstattung", name: "Umsatzsteuererstattung", richtung: .einnahme,
            euerZeile: 16,
            beschreibung: "Erstattung des Finanzamts aus der Umsatzsteuervoranmeldung.",
            symbol: "building.columns"
        ),
        Kategorie(
            schluessel: "zinsen", name: "Zinsen", richtung: .einnahme,
            euerZeile: 21,
            beschreibung: "Zinserträge aus Geschäftskonten oder Anlagen.",
            symbol: "percent"
        ),
        Kategorie(
            schluessel: "software", name: "Software", richtung: .ausgabe,
            euerZeile: 43,
            beschreibung: "Programme, Abos und Dienste wie Entwicklungswerkzeuge oder KI-APIs.",
            symbol: "app"
        ),
        Kategorie(
            schluessel: "hosting", name: "Hosting", richtung: .ausgabe,
            euerZeile: 43,
            beschreibung: "Server, Domains, Cloud-Speicher und Rechenzeit.",
            symbol: "cloud"
        ),
        Kategorie(
            schluessel: "telekommunikation", name: "Telekommunikation", richtung: .ausgabe,
            euerZeile: 43,
            beschreibung: "Mobilfunk, Festnetz und Internetanschluss.",
            symbol: "phone"
        ),
        Kategorie(
            schluessel: "buerobedarf", name: "Bürobedarf", richtung: .ausgabe,
            euerZeile: 45,
            beschreibung: "Verbrauchsmaterial fürs Büro, Papier, Stifte, Kleinteile.",
            symbol: "pencil.and.ruler"
        ),
        Kategorie(
            schluessel: "miete", name: "Miete", richtung: .ausgabe,
            euerZeile: 41,
            beschreibung: "Miete und Nebenkosten für Arbeitsräume oder Coworking.",
            symbol: "building.2"
        ),
        Kategorie(
            schluessel: "hardware", name: "Hardware", richtung: .ausgabe,
            euerZeile: 47,
            beschreibung: "Rechner, Bildschirme, Telefone und sonstige Geräte.",
            symbol: "desktopcomputer"
        ),
        Kategorie(
            schluessel: "werbung", name: "Werbung", richtung: .ausgabe,
            euerZeile: 51,
            beschreibung: "Anzeigen, Website, Visitenkarten und andere Außendarstellung.",
            symbol: "megaphone"
        ),
        Kategorie(
            schluessel: "beratung", name: "Beratung", richtung: .ausgabe,
            euerZeile: 39,
            beschreibung: "Steuerberatung, Rechtsberatung, Notar und ähnliche Honorare.",
            symbol: "person.circle"
        ),
        Kategorie(
            schluessel: "fremdleistung", name: "Fremdleistung", richtung: .ausgabe,
            euerZeile: 27,
            beschreibung: "Zugekaufte Arbeit von Subunternehmern für eigene Projekte.",
            symbol: "person.2"
        ),
        Kategorie(
            schluessel: "reise_fahrt", name: "Reise: Fahrt", richtung: .ausgabe,
            euerZeile: 55,
            beschreibung: "Bahn, Flug, Taxi, Mietwagen und Tankbelege einer Geschäftsreise.",
            symbol: "suitcase"
        ),
        Kategorie(
            schluessel: "reise_uebernachtung", name: "Reise: Übernachtung", richtung: .ausgabe,
            euerZeile: 55,
            beschreibung: "Hotel und Unterkunft auf einer Geschäftsreise.",
            symbol: "bed.double"
        ),
        Kategorie(
            schluessel: "bewirtung", name: "Bewirtung", richtung: .ausgabe,
            euerZeile: 56,
            beschreibung: "Restaurantbelege für Geschäftsessen mit Bewirtungsanlass.",
            symbol: "fork.knife"
        ),
        Kategorie(
            schluessel: "fortbildung", name: "Fortbildung", richtung: .ausgabe,
            euerZeile: 48,
            beschreibung: "Kurse, Konferenzen, Fachbücher und Schulungen.",
            symbol: "book"
        ),
        Kategorie(
            schluessel: "versicherung", name: "Versicherung", richtung: .ausgabe,
            euerZeile: 44,
            beschreibung: "Betriebliche Versicherungen wie Haftpflicht oder Rechtsschutz.",
            symbol: "shield"
        ),
        Kategorie(
            schluessel: "bankgebuehren", name: "Bankgebühren", richtung: .ausgabe,
            euerZeile: 50,
            beschreibung: "Kontoführung, Überweisungsentgelte und Kartengebühren.",
            symbol: "banknote"
        ),
        Kategorie(
            schluessel: "zahlungsanbieter", name: "Zahlungsanbieter", richtung: .ausgabe,
            euerZeile: 50,
            beschreibung: "Gebühren von Stripe, PayPal und vergleichbaren Diensten.",
            symbol: "creditcard"
        ),
        Kategorie(
            schluessel: "mitgliedschaft", name: "Mitgliedschaft", richtung: .ausgabe,
            euerZeile: 49,
            beschreibung: "Beiträge zu Kammern, Verbänden und Berufsvereinigungen.",
            symbol: "person.3"
        ),
        Kategorie(
            schluessel: "porto", name: "Porto", richtung: .ausgabe,
            euerZeile: 46,
            beschreibung: "Briefmarken, Pakete und Versandkosten.",
            symbol: "envelope"
        ),
        Kategorie(
            schluessel: "ust_zahlung", name: "Umsatzsteuerzahlung", richtung: .ausgabe,
            euerZeile: 60,
            beschreibung: "Zahlung an das Finanzamt aus der Umsatzsteuervoranmeldung.",
            symbol: "building.columns"
        ),
        Kategorie(
            schluessel: "sonstige_ausgabe", name: "Sonstige Ausgabe", richtung: .ausgabe,
            euerZeile: 62,
            beschreibung: "Ausgabe, die in keine andere Ausgabekategorie passt.",
            symbol: "doc.text"
        )
    ]
}
