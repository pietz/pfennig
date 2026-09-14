import Domain
@testable import Validation
import Testing

@Suite("TransactionValidator - baseline")
struct TransactionValidatorBaselineTests {
    @Test("A well-formed snapshot has no hard or soft issues")
    func passingSnapshotHasNoIssues() {
        let result = TransactionValidator.validate(Fixture.passingSnapshot())
        #expect(result.hard.isEmpty)
        #expect(result.soft.isEmpty)
        #expect(result.isValid)
    }
}

@Suite("TransactionValidator - hard rules (spec 14.1)")
struct TransactionValidatorHardRuleTests {
    @Test("CURRENCY_INVALID: a raw currency code that failed parsing is a hard issue")
    func currencyInvalid() {
        var passing = Fixture.passingSnapshot()
        passing.unparseableCurrencyCode = nil
        #expect(TransactionValidator.validate(passing).hard.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.unparseableCurrencyCode = "XX"
        let result = TransactionValidator.validate(failing)
        #expect(result.hard.contains { $0.code == .currencyInvalid })
    }

    @Test("DATE_IMPOSSIBLE: a raw date string that failed parsing is a hard issue")
    func dateImpossible() {
        var passing = Fixture.passingSnapshot()
        passing.unparseableDateFields = []
        #expect(TransactionValidator.validate(passing).hard.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.unparseableDateFields = ["invoiceDate"]
        let result = TransactionValidator.validate(failing)
        #expect(result.hard.contains { $0.code == .dateImpossible })
    }

    @Test("SERVICE_PERIOD_INVERTED: end before start is a hard issue")
    func servicePeriodInverted() {
        var passing = Fixture.passingSnapshot()
        passing.servicePeriodStart = LocalDate(year: 2026, month: 3, day: 1)
        passing.servicePeriodEnd = LocalDate(year: 2026, month: 3, day: 31)
        #expect(TransactionValidator.validate(passing).hard.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.servicePeriodStart = LocalDate(year: 2026, month: 3, day: 31)
        failing.servicePeriodEnd = LocalDate(year: 2026, month: 3, day: 1)
        let result = TransactionValidator.validate(failing)
        #expect(result.hard.contains { $0.code == .servicePeriodInverted })
    }

    @Test("TAX_COMPONENT_NET_MISMATCH: component net sum differing beyond tolerance is a hard issue")
    func taxComponentNetMismatch() {
        #expect(TransactionValidator.validate(Fixture.passingSnapshot()).hard.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.taxComponents = [TaxComponentSnapshot(rate: "19", net: Fixture.eur("90.00"), tax: Fixture.eur("19.00"), kind: .standard)]
        let result = TransactionValidator.validate(failing)
        let issue = result.hard.first { $0.code == .taxComponentNetMismatch }
        #expect(issue != nil)
        #expect(issue?.isOverridable == false) // 10 EUR deviation, over the 1 EUR override ceiling
    }

    @Test("TAX_COMPONENT_NET_MISMATCH within 1 EUR is overridable")
    func taxComponentNetMismatchOverridable() {
        var failing = Fixture.passingSnapshot()
        failing.taxComponents = [TaxComponentSnapshot(rate: "19", net: Fixture.eur("99.50"), tax: Fixture.eur("19.00"), kind: .standard)]
        let issue = TransactionValidator.validate(failing).hard.first { $0.code == .taxComponentNetMismatch }
        #expect(issue?.isOverridable == true)
    }

    @Test("TAX_COMPONENT_TAX_MISMATCH: component tax sum differing beyond tolerance is a hard issue")
    func taxComponentTaxMismatch() {
        var failing = Fixture.passingSnapshot()
        failing.taxComponents = [TaxComponentSnapshot(rate: "19", net: Fixture.eur("100.00"), tax: Fixture.eur("10.00"), kind: .standard)]
        let result = TransactionValidator.validate(failing)
        #expect(result.hard.contains { $0.code == .taxComponentTaxMismatch })
    }

    @Test("GROSS_MISMATCH: net + tax != gross beyond tolerance is a hard issue")
    func grossMismatch() {
        var failing = Fixture.passingSnapshot()
        failing.gross = Fixture.eur("200.00")
        let result = TransactionValidator.validate(failing)
        #expect(result.hard.contains { $0.code == .grossMismatch })
    }

    @Test("ALLOCATION_SUM_MISMATCH: allocation sum differing from the expected total is a hard issue")
    func allocationSumMismatch() {
        var failing = Fixture.passingSnapshot()
        failing.allocations = [AllocationSnapshot(categoryID: "software_subscriptions", amount: Fixture.eur("50.00"), assetFlag: false)]
        let result = TransactionValidator.validate(failing)
        #expect(result.hard.contains { $0.code == .allocationSumMismatch })
    }

    @Test("PAYMENT_ALLOCATION_EXCEEDS: allocated total exceeding the payment amount is a hard issue")
    func paymentAllocationExceeds() {
        #expect(TransactionValidator.validate(Fixture.passingSnapshot()).hard.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.paymentAllocations = [
            PaymentAllocationFact(
                paymentID: "p1",
                paymentBookedAmount: Fixture.eur("100.00"),
                allocatedToThisTransaction: Fixture.eur("100.00"),
                totalAllocatedForPayment: Fixture.eur("150.00")
            ),
        ]
        let result = TransactionValidator.validate(failing)
        #expect(result.hard.contains { $0.code == .paymentAllocationExceeds })
    }
}
