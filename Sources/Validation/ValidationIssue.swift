import Domain

/// One deterministic validation finding (spec 17.20 `validation_issues`,
/// minus the persistence-only columns like `id`/`entity_id`/`status`, which
/// belong to the caller/Database layer - this module receives values and
/// returns values, spec 22).
public struct ValidationIssue: Sendable, Equatable, Codable {
    public let code: IssueCode
    public let severity: IssueSeverity
    public let fieldName: String?
    /// Localization parameters for `message_key`, e.g. the deviation amount.
    public let params: [String: String]
    public let isOverridable: Bool

    public init(
        code: IssueCode,
        severity: IssueSeverity? = nil,
        fieldName: String? = nil,
        params: [String: String] = [:],
        isOverridable: Bool = false
    ) {
        self.code = code
        self.severity = severity ?? code.severity
        self.fieldName = fieldName
        self.params = params
        self.isOverridable = isOverridable
    }

    /// Localization key, mirrors `IssueCode.messageKey`.
    public var messageKey: String { code.messageKey }
}
