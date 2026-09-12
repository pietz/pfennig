import Domain
import Foundation

/// Minimal calendar-day arithmetic for `LocalDate`, kept private to the
/// `Validation` module (the `Tax` module keeps its own tiny copy so the two
/// modules stay independent, spec 22).
enum DateMath {
    private static let utc = TimeZone(identifier: "UTC")!

    /// Whole calendar days from `from` to `to` (negative if `to` precedes `from`).
    static func daysBetween(_ from: LocalDate, _ to: LocalDate) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let start = from.date(in: utc)
        let end = to.date(in: utc)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
