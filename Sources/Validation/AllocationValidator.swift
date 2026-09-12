import Domain

/// A single bookkeeping allocation as seen by the validator (spec 17.6).
public struct AllocationSnapshot: Sendable, Equatable {
    public let categoryID: String
    public let amount: Money
    public let assetFlag: Bool

    public init(categoryID: String, amount: Money, assetFlag: Bool) {
        self.categoryID = categoryID
        self.amount = amount
        self.assetFlag = assetFlag
    }
}

/// Checks over `bookkeeping_allocations` (spec 14, 17.6).
public enum AllocationValidator {
    /// Spec 14.1: `sum(bookkeeping_allocations.amount) ≠ booked net amount`
    /// (or gross for non-deductible cases) beyond tolerance.
    public static func validateAllocationSum(
        allocations: [AllocationSnapshot],
        expectedTotal: Money,
        tolerance: Money = MoneyValidator.defaultTolerance
    ) -> ValidationIssue? {
        guard let sum = try? allocations.reduce(Money.zero(expectedTotal.currency), { try $0 + $1.amount }) else {
            return nil
        }
        guard let diff = try? sum - expectedTotal, diff.absolute > tolerance else { return nil }
        return ValidationIssue(
            code: .allocationSumMismatch,
            fieldName: "bookkeeping_allocations",
            params: ["deviation": diff.absolute.decimalString],
            isOverridable: IssueCode.allocationSumMismatch.isOverridable(deviation: diff.absolute)
        )
    }

    /// Spec 5.6 / 14.2: "Asset candidate." One issue per flagged allocation.
    public static func validateAssetCandidates(allocations: [AllocationSnapshot]) -> [ValidationIssue] {
        allocations
            .filter(\.assetFlag)
            .map { ValidationIssue(code: .assetCandidate, fieldName: $0.categoryID, params: ["amount": $0.amount.decimalString]) }
    }
}
