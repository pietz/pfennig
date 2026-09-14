import Domain
import Foundation

/// UStVA (Umsatzsteuer-Voranmeldung) 2026 Kennzahlen (spec 16.3): the numbers,
/// their printed titles, and the routing from a bookkeeping treatment to a
/// form line. Pure data plus a small amount of routing logic, versioned by
/// form year.
///
/// ## Verification
///
/// Checked on 2026-09-14 against the **official BMF Vordruckmuster USt 1 A
/// 2026**, published with the BMF letter of 29 December 2025
/// (GZ III C 3 - S 7344/00039/007/036), downloaded from
/// <https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/2025-12-29-vordruckmuster-USt-voranmeldung-2026.pdf>
/// and read as text. Every Kennzahl below carries the form's own Zeile
/// number; `isVerified` is true only for entries whose number, column
/// (Bemessungsgrundlage vs. Steuer) and wording were read off that document.
///
/// Corrections this verification produced against the earlier placeholder
/// table, which had been written before the 2026 form existed:
///
/// - **Kz 66** is domestic input VAT (Zeile 38), not a §13b line. The
///   placeholder routed reverse-charge input VAT here.
/// - **Kz 61** is input VAT from intra-Community acquisitions (Zeile 39). The
///   placeholder used Kz 67 for that.
/// - **Kz 67** is input VAT from §13b services (Zeile 41).
/// - **Kz 46/47** are *one* Bemessungsgrundlage/Steuer pair (Zeile 30), not a
///   19 %/7 % split as the placeholder assumed. The form restricts them to
///   "Sonstige Leistungen nach § 3a Absatz 2 UStG eines im übrigen
///   Gemeinschaftsgebiet ansässigen Unternehmers (§ 13b Absatz 1 UStG)" -
///   that is, **EU** suppliers only.
/// - **Kz 84/85** (Zeile 32) take "Andere Leistungen (§ 13b Absatz 2
///   Nummer 1, 2, 4 bis 12 UStG)". §13b Abs. 2 Nr. 1 - services from an
///   entrepreneur established abroad - is the **third-country** SaaS case, so
///   it belongs here and *not* in Kz 46/47. See `reverseChargeExpense(supplierCountry:)`.
/// - **Kz 89/93** are the intra-Community acquisition bases at 19 %/7 %
///   (Zeilen 25, 26). The placeholder used Kz 41/44, which the form assigns to
///   intra-Community *supplies* on the income side (Zeilen 19, 20).
/// - **Kz 21** is "Nicht steuerbare sonstige Leistungen gemäß § 18b Satz 1
///   Nummer 2 UStG" (Zeile 35) - EU B2B services. The placeholder also routed
///   exports here; exports belong in **Kz 43** (Zeile 22).
///
/// Neither Kz 89/93 nor Kz 81/86 have a Steuer column on the form: ELSTER
/// derives their tax from the whole-euro base. `derivedTaxRatePercent` records
/// that, and the Zahllast (Kz 83) is computed the same way so it matches what
/// the portal shows.
public enum UStVA_2026 {
    public struct Kennzahl: Sendable, Equatable, Identifiable {
        public var id: Int {
            number
        }

        public let number: Int
        /// German title as printed on the 2026 form, shortened where the form
        /// spreads one label over several lines.
        public let title: String
        /// True for a Bemessungsgrundlage (whole euros on the form), false for
        /// a Steuer amount (euros and cents).
        public let isBase: Bool
        /// "Zeile" of the printed form; also the display order.
        public let formLine: Int
        /// True when number, column and wording were read off the official
        /// 2026 Vordruckmuster (see the type documentation).
        public let isVerified: Bool

        public init(number: Int, title: String, isBase: Bool, formLine: Int, isVerified: Bool = true) {
            self.number = number
            self.title = title
            self.isBase = isBase
            self.formLine = formLine
            self.isVerified = isVerified
        }
    }

    /// Every Kennzahl Pfennig can currently fill, in form order.
    public static let all: [Kennzahl] = [
        // A. Steuerpflichtige Lieferungen, sonstige Leistungen und unentgeltliche Wertabgaben
        Kennzahl(number: 81, title: "Steuerpflichtige Umsätze zum Steuersatz von 19 %", isBase: true, formLine: 13),
        Kennzahl(number: 86, title: "Steuerpflichtige Umsätze zum Steuersatz von 7 %", isBase: true, formLine: 14),
        Kennzahl(number: 87, title: "Steuerpflichtige Umsätze zum Steuersatz von 0 %", isBase: true, formLine: 15),

        // B. Steuerfreie Lieferungen, sonstige Leistungen und unentgeltliche Wertabgaben
        Kennzahl(
            number: 41,
            title: "Innergemeinschaftliche Lieferungen an Abnehmer mit Umsatzsteuer-Identifikationsnummer",
            isBase: true,
            formLine: 19
        ),
        Kennzahl(
            number: 43,
            title: "Weitere steuerfreie Umsätze mit Vorsteuerabzug (z. B. Ausfuhrlieferungen)",
            isBase: true,
            formLine: 22
        ),
        Kennzahl(
            number: 48,
            title: "Steuerfreie Umsätze ohne Vorsteuerabzug (z. B. § 4 Nummer 8 bis 29 oder § 19 Absatz 1 UStG)",
            isBase: true,
            formLine: 23
        ),

        // C. Innergemeinschaftliche Erwerbe
        Kennzahl(
            number: 89,
            title: "Steuerpflichtige innergemeinschaftliche Erwerbe zum Steuersatz von 19 %",
            isBase: true,
            formLine: 25
        ),
        Kennzahl(
            number: 93,
            title: "Steuerpflichtige innergemeinschaftliche Erwerbe zum Steuersatz von 7 %",
            isBase: true,
            formLine: 26
        ),

        // D. Leistungsempfänger als Steuerschuldner (§ 13b UStG)
        Kennzahl(
            number: 46,
            title: "Sonstige Leistungen nach § 3a Absatz 2 UStG eines im übrigen Gemeinschaftsgebiet "
                + "ansässigen Unternehmers (§ 13b Absatz 1 UStG)",
            isBase: true,
            formLine: 30
        ),
        Kennzahl(
            number: 47,
            title: "Steuer auf sonstige Leistungen eines im übrigen Gemeinschaftsgebiet ansässigen "
                + "Unternehmers (§ 13b Absatz 1 UStG)",
            isBase: false,
            formLine: 30
        ),
        Kennzahl(
            number: 84,
            title: "Andere Leistungen (§ 13b Absatz 2 Nummer 1, 2, 4 bis 12 UStG)",
            isBase: true,
            formLine: 32
        ),
        Kennzahl(
            number: 85,
            title: "Steuer auf andere Leistungen (§ 13b Absatz 2 Nummer 1, 2, 4 bis 12 UStG)",
            isBase: false,
            formLine: 32
        ),

        // E. Ergänzende Angaben zu Umsätzen
        Kennzahl(
            number: 21,
            title: "Nicht steuerbare sonstige Leistungen gemäß § 18b Satz 1 Nummer 2 UStG",
            isBase: true,
            formLine: 35
        ),
        Kennzahl(
            number: 45,
            title: "Übrige nicht steuerbare Umsätze (Leistungsort nicht im Inland)",
            isBase: true,
            formLine: 36
        ),

        // F. Abziehbare Vorsteuerbeträge
        Kennzahl(
            number: 66,
            title: "Vorsteuerbeträge aus Rechnungen von anderen Unternehmern (§ 15 Absatz 1 Satz 1 Nummer 1 UStG)",
            isBase: false,
            formLine: 38
        ),
        Kennzahl(
            number: 61,
            title: "Vorsteuerbeträge aus dem innergemeinschaftlichen Erwerb von Gegenständen "
                + "(§ 15 Absatz 1 Satz 1 Nummer 3 UStG)",
            isBase: false,
            formLine: 39
        ),
        Kennzahl(
            number: 62,
            title: "Entstandene Einfuhrumsatzsteuer (§ 15 Absatz 1 Satz 1 Nummer 2 UStG)",
            isBase: false,
            formLine: 40
        ),
        Kennzahl(
            number: 67,
            title: "Vorsteuerbeträge aus Leistungen im Sinne des § 13b UStG (§ 15 Absatz 1 Satz 1 Nummer 4 UStG)",
            isBase: false,
            formLine: 41
        ),

        // H. Vorauszahlung/Überschuss
        Kennzahl(
            number: 83,
            title: "Verbleibende Umsatzsteuer-Vorauszahlung / Verbleibender Überschuss",
            isBase: false,
            formLine: 50
        )
    ]

    private static let byNumber: [Int: Kennzahl] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.number, $0) }
    )

    public static func kennzahl(_ number: Int) -> Kennzahl? {
        byNumber[number]
    }

    /// Printed title, or a stable placeholder for a number Pfennig does not
    /// know (which then also reports `isVerified == false`).
    public static func title(_ number: Int) -> String {
        byNumber[number]?.title ?? "Kennzahl \(number)"
    }

    public static func isVerified(_ number: Int) -> Bool {
        byNumber[number]?.isVerified ?? false
    }

    public static func isBase(_ number: Int) -> Bool {
        byNumber[number]?.isBase ?? false
    }

    /// Sort key for displaying lines in the order of the printed form.
    public static func formLine(_ number: Int) -> Int {
        byNumber[number]?.formLine ?? Int.max
    }

    // MARK: - Zahllast arithmetic

    /// Bases that have no Steuer column: ELSTER computes their tax from the
    /// whole-euro base at this rate. Value is a whole percent, so the tax in
    /// cents is `wholeEuros(base) * percent` with no rounding at all.
    public static let derivedTaxRatePercent: [Int: Int64] = [
        81: 19,
        86: 7,
        87: 0,
        89: 19,
        93: 7
    ]

    /// Steuer Kennzahlen that increase the Zahllast.
    public static let outputTaxKennzahlen: Set<Int> = [47, 85]

    /// Vorsteuer Kennzahlen that reduce the Zahllast.
    public static let inputVATKennzahlen: Set<Int> = [66, 61, 62, 67]

    /// Bemessungsgrundlagen are entered in whole euros with the cents cut off.
    /// Integer division already truncates toward zero, so -1999 becomes -19.
    public static func wholeEuros(_ minor: Int64) -> Int64 {
        minor / 100
    }

    /// The tax ELSTER derives for a base Kennzahl, in cents. Zero for lines
    /// that carry their own Steuer column.
    public static func derivedTaxMinor(kennzahl: Int, baseMinor: Int64) -> Int64 {
        guard let percent = derivedTaxRatePercent[kennzahl] else { return 0 }
        return wholeEuros(baseMinor) * percent
    }

    // MARK: - Routing

    /// Income line for a treatment and (for domestic VAT) a rate. Returns
    /// `nil` when the combination has no line on the form, which the caller
    /// turns into an exception rather than silently dropping the amount.
    public static func incomeKennzahl(treatment: TaxTreatment, rate: String?) -> Int? {
        switch treatment {
        case .domesticVAT:
            switch rate {
            case "19": 81
            case "7": 86
            case "0": 87
            default: nil
            }
        case .intraCommunitySupply: 41
        case .export: 43
        case .smallBusiness, .exempt: 48
        case .reverseCharge: 21
        case .nonTaxable: 45
        case .intraCommunityAcquisition, .importVAT, .unknown: nil
        }
    }

    /// §13b expense lines. The 2026 form splits by where the supplier is
    /// established: Kz 46/47 cover §13b Abs. 1 (supplier in another EU member
    /// state), Kz 84/85 cover the other §13b cases including Abs. 2 Nr. 1,
    /// services from a supplier established outside the EU.
    ///
    /// An unknown supplier country cannot be routed reliably; the caller gets
    /// the EU pair (much the more common case for this audience: Irish and
    /// Dutch SaaS vendors) together with a `reverseChargeUnclear` exception.
    public static func reverseChargeExpense(supplierCountry: String?) -> (base: Int, tax: Int) {
        guard let country = supplierCountry?.uppercased(), !country.isEmpty else { return (46, 47) }
        return TaxTreatmentDecider.euMemberStates.contains(country) ? (46, 47) : (84, 85)
    }

    /// True when the supplier country is missing or is Germany, in which case
    /// the §13b line cannot be chosen from the facts on file.
    public static func reverseChargeCountryIsUnclear(supplierCountry: String?) -> Bool {
        guard let country = supplierCountry?.uppercased(), !country.isEmpty else { return true }
        return country == "DE"
    }

    /// Intra-Community acquisition base line for a rate; defaults to the
    /// standard rate, which is what `SelfAssessedVAT` computes.
    public static func intraCommunityAcquisitionBase(rate: String?) -> Int {
        rate == "7" ? 93 : 89
    }

    /// Statutory percent behind an acquisition base line.
    public static func ratePercent(forBase kennzahl: Int) -> Decimal {
        Decimal(derivedTaxRatePercent[kennzahl] ?? 0)
    }
}
