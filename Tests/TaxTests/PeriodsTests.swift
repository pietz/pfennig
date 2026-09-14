import Domain
@testable import Tax
import Testing

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
