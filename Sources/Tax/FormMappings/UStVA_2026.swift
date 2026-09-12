import Domain

/// UStVA (Umsatzsteuer-Voranmeldung) 2026 Kennzahlen mapping (spec 16.3):
/// treatment × direction × rate → Kennzahl. Pure data, versioned by form
/// year - no logic beyond a dictionary lookup lives here.
///
/// **NEEDS VERIFICATION**: the official 2026 UStVA form did not exist at the
/// time this table was written. The Kennzahlen below reflect the historically
/// stable numbering used on the 2021-2025 forms (81/86 domestic sales, 66
/// input VAT, 46/47 §13b, 67 intra-Community acquisition input VAT, 41/44
/// intra-Community acquisition base, 21 non-taxable exports) and must be
/// checked against the BMF's published 2026 form before this is relied on
/// for an actual filing.
public enum UStVA_2026 {
    public struct Key: Hashable, Sendable {
        public let treatment: TaxTreatment
        public let direction: Direction
        /// Decimal rate string ("19", "7", "0"), or "" for a rate-independent line.
        public let rate: String

        public init(treatment: TaxTreatment, direction: Direction, rate: String) {
            self.treatment = treatment
            self.direction = direction
            self.rate = rate
        }
    }

    /// Kennzahl per (treatment, direction, rate). NEEDS VERIFICATION (see above).
    public static let kennzahlen: [Key: Int] = [
        // Domestic output VAT (income), §13 UStG.
        Key(treatment: .domesticVAT, direction: .income, rate: "19"): 81,
        Key(treatment: .domesticVAT, direction: .income, rate: "7"): 86,

        // Deductible input VAT, domestic invoices (expense), §15 UStG.
        Key(treatment: .domesticVAT, direction: .expense, rate: "19"): 66,
        Key(treatment: .domesticVAT, direction: .expense, rate: "7"): 66,

        // §13b reverse charge received (expense): tax base by rate.
        Key(treatment: .reverseCharge, direction: .expense, rate: "19"): 47,
        Key(treatment: .reverseCharge, direction: .expense, rate: "7"): 46,
        // Deductible input VAT from the self-assessed §13b amount.
        Key(treatment: .reverseCharge, direction: .expense, rate: ""): 66,

        // Intra-Community acquisition (expense): tax base by rate.
        Key(treatment: .intraCommunityAcquisition, direction: .expense, rate: "19"): 41,
        Key(treatment: .intraCommunityAcquisition, direction: .expense, rate: "7"): 44,
        // Deductible input VAT from the intra-Community acquisition.
        Key(treatment: .intraCommunityAcquisition, direction: .expense, rate: ""): 67,

        // Reverse-charge income (EU B2B service, no VAT) - reported as other
        // non-taxable turnover pending ZM reporting (spec 5.4).
        Key(treatment: .reverseCharge, direction: .income, rate: "0"): 21,
        // Export (income, third country, no VAT).
        Key(treatment: .export, direction: .income, rate: "0"): 21,
    ]

    public static func kennzahl(treatment: TaxTreatment, direction: Direction, rate: String) -> Int? {
        kennzahlen[Key(treatment: treatment, direction: direction, rate: rate)]
    }
}
