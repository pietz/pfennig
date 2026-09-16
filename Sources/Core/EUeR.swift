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
/// The Privatanteil of a booking is taken off its own amount before it reaches
/// the line, and off its Vorsteuer the same way. The vereinnahmte Umsatzsteuer
/// is owed in full, so no Privatanteil is taken off it.
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

    /// The two lines that no category feeds.
    ///
    /// **Ungeprüft** like the numbers on `Kategorie.euerZeile`: they take the
    /// place the official form gives them, the vereinnahmte Umsatzsteuer after
    /// the Betriebseinnahmen and the gezahlte Vorsteuer right before the
    /// Umsatzsteuerzahlung, with the numbers that are still free in the
    /// 2023/2024 placeholder table.
    public static let zeileVereinnahmteUmsatzsteuer = 18
    public static let zeileGezahlteVorsteuer = 59

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
            let betrag = ohnePrivatanteil(
                summe.netto + (brutto ? summe.steuer : .null), prozent: buchung.privatanteilProzent
            )
            if betrag != .null {
                werte[kategorie.euerZeile, default: .null] = werte[kategorie.euerZeile, default: .null] + betrag
            }
            guard brutto == false else { continue }
            switch buchung.richtung {
            case .einnahme:
                vereinnahmt = vereinnahmt + summe.steuer
            case .ausgabe:
                vorsteuer = vorsteuer + ohnePrivatanteil(summe.steuer, prozent: buchung.privatanteilProzent)
            }
        }

        var rows = werte.keys.sorted().map { nummer in
            Zeile(
                zeile: nummer,
                bezeichnung: bezeichnung(nummer),
                richtung: Kategorie.alle.first { $0.euerZeile == nummer }?.richtung ?? .ausgabe,
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

    /// The categories that share a line, in the order of the list. The line
    /// titles of the official form are not part of Pfennig, so the categories
    /// name the line.
    private static func bezeichnung(_ zeile: Int) -> String {
        Kategorie.alle.filter { $0.euerZeile == zeile }.map(\.name).joined(separator: ", ")
    }

    // MARK: - CSV

    /// `Zeile;Bezeichnung;Betrag`, German decimal comma, UTF-8. The values of
    /// the Anlage EÜR are typed into the form by hand; there is no upload for
    /// it.
    public var csv: String {
        var zeilentext = ["Zeile;Bezeichnung;Betrag"]
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
