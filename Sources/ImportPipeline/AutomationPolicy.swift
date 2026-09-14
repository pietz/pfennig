import Database
import Domain
import Foundation

/// The single decision function behind the automation level
/// (`statement-import.md` 1: "Eine einzige Entscheidungsfunktion beantwortet
/// für jeden Vorschlag: sofort übernehmen oder in Prüfen legen"). It is pure
/// and deterministic: the model's own confidence is not one of its inputs.
///
/// The same function answers for document imports and for statement
/// movements, so the level means the same thing everywhere.
public enum AutomationPolicy {
    /// - Parameters:
    ///   - level: the user's setting.
    ///   - hardIssues: blocking validations (spec 14.1). Any of them blocks at
    ///     every level; the archive must not contain an impossible booking.
    ///   - softIssues: warnings (spec 14.2). They never block, but they are
    ///     what separates "Ausgewogen" from "Automatisch".
    ///   - isUnambiguous: the derivation or match has exactly one answer. A
    ///     competing payment match or an unresolved classification is not
    ///     auto-applied at any level, because the workflow specification makes
    ///     ambiguous links a visible exception regardless of the level.
    ///   - touchesManualOverride: the write would replace a field the user
    ///     entered by hand. Manual values are never silently overwritten.
    public static func decide(
        level: AutomationLevel,
        hardIssues: [ValidationIssueDraft],
        softIssues: [ValidationIssueDraft] = [],
        isUnambiguous: Bool = true,
        touchesManualOverride: Bool = false
    ) -> PolicyDecision {
        guard hardIssues.isEmpty else { return .blocked }
        switch level {
        case .manual:
            return .needsReview
        case .balanced:
            guard isUnambiguous, !touchesManualOverride, softIssues.isEmpty else { return .needsReview }
            return .autoCommit
        case .automatic:
            // Warnings are recorded on the booking instead of holding it back;
            // they stay visible under "Prüfen" - "Buchungen prüfen".
            guard isUnambiguous, !touchesManualOverride else { return .needsReview }
            return .autoCommit
        }
    }

    /// What an auto-committed booking's review state should be. A warning is a
    /// durable, actionable exception, so the booking is written but still
    /// listed under "Buchungen prüfen"; a clean standard case needs no second
    /// look and is confirmed.
    public static func reviewStatus(forAutoCommitWith softIssues: [ValidationIssueDraft]) -> ReviewStatus {
        softIssues.isEmpty ? .confirmed : .needsReview
    }
}

/// Reads and writes the automation level in the `settings` table (spec 10.5),
/// the same key/value store the UStVA preferences use. It lives here, next to
/// the policy, so both the app and the import pipeline read one definition and
/// the coordinator can be handed a plain value.
public enum AutomationPreferences {
    public static func level(in database: AppDatabase?) -> AutomationLevel {
        // `try?` flattens the "no row" and "unreadable row" cases into one
        // nil, and both mean the same thing here: the user has not chosen.
        guard let database,
              let level = try? database.setting(AutomationLevel.self, forKey: AutomationLevel.settingKey)
        else { return .default }
        return level
    }

    public static func setLevel(_ level: AutomationLevel, in database: AppDatabase?) {
        try? database?.setSetting(level, forKey: AutomationLevel.settingKey)
    }
}
