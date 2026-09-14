import Domain
@testable import Validation

/// A minimal `TransactionSnapshot` that passes every rule in
/// `TransactionValidator` (spec 14.1/14.2). Individual tests mutate exactly
/// one field to exercise a single rule.
enum Fixture {
    static func eur(_ decimal: String) -> Money {
        try! Money.fromDecimalString(decimal, currency: .eur)
    }

    static func passingSnapshot() -> TransactionSnapshot {
        TransactionSnapshot(
            invoiceDate: LocalDate(year: 2026, month: 3, day: 10),
            servicePeriodStart: LocalDate(year: 2026, month: 3, day: 10),
            net: eur("100.00"),
            tax: eur("19.00"),
            gross: eur("119.00"),
            taxComponents: [
                TaxComponentSnapshot(rate: "19", net: eur("100.00"), tax: eur("19.00"), kind: .standard)
            ],
            allocations: [
                AllocationSnapshot(categoryID: "software_subscriptions", amount: eur("100.00"), assetFlag: false)
            ],
            allocationExpectedTotal: eur("100.00"),
            treatment: .domesticVAT,
            direction: .expense,
            isCounterpartyDomestic: true,
            isCounterpartyEUMember: false,
            customerVATIDPresent: false,
            isKleinbetrag: false,
            invoiceNumberPresent: true
        )
    }
}
