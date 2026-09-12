import Domain
import Foundation
import GRDB

/// One row of the main transaction table (spec 6.2), joined with the derived
/// status view and the current tax assessment.
public struct TransactionListItem: FetchableRecord, Decodable, Identifiable, Sendable, Hashable {
    public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .convertFromSnakeCase
    }

    public var id: String
    public var title: String?
    public var counterpartyName: String?
    public var direction: Direction
    public var transactionType: TransactionType
    public var reviewStatus: ReviewStatus
    public var invoiceDate: LocalDate?
    public var lastPaymentDate: LocalDate?
    public var createdAt: String
    public var bookedGrossMinor: Int64?
    public var bookedCurrency: String
    public var originalGrossMinor: Int64?
    public var originalCurrency: String
    public var paymentStatus: PaymentStatus
    public var documentStatus: DocumentStatus
    public var taxTreatment: TaxTreatment?

    /// Counterparty if known, else the title, else a placeholder (spec 6.2).
    public var displayName: String {
        counterpartyName ?? title ?? "Ohne Bezeichnung"
    }

    /// Booked amount in EUR, signed by direction.
    public var bookedAmount: Money? {
        guard let minor = bookedGrossMinor else { return nil }
        let signed = direction == .expense ? -abs(minor) : minor
        return Money(minorUnits: signed, currency: CurrencyCode(bookedCurrency))
    }

    /// Original amount, shown secondary when it differs from the booked one.
    public var originalAmount: Money? {
        guard let minor = originalGrossMinor, originalCurrency != bookedCurrency else { return nil }
        let signed = direction == .expense ? -abs(minor) : minor
        return Money(minorUnits: signed, currency: CurrencyCode(originalCurrency))
    }

    /// EÜR date if paid, else invoice date, else import date (spec 5.2).
    public var relevantDate: LocalDate {
        lastPaymentDate ?? invoiceDate ?? LocalDate(Timestamp.date(createdAt) ?? Date())
    }

    public var relevantDateOrigin: String {
        if lastPaymentDate != nil {
            "Zahlung"
        } else if invoiceDate != nil {
            "Rechnung"
        } else {
            "Import"
        }
    }
}

public enum TransactionListQuery {
    /// Transactions for the main table, newest relevant date first.
    /// `search` matches counterparty, title, invoice number and amount.
    /// `direction`, when set, restricts the result to that direction only.
    public static func fetch(_ db: Database, search: String = "", direction: Direction? = nil) throws -> [TransactionListItem] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = StatementArguments()
        var filter = ""
        if !trimmed.isEmpty {
            let pattern = "%\(trimmed.lowercased())%"
            let digits = trimmed.replacingOccurrences(of: ",", with: ".")
                .filter { $0.isNumber || $0 == "." || $0 == "-" }
            filter += """
              AND (LOWER(COALESCE(c.display_name, '')) LIKE :pattern
                   OR LOWER(COALESCE(t.title, '')) LIKE :pattern
                   OR LOWER(COALESCE(t.invoice_number, '')) LIKE :pattern
                   OR (:digits <> '' AND CAST(ABS(COALESCE(t.booked_gross_minor, 0)) AS TEXT) LIKE :amountPattern))
            """
            arguments = arguments + [
                "pattern": pattern,
                "digits": digits,
                "amountPattern": "%\(digits.replacingOccurrences(of: ".", with: ""))%"
            ]
        }
        if let direction {
            filter += " AND t.direction = :direction"
            arguments = arguments + ["direction": direction.rawValue]
        }
        let sql = """
        SELECT
            t.id,
            t.title,
            c.display_name AS counterparty_name,
            t.direction,
            t.transaction_type,
            t.review_status,
            t.invoice_date,
            (SELECT MAX(p.payment_date)
               FROM payment_allocations pa
               JOIN payments p ON p.id = pa.payment_id
              WHERE pa.transaction_id = t.id) AS last_payment_date,
            t.created_at,
            t.booked_gross_minor,
            t.booked_currency,
            t.original_gross_minor,
            t.original_currency,
            COALESCE(v.payment_status, 'unknown') AS payment_status,
            COALESCE(v.document_status, 'missing') AS document_status,
            ta.treatment AS tax_treatment
        FROM transactions t
        LEFT JOIN counterparties c ON c.id = t.counterparty_id
        LEFT JOIN v_transaction_status v ON v.id = t.id
        LEFT JOIN tax_assessments ta ON ta.transaction_id = t.id AND ta.superseded_at IS NULL
        WHERE t.deleted_at IS NULL AND t.workflow_status <> 'archived'
        \(filter)
        ORDER BY COALESCE(last_payment_date, t.invoice_date, DATE(t.created_at)) DESC, t.created_at DESC
        """
        return try TransactionListItem.fetchAll(db, sql: sql, arguments: arguments)
    }

    /// Live query for SwiftUI; emits a new array on every relevant write.
    public static func observation(search: String = "", direction: Direction? = nil)
        -> ValueObservation<ValueReducers.Fetch<[TransactionListItem]>>
    {
        ValueObservation.tracking { try fetch($0, search: search, direction: direction) }
    }
}

public extension AppDatabase {
    /// The single business profile of V1, if onboarding completed.
    func businessProfile() throws -> BusinessProfile? {
        try reader.read { try BusinessProfile.fetchOne($0) }
    }

    /// Whether onboarding still needs to run: true unless the archive
    /// already has a saved business profile. Pure function of the database
    /// so it can be unit-tested without any UI (spec 20).
    func needsOnboarding() throws -> Bool {
        try businessProfile() == nil
    }

    func saveBusinessProfile(_ profile: BusinessProfile) throws {
        try writer.write { try profile.save($0) }
    }

    func categories() throws -> [Category] {
        try reader.read { db in
            try Category.fetchAll(db, sql: "SELECT * FROM categories WHERE archived_at IS NULL ORDER BY sort_order")
        }
    }

    func transactionList(search: String = "") throws -> [TransactionListItem] {
        try reader.read { try TransactionListQuery.fetch($0, search: search) }
    }
}
