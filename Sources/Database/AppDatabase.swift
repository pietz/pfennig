import Foundation
import GRDB

/// The bookkeeping database inside an archive folder (`bookkeeping.sqlite`).
///
/// One instance per open archive. `PRAGMA foreign_keys = ON` is enforced for
/// every connection; the schema is created and upgraded by numbered migrations.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    public var reader: any DatabaseReader {
        writer
    }

    /// Opens (and migrates) the database at `path`, creating it if needed.
    public init(path: String) throws {
        writer = try DatabaseQueue(path: path, configuration: Self.configuration)
        try Self.migrator.migrate(writer)
    }

    /// In-memory database for tests and previews.
    public init(inMemoryNamed name: String? = nil) throws {
        writer = try DatabaseQueue(named: name, configuration: Self.configuration)
        try Self.migrator.migrate(writer)
    }

    public static var configuration: Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true // spec 17
        return config
    }

    /// All registered migrations, in order.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v001_initial", migrate: V001Initial.migrate)
        migrator.registerMigration("v002_slim_tax_assessments", migrate: V002SlimTaxAssessments.migrate)
        return migrator
    }

    /// Identifiers of the migrations this build knows about.
    public static var migrationIdentifiers: [String] {
        migrator.migrations
    }

    public func appliedMigrations() throws -> Set<String> {
        try reader.read { try Set(Self.migrator.appliedIdentifiers($0)) }
    }
}

/// ISO-8601 UTC timestamps, the only timestamp format stored in the database.
public enum Timestamp {
    public static func string(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    public static func date(_ string: String) -> Date? {
        formatter.date(from: string)
    }

    /// ISO8601DateFormatter is thread-safe for formatting and parsing.
    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

public enum IDGenerator {
    /// Lowercase RFC 4122 UUID string, the primary-key format of every table.
    public static func new() -> String {
        UUID().uuidString.lowercased()
    }
}
