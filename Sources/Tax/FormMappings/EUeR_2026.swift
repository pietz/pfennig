import Domain

/// Anlage EÜR 2026 line mapping (spec 16.3): category ID → EÜR line number.
/// Pure data, versioned by form year.
///
/// **NEEDS VERIFICATION**: the official 2026 "Anlage EÜR" form did not exist
/// at the time this table was written. Line numbers below are placeholders
/// carried over from the 2023/2024 form layout and are likely to shift,
/// especially for the asset-candidate categories (which V1 excludes from
/// operating-expense totals per spec 5.6 and lists separately rather than
/// mapping to a numbered EÜR line at all).
public enum EUeR_2026 {
    /// EÜR line number per stable category ID. NEEDS VERIFICATION (see above).
    /// Categories of kind `assetCandidate` intentionally have no entry: spec
    /// 5.6 excludes them from EÜR operating-expense totals.
    public static let lines: [String: Int] = [
        // Income (spec 17.4).
        "revenue_services": 11,
        "revenue_goods": 14,
        "revenue_licenses": 15,
        "other_income": 17,
        "vat_refund": 16,
        "interest_income": 21,

        // Expenses.
        "software_subscriptions": 43,
        "hosting_cloud": 43,
        "telecom": 43,
        "office_supplies": 45,
        "office_rent": 41,
        "hardware_small": 47,
        "advertising": 51,
        "professional_services": 39,
        "contractors_freelancers": 27,
        "travel_transport": 55,
        "travel_lodging": 55,
        "meals_entertainment": 56,
        "training_books": 48,
        "insurance_business": 44,
        "bank_fees": 50,
        "payment_provider_fees": 50,
        "memberships": 49,
        "postage_shipping": 46,
        "vat_payment": 60,
        "other_expense": 62,
    ]

    public static func line(forCategoryID id: String) -> Int? {
        lines[id]
    }
}
