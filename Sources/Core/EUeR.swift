import Foundation

/// The yearly values of the Anlage EÜR: one line of the form per category
/// group, with the amounts of the year.
///
/// Zufluss and Abfluss, §11 EStG: ordinary income and expenses follow payments,
/// including partial payments and refunds. Assets follow their AfA schedule.
///
/// The Umsatzsteuer follows the method of the official form, not the net
/// shortcut. A regularly taxed business books the net amounts on the category
/// lines and adds the two computed lines the form asks for: the vereinnahmte
/// Umsatzsteuer of the year as an income line and the gezahlte Vorsteuer of
/// the year as an expense line. Together with the two category lines for the
/// payments to and refunds from the Finanzamt they make the four VAT lines of
/// the form, and the Gewinn comes out right. A Kleinunternehmer deducts no
/// Vorsteuer, books gross on the category lines and has no VAT lines; the
/// tax payments to the Finanzamt stay on their own category line.
///
/// Only deductible invoice VAT reaches line 58; non-deductible invoice VAT
/// stays with the expense. Recipient tax (§13b or acquisition) is not paid to
/// the supplier and creates no additional payment or input-VAT expense here.
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
        /// The form takes the nicht abziehbaren 30 Prozent der Bewirtung in
        /// its own column of line 64, the Gewinn does not take them at all.
        public var nichtAbziehbar = false

        /// Line 64 stands twice in the result, so its number alone does not
        /// name a row.
        public var id: String {
            "\(zeile) \(bezeichnung)"
        }
    }

    /// The year of the official form the line numbers belong to, BMF-Schreiben
    /// vom 01.09.2026.
    public static let formularjahr = 2026

    /// The two lines that no category feeds, Anlage EÜR 2026.
    public static let zeileVereinnahmteUmsatzsteuer = 17
    public static let zeileGezahlteVorsteuer = 58

    /// The line every Anlagegut goes on instead of its category line.
    static let zeileAfA = 34

    /// The two lines Pfennig fills that have a nicht abziehbare and an
    /// abziehbare column, §4 Abs. 5 Satz 1 Nr. 1 and 2 EStG.
    static let zeileGeschenke = 63
    static let zeileBewirtung = 64

    /// The line titles of the Anlage EÜR 2026 for the lines Pfennig fills,
    /// shortened to what fits a CSV cell.
    static let titel: [Int: String] = [
        12: "Betriebseinnahmen als umsatzsteuerlicher Kleinunternehmer",
        15: "Umsatzsteuerpflichtige Betriebseinnahmen",
        16: "Umsatzsteuerfreie, nicht steuerbare und § 13b-Betriebseinnahmen",
        17: "Vereinnahmte Umsatzsteuer",
        18: "Vom Finanzamt erstattete Umsatzsteuer",
        29: "Waren, Rohstoffe und Hilfsstoffe",
        30: "Bezogene Fremdleistungen",
        34: "AfA auf bewegliche Wirtschaftsgüter",
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
        63: "Geschenke",
        64: "Bewirtungsaufwendungen",
        71: "Sonstige tatsächliche Fahrtkosten"
    ]

    public let jahr: Int
    public let zeilen: [Zeile]
    /// The Anlagegüter still in the business at the end of the year; they
    /// fill the second block of the CSV, the Anlage AVEÜR.
    public let anlagen: [Buchung]
    /// Whether the Anschaffungskosten count gross, which is the Kleinunternehmer.
    let brutto: Bool

    public var einnahmen: Cent {
        zeilen.filter { $0.richtung == .einnahme }.reduce(Cent.null) { $0 + $1.betrag }
    }

    public var ausgaben: Cent {
        zeilen.filter { $0.richtung == .ausgabe && $0.nichtAbziehbar == false }
            .reduce(Cent.null) { $0 + $1.betrag }
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
        var geschenkeNichtAbziehbar = Cent.null

        for buchung in buchungen where buchung.art != .ignoriert {
            let kategorie = buchung.kategorie.flatMap { key in
                Kategorie.alle.first(where: { $0.schluessel == key })
            }
            guard kategorie != nil
                || (buchung.richtung == .ausgabe && buchung.nutzungsdauerJahre != nil)
            else { continue }
            let summe = summe(buchung, zeitraum: zeitraum)
            let betrag: Cent
            switch buchung.richtung {
            case .einnahme:
                // Income is earned in full; a Privatanteil only shortens expenses.
                betrag = summe.netto + (brutto ? summe.steuer : .null)
                if brutto == false {
                    vereinnahmt = vereinnahmt + summe.steuer
                }
            case .ausgabe:
                let prozent = buchung.privatanteilProzent
                // The same share the UStVA takes into Kz 66, and only where
                // the supplier charged German tax the business actually paid.
                let abziehbar = brutto || buchung.steuerbehandlung != .inland || vorsteuerAusgeschlossen(buchung)
                    ? Cent.null
                    : ohnePrivatanteil(summe.steuer, prozent: prozent)
                // The business share of net and tax, minus what line 58 takes:
                // what stays here is the tax that §15 UStG does not give back.
                let betrieblich = ohnePrivatanteil(summe.netto, prozent: prozent)
                    + ohnePrivatanteil(summe.steuer, prozent: prozent) - abziehbar
                // An Anlagegut is no expense of the year it was paid in; it
                // brings the AfA of the year instead, §4 Abs. 3 Satz 3 EStG.
                // Its Vorsteuer stays untouched and follows the payment.
                betrag = buchung.nutzungsdauerJahre == nil
                    ? betrieblich
                    : AfA.betrag(buchung, jahr: jahr, brutto: brutto)
                vorsteuer = vorsteuer + abziehbar
            }
            if betrag != .null {
                let zeilenummer = kategorie.map { EUeR.zeile(buchung, $0, profile: profile) } ?? zeileAfA
                if zeilenummer == zeileGeschenke, geschenkAbziehbar(buchung, brutto: brutto) == false {
                    geschenkeNichtAbziehbar = geschenkeNichtAbziehbar + betrag
                } else {
                    werte[zeilenummer, default: .null] = werte[zeilenummer, default: .null] + betrag
                }
            }
        }

        var rows = werte.keys.sorted().flatMap { nummer in
            zeilen(nummer, betrag: werte[nummer] ?? .null)
        }
        if geschenkeNichtAbziehbar != .null {
            rows.append(Zeile(
                zeile: zeileGeschenke,
                bezeichnung: "\(bezeichnung(zeileGeschenke)), nicht abziehbar",
                richtung: .ausgabe,
                betrag: geschenkeNichtAbziehbar,
                nichtAbziehbar: true
            ))
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
        // The form prints the nicht abziehbare column of lines 63 and 64 first, and
        // Swift does not promise a stable sort, so the order is part of the key.
        return EUeR(
            jahr: jahr,
            zeilen: rows.sorted {
                ($0.zeile, $0.nichtAbziehbar ? 0 : 1) < ($1.zeile, $1.nichtAbziehbar ? 0 : 1)
            },
            anlagen: anlagen(buchungen, jahr: jahr, brutto: brutto),
            brutto: brutto
        )
    }

    /// The Anlagegüter the Anlage AVEÜR of the year lists: everything bought
    /// in the year or earlier that still had a Buchwert when the year began.
    private static func anlagen(_ buchungen: [Buchung], jahr: Int, brutto: Bool) -> [Buchung] {
        buchungen.filter { buchung in
            guard buchung.art != .ignoriert, buchung.nutzungsdauerJahre != nil, buchung.datum.jahr <= jahr
            else { return false }
            return buchung.datum.jahr == jahr
                || AfA.restbuchwert(buchung, endeJahr: jahr - 1, brutto: brutto) > .null
        }
    }

    /// The rows one line of the form gets: one, except for the Bewirtung,
    /// which is 70 Prozent abziehbar and 30 Prozent nicht abziehbar, §4 Abs. 5
    /// Satz 1 Nr. 2 EStG. The abziehbare share is rounded and the rest is the
    /// remainder, so both columns together stay the full amount.
    private static func zeilen(_ nummer: Int, betrag: Cent) -> [Zeile] {
        let richtung: Richtung = nummer < 24 ? .einnahme : .ausgabe
        if nummer == zeileGeschenke {
            return [Zeile(
                zeile: nummer,
                bezeichnung: "\(bezeichnung(nummer)), abziehbar",
                richtung: richtung,
                betrag: betrag
            )]
        }
        guard nummer == zeileBewirtung else {
            return [Zeile(zeile: nummer, bezeichnung: bezeichnung(nummer), richtung: richtung, betrag: betrag)]
        }
        let abziehbar = ohnePrivatanteil(betrag, prozent: 30)
        return [
            Zeile(
                zeile: nummer,
                bezeichnung: "\(bezeichnung(nummer)), nicht abziehbar (30 %)",
                richtung: richtung,
                betrag: betrag - abziehbar,
                nichtAbziehbar: true
            ),
            Zeile(
                zeile: nummer,
                bezeichnung: "\(bezeichnung(nummer)), abziehbar (70 %)",
                richtung: richtung,
                betrag: abziehbar
            )
        ]
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

    /// A gift to someone who is not an employee is deductible only while it
    /// costs no more than 50 Euro, §4 Abs. 5 Satz 1 Nr. 1 EStG, net when the
    /// business deducts Vorsteuer and gross otherwise. The limit holds per
    /// recipient and year; Pfennig takes one booking as one recipient, and
    /// several gifts on one invoice or to one person need a manual check.
    static func geschenkAbziehbar(_ buchung: Buchung, brutto: Bool) -> Bool {
        let kosten = buchung.positionen.reduce(Cent.null) { $0 + $1.netto + (brutto ? $1.steuer : .null) }
        return kosten <= Cent(5000)
    }

    /// The Vorsteuer of a gift that is not deductible is not deductible
    /// either, §15 Abs. 1a UStG.
    static func vorsteuerAusgeschlossen(_ buchung: Buchung) -> Bool {
        buchung.richtung == .ausgabe && buchung.kategorie == "geschenke"
            && geschenkAbziehbar(buchung, brutto: false) == false
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
        if buchung.nutzungsdauerJahre != nil {
            return zeileAfA
        }
        guard buchung.richtung == .einnahme, kategorie.euerZeile != 18 else { return kategorie.euerZeile }
        if profile.kleinunternehmer {
            return 12
        }
        switch buchung.steuerbehandlung {
        case .reverseCharge, .steuerfrei, .nichtSteuerbar: return 16
        case .inland, .kleinunternehmer, .innergemeinschaftlicherErwerb, nil: return kategorie.euerZeile
        }
    }

    /// The official title of the line, or the categories on it when the form
    /// has no title Pfennig knows.
    private static func bezeichnung(_ zeile: Int) -> String {
        titel[zeile] ?? Kategorie.alle.filter { $0.euerZeile == zeile }.map(\.name).joined(separator: ", ")
    }

    // MARK: - CSV

    /// `"Zeile (Anlage EÜR 2026)";"Bezeichnung";"Betrag"`, German decimal
    /// comma, UTF-8, every text cell in double quotes. The header names the
    /// form year, because the line numbers only mean something with it. The
    /// values of the Anlage EÜR are typed into the form by hand; there is no
    /// upload for it.
    public var csv: String {
        var zeilentext = [["Zeile (Anlage EÜR \(EUeR.formularjahr))", "Bezeichnung", "Betrag"]
            .map(EUeR.text)
            .joined(separator: ";")]
        for zeile in zeilen {
            zeilentext.append("\(zeile.zeile);\(EUeR.text(zeile.bezeichnung));\(EUeR.komma(zeile.betrag))")
        }
        if anlagen.isEmpty == false {
            zeilentext += ["", EUeR.text("Anlage AVEÜR \(EUeR.formularjahr), Büroausstattung")] + anlageverzeichnis
        }
        return zeilentext.joined(separator: "\n") + "\n"
    }

    /// The second block: the values of the group Büroausstattung for the
    /// Anlage AVEÜR, and under them the list of the single Anlagegüter for the
    /// user's own records.
    private var anlageverzeichnis: [String] {
        let afa = addiert { AfA.betrag($0, jahr: jahr, brutto: brutto) }
        let werte: [(Int, String, Cent)] = [
            (48, "Anschaffungs-/Herstellungskosten", addiert { AfA.anschaffungskosten($0, brutto: brutto) }),
            (49, "Buchwert zu Beginn des Jahres", addiert {
                $0.datum.jahr < jahr ? AfA.restbuchwert($0, endeJahr: jahr - 1, brutto: brutto) : .null
            }),
            (50, "Zugänge", addiert { $0.datum.jahr == jahr ? AfA.anschaffungskosten($0, brutto: brutto) : .null }),
            (51, "Sonderabschreibungen", .null),
            (52, "AfA", afa),
            (53, "Abgänge", .null),
            (54, "Buchwert am Ende des Jahres", addiert { AfA.restbuchwert($0, endeJahr: jahr, brutto: brutto) }),
            (63, "Summe der AfA", afa)
        ]
        return werte.map { "\($0.0);\(EUeR.text($0.1));\(EUeR.komma($0.2))" }
            + ["", ["Anlagegut", "Anschaffung", "Anschaffungskosten", "AfA \(jahr)", "Restbuchwert"]
                .map(EUeR.text)
                .joined(separator: ";")]
            + anlagen.map { anlage in
                [
                    EUeR.text(anlage.titel),
                    anlage.datum.formatted,
                    EUeR.komma(AfA.anschaffungskosten(anlage, brutto: brutto)),
                    EUeR.komma(AfA.betrag(anlage, jahr: jahr, brutto: brutto)),
                    EUeR.komma(AfA.restbuchwert(anlage, endeJahr: jahr, brutto: brutto))
                ]
                .joined(separator: ";")
            }
            + ["", EUeR.text("""
            Nicht abgebildet: Fahrzeuge, Gebäude und Grundstücke, immaterielle Wirtschaftsgüter und Software, \
            Verkauf und Privatentnahme eines Anlageguts, degressive AfA, Sonderabschreibung nach §7g, \
            Sammelposten und nachträgliche Anschaffungskosten.
            """)]
    }

    /// A sum over the Anlagegüter of the year.
    private func addiert(_ wert: (Buchung) -> Cent) -> Cent {
        anlagen.reduce(Cent.null) { $0 + wert($1) }
    }

    /// A text cell of the CSV: in double quotes, an embedded quote doubled,
    /// so a semicolon or newline in a title cannot shift columns or add rows.
    /// Numbers and dates stay unquoted.
    static func text(_ wert: String) -> String {
        "\"\(wert.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// `1234,56`, without a thousands separator, so a spreadsheet reads the
    /// column back as a number.
    static func komma(_ betrag: Cent) -> String {
        let vorzeichen = betrag.value < 0 ? "-" : ""
        let betrag = betrag.value.magnitude
        return "\(vorzeichen)\(betrag / 100)," + String(format: "%02d", betrag % 100)
    }
}
