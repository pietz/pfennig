@testable import Domain
import Testing

/// The two values the inspector reads straight off a draft: the VAT rate it
/// prints next to "Steuer", and the remainder a new payment defaults to.
@Suite("TransactionDraft derived values")
struct TransactionDraftTests {
    private func draft(
        components: [TaxComponentDraft] = [],
        grossMinor: Int64? = nil,
        payments: [PaymentDraft] = []
    ) -> TransactionDraft {
        TransactionDraft(
            businessProfileId: "profile",
            grossMinor: grossMinor,
            components: components,
            payments: payments
        )
    }

    private func payment(_ amountMinor: Int64, allocatedMinor: Int64? = nil) -> PaymentDraft {
        PaymentDraft(
            direction: .outflow,
            paymentDate: LocalDate(year: 2026, month: 9, day: 14),
            amountMinor: amountMinor,
            currency: .eur,
            allocatedMinor: allocatedMinor
        )
    }

    // MARK: Steuersatz

    @Test("A single rate reads as one percentage")
    func singleRate() {
        let value = draft(components: [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 10000, taxMinor: 1900)])
        #expect(value.effectiveTaxRateText == "19 %")
    }

    @Test("Mixed rates read from low to high, each with its own sign")
    func mixedRates() {
        let value = draft(components: [
            TaxComponentDraft(kind: .standard, rate: "19", netMinor: 1000, taxMinor: 190),
            TaxComponentDraft(kind: .reduced, rate: "7", netMinor: 1112, taxMinor: 78)
        ])
        #expect(value.effectiveTaxRateText == "7 % / 19 %")
    }

    @Test("The same rate twice is named once")
    func repeatedRate() {
        let value = draft(components: [
            TaxComponentDraft(kind: .standard, rate: "19", netMinor: 1000, taxMinor: 190),
            TaxComponentDraft(kind: .standard, rate: "19", netMinor: 2000, taxMinor: 380)
        ])
        #expect(value.effectiveTaxRateText == "19 %")
    }

    @Test("A decimal rate is written the German way")
    func decimalRate() {
        let value = draft(components: [TaxComponentDraft(kind: .other, rate: "10.7", netMinor: 1000, taxMinor: 107)])
        #expect(value.effectiveTaxRateText == "10,7 %")
    }

    @Test("Without a rate the document is untaxed")
    func noRate() {
        #expect(draft().effectiveTaxRateText == "0 %")
        #expect(draft(components: [TaxComponentDraft(kind: .zero, rate: nil)]).effectiveTaxRateText == "0 %")
        #expect(draft(components: [TaxComponentDraft(kind: .zero, rate: " ")]).effectiveTaxRateText == "0 %")
        #expect(
            draft(components: [TaxComponentDraft(kind: .reverseChargeNote, rate: "0")])
                .effectiveTaxRateText == "0 %"
        )
    }

    // MARK: Offener Restbetrag

    @Test("Without a payment the whole gross amount is open")
    func nothingPaid() {
        #expect(draft(grossMinor: 11900).openAmountMinor == 11900)
    }

    @Test("A partial payment leaves its remainder open")
    func partiallyPaid() {
        let value = draft(grossMinor: 238_000, payments: [payment(100_000)])
        #expect(value.openAmountMinor == 138_000)
    }

    @Test("Only the share allocated to this transaction counts")
    func combinedPayment() {
        let value = draft(grossMinor: 11900, payments: [payment(20000, allocatedMinor: 5000)])
        #expect(value.openAmountMinor == 6900)
    }

    @Test("A fully paid or overpaid transaction has nothing open")
    func fullyPaid() {
        #expect(draft(grossMinor: 11900, payments: [payment(11900)]).openAmountMinor == 0)
        #expect(draft(grossMinor: 11900, payments: [payment(15000)]).openAmountMinor == 0)
    }

    @Test("Without a gross amount nothing is open")
    func withoutGross() {
        #expect(draft().openAmountMinor == 0)
    }
}
