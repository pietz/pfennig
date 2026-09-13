import Foundation

/// Enums that carry an `unknown` case can decode unexpected raw values coming
/// from the database into it, but trap in debug so bad data surfaces during
/// development (spec 18).
public protocol UnknownFallbackDecodable: RawRepresentable, Sendable where RawValue == String {
    static var fallback: Self { get }
}

public extension UnknownFallbackDecodable {
    static func fromDatabase(_ raw: String) -> Self {
        if let value = Self(rawValue: raw) {
            return value
        }
        assertionFailure("Unknown raw value '\(raw)' for \(Self.self)")
        return Self.fallback
    }
}

public enum Direction: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case income, expense, unknown
    public static var fallback: Direction {
        .unknown
    }
}

public enum TransactionType: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case invoice, receipt, creditNote, refund, paymentOnly, taxPayment, other
    public static var fallback: TransactionType {
        .other
    }
}

public enum WorkflowStatus: String, Codable, CaseIterable, Sendable {
    case draft, active, resolved, archived
}

public enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case unreviewed, needsReview, confirmed, conflict
}

/// See spec 16.1. `smallBusiness` represents a §19 UStG supply.
public enum TaxTreatment: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case domesticVAT
    case reverseCharge
    case intraCommunityAcquisition
    case intraCommunitySupply
    case export
    case importVAT
    case nonTaxable
    case exempt
    case smallBusiness
    case unknown
    public static var fallback: TaxTreatment {
        .unknown
    }
}

public enum TaxComponentKind: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case standard, reduced, zero, reverseChargeNote, exempt, fee, deposit, other
    public static var fallback: TaxComponentKind {
        .other
    }
}

public enum TaxAssessmentStatus: String, Codable, CaseIterable, Sendable {
    case proposed, confirmed, manualOverride
}

public enum CustomerType: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case b2b, b2c, unknown
    public static var fallback: CustomerType {
        .unknown
    }
}

public enum SupplyType: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case service, digitalService, goods, unknown
    public static var fallback: SupplyType {
        .unknown
    }
}

public enum ExchangeRateSource: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case bankActual, bmfMonthly, manual, documentStated, unknown
    public static var fallback: ExchangeRateSource {
        .unknown
    }
}

public enum DocumentType: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case invoice, receipt, creditNote, statement, contract, other, unknown
    public static var fallback: DocumentType {
        .unknown
    }
}

public enum DocumentRole: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case invoice, receipt, creditNote, statement, supportingEvidence, other
    public static var fallback: DocumentRole {
        .other
    }
}

public enum DocumentSource: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case dragDrop, fileImport, shareExtension, other
    public static var fallback: DocumentSource {
        .other
    }
}

public enum AccountKind: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case bank, creditCard, paypal, stripe, cash, other
    public static var fallback: AccountKind {
        .other
    }
}

public enum StatementLineClass: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case business, `private`, internalTransfer, taxPayment, unknown
    public static var fallback: StatementLineClass {
        .unknown
    }
}

public enum PaymentDirection: String, Codable, CaseIterable, Sendable {
    case inflow, outflow
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case bankTransfer, card, paypal, directDebit, cash, other, unknown
    public static var fallback: PaymentMethod {
        .unknown
    }
}

public enum PaymentSource: String, Codable, CaseIterable, Sendable {
    case statementLine, manual, documentStated
}

public enum MatchMethod: String, Codable, CaseIterable, Sendable {
    case exact, reference, invoiceNumber, heuristic, aiDisambiguated, manual, rule
}

public enum Provenance: String, Codable, CaseIterable, Sendable {
    case document, agent, calculated, manual, imported, rule
}

public enum RelationType: String, Codable, CaseIterable, Sendable {
    case creditNoteFor, refundOf, correctionOf, replaces, relatedTo
}

public enum ImportBatchStatus: String, Codable, CaseIterable, Sendable {
    case running, completed, completedWithErrors, cancelled
}

public enum ImportItemStatus: String, Codable, CaseIterable, Sendable {
    case queued, archiving, analyzing, matching, proposed, committed, skipped, duplicate, failed
}

public enum ModelRunOperation: String, Codable, CaseIterable, Sendable {
    case extraction, disambiguation, statementMapping
}

public enum ModelRunStatus: String, Codable, CaseIterable, Sendable {
    case running, succeeded, failed, timedOut
}

public enum ProposalKind: String, Codable, CaseIterable, Sendable {
    case createTransaction, updateTransaction, linkPayment, attachDocument, classifyStatementLines, mergeDuplicate
}

public enum ProposalStatus: String, Codable, CaseIterable, Sendable {
    case pending, accepted, acceptedEdited, rejected, skipped, superseded, committed
}

public enum PolicyDecision: String, Codable, CaseIterable, Sendable {
    case autoCommit, needsReview, blocked
}

public enum IssueSeverity: String, Codable, CaseIterable, Sendable {
    case info, warning, error
}

public enum IssueStatus: String, Codable, CaseIterable, Sendable {
    case open, resolved, ignored
}

public enum RuleKind: String, Codable, CaseIterable, Sendable {
    case counterpartyDefaults, statementLineClassification, statementColumnMapping, paymentMatchPattern
}

public enum AuditActor: String, Codable, CaseIterable, Sendable {
    case user, agent, system, `import`
}

public enum AuditAction: String, Codable, CaseIterable, Sendable {
    case create, update, delete, link, unlink, confirm, correct, lock, unlock
}

public enum LockScope: String, Codable, CaseIterable, Sendable {
    case ustva, eur
}

// MARK: - Derived status dimensions (spec 19)

public enum PaymentStatus: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case unknown, unpaid, partiallyPaid, paid
    public static var fallback: PaymentStatus {
        .unknown
    }
}

public enum DocumentStatus: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case missing, notRequired, complete
    public static var fallback: DocumentStatus {
        .missing
    }
}

// MARK: - Business profile enums (spec 17.1)

public enum VATStatus: String, Codable, CaseIterable, Sendable {
    case taxable, smallBusiness
}

public enum VATAccountingMethod: String, Codable, CaseIterable, Sendable {
    case cash, accrual
}

public enum UStVAPeriodicity: String, Codable, CaseIterable, Sendable {
    case monthly, quarterly, yearly
}

public enum BusinessType: String, Codable, CaseIterable, Sendable {
    case freelancer, soleProprietor
}

public enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case income, expense, assetCandidate, neutral
}
