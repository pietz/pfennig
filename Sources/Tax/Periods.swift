import Domain

/// Derived tax points for a `vat_accounting_method = cash` profile (spec 5.1).
/// Both dates are materialized on `tax_assessments` with provenance
/// `calculated`, overridable by the user.
public struct TaxPoints: Sendable, Equatable {
    /// §11 EStG (Zufluss/Abfluss): date the amount counts for income tax.
    /// The date of the first (or only) payment; `nil` if unpaid.
    public let eurDate: LocalDate?

    /// §15 Abs. 1 Nr. 1 UStG: date input VAT becomes deductible (expense side only).
    public let inputVATDate: LocalDate?

    /// §13 Abs. 1 Nr. 1 b UStG (Ist-Versteuerung): date output VAT becomes
    /// due (income side only) - date of the first/only payment, `nil` if unpaid.
    public let outputVATDate: LocalDate?
}

/// Inputs needed to derive `TaxPoints` for one transaction (spec 5.1).
public struct TaxPointsInput: Sendable {
    public var direction: Direction
    public var treatment: TaxTreatment
    public var invoiceDate: LocalDate?
    public var serviceDate: LocalDate?
    public var servicePeriodEnd: LocalDate?
    public var isAdvancePayment: Bool
    /// Cash movement dates for this transaction, in any order; may be empty (unpaid).
    public var paymentDates: [LocalDate]

    public init(
        direction: Direction,
        treatment: TaxTreatment,
        invoiceDate: LocalDate?,
        serviceDate: LocalDate? = nil,
        servicePeriodEnd: LocalDate? = nil,
        isAdvancePayment: Bool = false,
        paymentDates: [LocalDate] = []
    ) {
        self.direction = direction
        self.treatment = treatment
        self.invoiceDate = invoiceDate
        self.serviceDate = serviceDate
        self.servicePeriodEnd = servicePeriodEnd
        self.isAdvancePayment = isAdvancePayment
        self.paymentDates = paymentDates
    }
}

public enum TaxPointDeriver {
    /// Derives `eurDate`, `inputVATDate` and `outputVATDate` per spec 5.1.
    public static func derive(_ input: TaxPointsInput) -> TaxPoints {
        let firstPayment = input.paymentDates.min()

        switch input.direction {
        case .income:
            // Ist-Versteuerung: both the EÜR date and the output VAT date
            // are the date of the first/only payment (spec 5.1, 17.8).
            return TaxPoints(eurDate: firstPayment, inputVATDate: nil, outputVATDate: firstPayment)

        case .expense, .unknown:
            let inputDate = inputVATDate(input, firstPayment: firstPayment)
            return TaxPoints(eurDate: firstPayment, inputVATDate: inputDate, outputVATDate: nil)
        }
    }

    private static func inputVATDate(_ input: TaxPointsInput, firstPayment: LocalDate?) -> LocalDate? {
        switch input.treatment {
        case .reverseCharge, .intraCommunityAcquisition:
            // §13b Abs. 1/2 UStG: the invoice date drives both the
            // self-assessed VAT and the matching input VAT deduction.
            return input.invoiceDate

        default:
            if input.isAdvancePayment {
                // Advance payment before service/invoice: deductible when
                // paid and the invoice is on hand.
                guard let firstPayment, let invoiceDate = input.invoiceDate else { return nil }
                return max(firstPayment, invoiceDate)
            }
            // Normal case: deductible once the service has been performed
            // and a proper invoice is on hand. §15 Abs. 1 Nr. 1 UStG.
            let serviceReference = input.serviceDate ?? input.servicePeriodEnd ?? input.invoiceDate
            guard let invoiceDate = input.invoiceDate else { return serviceReference }
            guard let serviceReference else { return invoiceDate }
            return max(serviceReference, invoiceDate)
        }
    }

    /// Spec 5.2: the "Date" column shown in the main table - EÜR date if any
    /// payment exists, otherwise invoice date, otherwise import date.
    public static func relevantDate(taxPoints: TaxPoints, invoiceDate: LocalDate?, importDate: LocalDate?) -> LocalDate? {
        taxPoints.eurDate ?? invoiceDate ?? importDate
    }
}

// MARK: - Periods (spec 23)

/// A UStVA (Umsatzsteuer-Voranmeldung) reporting period: a calendar month or
/// quarter within a year.
public struct UStVAPeriod: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case monthly
        case quarterly
    }

    public let year: Int
    public let kind: Kind
    /// 1...12 for `.monthly`, 1...4 for `.quarterly`.
    public let index: Int

    public init(year: Int, month: Int) {
        precondition((1 ... 12).contains(month), "month must be 1...12")
        self.year = year
        self.kind = .monthly
        self.index = month
    }

    public init(year: Int, quarter: Int) {
        precondition((1 ... 4).contains(quarter), "quarter must be 1...4")
        self.year = year
        self.kind = .quarterly
        self.index = quarter
    }

    /// First calendar month (1...12) of this period.
    private var startMonth: Int {
        switch kind {
        case .monthly: index
        case .quarterly: (index - 1) * 3 + 1
        }
    }

    /// Last calendar month (1...12) of this period.
    private var endMonth: Int {
        switch kind {
        case .monthly: index
        case .quarterly: startMonth + 2
        }
    }

    public var periodStart: LocalDate {
        LocalDate(year: year, month: startMonth, day: 1)
    }

    public var periodEnd: LocalDate {
        LocalDate(year: year, month: endMonth, day: LocalDate.daysInMonth(year: year, month: endMonth))
    }

    public func contains(_ date: LocalDate) -> Bool {
        periodStart <= date && date <= periodEnd
    }

    /// Filing due date: the 10th of the month following the period, §18
    /// Abs. 1 UStG. `dauerfristverlaengerung` (permanent extension, §46-48
    /// UStDV) shifts this out by one additional month.
    public func dueDate(dauerfristverlaengerung: Bool = false) -> LocalDate {
        var year = year
        var month = endMonth + 1 + (dauerfristverlaengerung ? 1 : 0)
        while month > 12 {
            month -= 12
            year += 1
        }
        return LocalDate(year: year, month: month, day: 10)
    }
}

/// A business's fiscal year, spec 23. V1 defaults `fiscal_year_start_month`
/// to 1 (the calendar year), but the type supports any start month.
public struct FiscalYear: Sendable, Equatable {
    /// The calendar year in which this fiscal year starts.
    public let year: Int
    /// 1...12; spec 17.1 `fiscal_year_start_month`, default 1.
    public let startMonth: Int

    public init(year: Int, startMonth: Int = 1) {
        precondition((1 ... 12).contains(startMonth), "startMonth must be 1...12")
        self.year = year
        self.startMonth = startMonth
    }

    public var start: LocalDate {
        LocalDate(year: year, month: startMonth, day: 1)
    }

    /// Last day of the fiscal year (the day before `start` one year later).
    public var end: LocalDate {
        let endMonth = startMonth == 1 ? 12 : startMonth - 1
        let endYear = startMonth == 1 ? year : year + 1
        return LocalDate(year: endYear, month: endMonth, day: LocalDate.daysInMonth(year: endYear, month: endMonth))
    }

    public func contains(_ date: LocalDate) -> Bool {
        start <= date && date <= end
    }
}
