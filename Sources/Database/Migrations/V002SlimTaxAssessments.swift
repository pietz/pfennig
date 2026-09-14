import Foundation
import GRDB

/// Removes the obsolete per-transaction tax-point and bookkeeping columns from
/// `tax_assessments`: `input_vat_date`, `output_vat_date`, `tax_country`,
/// `reasoning` and `superseded_at`.
///
/// `v001_initial` already creates the slim table, so a fresh database has
/// nothing to do here. Development databases created before this change still
/// carry the old columns; they are converged by rebuilding the table, which
/// also drops the `superseded_at` history (the current row per transaction is
/// the only one anything ever read).
///
/// `superseded_at` is part of `idx_taxassess_transaction`, so `ALTER TABLE
/// ... DROP COLUMN` is not available; the rebuild is the supported path.
enum V002SlimTaxAssessments {
    static func migrate(_ db: Database) throws {
        let columns = try db.columns(in: "tax_assessments").map(\.name)
        guard columns.contains("superseded_at") || columns.contains("input_vat_date") else { return }

        try db.execute(sql: "DROP INDEX IF EXISTS idx_taxassess_transaction")
        try db.execute(sql: "ALTER TABLE tax_assessments RENAME TO tax_assessments_old")
        for statement in V001Initial.statements where statement.contains("CREATE TABLE tax_assessments") {
            try db.execute(sql: statement)
        }
        try db.execute(sql: "CREATE INDEX idx_taxassess_transaction ON tax_assessments(transaction_id)")

        // Only the current assessment survives; a superseded row was never read.
        let supersededFilter = columns.contains("superseded_at") ? "WHERE superseded_at IS NULL" : ""
        try db.execute(sql: """
        INSERT INTO tax_assessments (
            id, transaction_id, treatment, customer_type, supply_type, customer_vat_id,
            taxable_base_minor, vat_shown_minor, self_assessed_vat_minor,
            deductible_input_vat_minor, output_vat_minor, currency,
            status, created_at, updated_at
        )
        SELECT id, transaction_id, treatment, customer_type, supply_type, customer_vat_id,
               taxable_base_minor, vat_shown_minor, self_assessed_vat_minor,
               deductible_input_vat_minor, output_vat_minor, currency,
               status, created_at, updated_at
          FROM tax_assessments_old
          \(supersededFilter)
        """)
        try db.execute(sql: "DROP TABLE tax_assessments_old")
    }
}
