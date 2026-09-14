import CryptoKit
import Database
import Domain
import Foundation
import GRDB
import Tax

/// "Als übermittelt markieren" (spec `ustva-preparation.md`): remembers which
/// periods the user already filed, without locking anything. Marking is
/// reversible and never changes a booking.
///
/// Change detection stores a fingerprint of the prepared form lines instead of
/// a second copy of the values: `hasChangedSinceSubmission` re-prepares the
/// period and compares hashes, so any edit that moves a Kennzahl - a new
/// payment, a corrected rate, a deleted transaction - surfaces as
/// "Zeitraum verändert seit Übermittlung".
public enum SubmittedReturnRepository {
    /// Marks `result`'s period as submitted, replacing an earlier mark for the
    /// same period. Returns the stored row.
    @discardableResult
    public static func markSubmitted(
        _ database: AppDatabase,
        profileID: String,
        result: UStVAReturn,
        submittedAt: String = Timestamp.string()
    ) throws -> SubmittedReturnRecord {
        let record = SubmittedReturnRecord(
            businessProfileId: profileID,
            year: result.period.year,
            kind: kindName(result.period.kind),
            periodIndex: result.period.index,
            submittedAt: submittedAt,
            payableMinor: result.payableMinor,
            contentHash: contentHash(of: result)
        )
        try database.writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM submitted_returns
                 WHERE business_profile_id = ? AND year = ? AND kind = ? AND period_index = ?
                """,
                arguments: [profileID, record.year, record.kind, record.periodIndex]
            )
            try record.insert(db)
        }
        return record
    }

    /// Removes the mark for a period. Does nothing when it was not marked.
    public static func unmark(_ database: AppDatabase, profileID: String, period: UStVAPeriod) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM submitted_returns
                 WHERE business_profile_id = ? AND year = ? AND kind = ? AND period_index = ?
                """,
                arguments: [profileID, period.year, kindName(period.kind), period.index]
            )
        }
    }

    /// All marked periods, newest period first.
    public static func fetchAll(_ database: AppDatabase, profileID: String) throws -> [SubmittedReturnRecord] {
        try database.reader.read { try fetchAll($0, profileID: profileID) }
    }

    public static func fetchAll(_ db: Database, profileID: String) throws -> [SubmittedReturnRecord] {
        try SubmittedReturnRecord.fetchAll(
            db,
            sql: """
            SELECT * FROM submitted_returns
             WHERE business_profile_id = ?
             ORDER BY year DESC, period_index DESC, kind
            """,
            arguments: [profileID]
        )
    }

    public static func fetch(
        _ database: AppDatabase,
        profileID: String,
        period: UStVAPeriod
    ) throws -> SubmittedReturnRecord? {
        try database.reader.read { try fetch($0, profileID: profileID, period: period) }
    }

    public static func fetch(
        _ db: Database,
        profileID: String,
        period: UStVAPeriod
    ) throws -> SubmittedReturnRecord? {
        try SubmittedReturnRecord.fetchOne(
            db,
            sql: """
            SELECT * FROM submitted_returns
             WHERE business_profile_id = ? AND year = ? AND kind = ? AND period_index = ?
            """,
            arguments: [profileID, period.year, kindName(period.kind), period.index]
        )
    }

    /// True when the period was marked as submitted and its values no longer
    /// match what was filed. False when it was never marked.
    public static func hasChangedSinceSubmission(
        _ database: AppDatabase,
        profileID: String,
        profile: BusinessProfile,
        period: UStVAPeriod
    ) throws -> Bool {
        try database.reader.read { db in
            guard let record = try fetch(db, profileID: profileID, period: period) else { return false }
            let current = try UStVACalculator.prepare(period: period, profile: profile, db: db)
            return record.contentHash != contentHash(of: current)
        }
    }

    /// Same check against an already prepared return, for callers that just
    /// computed it (the task window).
    public static func hasChangedSinceSubmission(
        _ database: AppDatabase,
        profileID: String,
        current: UStVAReturn
    ) throws -> Bool {
        guard let record = try fetch(database, profileID: profileID, period: current.period) else { return false }
        return record.contentHash != contentHash(of: current)
    }

    /// SHA-256 over the form values only: period, every Kennzahl with its
    /// amount, and the Zahllast. Deliberately independent of contribution
    /// details and exception wording, so re-ordering evidence does not read as
    /// a changed filing while any moved value does.
    public static func contentHash(of result: UStVAReturn) -> String {
        var payload = "\(result.period.year)|\(kindName(result.period.kind))|\(result.period.index)"
        for line in result.lines.sorted(by: { $0.kennzahl < $1.kennzahl }) {
            payload += "|\(line.kennzahl)=\(line.amountMinor)"
        }
        payload += "|83=\(result.payableMinor)"
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func kindName(_ kind: UStVAPeriod.Kind) -> String {
        switch kind {
        case .monthly: "monthly"
        case .quarterly: "quarterly"
        }
    }

    /// Rebuilds the period a stored row refers to.
    public static func period(of record: SubmittedReturnRecord) -> UStVAPeriod {
        record.kind == "monthly"
            ? UStVAPeriod(year: record.year, month: record.periodIndex)
            : UStVAPeriod(year: record.year, quarter: record.periodIndex)
    }
}
