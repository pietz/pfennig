@testable import Domain
import Foundation
import Testing

/// Raw values are the on-disk format (spec 18). This snapshot fails whenever a
/// case is renamed, removed or added without a conscious decision - and, where
/// a value already exists in user databases, without a migration.
@Suite("Enum raw values")
struct EnumRawValueTests {
    static let snapshot: [String: [String]] = [
        "Direction": ["income", "expense", "unknown"],
        "TransactionType": ["invoice", "receipt", "creditNote", "paymentOnly", "taxPayment", "other"],
        "WorkflowStatus": ["active", "archived"],
        "ReviewStatus": ["unreviewed", "needsReview", "confirmed", "conflict"],
        "TaxTreatment": ["domesticVAT", "reverseCharge", "intraCommunityAcquisition", "intraCommunitySupply",
                         "export", "importVAT", "nonTaxable", "exempt", "smallBusiness", "unknown"],
        "TaxComponentKind": ["standard", "reduced", "zero", "reverseChargeNote", "exempt", "fee", "deposit", "other"],
        "TaxAssessmentStatus": ["proposed", "confirmed", "manualOverride"],
        "CustomerType": ["b2b", "b2c", "unknown"],
        "SupplyType": ["service", "goods", "unknown"],
        "DocumentType": ["invoice", "receipt", "creditNote", "statement", "contract", "other", "unknown"],
        "DocumentRole": ["invoice", "receipt", "creditNote", "statement", "other"],
        "DocumentSource": ["dragDrop", "fileImport", "other"],
        "PaymentDirection": ["inflow", "outflow"],
        "PaymentMethod": ["bankTransfer", "card", "paypal", "directDebit", "cash", "other", "unknown"],
        "PaymentSource": ["statementLine", "manual"],
        "MatchMethod": ["exact", "reference", "invoiceNumber", "heuristic", "manual"],
        "Provenance": ["document", "agent", "calculated", "manual", "imported"],
        "ImportBatchStatus": ["running", "completed", "completedWithErrors", "cancelled"],
        "ImportItemStatus": ["queued", "archiving", "analyzing", "matching", "proposed", "committed",
                             "skipped", "duplicate", "failed"],
        "ModelRunOperation": ["extraction", "disambiguation", "statementMapping"],
        "ModelRunStatus": ["running", "succeeded", "failed"],
        "ProposalKind": ["createTransaction", "updateTransaction", "attachDocument", "mergeDuplicate"],
        "ProposalStatus": ["pending", "accepted", "acceptedEdited", "rejected", "skipped", "superseded", "committed"],
        "PolicyDecision": ["autoCommit", "needsReview", "blocked"],
        "AutomationLevel": ["manual", "balanced", "automatic"],
        "IssueSeverity": ["info", "warning", "error"],
        "IssueStatus": ["open", "resolved", "ignored"],
        "AuditActor": ["user", "agent", "system", "import"],
        "AuditAction": ["create", "update", "delete", "link", "unlink", "confirm", "correct", "lock", "unlock"],
        "PaymentStatus": ["unknown", "unpaid", "partiallyPaid", "paid", "refunded"],
        "DocumentStatus": ["missing", "notRequired", "complete"],
        "VATStatus": ["taxable", "smallBusiness"],
        "VATAccountingMethod": ["cash", "accrual"],
        "UStVAPeriodicity": ["monthly", "quarterly", "yearly"],
        "BusinessType": ["freelancer", "soleProprietor"],
        "CategoryKind": ["income", "expense", "assetCandidate", "neutral"]
    ]

    /// Every enum that is stored in the database, erased to its raw values.
    static let live: [String: [String]] = {
        var result: [String: [String]] = [:]
        func add<T: RawRepresentable & CaseIterable>(_ type: T.Type) where T.RawValue == String {
            result[String(describing: type)] = T.allCases.map(\.rawValue)
        }
        add(Direction.self); add(TransactionType.self); add(WorkflowStatus.self); add(ReviewStatus.self)
        add(TaxTreatment.self); add(TaxComponentKind.self); add(TaxAssessmentStatus.self)
        add(CustomerType.self); add(SupplyType.self)
        add(DocumentType.self); add(DocumentRole.self); add(DocumentSource.self)
        add(PaymentDirection.self)
        add(PaymentMethod.self); add(PaymentSource.self); add(MatchMethod.self); add(Provenance.self)
        add(ImportBatchStatus.self); add(ImportItemStatus.self)
        add(ModelRunOperation.self); add(ModelRunStatus.self); add(ProposalKind.self); add(ProposalStatus.self)
        add(PolicyDecision.self); add(AutomationLevel.self); add(IssueSeverity.self); add(IssueStatus.self)
        add(AuditActor.self); add(AuditAction.self)
        add(PaymentStatus.self); add(DocumentStatus.self)
        add(VATStatus.self); add(VATAccountingMethod.self); add(UStVAPeriodicity.self); add(BusinessType.self)
        add(CategoryKind.self)
        return result
    }()

    @Test("Raw values are stable")
    func stability() {
        #expect(Set(Self.live.keys) == Set(Self.snapshot.keys))
        for (name, expected) in Self.snapshot {
            #expect(Self.live[name] == expected, "Raw values of \(name) changed")
        }
    }

    @Test("Unknown raw values fall back in release")
    func fallback() {
        #expect(TaxTreatment(rawValue: "somethingNew") == nil)
        #expect(TaxTreatment.fallback == .unknown)
        #expect(Direction.fallback == .unknown)
        #expect(PaymentStatus.fallback == .unknown)
    }
}
