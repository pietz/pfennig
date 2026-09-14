import Foundation

/// The yearly values of the Anlage EÜR: one line of the form per category
/// group, with the amounts of the year.
///
/// Zufluss and Abfluss, §11 EStG, the same way the UStVA counts: only what was
/// paid in the year counts, a partial payment with its proportional share of
/// the positions, a refund against it. The Belegdatum decides nothing here.
///
/// The Umsatzsteuer is a transit item and stays out of the lines as long as it
/// is deductible: a regular business books the net amounts, a Kleinunternehmer,
/// who deducts no Vorsteuer, books the gross ones. The Privatanteil of a
/// booking is taken off its own amount before it reaches the line.
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

    public static func berechnen(_ buchungen: [Buchung], jahr: Int, profil: Profil) -> EUeR {
        let zeitraum = Zeitraum(jahr: jahr, einteilung: .jahr)
        var werte: [Int: Cent] = [:]
        for buchung in buchungen where buchung.art != .ignoriert {
            guard let schluessel = buchung.kategorie,
                  let kategorie = Kategorie.alle.first(where: { $0.schluessel == schluessel })
            else { continue }
            let betrag = betrag(buchung, zeitraum: zeitraum, brutto: profil.kleinunternehmer)
            guard betrag != .null else { continue }
            werte[kategorie.euerZeile, default: .null] = werte[kategorie.euerZeile, default: .null] + betrag
        }

        let zeilen = werte.keys.sorted().map { nummer in
            Zeile(
                zeile: nummer,
                bezeichnung: bezeichnung(nummer),
                richtung: Kategorie.alle.first { $0.euerZeile == nummer }?.richtung ?? .ausgabe,
                betrag: werte[nummer] ?? .null
            )
        }
        return EUeR(jahr: jahr, zeilen: zeilen)
    }

    /// What one booking contributes to its line: the shares of the payments of
    /// the year, without the private part.
    private static func betrag(_ buchung: Buchung, zeitraum: Zeitraum, brutto: Bool) -> Cent {
        let zahlungen = buchung.zahlungen
            .sorted { ($0.datum, $0.id ?? 0) < ($1.datum, $1.id ?? 0) }
            .map { (datum: $0.datum, betrag: $0.richtung == buchung.richtung ? $0.betrag : -$0.betrag) }
        let anteile = Aufteilung.aufteilen(positionen: buchung.positionen, betraege: zahlungen.map(\.betrag))

        var summe = Cent.null
        for (stelle, zahlung) in zahlungen.enumerated() where zeitraum.enthaelt(zahlung.datum) {
            summe = anteile[stelle].reduce(summe) { $0 + $1.netto + (brutto ? $1.steuer : .null) }
        }
        return ohnePrivatanteil(summe, prozent: buchung.privatanteilProzent)
    }

    /// The business part of an amount, rounded to the cent.
    static func ohnePrivatanteil(_ betrag: Cent, prozent: Int) -> Cent {
        guard prozent > 0 else { return betrag }
        var roh = Decimal(betrag.wert) * Decimal(100 - prozent) / 100
        var gerundet = Decimal()
        NSDecimalRound(&gerundet, &roh, 0, .plain)
        return Cent(NSDecimalNumber(decimal: gerundet).int64Value)
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
        let vorzeichen = betrag.wert < 0 ? "-" : ""
        let betrag = betrag.wert.magnitude
        return "\(vorzeichen)\(betrag / 100)," + String(format: "%02d", betrag % 100)
    }
}
