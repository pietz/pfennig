import Database
import Domain
import Foundation
import GRDB

/// The small, read-only data set used by the start page. Amounts are booked
/// gross amounts in EUR; no proposal is considered a booked transaction.
public struct StartOverview: Equatable, Sendable {
    public struct OpenItems: Equatable, Sendable {
        public let transactionsToReview: Int
        public let documentsToAdd: Int
        public let importProposals: Int

        public init(transactionsToReview: Int, documentsToAdd: Int, importProposals: Int) {
            self.transactionsToReview = transactionsToReview
            self.documentsToAdd = documentsToAdd
            self.importProposals = importProposals
        }

        public var isEmpty: Bool {
            transactionsToReview == 0 && documentsToAdd == 0 && importProposals == 0
        }
    }

    public let year: Int
    public let incomeMinor: Int64?
    public let expenseMinor: Int64?
    public let recordedBookingCount: Int
    public let incompleteEurAmountCount: Int
    public let openItems: OpenItems
    public let availableYears: [Int]

    public init(
        year: Int,
        incomeMinor: Int64?,
        expenseMinor: Int64?,
        recordedBookingCount: Int,
        incompleteEurAmountCount: Int,
        openItems: OpenItems,
        availableYears: [Int]
    ) {
        self.year = year
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
        self.recordedBookingCount = recordedBookingCount
        self.incompleteEurAmountCount = incompleteEurAmountCount
        self.openItems = openItems
        self.availableYears = availableYears
    }

    /// The result of the known EUR amounts. It is nil when one side consists
    /// only of bookings that cannot be included in an EUR total.
    public var resultMinor: Int64? {
        guard incompleteEurAmountCount == 0, let incomeMinor, let expenseMinor else { return nil }
        return incomeMinor - expenseMinor
    }
}

/// Deterministic aggregation for the local start page. The relevant date is
/// intentionally the same expression as the transaction list: last payment,
/// then invoice date, then import date.
public enum StartOverviewQuery {
    private struct TotalsRow: FetchableRecord, Decodable {
        var recordedBookingCount: Int
        var incomeBookingCount: Int
        var expenseBookingCount: Int
        var incomeMinor: Int64?
        var expenseMinor: Int64?
        var incompleteEurAmountCount: Int

        static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }
    }

    private struct OpenItemsRow: FetchableRecord, Decodable {
        var transactionsToReview: Int
        var documentsToAdd: Int

        static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }
    }

    private static let recordedCTE = """
    WITH recorded AS (
        SELECT
            t.*,
            \(TransactionQueryRules.relevantDateExpression(for: "t")) AS relevant_date
        FROM transactions t
        WHERE \(TransactionQueryRules.recordedVisibilityPredicate(for: "t"))
    )
    """

    /// Returns one snapshot for the selected year. `currentYear` is injected
    /// so boundary behaviour stays deterministic in tests.
    public static func fetch(_ db: Database, year: Int, currentYear: Int) throws -> StartOverview {
        let yearStart = String(format: "%04d-01-01", year)
        let nextYearStart = String(format: "%04d-01-01", year + 1)
        let yearArguments: StatementArguments = [
            "yearStart": yearStart,
            "nextYearStart": nextYearStart
        ]

        let totals = try TotalsRow.fetchOne(
            db,
            sql: recordedCTE + """
            SELECT
                COUNT(*) AS recorded_booking_count,
                COALESCE(SUM(CASE WHEN direction = 'income' THEN 1 ELSE 0 END), 0) AS income_booking_count,
                COALESCE(SUM(CASE WHEN direction = 'expense' THEN 1 ELSE 0 END), 0) AS expense_booking_count,
                SUM(CASE
                    WHEN direction = 'income' AND booked_currency = 'EUR' AND booked_gross_minor IS NOT NULL
                    THEN booked_gross_minor
                END) AS income_minor,
                SUM(CASE
                    WHEN direction = 'expense' AND booked_currency = 'EUR' AND booked_gross_minor IS NOT NULL
                    THEN booked_gross_minor
                END) AS expense_minor,
                COALESCE(SUM(CASE
                    WHEN direction NOT IN ('income', 'expense')
                      OR booked_currency <> 'EUR'
                      OR booked_gross_minor IS NULL THEN 1 ELSE 0
                END), 0) AS incomplete_eur_amount_count
            FROM recorded
            WHERE relevant_date >= :yearStart AND relevant_date < :nextYearStart
            """,
            arguments: yearArguments
        ) ?? TotalsRow(
            recordedBookingCount: 0,
            incomeBookingCount: 0,
            expenseBookingCount: 0,
            incomeMinor: nil,
            expenseMinor: nil,
            incompleteEurAmountCount: 0
        )

        let openItems = try OpenItemsRow.fetchOne(
            db,
            sql: recordedCTE + """
            SELECT
                COALESCE(SUM(CASE
                    WHEN \(TransactionQueryRules.needsAttentionPredicate(for: "recorded")) THEN 1 ELSE 0
                END), 0) AS transactions_to_review,
                COALESCE(SUM(CASE
                    WHEN \(TransactionQueryRules.missingDocumentsPredicate(for: "recorded"))
                    THEN 1 ELSE 0
                END), 0) AS documents_to_add
            FROM recorded
            """
        ) ?? OpenItemsRow(transactionsToReview: 0, documentsToAdd: 0)

        let pendingProposalCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM proposals WHERE status = 'pending'"
        ) ?? 0

        let years = try Int.fetchAll(
            db,
            sql: recordedCTE + """
            SELECT DISTINCT CAST(strftime('%Y', relevant_date) AS INTEGER)
              FROM recorded
             WHERE relevant_date IS NOT NULL
             ORDER BY 1 DESC
            """
        ).filter { $0 > 0 } + [currentYear]

        let availableYears = Array(Set(years)).sorted(by: >)
        let incomeMinor = totals.incomeBookingCount > 0 && totals.incomeMinor == nil
            ? nil
            : totals.incomeMinor ?? 0
        let expenseMinor = totals.expenseBookingCount > 0 && totals.expenseMinor == nil
            ? nil
            : totals.expenseMinor ?? 0

        return StartOverview(
            year: year,
            incomeMinor: incomeMinor,
            expenseMinor: expenseMinor,
            recordedBookingCount: totals.recordedBookingCount,
            incompleteEurAmountCount: totals.incompleteEurAmountCount,
            openItems: .init(
                transactionsToReview: openItems.transactionsToReview,
                documentsToAdd: openItems.documentsToAdd,
                importProposals: pendingProposalCount
            ),
            availableYears: availableYears
        )
    }

    public static func observation(year: Int, currentYear: Int)
        -> ValueObservation<ValueReducers.Fetch<StartOverview>>
    {
        ValueObservation.tracking { try fetch($0, year: year, currentYear: currentYear) }
    }
}

/// EÜR and VAT aggregation queries (spec 28).
public enum Aggregations {}
