/// Shared SQL rules for the recorded transaction scope and Start/list exceptions.
public enum TransactionQueryRules {
    /// The latest payment date used by the relevant-date rule.
    public static func lastPaymentDateExpression(for alias: String) -> String {
        "(SELECT MAX(p.payment_date) FROM payment_allocations pa JOIN payments p ON p.id = pa.payment_id WHERE pa.transaction_id = \(alias).id)"
    }

    /// Ledger display date: last payment, then invoice date, then import date.
    public static func relevantDateExpression(for alias: String) -> String {
        "COALESCE(\(lastPaymentDateExpression(for: alias)), \(alias).invoice_date, DATE(\(alias).created_at))"
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
