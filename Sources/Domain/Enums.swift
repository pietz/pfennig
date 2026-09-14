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

    /// The payment direction that settles an ordinary transaction of this
    /// direction: money out pays an expense, money in pays an invoice. A
    /// payment moving the other way is a refund and counts negatively; a
    /// credit note settles with the opposite direction because its amounts
    /// are negative, not because this rule changes.
    public var settlingPaymentDirection: PaymentDirection {
        self == .income ? .inflow : .outflow
    }
}

/// A refund is not a type of its own: it is an opposite-direction payment on
/// the transaction it refunds. `paymentOnly` belongs to the statement import
/// and is not offered in the user's picker (`userSelectable`).
public enum TransactionType: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case invoice, receipt, creditNote, paymentOnly, taxPayment, other

    /// The types a person can choose in the inspector.
    public static let userSelectable: [TransactionType] = [.invoice, .receipt, .creditNote, .taxPayment, .other]

    public static var fallback: TransactionType {
        .other
    }
}

public enum WorkflowStatus: String, Codable, CaseIterable, Sendable {
    case active, archived
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

/// Services and goods are the distinction that separates a §13b reverse
/// charge from an intra-Community acquisition. A digital service is a service;
/// the only rule that would separate the two - B2C supplies to EU consumers -
/// is out of scope.
public enum SupplyType: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case service, goods, unknown
    public static var fallback: SupplyType {
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
    case invoice, receipt, creditNote, statement, other
    public static var fallback: DocumentRole {
        .other
    }
}

public enum DocumentSource: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case dragDrop, fileImport, other
    public static var fallback: DocumentSource {
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

    /// The other way round: the direction a refund of this payment moves in.
    public var opposite: PaymentDirection {
        self == .inflow ? .outflow : .inflow
    }
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case bankTransfer, card, paypal, directDebit, cash, other, unknown
    public static var fallback: PaymentMethod {
        .unknown
    }
}

public enum PaymentSource: String, Codable, CaseIterable, Sendable {
    case statementLine, manual
}

public enum MatchMethod: String, Codable, CaseIterable, Sendable {
    case exact, reference, invoiceNumber, heuristic, manual
}

public enum Provenance: String, Codable, CaseIterable, Sendable {
    case document, agent, calculated, manual, imported
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
    case running, succeeded, failed
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

public enum AuditActor: String, Codable, CaseIterable, Sendable {
    case user, agent, system, `import`
}

public enum AuditAction: String, Codable, CaseIterable, Sendable {
    case create, update, delete, link, unlink, confirm, correct, lock, unlock
}

// MARK: - Derived status dimensions (spec 19)

/// Derived from the *net* allocated amount: payments in the transaction's own
/// direction minus payments back. `refunded` is the state where money moved
/// both ways and nothing is left: payments exist, but they cancel out.
public enum PaymentStatus: String, Codable, CaseIterable, Sendable, UnknownFallbackDecodable {
    case unknown, unpaid, partiallyPaid, paid, refunded
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
