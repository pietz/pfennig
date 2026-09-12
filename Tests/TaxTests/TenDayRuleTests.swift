import Domain
@testable import Tax
import Testing

@Suite("TenDayRule")
struct TenDayRuleTests {
    @Test("21 Dec is outside the window")
    func dec21Outside() {
        #expect(!TenDayRule.isInWindow(LocalDate(year: 2026, month: 12, day: 21)))
    }

    @Test("22 Dec is the start of the window")
    func dec22Inside() {
        #expect(TenDayRule.isInWindow(LocalDate(year: 2026, month: 12, day: 22)))
    }

    @Test("31 Dec is inside the window")
    func dec31Inside() {
        #expect(TenDayRule.isInWindow(LocalDate(year: 2026, month: 12, day: 31)))
    }

    @Test("1 Jan is inside the window")
    func jan1Inside() {
        #expect(TenDayRule.isInWindow(LocalDate(year: 2027, month: 1, day: 1)))
    }

    @Test("10 Jan is the end of the window")
    func jan10Inside() {
        #expect(TenDayRule.isInWindow(LocalDate(year: 2027, month: 1, day: 10)))
    }

    @Test("11 Jan is outside the window")
    func jan11Outside() {
        #expect(!TenDayRule.isInWindow(LocalDate(year: 2027, month: 1, day: 11)))
    }

    @Test("Mid-year date is outside the window")
    func midYearOutside() {
        #expect(!TenDayRule.isInWindow(LocalDate(year: 2026, month: 6, day: 15)))
    }

    @Test("January payment's adjacent year is the previous year")
    func adjacentYearJanuary() {
        #expect(TenDayRule.adjacentYear(for: LocalDate(year: 2027, month: 1, day: 5)) == 2026)
    }

    @Test("Late-December payment's adjacent year is the next year")
    func adjacentYearDecember() {
        #expect(TenDayRule.adjacentYear(for: LocalDate(year: 2026, month: 12, day: 28)) == 2027)
    }

    @Test("adjacentYear is nil outside the window")
    func adjacentYearNilOutside() {
        #expect(TenDayRule.adjacentYear(for: LocalDate(year: 2026, month: 6, day: 15)) == nil)
    }

    @Test("appliesReassignment true when the related year matches the adjacent year")
    func appliesReassignmentTrue() {
        #expect(TenDayRule.appliesReassignment(paymentDate: LocalDate(year: 2027, month: 1, day: 5), economicallyRelatedYear: 2026))
    }

    @Test("appliesReassignment false when the related year is the payment's own year")
    func appliesReassignmentFalse() {
        #expect(!TenDayRule.appliesReassignment(paymentDate: LocalDate(year: 2027, month: 1, day: 5), economicallyRelatedYear: 2027))
    }
}
