import Foundation
import StatementImport

/// The statement fixtures and small helpers shared by the suites.
enum Support {
    static let repositoryRoot: URL = .init(filePath: #filePath)
        .deletingLastPathComponent() // StatementImportTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo

    static var statementsURL: URL {
        repositoryRoot.appending(path: "Fixtures/statements")
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: statementsURL.appending(path: "\(name).csv"))
    }

    /// Runs a fixture and unwraps the successful outcome.
    static func run(
        _ name: String,
        accountKey: String? = nil,
        knownAccountKeys: Set<String> = []
    ) throws -> StatementImportResult {
        let outcome = try CSVStatementImporter.run(
            data: fixture(name),
            accountKey: accountKey,
            knownAccountKeys: knownAccountKeys
        )
        guard case let .imported(result) = outcome else {
            throw Failure.notImported(String(describing: outcome))
        }
        return result
    }

    static func outcome(
        _ name: String,
        accountKey: String? = nil,
        knownAccountKeys: Set<String> = []
    ) throws -> StatementImportOutcome {
        try CSVStatementImporter.run(
            data: fixture(name),
            accountKey: accountKey,
            knownAccountKeys: knownAccountKeys
        )
    }

    /// Builds a CSV from lines, so encoding and line endings are explicit.
    static func csv(
        _ lines: [String],
        separator: String = "\r\n",
        encoding: String.Encoding = .utf8,
        byteOrderMark: Bool = false
    ) -> Data {
        var data = byteOrderMark ? Data([0xEF, 0xBB, 0xBF]) : Data()
        data.append(lines.joined(separator: separator).data(using: encoding) ?? Data())
        return data
    }

    enum Failure: Error {
        case notImported(String)
    }
}
