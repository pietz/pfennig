@testable import Database
import Foundation
import GRDB
import Testing

/// `docs/schema.md` is the human-readable contract of the schema (spec 21).
/// This test fails whenever a migration adds or removes a table or view
/// without updating the documentation.
@Suite("Schema documentation")
struct SchemaDocumentationTests {
    static let documentationURL = URL(filePath: #filePath)
        .deletingLastPathComponent() // DatabaseTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appending(path: "docs/schema.md")

    /// Reads the fenced list that follows `<!-- sqlite_master:<kind> -->`.
    static func documented(_ kind: String) throws -> [String] {
        let text = try String(contentsOf: documentationURL, encoding: .utf8)
        guard let marker = text.range(of: "<!-- sqlite_master:\(kind) -->"),
              let fenceStart = text.range(of: "```text", range: marker.upperBound ..< text.endIndex),
              let fenceEnd = text.range(of: "```", range: fenceStart.upperBound ..< text.endIndex)
        else {
            Issue.record("Missing sqlite_master:\(kind) block in docs/schema.md")
            return []
        }
        return text[fenceStart.upperBound ..< fenceEnd.lowerBound]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func objects(ofType type: String) throws -> [String] {
        let database = try AppDatabase(inMemoryNamed: "schema-doc-\(type)")
        return try database.reader.read { db in
            try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = ? AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            ORDER BY name
            """, arguments: [type])
        }
    }

    @Test("Documented tables match sqlite_master")
    func tables() throws {
        #expect(try Self.documented("tables") == (Self.objects(ofType: "table")))
    }

    @Test("Documented views match sqlite_master")
    func views() throws {
        #expect(try Self.documented("views") == (Self.objects(ofType: "view")))
    }
}
