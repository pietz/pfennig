import Domain

/// Result of preparing one Umsatzsteuer-Voranmeldung period. Produced by the
/// deterministic UStVA calculation, consumed by the task window, the copyable
/// value list, and the XML exporter. Amounts are EUR minor units (cents);
/// base lines (Kz 81, 86, 46, ...) are additionally rounded to whole euros by
/// the consumer where the form requires it.
public struct UStVAReturn: Sendable, Equatable {
    /// One transaction/payment slice contributing to a form line.
    public struct Contribution: Sendable, Equatable, Identifiable {
        public var id: String { "\(transactionID)|\(paymentID ?? "-")|\(kennzahl)" }
        public let kennzahl: Int
        public let transactionID: String
        public let paymentID: String?
        /// Date that placed the slice into this period (payment date, or invoice/service date for §13b).
        public let date: LocalDate
        public let counterpartyName: String?
        public let description: String
        public let amountMinor: Int64

        public init(kennzahl: Int, transactionID: String, paymentID: String?, date: LocalDate,
                    counterpartyName: String?, description: String, amountMinor: Int64) {
            self.kennzahl = kennzahl
            self.transactionID = transactionID
            self.paymentID = paymentID
            self.date = date
            self.counterpartyName = counterpartyName
            self.description = description
            self.amountMinor = amountMinor
        }
    }

    /// One Kennzahl of the form.
    public struct Line: Sendable, Equatable, Identifiable {
        public var id: Int { kennzahl }
        public let kennzahl: Int
        /// Short German label as printed on the form, e.g. "Steuerpflichtige Umsätze 19 %".
        public let title: String
        /// Base lines report a Bemessungsgrundlage (whole euros on the form); tax lines report a tax amount in cents.
        public let isBase: Bool
        public let amountMinor: Int64
        /// False while the Kennzahl mapping has not been checked against the official form for this year.
        public let isVerified: Bool
        public let contributions: [Contribution]

        public init(kennzahl: Int, title: String, isBase: Bool, amountMinor: Int64, isVerified: Bool,
                    contributions: [Contribution]) {
            self.kennzahl = kennzahl
            self.title = title
            self.isBase = isBase
            self.amountMinor = amountMinor
            self.isVerified = isVerified
            self.contributions = contributions
        }
    }

    /// A case that could not be resolved deterministically; the return is a draft while any exist.
    public struct Exception: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable, Codable {
            case unknownTreatment
            case missingEURAmount
            case componentMismatch
            case paymentWithoutTransaction
            case expenseWithoutDocument
            case reverseChargeUnclear
            case other
        }

        public var id: String { "\(kind.rawValue)|\(transactionID ?? "-")|\(paymentID ?? "-")" }
        public let kind: Kind
        public let transactionID: String?
        public let paymentID: String?
        public let message: String

        public init(kind: Kind, transactionID: String?, paymentID: String?, message: String) {
            self.kind = kind
            self.transactionID = transactionID
            self.paymentID = paymentID
            self.message = message
        }
    }

    public let period: UStVAPeriod
    public let formYear: Int
    public let taxNumber: String?
    public let isSmallBusiness: Bool
    /// Ordered as they appear on the form.
    public let lines: [Line]
    /// Kz 83: positive = Zahllast, negative = Erstattung.
    public let payableMinor: Int64
    public let exceptions: [Exception]

    public var isDraft: Bool { !exceptions.isEmpty }

    public init(period: UStVAPeriod, formYear: Int, taxNumber: String?, isSmallBusiness: Bool,
                lines: [Line], payableMinor: Int64, exceptions: [Exception]) {
        self.period = period
        self.formYear = formYear
        self.taxNumber = taxNumber
        self.isSmallBusiness = isSmallBusiness
        self.lines = lines
        self.payableMinor = payableMinor
        self.exceptions = exceptions
    }

    public func line(_ kennzahl: Int) -> Line? { lines.first { $0.kennzahl == kennzahl } }
}
