import Domain

/// Checks that need to know about *other* rows (existing IDs, allowed
/// transitions) which a single transaction/entity snapshot cannot see - the
/// caller (Database layer) supplies the needed facts (spec 14.1, spec 22:
/// `Validation` has no database dependency of its own).
public enum ReferentialValidator {
    /// Spec 14.1: "Linked IDs do not exist." One issue per dangling reference.
    public static func validateLinkedIDsExist(
        fieldName: String,
        referencedIDs: [String],
        existingIDs: Set<String>
    ) -> [ValidationIssue] {
        referencedIDs
            .filter { !existingIDs.contains($0) }
            .map { ValidationIssue(code: .linkedEntityMissing, fieldName: fieldName, params: ["id": $0]) }
    }

    /// Spec 14.1: "unsupported state transition." The caller (business
    /// layer) owns the transition policy; this only checks membership.
    public static func validateStateTransition(
        from: WorkflowStatus,
        to: WorkflowStatus,
        allowedTransitions: Set<WorkflowTransition>
    ) -> ValidationIssue? {
        guard from != to else { return nil }
        guard !allowedTransitions.contains(WorkflowTransition(from: from, to: to)) else { return nil }
        return ValidationIssue(
            code: .unsupportedStateTransition,
            fieldName: "workflowStatus",
            params: ["from": from.rawValue, "to": to.rawValue]
        )
    }
}
