import Domain
import Foundation
import GRDB

/// What one statement import changed in `statement_lines`.
public struct StatementLineInsertReport: Sendable, Equatable {
    public let inserted: Int
    /// Lines the archive already had, from an earlier or overlapping export.
    public let alreadyKnown: Int
    public let insertedIDs: [String]

    public init(inserted: Int, alreadyKnown: Int, insertedIDs: [String]) {
        self.inserted = inserted
        self.alreadyKnown = alreadyKnown
        self.insertedIDs = insertedIDs
    }
}

/// Persistence for account statement lines (spec 17.12).
///
/// Identity is `UNIQUE(account_iban, line_fingerprint)`: re-importing the same
/// export, or an export overlapping a previous period, adds only the lines the
/// archive does not have yet. Classification stays as the deterministic
/// classifier left it and `payment_id` stays `NULL` — matching is a later step.
public struct StatementLineRepository: Sendable {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Inserts the drafts of one import.
    ///
    /// The drafts carry the fingerprint the importer computed for
    /// `accountKey`; passing drafts fingerprinted for a different account
    /// would defeat the duplicate check, so both always come from the same
    /// `StatementImportResult`.
    @discardableResult
    public func insert(
        _ drafts: [StatementLineDraft],
        accountKey: String,
        documentID: String? = nil
    ) throws -> StatementLineInsertReport {
        guard !drafts.isEmpty else {
            return StatementLineInsertReport(inserted: 0, alreadyKnown: 0, insertedIDs: [])
        }
        return try database.writer.write { db in
            var existing = try Set(String.fetchAll(
                db,
                sql: "SELECT line_fingerprint FROM statement_lines WHERE account_iban = ?",
                arguments: [accountKey]
            ))
            var insertedIDs: [String] = []
            var alreadyKnown = 0
            let now = Timestamp.string()

            for draft in drafts {
                guard existing.insert(draft.lineFingerprint).inserted else {
                    alreadyKnown += 1
                    continue
                }
                let record = StatementLine(
                    accountIban: accountKey,
                    documentId: documentID,
                    lineFingerprint: draft.lineFingerprint,
                    externalId: draft.externalId,
                    bookingDate: draft.bookingDate,
                    valueDate: draft.valueDate,
                    amountMinor: draft.amountMinor,
                    feeMinor: draft.feeMinor,
                    currency: draft.currency.rawValue,
                    counterpartyRaw: draft.counterpartyRaw,
                    counterpartyIban: draft.counterpartyIban,
                    reference: draft.reference,
                    bookingText: draft.bookingText,
                    rawJson: draft.rawJson,
                    classification: draft.classification,
                    classificationSubtype: nil,
                    paymentId: nil,
                    createdAt: now,
                    updatedAt: now
                )
                try record.insert(db)
                insertedIDs.append(record.id)
            }
            return StatementLineInsertReport(
                inserted: insertedIDs.count,
                alreadyKnown: alreadyKnown,
                insertedIDs: insertedIDs
            )
        }
    }

    /// Every account the archive already holds statement lines for. This is
    /// the set the classifier recognizes internal transfers against.
    public func knownAccountKeys() throws -> Set<String> {
        try database.reader.read { try Self.knownAccountKeys($0) }
    }

    public static func knownAccountKeys(_ db: Database) throws -> Set<String> {
        try Set(String.fetchAll(db, sql: "SELECT DISTINCT account_iban FROM statement_lines"))
    }

    public func lines(accountKey: String) throws -> [StatementLine] {
        try database.reader.read { db in
            try StatementLine.fetchAll(
                db,
                sql: "SELECT * FROM statement_lines WHERE account_iban = ? ORDER BY booking_date, rowid",
                arguments: [accountKey]
            )
        }
    }

    public func count(accountKey: String? = nil) throws -> Int {
        try database.reader.read { db in
            if let accountKey {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM statement_lines WHERE account_iban = ?",
                    arguments: [accountKey]
                ) ?? 0
            }
            return try StatementLine.fetchCount(db)
        }
    }
}
