import Foundation
import GRDB

/// Converges a development database onto the slimmer schema of `v001_initial`
/// after the pre-release cleanup: the four tables nothing ever wrote
/// (`accounts`, `rules`, `transaction_relations`, `locked_periods`) are gone,
/// and with them the columns that only existed to reference them or that no
/// code ever read back.
///
/// `v001_initial` already creates the slim shape, so a fresh database has
/// nothing to do here; `accounts` is the marker of an older database.
///
/// Every affected table is rebuilt in place - dropped columns take part in
/// indexes and foreign keys, so `ALTER TABLE ... DROP COLUMN` is not
/// available. Rows are carried over column by column, so no bookkeeping data
/// is lost; a statement line keeps its account as the account's IBAN.
///
/// The migration runs with `foreignKeyChecks: .deferred` (GRDB's default),
/// which disables foreign keys for the duration and verifies them again
/// before the changes are committed.
enum V003RemoveUnusedScaffolding {
    /// Rebuilt in dependency-free order; the view that reads several of them
    /// is dropped first and recreated afterwards.
    private static let rebuiltTables = [
        "business_profiles", "categories", "counterparties", "documents",
        "transactions", "payments", "payment_allocations",
        "field_provenance", "import_items"
    ]

    private static let droppedTables = ["transaction_relations", "locked_periods", "accounts", "rules"]

    /// Enum values whose Swift case is gone. Rewritten to the neighbouring
    /// case that means the same thing, so an old row still decodes.
    private static let replacedEnumValues: [(table: String, column: String, from: [String], to: String)] = [
        ("transactions", "workflow_status", ["draft", "resolved"], "active"),
        ("transaction_documents", "role", ["supportingEvidence"], "other"),
        ("documents", "source", ["shareExtension"], "other"),
        ("payments", "source", ["documentStated"], "manual"),
        ("payment_allocations", "match_method", ["aiDisambiguated"], "heuristic"),
        ("model_runs", "status", ["timedOut"], "failed")
    ]

    static func migrate(_ db: Database) throws {
        guard try db.tableExists("accounts") else { return }

        try db.execute(sql: "DROP VIEW IF EXISTS v_transaction_status")

        // A statement line referenced an account row; its IBAN is the only
        // part of that row anything would have used.
        try rebuild(
            db,
            table: "statement_lines",
            mapping: ["account_iban": "COALESCE(accounts.iban, old.account_id)"],
            join: "LEFT JOIN accounts ON accounts.id = old.account_id"
        )
        for table in rebuiltTables {
            try rebuild(db, table: table)
        }
        for table in droppedTables {
            try db.execute(sql: "DROP TABLE IF EXISTS \(table)")
        }

        for replacement in replacedEnumValues {
            let placeholders = databaseQuestionMarks(count: replacement.from.count)
            try db.execute(
                sql: "UPDATE \(replacement.table) SET \(replacement.column) = ? WHERE \(replacement.column) IN (\(placeholders))",
                arguments: StatementArguments([replacement.to] + replacement.from)
            )
        }

        for statement in V001Initial.statements where statement.contains("CREATE VIEW v_transaction_status") {
            try db.execute(sql: statement)
        }
    }

    /// Recreates `table` in its `v001_initial` shape and copies every row
    /// over. Columns the new table no longer has are left behind; columns
    /// listed in `mapping` take their value from the given SQL expression
    /// instead of from the old row.
    private static func rebuild(
        _ db: Database,
        table: String,
        mapping: [String: String] = [:],
        join: String = ""
    ) throws {
        let oldColumns = Set(try db.columns(in: table).map(\.name))
        for index in try db.indexes(on: table) where !index.name.hasPrefix("sqlite_") {
            try db.execute(sql: "DROP INDEX \(index.name)")
        }
        try db.execute(sql: "ALTER TABLE \(table) RENAME TO \(table)_old")
        for statement in V001Initial.statements(for: table) {
            try db.execute(sql: statement)
        }

        let targets = try db.columns(in: table)
            .map(\.name)
            .filter { mapping[$0] != nil || oldColumns.contains($0) }
        let sources = targets.map { mapping[$0] ?? "old.\($0)" }
        try db.execute(sql: """
        INSERT INTO \(table) (\(targets.joined(separator: ", ")))
        SELECT \(sources.joined(separator: ", ")) FROM \(table)_old old \(join)
        """)
        try db.execute(sql: "DROP TABLE \(table)_old")
    }

    private static func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
