/// The fixed list of categories, income first. The keys are what
/// `buchungen.kategorie` stores and they never change; a booking with an
/// unknown key keeps it and is shown with the raw key. The one-line
/// description is what the agent reads in its instructions.
public struct Kategorie: Hashable, Sendable, Identifiable {
    public let schluessel: String
    public let name: String
    public let richtung: Richtung
    public let beschreibung: String

    public var id: String {
        schluessel
    }

    /// The categories of one direction, in the order of the list.
    public static func fuer(_ richtung: Richtung) -> [Kategorie] {
        alle.filter { $0.richtung == richtung }
    }

    /// The display name of a key, or the key itself when it is not in the list.
    public static func name(_ schluessel: String) -> String {
        alle.first { $0.schluessel == schluessel }?.name ?? schluessel
    }

    public static func bekannt(_ schluessel: String) -> Bool {
        alle.contains { $0.schluessel == schluessel }
    }

    public static let alle: [Kategorie] = [
        Kategorie(
            schluessel: "umsatz_dienstleistung", name: "Umsatz Dienstleistung", richtung: .einnahme,
            beschreibung: "Honorare für eigene Arbeit, Projekte, Beratung, Entwicklung."
        ),
        Kategorie(
            schluessel: "umsatz_waren", name: "Umsatz Waren", richtung: .einnahme,
            beschreibung: "Verkauf von Gegenständen oder Handelsware."
        ),
        Kategorie(
            schluessel: "umsatz_lizenzen", name: "Umsatz Lizenzen", richtung: .einnahme,
            beschreibung: "Lizenzen, Nutzungsrechte, Tantiemen, Abo-Erlöse aus eigenen Produkten."
        ),
        Kategorie(
            schluessel: "sonstige_einnahme", name: "Sonstige Einnahme", richtung: .einnahme,
            beschreibung: "Einnahme, die in keine andere Einnahmekategorie passt."
        ),
        Kategorie(
            schluessel: "ust_erstattung", name: "Umsatzsteuererstattung", richtung: .einnahme,
            beschreibung: "Erstattung des Finanzamts aus der Umsatzsteuervoranmeldung."
        ),
        Kategorie(
            schluessel: "zinsen", name: "Zinsen", richtung: .einnahme,
            beschreibung: "Zinserträge aus Geschäftskonten oder Anlagen."
        ),
        Kategorie(
            schluessel: "software", name: "Software", richtung: .ausgabe,
            beschreibung: "Programme, Abos und Dienste wie Entwicklungswerkzeuge oder KI-APIs."
        ),
        Kategorie(
            schluessel: "hosting", name: "Hosting", richtung: .ausgabe,
            beschreibung: "Server, Domains, Cloud-Speicher und Rechenzeit."
        ),
        Kategorie(
            schluessel: "telekommunikation", name: "Telekommunikation", richtung: .ausgabe,
            beschreibung: "Mobilfunk, Festnetz und Internetanschluss."
        ),
        Kategorie(
            schluessel: "buerobedarf", name: "Bürobedarf", richtung: .ausgabe,
            beschreibung: "Verbrauchsmaterial fürs Büro, Papier, Stifte, Kleinteile."
        ),
        Kategorie(
            schluessel: "miete", name: "Miete", richtung: .ausgabe,
            beschreibung: "Miete und Nebenkosten für Arbeitsräume oder Coworking."
        ),
        Kategorie(
            schluessel: "hardware", name: "Hardware", richtung: .ausgabe,
            beschreibung: "Rechner, Bildschirme, Telefone und sonstige Geräte."
        ),
        Kategorie(
            schluessel: "werbung", name: "Werbung", richtung: .ausgabe,
            beschreibung: "Anzeigen, Website, Visitenkarten und andere Außendarstellung."
        ),
        Kategorie(
            schluessel: "beratung", name: "Beratung", richtung: .ausgabe,
            beschreibung: "Steuerberatung, Rechtsberatung, Notar und ähnliche Honorare."
        ),
        Kategorie(
            schluessel: "fremdleistung", name: "Fremdleistung", richtung: .ausgabe,
            beschreibung: "Zugekaufte Arbeit von Subunternehmern für eigene Projekte."
        ),
        Kategorie(
            schluessel: "reise_fahrt", name: "Reise: Fahrt", richtung: .ausgabe,
            beschreibung: "Bahn, Flug, Taxi, Mietwagen und Tankbelege einer Geschäftsreise."
        ),
        Kategorie(
            schluessel: "reise_uebernachtung", name: "Reise: Übernachtung", richtung: .ausgabe,
            beschreibung: "Hotel und Unterkunft auf einer Geschäftsreise."
        ),
        Kategorie(
            schluessel: "bewirtung", name: "Bewirtung", richtung: .ausgabe,
            beschreibung: "Restaurantbelege für Geschäftsessen mit Bewirtungsanlass."
        ),
        Kategorie(
            schluessel: "fortbildung", name: "Fortbildung", richtung: .ausgabe,
            beschreibung: "Kurse, Konferenzen, Fachbücher und Schulungen."
        ),
        Kategorie(
            schluessel: "versicherung", name: "Versicherung", richtung: .ausgabe,
            beschreibung: "Betriebliche Versicherungen wie Haftpflicht oder Rechtsschutz."
        ),
        Kategorie(
            schluessel: "bankgebuehren", name: "Bankgebühren", richtung: .ausgabe,
            beschreibung: "Kontoführung, Überweisungsentgelte und Kartengebühren."
        ),
        Kategorie(
            schluessel: "zahlungsanbieter", name: "Zahlungsanbieter", richtung: .ausgabe,
            beschreibung: "Gebühren von Stripe, PayPal und vergleichbaren Diensten."
        ),
        Kategorie(
            schluessel: "mitgliedschaft", name: "Mitgliedschaft", richtung: .ausgabe,
            beschreibung: "Beiträge zu Kammern, Verbänden und Berufsvereinigungen."
        ),
        Kategorie(
            schluessel: "porto", name: "Porto", richtung: .ausgabe,
            beschreibung: "Briefmarken, Pakete und Versandkosten."
        ),
        Kategorie(
            schluessel: "ust_zahlung", name: "Umsatzsteuerzahlung", richtung: .ausgabe,
            beschreibung: "Zahlung an das Finanzamt aus der Umsatzsteuervoranmeldung."
        ),
        Kategorie(
            schluessel: "sonstige_ausgabe", name: "Sonstige Ausgabe", richtung: .ausgabe,
            beschreibung: "Ausgabe, die in keine andere Ausgabekategorie passt."
        )
    ]
}
