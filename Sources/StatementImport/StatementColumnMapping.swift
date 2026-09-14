import Domain
import Foundation

/// How to read one statement CSV: which header column holds which fact.
///
/// Columns are addressed by **header name**, not by position, so a mapping
/// survives an export that gained or reordered a column, and so the model can
/// answer the "unknown header" question in the same vocabulary the user sees.
/// Every case is `Codable`: this is exactly the shape the model must return
/// for a header the catalog does not recognize (see ``UnmappedHeader``).
public struct StatementColumnMapping: Codable, Sendable, Hashable {
    /// Identifier of the catalog entry this came from, `nil` when it was
    /// derived heuristically or supplied by the model.
    public var formatID: String?

    public var bookingDate: String
    public var bookingDateFormat: StatementDateFormat
    public var valueDate: String?
    public var valueDateFormat: StatementDateFormat?

    public var amount: AmountSource
    /// Some card statements (Amex DE) report purchases as positive amounts.
    public var invertSign: Bool

    /// Column holding a separately reported processor fee.
    public var feeColumn: String?
    /// `true` when the amount column is already net of the fee (PayPal's
    /// `Netto`, Stripe's `net`); `false` when the fee still has to be
    /// subtracted to get the balance effect (Revolut).
    public var feeIncludedInAmount: Bool

    /// Running balance after the booking, when the export carries one. Used
    /// for the continuity check, never stored.
    public var balanceColumn: String?
    /// Rows that do not pass are not imported but reported.
    public var rowFilter: RowFilter?

    public var currencyColumn: String?
    public var defaultCurrency: CurrencyCode

    public var counterparty: CounterpartySource?
    public var counterpartyIBAN: String?
    public var reference: ReferenceSource?
    public var bookingText: String?
    public var externalID: String?
    /// Column holding the *own* account's IBAN, repeated on every row.
    public var ownIBANColumn: String?

    /// All labels that may start a segment inside a label-packed text column
    /// (comdirect). Used to know where a segment ends.
    public var labelVocabulary: [String]

    public init(
        formatID: String? = nil,
        bookingDate: String,
        bookingDateFormat: StatementDateFormat = .auto,
        valueDate: String? = nil,
        valueDateFormat: StatementDateFormat? = nil,
        amount: AmountSource,
        invertSign: Bool = false,
        feeColumn: String? = nil,
        feeIncludedInAmount: Bool = false,
        balanceColumn: String? = nil,
        rowFilter: RowFilter? = nil,
        currencyColumn: String? = nil,
        defaultCurrency: CurrencyCode = .eur,
        counterparty: CounterpartySource? = nil,
        counterpartyIBAN: String? = nil,
        reference: ReferenceSource? = nil,
        bookingText: String? = nil,
        externalID: String? = nil,
        ownIBANColumn: String? = nil,
        labelVocabulary: [String] = []
    ) {
        self.formatID = formatID
        self.bookingDate = bookingDate
        self.bookingDateFormat = bookingDateFormat
        self.valueDate = valueDate
        self.valueDateFormat = valueDateFormat
        self.amount = amount
        self.invertSign = invertSign
        self.feeColumn = feeColumn
        self.feeIncludedInAmount = feeIncludedInAmount
        self.balanceColumn = balanceColumn
        self.rowFilter = rowFilter
        self.currencyColumn = currencyColumn
        self.defaultCurrency = defaultCurrency
        self.counterparty = counterparty
        self.counterpartyIBAN = counterpartyIBAN
        self.reference = reference
        self.bookingText = bookingText
        self.externalID = externalID
        self.ownIBANColumn = ownIBANColumn
        self.labelVocabulary = labelVocabulary
    }

    // MARK: - Amount

    public enum AmountSource: Codable, Sendable, Hashable {
        /// One column carrying the sign, the common case.
        case signed(column: String)
        /// A debit and a credit column, one of them empty per row. The debit
        /// value becomes negative.
        case debitCredit(debit: String, credit: String)
        /// A magnitude column plus a column that decides the sign, such as
        /// `Soll`/`Haben` or `Ausgang`/`Eingang`.
        case indicated(amount: String, indicator: String, debitValues: [String], creditValues: [String])

        /// Every column this needs, for validating a mapping against a header.
        public var columns: [String] {
            switch self {
            case let .signed(column): [column]
            case let .debitCredit(debit, credit): [debit, credit]
            case let .indicated(amount, indicator, _, _): [amount, indicator]
            }
        }
    }

    // MARK: - Counterparty

    public enum CounterpartySource: Codable, Sendable, Hashable {
        case column(String)
        /// Two columns, payer and payee, one of which is the account owner.
        /// Which one is the counterparty follows the sign of the amount.
        case payerOrPayee(payer: String, payee: String)
        /// Labelled segments packed into one free-text column (comdirect):
        /// the first of `labels` that occurs wins.
        case labelled(column: String, labels: [String])

        public var columns: [String] {
            switch self {
            case let .column(column): [column]
            case let .payerOrPayee(payer, payee): [payer, payee]
            case let .labelled(column, _): [column]
            }
        }
    }

    // MARK: - Row filter

    /// Keeps only rows whose `column` holds one of `values`, compared
    /// case-insensitively. Revolut's `State` is the reason this exists: only
    /// `COMPLETED` rows are real movements.
    public struct RowFilter: Codable, Sendable, Hashable {
        public var column: String
        public var keepValues: [String]

        public init(column: String, keepValues: [String]) {
            self.column = column
            self.keepValues = keepValues
        }

        public func keeps(_ value: String) -> Bool {
            let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return keepValues.contains { $0.lowercased() == candidate }
        }
    }

    // MARK: - Reference

    public enum ReferenceSource: Codable, Sendable, Hashable {
        /// One or several columns, concatenated with a single space.
        case columns([String])
        /// The segment behind one label inside a label-packed column.
        case labelled(column: String, label: String)

        public var columns: [String] {
            switch self {
            case let .columns(columns): columns
            case let .labelled(column, _): [column]
            }
        }
    }

    // MARK: - Validation

    /// Every header name the mapping refers to.
    public var referencedColumns: [String] {
        var columns = [bookingDate]
        columns += amount.columns
        columns += [
            valueDate, currencyColumn, counterpartyIBAN, bookingText, externalID, ownIBANColumn,
            feeColumn, balanceColumn, rowFilter?.column
        ].compactMap(\.self)
        columns += counterparty?.columns ?? []
        columns += reference?.columns ?? []
        return columns
    }

    /// Names the mapping refers to that the header does not contain. A
    /// model-supplied mapping is only accepted when this is empty.
    public func missingColumns(in header: [String]) -> [String] {
        let known = Set(header.map(HeaderNormalization.normalize))
        return referencedColumns
            .filter { !known.contains(HeaderNormalization.normalize($0)) }
            .sorted()
    }
}

/// Date layouts a mapping can declare. `auto` sniffs the value itself and is
/// what the generic heuristic uses when the header alone says nothing.
public enum StatementDateFormat: String, Codable, Sendable, CaseIterable {
    case auto
    /// The German dotted date, with either year length: `31.08.2026` and
    /// `31.08.26` are the same layout. Nothing distinguishes them but the
    /// export template, and they cannot be confused with each other, so a
    /// format that gains or loses the century keeps importing.
    case dayMonthYear
    /// `2026-08-31`, with an optional time part that is ignored.
    case iso
    /// `31/08/2026`
    case dayMonthYearSlash
    /// `08/31/2026`
    case monthDayYearSlash
}
