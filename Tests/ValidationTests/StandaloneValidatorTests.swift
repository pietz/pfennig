import Domain
@testable import Validation
import Testing

@Suite("ReferentialValidator (needs DB context)")
struct ReferentialValidatorTests {
    @Test("LINKED_ENTITY_MISSING: all referenced IDs existing produces no issue")
    func linkedIDsAllExist() {
        let issues = ReferentialValidator.validateLinkedIDsExist(
            fieldName: "counterpartyId", referencedIDs: ["a", "b"], existingIDs: ["a", "b", "c"]
        )
        #expect(issues.isEmpty)
    }

    @Test("LINKED_ENTITY_MISSING: a dangling reference is a hard issue")
    func linkedIDMissing() {
        let issues = ReferentialValidator.validateLinkedIDsExist(
            fieldName: "counterpartyId", referencedIDs: ["a", "missing"], existingIDs: ["a"]
        )
        #expect(issues.count == 1)
        #expect(issues[0].code == .linkedEntityMissing)
        #expect(issues[0].severity == .error)
    }

    @Test("UNSUPPORTED_STATE_TRANSITION: an allowed transition produces no issue")
    func allowedStateTransition() {
        let allowed: Set<WorkflowTransition> = [WorkflowTransition(from: .draft, to: .active)]
        let issue = ReferentialValidator.validateStateTransition(from: .draft, to: .active, allowedTransitions: allowed)
        #expect(issue == nil)
    }

    @Test("UNSUPPORTED_STATE_TRANSITION: an unlisted transition is a hard issue")
    func disallowedStateTransition() {
        let allowed: Set<WorkflowTransition> = [WorkflowTransition(from: .draft, to: .active)]
        let issue = ReferentialValidator.validateStateTransition(from: .archived, to: .draft, allowedTransitions: allowed)
        #expect(issue?.code == .unsupportedStateTransition)
    }

    @Test("A no-op transition never raises an issue")
    func sameStateTransitionIsAllowed() {
        let issue = ReferentialValidator.validateStateTransition(from: .active, to: .active, allowedTransitions: [])
        #expect(issue == nil)
    }
}

@Suite("DuplicateValidator (needs DB context)")
struct DuplicateValidatorTests {
    @Test("DUPLICATE_DOCUMENT_IDENTITY: a new sha256 produces no issue")
    func newDocumentHash() {
        let issue = DuplicateValidator.validateDocumentIdentity(sha256: "abc123", existingHashes: ["def456"])
        #expect(issue == nil)
    }

    @Test("DUPLICATE_DOCUMENT_IDENTITY: a known sha256 is a hard issue")
    func duplicateDocumentHash() {
        let issue = DuplicateValidator.validateDocumentIdentity(sha256: "abc123", existingHashes: ["abc123"])
        #expect(issue?.code == .duplicateDocumentIdentity)
    }

    @Test("DUPLICATE_STATEMENT_LINE_FINGERPRINT: a new fingerprint on the account produces no issue")
    func newStatementLineFingerprint() {
        let existing: Set<StatementLineFingerprintKey> = [StatementLineFingerprintKey(accountID: "acc1", fingerprint: "fp1")]
        let issue = DuplicateValidator.validateStatementLineFingerprint(accountID: "acc1", fingerprint: "fp2", existingFingerprints: existing)
        #expect(issue == nil)
    }

    @Test("DUPLICATE_STATEMENT_LINE_FINGERPRINT: a repeated fingerprint on the same account is a hard issue")
    func duplicateStatementLineFingerprint() {
        let existing: Set<StatementLineFingerprintKey> = [StatementLineFingerprintKey(accountID: "acc1", fingerprint: "fp1")]
        let issue = DuplicateValidator.validateStatementLineFingerprint(accountID: "acc1", fingerprint: "fp1", existingFingerprints: existing)
        #expect(issue?.code == .duplicateStatementLineFingerprint)
    }

    @Test("The same fingerprint on a different account produces no issue")
    func sameFingerprintDifferentAccount() {
        let existing: Set<StatementLineFingerprintKey> = [StatementLineFingerprintKey(accountID: "acc1", fingerprint: "fp1")]
        let issue = DuplicateValidator.validateStatementLineFingerprint(accountID: "acc2", fingerprint: "fp1", existingFingerprints: existing)
        #expect(issue == nil)
    }

    @Test("SEMANTIC_DUPLICATE: a low similarity score produces no issue")
    func lowSimilarityScore() {
        let issue = DuplicateValidator.validateSemanticDuplicate(similarityScore: 0.4)
        #expect(issue == nil)
    }

    @Test("SEMANTIC_DUPLICATE: a high similarity score is a soft issue")
    func highSimilarityScore() {
        let issue = DuplicateValidator.validateSemanticDuplicate(similarityScore: 0.95)
        #expect(issue?.code == .semanticDuplicate)
        #expect(issue?.severity == .warning)
    }
}

@Suite("PaymentMatchValidator (needs DB context)")
struct PaymentMatchValidatorTests {
    @Test("UNMATCHED_BUSINESS_LINE: within 60 days produces no issue")
    func withinWindow() {
        let issue = PaymentMatchValidator.validateUnmatchedBusinessLine(
            statementLineDate: LocalDate(year: 2026, month: 1, day: 1),
            today: LocalDate(year: 2026, month: 2, day: 1),
            isBusiness: true,
            hasMatchingDocument: false
        )
        #expect(issue == nil)
    }

    @Test("UNMATCHED_BUSINESS_LINE: a business line unmatched after 60 days is a soft issue")
    func afterWindow() {
        let issue = PaymentMatchValidator.validateUnmatchedBusinessLine(
            statementLineDate: LocalDate(year: 2026, month: 1, day: 1),
            today: LocalDate(year: 2026, month: 3, day: 15),
            isBusiness: true,
            hasMatchingDocument: false
        )
        #expect(issue?.code == .unmatchedBusinessLine)
    }

    @Test("A matched document never raises the issue, however old")
    func matchedNeverFlags() {
        let issue = PaymentMatchValidator.validateUnmatchedBusinessLine(
            statementLineDate: LocalDate(year: 2020, month: 1, day: 1),
            today: LocalDate(year: 2026, month: 1, day: 1),
            isBusiness: true,
            hasMatchingDocument: true
        )
        #expect(issue == nil)
    }

    @Test("A private line never raises the issue")
    func privateLineNeverFlags() {
        let issue = PaymentMatchValidator.validateUnmatchedBusinessLine(
            statementLineDate: LocalDate(year: 2020, month: 1, day: 1),
            today: LocalDate(year: 2026, month: 1, day: 1),
            isBusiness: false,
            hasMatchingDocument: false
        )
        #expect(issue == nil)
    }
}
