import Domain

/// §11 Abs. 2 S. 2 EStG: regularly recurring payments made shortly before or
/// after a calendar year boundary belong to the year they economically
/// relate to, not the year of actual payment (spec 5.3). V1 never
/// auto-reassigns; it only detects the window so a soft warning can be
/// raised and lets the user set `eur_year_override`.
public enum TenDayRule {
    /// True when `paymentDate` falls within the window: 22 Dec through
    /// 31 Dec, or 1 Jan through 10 Jan (inclusive on both ends).
    public static func isInWindow(_ paymentDate: LocalDate) -> Bool {
        if paymentDate.month == 12, paymentDate.day >= (31 - Thresholds.tenDayWindowDays + 1) {
            return true
        }
        if paymentDate.month == 1, paymentDate.day <= Thresholds.tenDayWindowDays {
            return true
        }
        return false
    }

    /// The calendar year adjacent to `paymentDate` that the 10-day rule could
    /// reassign a payment to: the previous year for a January payment, the
    /// next year for a late-December payment. `nil` outside the window.
    ///
    /// Whether the reassignment actually applies still depends on which year
    /// the underlying service/expense economically relates to (a fact the
    /// caller supplies); this only reports the *candidate* adjacent year.
    public static func adjacentYear(for paymentDate: LocalDate) -> Int? {
        guard isInWindow(paymentDate) else { return nil }
        return paymentDate.month == 1 ? paymentDate.year - 1 : paymentDate.year + 1
    }

    /// True when the rule reassigns `paymentDate` to `economicallyRelatedYear`:
    /// the payment is inside the window and the related year is the adjacent
    /// one (spec 5.3).
    public static func appliesReassignment(paymentDate: LocalDate, economicallyRelatedYear: Int) -> Bool {
        adjacentYear(for: paymentDate) == economicallyRelatedYear
    }
}
