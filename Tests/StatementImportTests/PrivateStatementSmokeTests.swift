import Domain
import Foundation
import StatementImport
import Testing

/// A hook for the one thing the fixtures cannot prove: that a real export of
/// the user's own account goes through the importer.
///
/// The file stays outside the repository. The test is skipped unless
/// `PFENNIG_PRIVATE_STATEMENT_CSV` points at an existing file:
///
/// ```
/// PFENNIG_PRIVATE_STATEMENT_CSV=/pfad/zum/auszug.csv swift test \
///     --filter "Privater Kontoauszug"
/// ```
///
/// It asserts only that the import does not throw and prints an aggregate
/// summary - counts, dates, format - so the result can be read without the
/// file's content ever reaching the terminal, the repository or a log.
@Suite("Privater Kontoauszug")
struct PrivateStatementSmokeTests {
    static let environmentKey = "PFENNIG_PRIVATE_STATEMENT_CSV"

    static var path: String? {
        guard let path = ProcessInfo.processInfo.environment[environmentKey],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return path
    }

    static var isAvailable: Bool {
        guard let path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    @Test(
        "Ein echter Export wird ohne Fehler gelesen",
        .enabled(if: PrivateStatementSmokeTests.isAvailable)
    )
    func readsTheFile() throws {
        let path = try #require(Self.path)
        let outcome = try CSVStatementImporter.run(
            contentsOf: URL(filePath: path),
            accountKey: "revolut-test"
        )

        switch outcome {
        case let .imported(result):
            print(Self.summary(of: result))
        case let .unmappedHeader(header):
            print("Kopfzeile nicht erkannt: \(header.columns.joined(separator: " | "))")
            Issue.record("Die Kopfzeile wurde weder vom Katalog noch von der Heuristik erkannt.")
        case let .accountKeyRequired(request):
            // Cannot happen with an account key supplied, but says so clearly.
            print("Konto unklar, Format \(request.formatID ?? "unbekannt"), \(request.lineCount) Zeilen")
            Issue.record("Der Importer hat trotz Kontoschlüssel nach dem Konto gefragt.")
        }
    }

    /// Counts, dates and the format only - never a counterparty, a purpose or
    /// an amount of the file itself.
    static func summary(of result: StatementImportResult) -> String {
        let dates = result.drafts.map(\.bookingDate).sorted()
        let skipped = Dictionary(grouping: result.skippedRows, by: \.reason.rawValue)
            .map { "\($0.key) \($0.value.count)" }
            .sorted()
        let classes = Dictionary(grouping: result.drafts, by: \.classification.rawValue)
            .map { "\($0.key) \($0.value.count)" }
            .sorted()
        let balance = if let hit = result.balance.firstBreak {
            "Bruch in Zeile \(hit.lineNumber) (erwartet \(hit.expectedMinor), gefunden \(hit.foundMinor))"
        } else if result.balance.isConsistent {
            "stimmig oder nicht prüfbar"
        } else {
            "unstimmig"
        }

        var lines = [
            "--- Privater Kontoauszug ---",
            "Format: \(result.formatID ?? "keines (Heuristik)")",
            "Heuristische Zuordnung: \(result.isHeuristicMapping ? "ja" : "nein")",
            "Zeilen: \(result.drafts.count)",
            "Fehler: \(result.errors.count)"
        ]
        lines += result.errors.prefix(3).map { "  \($0.message)" }
        lines += [
            "Übersprungen: \(skipped.isEmpty ? "keine" : skipped.joined(separator: ", "))",
            "Saldenlauf: \(balance)",
            "Einordnung: \(classes.joined(separator: ", "))",
            "Zeitraum: \(dates.first?.description ?? "-") bis \(dates.last?.description ?? "-")"
        ]
        return lines.joined(separator: "\n")
    }
}
