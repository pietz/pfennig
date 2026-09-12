import Domain

/// Spec 14.2: "Business statement line with no matching document after 60
/// days." Needs "today" and match-state facts the caller looks up from the
/// database - not part of a single transaction snapshot.
public enum PaymentMatchValidator {
    public static func validateUnmatchedBusinessLine(
        statementLineDate: LocalDate,
        today: LocalDate,
        isBusiness: Bool,
        hasMatchingDocument: Bool,
        windowDays: Int = 60
    ) -> ValidationIssue? {
        guard isBusiness, !hasMatchingDocument else { return nil }
        let days = DateMath.daysBetween(statementLineDate, today)
        guard days >= windowDays else { return nil }
        return ValidationIssue(code: .unmatchedBusinessLine, params: ["days": String(days)])
    }
}
