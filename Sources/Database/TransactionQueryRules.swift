/// Shared SQL rules for the recorded transaction scope and Start/list exceptions.
public enum TransactionQueryRules {
    /// The earliest payment date used by the relevant-date fallback.
    public static func firstPaymentDateExpression(for alias: String) -> String {
        "(SELECT MIN(p.payment_date) FROM payment_allocations pa JOIN payments p ON p.id = pa.payment_id WHERE pa.transaction_id = \(alias).id)"
    }

    /// Ledger and Start date: document date, then earliest payment, then import
    /// date. Tax periods are dated by payment and do not use this expression.
    ///
    /// `created_at` is a UTC timestamp while the ledger shows its local
    /// calendar day, so the fallback converts: without `localtime` an evening
    /// import would sort and filter one day - and on New Year one year -
    /// before the date printed in its own row.
    public static func relevantDateExpression(for alias: String) -> String {
        "COALESCE(\(alias).invoice_date, \(firstPaymentDateExpression(for: alias)), DATE(\(alias).created_at, 'localtime'))"
    }

    /// Recorded transactions exclude archived and soft-deleted rows.
    public static func recordedVisibilityPredicate(for alias: String) -> String {
        "\(alias).deleted_at IS NULL AND \(alias).workflow_status <> 'archived'"
    }

    /// Review states shown by the open-items drilldown.
    public static func needsAttentionPredicate(for alias: String) -> String {
        "\(alias).review_status IN ('unreviewed', 'needsReview', 'conflict')"
    }

    /// A transaction needs a document when it has no allocation or any
    /// allocation expects a document. Existing documents suppress the result.
    public static func missingDocumentsPredicate(for alias: String) -> String {
        """
        NOT EXISTS (
            SELECT 1
              FROM transaction_documents td
             WHERE td.transaction_id = \(alias).id
        )
        AND (
            NOT EXISTS (
                SELECT 1
                  FROM bookkeeping_allocations ba
                 WHERE ba.transaction_id = \(alias).id
            )
            OR EXISTS (
                SELECT 1
                  FROM bookkeeping_allocations ba
                  JOIN categories expected_category ON expected_category.id = ba.category_id
                 WHERE ba.transaction_id = \(alias).id
                   AND expected_category.document_expected = 1
            )
        )
        """
    }
}
