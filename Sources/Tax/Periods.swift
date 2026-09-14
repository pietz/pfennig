import Domain

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
