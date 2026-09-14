@testable import Database
import Domain
import Foundation
import GRDB
import Testing

@Suite("Import-Abfragen für Prüfen")
struct ImportQueryTests {
    private func database() throws -> AppDatabase {
        try AppDatabase(inMemoryNamed: "import-query-\(UUID().uuidString)")
    }

    @Test("Ohne Import gibt es keinen Zeitpunkt")
    func withoutImport() throws {
        let database = try database()
        let last = try database.reader.read { try ImportRepository.lastImportAt($0) }
        #expect(last == nil)
    }

    @Test("Der jüngste Abschluss gewinnt, ein laufender Batch zählt ab seinem Start")
    func newestBatchWins() throws {
        let database = try database()
        try database.writer.write { db in
            try ImportBatch(
                startedAt: "2026-09-01T10:00:00Z",
                completedAt: "2026-09-01T10:05:00Z",
                status: .completed,
                fileCount: 2
            ).insert(db)
            try ImportBatch(
                startedAt: "2026-09-02T09:00:00Z",
                completedAt: nil,
                status: .running,
                fileCount: 1
            ).insert(db)
        }

        let last = try database.reader.read { try ImportRepository.lastImportAt($0) }
        #expect(last == "2026-09-02T09:00:00Z")
    }
}
