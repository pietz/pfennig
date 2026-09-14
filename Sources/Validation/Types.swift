import Domain

/// A single `tax_components` row as seen by the validator (spec 17.7).
public struct TaxComponentSnapshot: Sendable, Equatable {
    public let rate: String?
    public let net: Money
    public let tax: Money
    public let kind: TaxComponentKind

    public init(rate: String?, net: Money, tax: Money, kind: TaxComponentKind) {
        self.rate = rate
        self.net = net
        self.tax = tax
        self.kind = kind
    }
}

/// One `payment_allocations` row relevant to this transaction, plus the
/// running total already allocated against that same payment across *all*
/// transactions (the caller/Database layer supplies this since a single
/// transaction snapshot cannot see other transactions, spec 22).
public struct PaymentAllocationFact: Sendable, Equatable {
    public let paymentID: String
    public let paymentBookedAmount: Money
    public let allocatedToThisTransaction: Money
    public let totalAllocatedForPayment: Money

    public init(
        paymentID: String,
        paymentBookedAmount: Money,
        allocatedToThisTransaction: Money,
        totalAllocatedForPayment: Money
    ) {
        self.paymentID = paymentID
        self.paymentBookedAmount = paymentBookedAmount
        self.allocatedToThisTransaction = allocatedToThisTransaction
        self.totalAllocatedForPayment = totalAllocatedForPayment
    }
}

/// Summary of `field_provenance` for a transaction, just enough for spec
/// 14.2's "Amount > configurable threshold with `agent` provenance only".
public struct ProvenanceSummary: Sendable, Equatable {
    /// True if at least one relevant field has non-`agent` provenance
    /// (`document`, `manual`, `calculated`, `imported`, `rule`) - i.e. a
    /// human or a deterministic source has touched it.
    public let hasAnyNonAgentProvenance: Bool

    public init(hasAnyNonAgentProvenance: Bool) {
        self.hasAnyNonAgentProvenance = hasAnyNonAgentProvenance
    }
}

/// A workflow-status transition (spec 18 `WorkflowStatus`).
public struct WorkflowTransition: Hashable, Sendable {
    public let from: WorkflowStatus
    public let to: WorkflowStatus

    public init(from: WorkflowStatus, to: WorkflowStatus) {
        self.from = from
        self.to = to
    }
}

/// Key for a statement-line duplicate fingerprint check (spec 14.1: "on the
/// same account").
public struct StatementLineFingerprintKey: Hashable, Sendable {
    public let accountIBAN: String
    public let fingerprint: String

    public init(accountIBAN: String, fingerprint: String) {
        self.accountIBAN = accountIBAN
        self.fingerprint = fingerprint
    }
}
