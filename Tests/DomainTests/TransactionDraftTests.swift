@testable import Domain
import Testing

/// The two values the inspector reads straight off a draft: the VAT rate it
/// prints next to "Steuer", and the remainder a new payment defaults to.
@Suite("TransactionDraft derived values")
struct TransactionDraftTests {
    private func draft(
        components: [TaxComponentDraft] = [],
        direction: Direction = .expense,
        transactionType: TransactionType = .invoice,
        netMinor: Int64? = nil,
        taxMinor: Int64? = nil,
        grossMinor: Int64? = nil,
        payments: [PaymentDraft] = []
    ) -> TransactionDraft {
        TransactionDraft(
            businessProfileId: "profile",
            direction: direction,
            transactionType: transactionType,
            netMinor: netMinor,
            taxMinor: taxMinor,
            grossMinor: grossMinor,
            components: components,
            payments: payments
        )
    }

    private func payment(
        _ amountMinor: Int64,
        allocatedMinor: Int64? = nil,
        direction: PaymentDirection = .outflow
    ) -> PaymentDraft {
        PaymentDraft(
            direction: direction,
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

    @Test("A booking without components calculates its rate from tax and net")
    func rateFromAmounts() {
        #expect(draft(netMinor: 10000, taxMinor: 1900).effectiveTaxRateText == "19 %")
        #expect(draft(netMinor: 10000, taxMinor: 700).effectiveTaxRateText == "7 %")
        // Rounded cent amounts still name the plain rate.
        #expect(draft(netMinor: 4197, taxMinor: 798).effectiveTaxRateText == "19 %")
        // Without a net amount, gross minus tax is enough.
        #expect(draft(taxMinor: 1900, grossMinor: 11900).effectiveTaxRateText == "19 %")
        // A credit note with negative amounts names the same rate.
        #expect(draft(netMinor: -10000, taxMinor: -1900).effectiveTaxRateText == "19 %")
        #expect(draft(netMinor: 10000, taxMinor: 0).effectiveTaxRateText == "0 %")
        #expect(draft(netMinor: 10000).effectiveTaxRateText == "0 %")
    }

    @Test("A calculated rate off every German rate reads as mixed")
    func mixedRateFromAmounts() {
        // 8,15 %: a ticket with a 7 % fare and a 19 % reservation.
        #expect(draft(netMinor: 8775, taxMinor: 715).effectiveTaxRateText == "gemischt")
        #expect(draft(netMinor: 10000, taxMinor: 1000).effectiveTaxRateText == "gemischt")
    }

    @Test("A rate within 0,05 points of a German rate is that rate")
    func rateTolerance() {
        #expect(draft(netMinor: 10000, taxMinor: 1905).effectiveTaxRateText == "19 %")
        #expect(draft(netMinor: 10000, taxMinor: 1906).effectiveTaxRateText == "gemischt")
        #expect(draft(netMinor: 10000, taxMinor: 695).effectiveTaxRateText == "7 %")
        #expect(draft(netMinor: 10000, taxMinor: 4).effectiveTaxRateText == "0 %")
        #expect(draft(netMinor: 10000, taxMinor: 6).effectiveTaxRateText == "gemischt")
    }

    @Test("The document's own components beat the calculated rate")
    func componentsWinOverAmounts() {
        let value = draft(
            components: [TaxComponentDraft(kind: .reduced, rate: "7", netMinor: 10000, taxMinor: 700)],
            netMinor: 10000,
            taxMinor: 1900
        )
        #expect(value.effectiveTaxRateText == "7 %")
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

    // MARK: Erstattungen

    @Test("A refund is the opposite-direction payment and counts negatively")
    func refundCountsNegatively() {
        let value = draft(
            grossMinor: 11900,
            payments: [payment(11900), payment(11900, direction: .inflow)]
        )
        #expect(value.netAllocatedMinor == 0)
        #expect(value.openAmountMinor == 11900)
        #expect(value.payments[1].isRefund(of: .expense))
        #expect(value.payments[1].signedAllocated(for: .expense) == -11900)
    }

    @Test("A partial refund leaves the difference settled")
    func partialRefund() {
        let value = draft(
            grossMinor: 11900,
            payments: [payment(11900), payment(1900, direction: .inflow)]
        )
        #expect(value.netAllocatedMinor == 10000)
        #expect(value.openAmountMinor == 1900)
    }

    @Test("Money can only be given back once something was settled")
    func refundNeedsAPayment() {
        #expect(draft(grossMinor: 11900).canRefund == false)
        #expect(draft(grossMinor: 11900, payments: [payment(5000)]).canRefund)
    }

    @Test("On an income transaction the inflow settles and the outflow refunds")
    func incomeDirections() {
        let value = draft(
            direction: .income,
            grossMinor: 11900,
            payments: [payment(11900, direction: .inflow), payment(11900, direction: .outflow)]
        )
        #expect(value.netAllocatedMinor == 0)
        #expect(value.payments[0].isRefund(of: .income) == false)
        #expect(value.payments[1].isRefund(of: .income))
    }

    // MARK: Gutschriften

    @Test("A credit note is open with a negative amount and settled by the opposite direction")
    func creditNoteIsSettledTheOtherWayRound() {
        let value = draft(
            transactionType: .creditNote,
            netMinor: -10000,
            taxMinor: -1900,
            grossMinor: -11900
        )
        #expect(value.isCreditNote)
        #expect(value.openAmountMinor == -11900)
        #expect(value.settlingPaymentDirection == .inflow)
    }

    @Test("A settled credit note has nothing open")
    func settledCreditNote() {
        let value = draft(
            transactionType: .creditNote,
            grossMinor: -11900,
            payments: [payment(11900, direction: .inflow)]
        )
        #expect(value.netAllocatedMinor == -11900)
        #expect(value.openAmountMinor == 0)
        // The settling side does not change once everything is settled; a
        // payment the other way would be giving the credit note back.
        #expect(value.settlingPaymentDirection == .inflow)
    }

    @Test("An overpaid credit note reads as nothing open rather than a positive remainder")
    func overpaidCreditNote() {
        let value = draft(
            transactionType: .creditNote,
            grossMinor: -11900,
            payments: [payment(15000, direction: .inflow)]
        )
        #expect(value.openAmountMinor == 0)
    }
}
