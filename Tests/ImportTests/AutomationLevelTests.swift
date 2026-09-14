import Database
import Domain
import Foundation
import ImportPipeline
import Testing

/// The automation level and the single decision function behind it
/// (`document-to-tax-workflow.md` "Automatik und Ausnahmen").
@Suite("Automatisierungsstufe")
struct AutomationLevelTests {
    private static let hard = ValidationIssueDraft(
        code: "GROSS_MISMATCH",
        severity: .error,
        messageKey: "issue.grossMismatch",
        message: "Brutto passt nicht zu Netto plus Steuer."
    )
    private static let soft = ValidationIssueDraft(
        code: "INVOICE_NUMBER_MISSING",
        severity: .warning,
        messageKey: "issue.invoiceNumberMissing",
        message: "Keine Rechnungsnummer erkannt."
    )

    /// Every combination of level, hard issue, soft issue, ambiguity and
    /// manual override, spelled out rather than recomputed from the rule.
    @Test("Die Entscheidungsmatrix ist vollständig festgelegt")
    func matrix() {
        var checked = 0
        for level in AutomationLevel.allCases {
            for hasHard in [false, true] {
                for hasSoft in [false, true] {
                    for isUnambiguous in [false, true] {
                        for touchesManualOverride in [false, true] {
                            let expected: PolicyDecision = if hasHard {
                                .blocked
                            } else {
                                switch level {
                                case .manual:
                                    .needsReview
                                case .balanced:
                                    isUnambiguous && !touchesManualOverride && !hasSoft
                                        ? .autoCommit : .needsReview
                                case .automatic:
                                    isUnambiguous && !touchesManualOverride ? .autoCommit : .needsReview
                                }
                            }
                            let decision = AutomationPolicy.decide(
                                level: level,
                                hardIssues: hasHard ? [Self.hard] : [],
                                softIssues: hasSoft ? [Self.soft] : [],
                                isUnambiguous: isUnambiguous,
                                touchesManualOverride: touchesManualOverride
                            )
                            #expect(
                                decision == expected,
                                """
                                \(level.rawValue) hart=\(hasHard) weich=\(hasSoft) \
                                eindeutig=\(isUnambiguous) manuell=\(touchesManualOverride)
                                """
                            )
                            checked += 1
                        }
                    }
                }
            }
        }
        #expect(checked == 48)
    }

    @Test("Harte Fehler blockieren auf jeder Stufe")
    func hardIssuesAlwaysBlock() {
        for level in AutomationLevel.allCases {
            #expect(AutomationPolicy.decide(level: level, hardIssues: [Self.hard]) == .blocked)
        }
    }

    @Test("Manuell bestätigt auch den eindeutigen, fehlerfreien Fall")
    func manualNeverCommits() {
        #expect(AutomationPolicy.decide(level: .manual, hardIssues: []) == .needsReview)
    }

    @Test("Ausgewogen übernimmt nur den vollständig geprüften Standardfall")
    func balanced() {
        #expect(AutomationPolicy.decide(level: .balanced, hardIssues: []) == .autoCommit)
        #expect(AutomationPolicy.decide(level: .balanced, hardIssues: [], softIssues: [Self.soft]) == .needsReview)
        #expect(AutomationPolicy.decide(level: .balanced, hardIssues: [], isUnambiguous: false) == .needsReview)
        #expect(
            AutomationPolicy.decide(level: .balanced, hardIssues: [], touchesManualOverride: true) == .needsReview
        )
    }

    @Test("Automatisch übernimmt trotz Warnung, aber nie über einen manuellen Wert")
    func automatic() {
        #expect(AutomationPolicy.decide(level: .automatic, hardIssues: [], softIssues: [Self.soft]) == .autoCommit)
        #expect(
            AutomationPolicy.decide(level: .automatic, hardIssues: [], touchesManualOverride: true) == .needsReview
        )
        #expect(AutomationPolicy.decide(level: .automatic, hardIssues: [], isUnambiguous: false) == .needsReview)
    }

    /// A warning is a durable exception: the booking is written, but it stays
    /// in "Buchungen prüfen" until someone looks at it.
    @Test("Die automatische Übernahme bestätigt nur den warnungsfreien Fall")
    func reviewStatusOfAutoCommit() {
        #expect(AutomationPolicy.reviewStatus(forAutoCommitWith: []) == .confirmed)
        #expect(AutomationPolicy.reviewStatus(forAutoCommitWith: [Self.soft]) == .needsReview)
    }

    // MARK: - Setting

    @Test("Ohne Einstellung gilt Manuell")
    func defaultsToManual() throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        #expect(AutomationPreferences.level(in: workspace.database) == .manual)
        #expect(AutomationLevel.default == .manual)
    }

    @Test("Die Stufe überlebt den Weg durch die settings-Tabelle")
    func roundTrip() throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        for level in AutomationLevel.allCases {
            AutomationPreferences.setLevel(level, in: workspace.database)
            #expect(AutomationPreferences.level(in: workspace.database) == level)
        }
        let raw = try workspace.database.setting(AutomationLevel.self, forKey: "automation.level")
        #expect(raw == .automatic, "Der Schlüssel der Einstellung ist Teil des Archivformats")
    }

    @Test("Ohne Archiv gilt ebenfalls Manuell")
    func withoutDatabase() {
        #expect(AutomationPreferences.level(in: nil) == .manual)
    }
}
