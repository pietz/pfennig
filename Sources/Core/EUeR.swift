import Foundation

/// The yearly values of the Anlage EÜR: one line of the form per category
/// group, with the amounts of the year.
///
/// Zufluss and Abfluss, §11 EStG, the same way the UStVA counts: only what was
/// paid in the year counts, a partial payment with its proportional share of
/// the positions, a refund against it. The Belegdatum decides nothing here.
///
/// The Umsatzsteuer follows the method of the official form, not the net
/// shortcut. A regularly taxed business books the net amounts on the category
/// lines and adds the two computed lines the form asks for: the vereinnahmte
/// Umsatzsteuer of the year as an income line and the gezahlte Vorsteuer of
/// the year as an expense line. Together with the two category lines for the
/// payments to and refunds from the Finanzamt they make the four VAT lines of
/// the form, and the Gewinn comes out right. A Kleinunternehmer deducts no
/// Vorsteuer, books gross on the category lines and has no VAT lines; the
/// payments he makes under §13b stay on their own category line.
///
/// The Privatanteil of an expense is taken off its own amount before it
/// reaches the line, and off its Vorsteuer the same way. Income has no private
/// share, and the vereinnahmte Umsatzsteuer is owed in full, so neither is
/// shortened.
public struct EUeR: Hashable, Sendable {
    public struct Zeile: Hashable, Sendable, Identifiable {
        public let zeile: Int
        public let bezeichnung: String
        public let richtung: Richtung
        public let betrag: Cent

        public var id: Int {
            zeile
        }
    }

    /// The year of the official form the line numbers belong to, BMF-Schreiben
    /// vom 01.09.2026.
    public static let formularjahr = 2026

    /// The two lines that no category feeds, Anlage EÜR 2026.
    public static let zeileVereinnahmteUmsatzsteuer = 17
    public static let zeileGezahlteVorsteuer = 58

    /// The line titles of the Anlage EÜR 2026 for the lines Pfennig fills,
    /// shortened to what fits a CSV cell.
    static let titel: [Int: String] = [
        12: "Betriebseinnahmen als umsatzsteuerlicher Kleinunternehmer",
        15: "Umsatzsteuerpflichtige Betriebseinnahmen",
        16: "Umsatzsteuerfreie, nicht steuerbare und § 13b-Betriebseinnahmen",
        17: "Vereinnahmte Umsatzsteuer",
        18: "Vom Finanzamt erstattete Umsatzsteuer",
        30: "Bezogene Fremdleistungen",
        37: "Geringwertige Wirtschaftsgüter",
        40: "Miete/Pacht für Geschäftsräume",
        44: "Telekommunikation",
        45: "Übernachtungs- und Reisenebenkosten",
        46: "Fortbildungskosten",
        47: "Rechts- und Steuerberatung, Buchführung",
        50: "Beiträge, Gebühren, Abgaben und Versicherungen",
        51: "Laufende EDV-Kosten",
        52: "Arbeitsmittel",
        55: "Werbekosten",
        58: "Gezahlte Vorsteuer",
        59: "An das Finanzamt gezahlte Umsatzsteuer",
        61: "Übrige unbeschränkt abziehbare Betriebsausgaben",
        64: "Bewirtungsaufwendungen",
        71: "Sonstige tatsächliche Fahrtkosten"
    ]

    public let jahr: Int
    public let zeilen: [Zeile]

    public var einnahmen: Cent {
        zeilen.filter { $0.richtung == .einnahme }.reduce(Cent.null) { $0 + $1.betrag }
    }

    public var ausgaben: Cent {
        zeilen.filter { $0.richtung == .ausgabe }.reduce(Cent.null) { $0 + $1.betrag }
    }

    public var ergebnis: Cent {
        einnahmen - ausgaben
    }

    // MARK: - Berechnung

    public static func calculate(_ buchungen: [Buchung], jahr: Int, profile: Profil) -> EUeR {
        let zeitraum = Zeitraum(jahr: jahr, einteilung: .jahr)
        let brutto = profile.kleinunternehmer
        var werte: [Int: Cent] = [:]
        var vereinnahmt = Cent.null
        var vorsteuer = Cent.null

        for buchung in buchungen where buchung.art != .ignoriert {
            guard let key = buchung.kategorie,
                  let kategorie = Kategorie.alle.first(where: { $0.schluessel == key })
            else { continue }
            let summe = summe(buchung, zeitraum: zeitraum)
            let roh = summe.netto + (brutto ? summe.steuer : .null)
            // Only an expense can be partly private; income is earned in full.
            let betrag = buchung.richtung == .ausgabe
                ? ohnePrivatanteil(roh, prozent: buchung.privatanteilProzent)
                : roh
            if betrag != .null {
                let zeile = zeile(buchung, kategorie, profile: profile)
                werte[zeile, default: .null] = werte[zeile, default: .null] + betrag
            }
            guard brutto == false else { continue }
            switch buchung.richtung {
            case .einnahme:
                vereinnahmt = vereinnahmt + summe.steuer
            case .ausgabe:
                // The same share the UStVA takes into Kz 66.
                vorsteuer = vorsteuer + UStVA.abziehbar(summe.steuer, privatanteil: buchung.privatanteilProzent)
            }
        }

        var rows = werte.keys.sorted().map { nummer in
            Zeile(
                zeile: nummer,
                bezeichnung: bezeichnung(nummer),
                richtung: nummer < 24 ? .einnahme : .ausgabe,
                betrag: werte[nummer] ?? .null
            )
        }
        if vereinnahmt != .null {
            rows.append(Zeile(
                zeile: zeileVereinnahmteUmsatzsteuer,
                bezeichnung: "Vereinnahmte Umsatzsteuer",
                richtung: .einnahme,
                betrag: vereinnahmt
            ))
        }
        if vorsteuer != .null {
            rows.append(Zeile(
                zeile: zeileGezahlteVorsteuer,
                bezeichnung: "Gezahlte Vorsteuer",
                richtung: .ausgabe,
                betrag: vorsteuer
            ))
        }
        return EUeR(jahr: jahr, zeilen: rows.sorted { $0.zeile < $1.zeile })
    }

    /// What one booking brings into the year: the net and the tax of the
    /// shares of its payments of the year, both before the Privatanteil.
    private static func summe(_ buchung: Buchung, zeitraum: Zeitraum) -> (netto: Cent, steuer: Cent) {
        let zahlungen = buchung.zahlungen.sorted { $0.datum < $1.datum }
        let anteile = Aufteilung.aufteilen(positionen: buchung.positionen, betraege: zahlungen.map(\.betrag))

        var netto = Cent.null
        var steuer = Cent.null
        for (stelle, zahlung) in zahlungen.enumerated() where zeitraum.enthaelt(zahlung.datum) {
            for anteil in anteile[stelle] {
                netto = netto + anteil.netto
                steuer = steuer + anteil.steuer
            }
        }
        return (netto, steuer)
    }

    /// The business part of an amount, rounded to the cent.
    static func ohnePrivatanteil(_ betrag: Cent, prozent: Int) -> Cent {
        guard prozent > 0 else { return betrag }
        var raw = Decimal(betrag.value) * Decimal(100 - prozent) / 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return Cent(NSDecimalNumber(decimal: rounded).int64Value)
    }

    /// The income lines of the form follow the tax treatment, not the kind of
    /// income: a Kleinunternehmer puts all income on line 12, regularly taxed
    /// income goes on 15, tax-free, non-taxable and §13b income on 16. Only
    /// the Umsatzsteuererstattung keeps its own line. Expenses follow the
    /// category.
    static func zeile(_ buchung: Buchung, _ kategorie: Kategorie, profile: Profil) -> Int {
        guard buchung.richtung == .einnahme, kategorie.euerZeile != 18 else { return kategorie.euerZeile }
        if profile.kleinunternehmer {
            return 12
        }
        switch buchung.steuerbehandlung {
        case .reverseCharge, .steuerfrei, .nichtSteuerbar: return 16
        case .inland, .kleinunternehmer, .unklar: return kategorie.euerZeile
        }
    }

    /// The official title of the line, or the categories on it when the form
    /// has no title Pfennig knows.
    private static func bezeichnung(_ zeile: Int) -> String {
        titel[zeile] ?? Kategorie.alle.filter { $0.euerZeile == zeile }.map(\.name).joined(separator: ", ")
    }

    // MARK: - CSV

    /// `Zeile (Anlage EÜR 2026);Bezeichnung;Betrag`, German decimal comma,
    /// UTF-8. The header names the form year, because the line numbers only
    /// mean something with it. The values of the Anlage EÜR are typed into the
    /// form by hand; there is no upload for it.
    public var csv: String {
        var zeilentext = ["Zeile (Anlage EÜR \(EUeR.formularjahr));Bezeichnung;Betrag"]
        for zeile in zeilen {
            zeilentext.append("\(zeile.zeile);\(zeile.bezeichnung);\(EUeR.komma(zeile.betrag))")
        }
        return zeilentext.joined(separator: "\n") + "\n"
    }

    /// `1234,56`, without a thousands separator, so a spreadsheet reads the
    /// column back as a number.
    static func komma(_ betrag: Cent) -> String {
        let vorzeichen = betrag.value < 0 ? "-" : ""
        let betrag = betrag.value.magnitude
        return "\(vorzeichen)\(betrag / 100)," + String(format: "%02d", betrag % 100)
    }
}
