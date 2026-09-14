/// The fixed list of categories, income first. The keys are what
/// `buchungen.kategorie` stores and they never change; a booking with an
/// unknown key keeps it and is shown with the raw key.
public struct Kategorie: Hashable, Sendable, Identifiable {
    public let schluessel: String
    public let name: String
    public let richtung: Richtung

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

    public static let alle: [Kategorie] = [
        Kategorie(schluessel: "umsatz_dienstleistung", name: "Umsatz Dienstleistung", richtung: .einnahme),
        Kategorie(schluessel: "umsatz_waren", name: "Umsatz Waren", richtung: .einnahme),
        Kategorie(schluessel: "umsatz_lizenzen", name: "Umsatz Lizenzen", richtung: .einnahme),
        Kategorie(schluessel: "sonstige_einnahme", name: "Sonstige Einnahme", richtung: .einnahme),
        Kategorie(schluessel: "ust_erstattung", name: "Umsatzsteuererstattung", richtung: .einnahme),
        Kategorie(schluessel: "zinsen", name: "Zinsen", richtung: .einnahme),
        Kategorie(schluessel: "software", name: "Software", richtung: .ausgabe),
        Kategorie(schluessel: "hosting", name: "Hosting", richtung: .ausgabe),
        Kategorie(schluessel: "telekommunikation", name: "Telekommunikation", richtung: .ausgabe),
        Kategorie(schluessel: "buerobedarf", name: "Bürobedarf", richtung: .ausgabe),
        Kategorie(schluessel: "miete", name: "Miete", richtung: .ausgabe),
        Kategorie(schluessel: "hardware", name: "Hardware", richtung: .ausgabe),
        Kategorie(schluessel: "werbung", name: "Werbung", richtung: .ausgabe),
        Kategorie(schluessel: "beratung", name: "Beratung", richtung: .ausgabe),
        Kategorie(schluessel: "fremdleistung", name: "Fremdleistung", richtung: .ausgabe),
        Kategorie(schluessel: "reise_fahrt", name: "Reise: Fahrt", richtung: .ausgabe),
        Kategorie(schluessel: "reise_uebernachtung", name: "Reise: Übernachtung", richtung: .ausgabe),
        Kategorie(schluessel: "bewirtung", name: "Bewirtung", richtung: .ausgabe),
        Kategorie(schluessel: "fortbildung", name: "Fortbildung", richtung: .ausgabe),
        Kategorie(schluessel: "versicherung", name: "Versicherung", richtung: .ausgabe),
        Kategorie(schluessel: "bankgebuehren", name: "Bankgebühren", richtung: .ausgabe),
        Kategorie(schluessel: "zahlungsanbieter", name: "Zahlungsanbieter", richtung: .ausgabe),
        Kategorie(schluessel: "mitgliedschaft", name: "Mitgliedschaft", richtung: .ausgabe),
        Kategorie(schluessel: "porto", name: "Porto", richtung: .ausgabe),
        Kategorie(schluessel: "ust_zahlung", name: "Umsatzsteuerzahlung", richtung: .ausgabe),
        Kategorie(schluessel: "sonstige_ausgabe", name: "Sonstige Ausgabe", richtung: .ausgabe)
    ]
}
