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

    /// The signed contribution of one payment allocation: positive when the
    /// payment moves in the transaction's own direction (money out on an
    /// expense, money in on an income), negative when it moves back. A refund
    /// is exactly that opposite-direction payment; amounts stay positive on
    /// both the payment and its allocation.
    public static func signedAllocationExpression(
        allocation: String,
        payment: String,
        transaction: String
    ) -> String {
        """
        CASE WHEN \(payment).direction =
                  CASE \(transaction).direction WHEN 'income' THEN 'inflow' ELSE 'outflow' END
             THEN \(allocation).allocated_minor ELSE -\(allocation).allocated_minor END
        """
    }

    /// What the payments of a transaction have settled: everything allocated
    /// in its own direction minus everything paid back. A credit note is
    /// settled with a negative amount, because its gross is negative too.
    public static func netAllocatedExpression(for alias: String) -> String {
        """
        (SELECT COALESCE(SUM(\(signedAllocationExpression(
            allocation: "pa",
            payment: "p",
            transaction: alias
        ))), 0)
           FROM payment_allocations pa
           JOIN payments p ON p.id = pa.payment_id
          WHERE pa.transaction_id = \(alias).id)
        """
    }

    /// The same sum for every transaction at once, one row per transaction
    /// that has payments at all - so a missing row means "nothing paid" and a
    /// row with zero means "paid and given back again".
    public static let settledAllocationsSubquery = """
    SELECT pa.transaction_id AS transaction_id,
           SUM(\(signedAllocationExpression(allocation: "pa", payment: "p", transaction: "tx"))) AS net_allocated
      FROM payment_allocations pa
      JOIN payments p ON p.id = pa.payment_id
      JOIN transactions tx ON tx.id = pa.transaction_id
     GROUP BY pa.transaction_id
    """

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
