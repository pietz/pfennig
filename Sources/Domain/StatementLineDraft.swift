import Foundation

/// One account movement read from a statement, before it is persisted.
///
/// The CSV importer (and later the PDF path) produce these; `Database`
/// turns them into `statement_lines` rows. Like the other drafts this is a
/// plain value type without behaviour, so both sides can depend on `Domain`
/// alone.
///
/// `lineFingerprint` is computed by the importer for the account the file
/// belongs to (`LineFingerprint.make`), because only the importer knows the
/// account key at that point. Storing it on the draft keeps the persistence
/// layer free of hashing.
public struct StatementLineDraft: Codable, Sendable, Hashable, Identifiable {
    /// Stable within one import run; the database assigns the real row id.
    public var id: String {
        lineFingerprint
    }

    /// 1-based line number in the source file, for error reporting and for
    /// showing the user where a value came from.
    public var sourceLineNumber: Int
    public var lineFingerprint: String

    public var bookingDate: LocalDate
    public var valueDate: LocalDate?
    /// The net effect on the account balance, fee included.
    public var amountMinor: Int64
    /// The processor fee contained in this movement, as a non-negative
    /// amount, when the export reports it separately (Revolut, PayPal,
    /// Stripe). A later step books it; `amountMinor` already accounts for it.
    public var feeMinor: Int64?
    public var currency: CurrencyCode
    public var counterpartyRaw: String?
    public var counterpartyIban: String?
    public var reference: String?
    public var bookingText: String?
    public var externalId: String?
    /// The untouched source row as a JSON object, column name to cell value.
    public var rawJson: String?
    public var classification: StatementLineClass

    public init(
        sourceLineNumber: Int,
        lineFingerprint: String,
        bookingDate: LocalDate,
        valueDate: LocalDate? = nil,
        amountMinor: Int64,
        feeMinor: Int64? = nil,
        currency: CurrencyCode = .eur,
        counterpartyRaw: String? = nil,
        counterpartyIban: String? = nil,
        reference: String? = nil,
        bookingText: String? = nil,
        externalId: String? = nil,
        rawJson: String? = nil,
        classification: StatementLineClass = .unknown
    ) {
        self.sourceLineNumber = sourceLineNumber
        self.lineFingerprint = lineFingerprint
        self.bookingDate = bookingDate
        self.valueDate = valueDate
        self.amountMinor = amountMinor
        self.feeMinor = feeMinor
        self.currency = currency
        self.counterpartyRaw = counterpartyRaw
        self.counterpartyIban = counterpartyIban
        self.reference = reference
        self.bookingText = bookingText
        self.externalId = externalId
        self.rawJson = rawJson
        self.classification = classification
    }

    public var money: Money {
        Money(minorUnits: amountMinor, currency: currency)
    }
}
