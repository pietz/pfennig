import Domain
@testable import Validation
import Testing

@Suite("TransactionValidator - soft rules (spec 14.2)")
struct TransactionValidatorSoftRuleTests {
    @Test("TAX_RATE_UNUSUAL: an unexpected rate for the treatment is a soft issue")
    func taxRateUnusual() {
        #expect(TransactionValidator.validate(Fixture.passingSnapshot()).soft.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.taxComponents = [TaxComponentSnapshot(rate: "25", net: Fixture.eur("100.00"), tax: Fixture.eur("19.00"), kind: .standard)]
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .taxRateUnusual })
    }

    @Test("TREATMENT_COUNTRY_MISMATCH: reverseCharge with a domestic counterparty is a soft issue")
    func treatmentCountryMismatchReverseChargeDomestic() {
        var failing = Fixture.passingSnapshot()
        failing.treatment = .reverseCharge
        failing.isCounterpartyDomestic = true
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .treatmentCountryMismatch })
    }

    @Test("TREATMENT_COUNTRY_MISMATCH: domesticVAT with an EU counterparty and VAT ID present is a soft issue")
    func treatmentCountryMismatchDomesticWithEUVATId() {
        var failing = Fixture.passingSnapshot()
        failing.treatment = .domesticVAT
        failing.isCounterpartyDomestic = false
        failing.isCounterpartyEUMember = true
        failing.customerVATIDPresent = true
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .treatmentCountryMismatch })
    }

    @Test("CUSTOMER_VAT_ID_MISSING: reverse-charge income without a customer VAT ID is a soft issue")
    func customerVATIdMissing() {
        var passing = Fixture.passingSnapshot()
        passing.treatment = .reverseCharge
        passing.direction = .income
        passing.isCounterpartyDomestic = false
        passing.customerVATIDPresent = true
        #expect(!TransactionValidator.validate(passing).soft.contains { $0.code == .customerVATIdMissing })

        var failing = passing
        failing.customerVATIDPresent = false
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .customerVATIdMissing })
    }

    @Test("SERVICE_DATE_MISSING: a missing service date (not Kleinbetrag) is a soft issue")
    func serviceDateMissing() {
        #expect(TransactionValidator.validate(Fixture.passingSnapshot()).soft.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.serviceDate = nil
        failing.servicePeriodEnd = nil
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .serviceDateMissing })
    }

    @Test("SERVICE_DATE_MISSING is suppressed for Kleinbetrag")
    func serviceDateMissingSuppressedForKleinbetrag() {
        var snapshot = Fixture.passingSnapshot()
        snapshot.serviceDate = nil
        snapshot.servicePeriodEnd = nil
        snapshot.isKleinbetrag = true
        #expect(!TransactionValidator.validate(snapshot).soft.contains { $0.code == .serviceDateMissing })
    }

    @Test("INVOICE_NUMBER_MISSING: a missing invoice number is a soft issue")
    func invoiceNumberMissing() {
        var failing = Fixture.passingSnapshot()
        failing.invoiceNumberPresent = false
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .invoiceNumberMissing })
    }

    @Test("INVOICE_NUMBER_MISSING is suppressed for Kleinbetrag")
    func invoiceNumberMissingSuppressedForKleinbetrag() {
        var snapshot = Fixture.passingSnapshot()
        snapshot.invoiceNumberPresent = false
        snapshot.isKleinbetrag = true
        #expect(!TransactionValidator.validate(snapshot).soft.contains { $0.code == .invoiceNumberMissing })
    }

    @Test("PAYMENT_AMOUNT_DIFFERS: a paid amount differing from gross beyond tolerance is a soft issue")
    func paymentAmountDiffers() {
        var passing = Fixture.passingSnapshot()
        passing.totalPaid = Fixture.eur("119.00")
        #expect(TransactionValidator.validate(passing).soft.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.totalPaid = Fixture.eur("125.00")
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .paymentAmountDiffers })
    }

    @Test("EXCHANGE_RATE_DEVIATION: a booked rate deviating more than 5% from the bank rate is a soft issue")
    func exchangeRateDeviation() {
        var passing = Fixture.passingSnapshot()
        passing.bookedExchangeRate = 0.92
        passing.bankActualExchangeRate = 0.9214
        #expect(TransactionValidator.validate(passing).soft.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.bookedExchangeRate = 0.80
        failing.bankActualExchangeRate = 0.9214
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .exchangeRateDeviation })
    }

    @Test("ASSET_CANDIDATE: an allocation flagged as an asset candidate is a soft issue")
    func assetCandidate() {
        var failing = Fixture.passingSnapshot()
        failing.allocations = [AllocationSnapshot(categoryID: "hardware_equipment", amount: Fixture.eur("1850.00"), assetFlag: true)]
        failing.allocationExpectedTotal = Fixture.eur("1850.00")
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .assetCandidate })
    }

    @Test("TEN_DAY_RULE: a payment inside the 10-day window is a soft issue")
    func tenDayRule() {
        var failing = Fixture.passingSnapshot()
        failing.paymentsInTenDayWindow = [LocalDate(year: 2027, month: 1, day: 5)]
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .tenDayRule })
    }

    @Test("HIGH_AMOUNT_AGENT_ONLY: an amount above threshold with only agent provenance is a soft issue")
    func highAmountAgentOnly() {
        var passing = Fixture.passingSnapshot()
        passing.highAmountThreshold = Fixture.eur("1000.00")
        passing.provenance = ProvenanceSummary(hasAnyNonAgentProvenance: true)
        #expect(TransactionValidator.validate(passing).soft.isEmpty)

        var failing = Fixture.passingSnapshot()
        failing.gross = Fixture.eur("5000.00")
        failing.net = Fixture.eur("4201.68")
        failing.tax = Fixture.eur("798.32")
        failing.taxComponents = [TaxComponentSnapshot(rate: "19", net: Fixture.eur("4201.68"), tax: Fixture.eur("798.32"), kind: .standard)]
        failing.allocations = [AllocationSnapshot(categoryID: "software_subscriptions", amount: Fixture.eur("4201.68"), assetFlag: false)]
        failing.allocationExpectedTotal = Fixture.eur("4201.68")
        failing.highAmountThreshold = Fixture.eur("1000.00")
        failing.provenance = ProvenanceSummary(hasAnyNonAgentProvenance: false)
        let result = TransactionValidator.validate(failing)
        #expect(result.soft.contains { $0.code == .highAmountAgentOnly })
    }
}
