import Domain
@testable import Tax
import Testing

@Suite("TaxPointDeriver")
struct TaxPointsTests {
    static let invoiceDate = LocalDate(year: 2026, month: 3, day: 10)
    static let serviceDate = LocalDate(year: 2026, month: 3, day: 5)
    static let servicePeriodEnd = LocalDate(year: 2026, month: 3, day: 31)
    static let payment1 = LocalDate(year: 2026, month: 3, day: 20)
    static let payment2 = LocalDate(year: 2026, month: 4, day: 1)

    // MARK: Full matrix - direction × treatment × advance-payment invariants

    @Test(
        "Income direction: eurDate/outputVATDate track first payment, inputVATDate always nil",
        arguments: TaxTreatment.allCases, [false, true]
    )
    func incomeInvariants(treatment: TaxTreatment, isAdvancePayment: Bool) {
        let unpaid = TaxPointDeriver.derive(TaxPointsInput(
            direction: .income, treatment: treatment, invoiceDate: Self.invoiceDate,
            isAdvancePayment: isAdvancePayment, paymentDates: []
        ))
        #expect(unpaid.eurDate == nil)
        #expect(unpaid.outputVATDate == nil)
        #expect(unpaid.inputVATDate == nil)

        let paid = TaxPointDeriver.derive(TaxPointsInput(
            direction: .income, treatment: treatment, invoiceDate: Self.invoiceDate,
            isAdvancePayment: isAdvancePayment, paymentDates: [Self.payment2, Self.payment1]
        ))
        #expect(paid.eurDate == Self.payment1)
        #expect(paid.outputVATDate == Self.payment1)
        #expect(paid.inputVATDate == nil)
    }

    @Test(
        "Expense direction: outputVATDate always nil",
        arguments: TaxTreatment.allCases, [false, true]
    )
    func expenseOutputVATAlwaysNil(treatment: TaxTreatment, isAdvancePayment: Bool) {
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: treatment, invoiceDate: Self.invoiceDate,
            serviceDate: Self.serviceDate, isAdvancePayment: isAdvancePayment, paymentDates: [Self.payment1]
        ))
        #expect(result.outputVATDate == nil)
        #expect(result.eurDate == Self.payment1)
    }

    // MARK: Reverse charge / intra-Community acquisition - invoice date drives input VAT (5.1)

    @Test("reverseCharge expense uses invoiceDate for inputVATDate regardless of advance payment", arguments: [false, true])
    func reverseChargeUsesInvoiceDate(isAdvancePayment: Bool) {
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .reverseCharge, invoiceDate: Self.invoiceDate,
            serviceDate: Self.serviceDate, isAdvancePayment: isAdvancePayment, paymentDates: [Self.payment1]
        ))
        #expect(result.inputVATDate == Self.invoiceDate)
    }

    @Test("intraCommunityAcquisition expense uses invoiceDate for inputVATDate")
    func intraCommunityAcquisitionUsesInvoiceDate() {
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .intraCommunityAcquisition, invoiceDate: Self.invoiceDate,
            serviceDate: Self.serviceDate, paymentDates: []
        ))
        #expect(result.inputVATDate == Self.invoiceDate)
    }

    // MARK: domesticVAT expense - normal vs advance payment (5.1)

    @Test("domesticVAT expense, normal case: inputVATDate = max(serviceDate, invoiceDate)")
    func domesticVATNormalCase() {
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .domesticVAT, invoiceDate: Self.invoiceDate,
            serviceDate: Self.serviceDate, paymentDates: []
        ))
        // serviceDate (3/5) < invoiceDate (3/10) -> max is invoiceDate.
        #expect(result.inputVATDate == Self.invoiceDate)
    }

    @Test("domesticVAT expense, service date after invoice date: inputVATDate = service date")
    func domesticVATServiceAfterInvoice() {
        let laterService = LocalDate(year: 2026, month: 3, day: 15)
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .domesticVAT, invoiceDate: Self.invoiceDate,
            serviceDate: laterService, paymentDates: []
        ))
        #expect(result.inputVATDate == laterService)
    }

    @Test("domesticVAT expense falls back to servicePeriodEnd when serviceDate is absent")
    func domesticVATUsesServicePeriodEnd() {
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .domesticVAT, invoiceDate: Self.invoiceDate,
            servicePeriodEnd: Self.servicePeriodEnd, paymentDates: []
        ))
        #expect(result.inputVATDate == Self.servicePeriodEnd)
    }

    @Test("domesticVAT expense advance payment before invoice/service: inputVATDate = max(payment, invoice)")
    func domesticVATAdvancePayment() {
        let earlyPayment = LocalDate(year: 2026, month: 2, day: 1)
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .domesticVAT, invoiceDate: Self.invoiceDate,
            isAdvancePayment: true, paymentDates: [earlyPayment]
        ))
        // invoiceDate (3/10) > payment (2/1) -> max is invoiceDate.
        #expect(result.inputVATDate == Self.invoiceDate)
    }

    @Test("domesticVAT expense advance payment after invoice date: inputVATDate = payment date")
    func domesticVATAdvancePaymentAfterInvoice() {
        let latePayment = LocalDate(year: 2026, month: 4, day: 1)
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .domesticVAT, invoiceDate: Self.invoiceDate,
            isAdvancePayment: true, paymentDates: [latePayment]
        ))
        #expect(result.inputVATDate == latePayment)
    }

    @Test("domesticVAT expense advance payment, unpaid: no input VAT date yet")
    func domesticVATAdvancePaymentUnpaid() {
        let result = TaxPointDeriver.derive(TaxPointsInput(
            direction: .expense, treatment: .domesticVAT, invoiceDate: Self.invoiceDate,
            isAdvancePayment: true, paymentDates: []
        ))
        #expect(result.inputVATDate == nil)
    }

    // MARK: relevantDate (5.2)

    @Test("relevantDate prefers eurDate, then invoiceDate, then importDate")
    func relevantDatePriority() {
        let importDate = LocalDate(year: 2026, month: 1, day: 1)
        let withPayment = TaxPoints(eurDate: Self.payment1, inputVATDate: nil, outputVATDate: Self.payment1)
        #expect(TaxPointDeriver.relevantDate(taxPoints: withPayment, invoiceDate: Self.invoiceDate, importDate: importDate) == Self.payment1)

        let unpaid = TaxPoints(eurDate: nil, inputVATDate: nil, outputVATDate: nil)
        #expect(TaxPointDeriver.relevantDate(taxPoints: unpaid, invoiceDate: Self.invoiceDate, importDate: importDate) == Self.invoiceDate)
        #expect(TaxPointDeriver.relevantDate(taxPoints: unpaid, invoiceDate: nil, importDate: importDate) == importDate)
        #expect(TaxPointDeriver.relevantDate(taxPoints: unpaid, invoiceDate: nil, importDate: nil) == nil)
    }
}

@Suite("UStVAPeriod")
struct UStVAPeriodTests {
    @Test("Monthly period bounds and due date")
    func monthly() {
        let period = UStVAPeriod(year: 2026, month: 3)
        #expect(period.periodStart == LocalDate(year: 2026, month: 3, day: 1))
        #expect(period.periodEnd == LocalDate(year: 2026, month: 3, day: 31))
        #expect(period.contains(LocalDate(year: 2026, month: 3, day: 15)))
        #expect(!period.contains(LocalDate(year: 2026, month: 4, day: 1)))
        #expect(period.dueDate() == LocalDate(year: 2026, month: 4, day: 10))
    }

    @Test("Monthly period due date rolls over into the next year")
    func monthlyYearRollover() {
        let period = UStVAPeriod(year: 2026, month: 12)
        #expect(period.dueDate() == LocalDate(year: 2027, month: 1, day: 10))
    }

    @Test("Quarterly period bounds and due date")
    func quarterly() {
        let period = UStVAPeriod(year: 2026, quarter: 2)
        #expect(period.periodStart == LocalDate(year: 2026, month: 4, day: 1))
        #expect(period.periodEnd == LocalDate(year: 2026, month: 6, day: 30))
        #expect(period.dueDate() == LocalDate(year: 2026, month: 7, day: 10))
    }

    @Test("Dauerfristverlängerung adds one month to the due date")
    func dauerfristverlaengerung() {
        let period = UStVAPeriod(year: 2026, month: 3)
        #expect(period.dueDate(dauerfristverlaengerung: true) == LocalDate(year: 2026, month: 5, day: 10))
    }

    @Test("Q4 due date with extension rolls over the year")
    func quarterlyExtensionRollover() {
        let period = UStVAPeriod(year: 2026, quarter: 4)
        #expect(period.dueDate(dauerfristverlaengerung: true) == LocalDate(year: 2027, month: 2, day: 10))
    }
}

@Suite("FiscalYear")
struct FiscalYearTests {
    @Test("Default calendar-year fiscal year")
    func calendarYear() {
        let year = FiscalYear(year: 2026)
        #expect(year.start == LocalDate(year: 2026, month: 1, day: 1))
        #expect(year.end == LocalDate(year: 2026, month: 12, day: 31))
        #expect(year.contains(LocalDate(year: 2026, month: 6, day: 1)))
        #expect(!year.contains(LocalDate(year: 2027, month: 1, day: 1)))
    }

    @Test("Non-January fiscal year start spans two calendar years")
    func offsetFiscalYear() {
        let year = FiscalYear(year: 2026, startMonth: 7)
        #expect(year.start == LocalDate(year: 2026, month: 7, day: 1))
        #expect(year.end == LocalDate(year: 2027, month: 6, day: 30))
    }
}
