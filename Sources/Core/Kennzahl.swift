import Foundation

/// One Kennzahl of the Umsatzsteuer-Voranmeldung 2026: its number, the title
/// the form prints, and whether it carries a Bemessungsgrundlage in whole
/// euros or a tax amount in euros and cents. `alle` stands in the order of the
/// form, which is the order the values are shown and written in.
///
/// ## Prüfung
///
/// Checked on 2026-09-14 against the official BMF Vordruckmuster USt 1 A 2026,
/// published with the BMF letter of 29 December 2025
/// (GZ III C 3 - S 7344/00039/007/036). Number, column and wording of every
/// Kennzahl below were read off that document.
///
/// Kz 46/47 are one Bemessungsgrundlage and tax pair for suppliers in another
/// EU member state (§13b Abs. 1 UStG), Kz 84/85 the pair for the other §13b
/// cases, among them §13b Abs. 2 Nr. 1, a supplier established outside the EU,
/// which is the third country SaaS case. Kz 66 is domestic input VAT, Kz 67
/// the input VAT out of §13b services. Kz 81, 86 and 87 have no tax column;
/// ELSTER derives their tax from the whole euro base, and so does `zahllast`.
///
/// Also verified on the same form but not reachable from this data model, so
/// they are not in the table: Kz 41 (innergemeinschaftliche Lieferungen),
/// Kz 43 (Ausfuhrlieferungen), Kz 89/93 (innergemeinschaftliche Erwerbe),
/// Kz 61 (Vorsteuer daraus) and Kz 62 (Einfuhrumsatzsteuer). `Steuerbehandlung`
/// has no value that tells any of them apart from a plain steuerfreier or
/// nicht steuerbarer Umsatz.
public struct Kennzahl: Hashable, Sendable {
    public let nummer: Int
    public let titel: String
    public let istBemessung: Bool

    public static let alle: [Kennzahl] = [
        // A. Steuerpflichtige Lieferungen und sonstige Leistungen
        Kennzahl(
            nummer: 81,
            titel: "Steuerpflichtige Umsätze zum Steuersatz von 19 %",
            istBemessung: true
        ),
        Kennzahl(
            nummer: 86,
            titel: "Steuerpflichtige Umsätze zum Steuersatz von 7 %",
            istBemessung: true
        ),
        Kennzahl(
            nummer: 87,
            titel: "Steuerpflichtige Umsätze zum Steuersatz von 0 %",
            istBemessung: true
        ),

        // B. Steuerfreie Lieferungen und sonstige Leistungen
        Kennzahl(
            nummer: 48,
            titel: "Steuerfreie Umsätze ohne Vorsteuerabzug (z. B. § 4 Nummer 8 bis 29 oder § 19 Absatz 1 UStG)",
            istBemessung: true
        ),

        // D. Leistungsempfänger als Steuerschuldner (§ 13b UStG)
        Kennzahl(
            nummer: 46,
            titel: "Sonstige Leistungen eines im übrigen Gemeinschaftsgebiet ansässigen Unternehmers "
                + "(§ 13b Absatz 1 UStG)",
            istBemessung: true
        ),
        Kennzahl(
            nummer: 47,
            titel: "Steuer auf sonstige Leistungen eines im übrigen Gemeinschaftsgebiet ansässigen Unternehmers",
            istBemessung: false
        ),
        Kennzahl(
            nummer: 84,
            titel: "Andere Leistungen (§ 13b Absatz 2 Nummer 1, 2, 4 bis 12 UStG)",
            istBemessung: true
        ),
        Kennzahl(
            nummer: 85,
            titel: "Steuer auf andere Leistungen (§ 13b Absatz 2 Nummer 1, 2, 4 bis 12 UStG)",
            istBemessung: false
        ),

        // E. Ergänzende Angaben zu Umsätzen
        Kennzahl(
            nummer: 21,
            titel: "Nicht steuerbare sonstige Leistungen gemäß § 18b Satz 1 Nummer 2 UStG",
            istBemessung: true
        ),
        Kennzahl(
            nummer: 45,
            titel: "Übrige nicht steuerbare Umsätze (Leistungsort nicht im Inland)",
            istBemessung: true
        ),

        // F. Abziehbare Vorsteuerbeträge
        Kennzahl(
            nummer: 66,
            titel: "Vorsteuerbeträge aus Rechnungen von anderen Unternehmern (§ 15 Absatz 1 Satz 1 Nummer 1 UStG)",
            istBemessung: false
        ),
        Kennzahl(
            nummer: 67,
            titel: "Vorsteuerbeträge aus Leistungen im Sinne des § 13b UStG (§ 15 Absatz 1 Satz 1 Nummer 4 UStG)",
            istBemessung: false
        ),

        // H. Vorauszahlung oder Überschuss
        Kennzahl(
            nummer: 83,
            titel: "Verbleibende Umsatzsteuer-Vorauszahlung / Verbleibender Überschuss",
            istBemessung: false
        )
    ]

    // MARK: - Zuordnung

    /// The line an income belongs on. A domestic rate other than 19, 7 or 0
    /// has no line on the 2026 form and is not reported.
    public static func einnahme(behandlung: Steuerbehandlung, steuersatz: Decimal) -> Int? {
        switch behandlung {
        case .inland:
            switch steuersatz {
            case 19: 81
            case 7: 86
            case 0: 87
            default: nil
            }
        case .kleinunternehmer, .steuerfrei: 48
        case .reverseCharge: 21
        case .nichtSteuerbar: 45
        case .unklar: nil
        }
    }

    /// The §13b pair of an expense. The form splits by where the supplier is
    /// established: Kz 46/47 for another EU member state (§13b Abs. 1), Kz
    /// 84/85 for the rest, among them the third country SaaS case. A missing
    /// country cannot be routed from the facts on file and takes the EU pair,
    /// by far the more common one for this audience; the Prüfregeln already
    /// keep a domestic counterparty out of reverse_charge.
    public static func reverseCharge(land: String?) -> (bemessung: Int, steuer: Int) {
        let kuerzel = land?.uppercased() ?? ""
        guard kuerzel.isEmpty == false else { return (46, 47) }
        return euStaaten.contains(kuerzel) ? (46, 47) : (84, 85)
    }

    /// The member states of the European Union without Germany.
    private static let euStaaten: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IE",
        "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK"
    ]

    // MARK: - Zahllast

    /// The bases without a tax column and the rate ELSTER derives their tax at.
    public static let abgeleiteteSaetze: [Int: Int64] = [81: 19, 86: 7, 87: 0]

    /// The tax Kennzahlen that raise the Zahllast.
    public static let steuerKennzahlen: Set<Int> = [47, 85]

    /// The Vorsteuer Kennzahlen that lower it.
    public static let vorsteuerKennzahlen: Set<Int> = [66, 67]

    /// A Bemessungsgrundlage is entered in whole euros with the cents cut off.
    /// Integer division truncates towards zero, so -1999 becomes -19.
    public static func volleEuro(_ betrag: Cent) -> Int64 {
        betrag.value / 100
    }

    /// The tax ELSTER derives from a base, in cents, and zero for a line that
    /// carries its own tax column.
    public static func abgeleiteteSteuer(nummer: Int, bemessung: Cent) -> Cent {
        guard let satz = abgeleiteteSaetze[nummer] else { return .null }
        return Cent(volleEuro(bemessung) * satz)
    }
}
