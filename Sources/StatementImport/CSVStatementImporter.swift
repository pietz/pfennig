import Domain
import Foundation

// MARK: - Result types

/// Why one source line could not be read. The import never aborts on these:
/// the remaining lines are imported and the failures are reported.
public struct StatementLineError: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case missingColumn
        case missingValue
        case unparseableDate
        case unparseableAmount
    }

    public let lineNumber: Int
    public let column: String?
    public let kind: Kind
    public let value: String?

    public init(lineNumber: Int, column: String?, kind: Kind, value: String?) {
        self.lineNumber = lineNumber
        self.column = column
        self.kind = kind
        self.value = value
    }

    public var message: String {
        let where_ = column.map { " in Spalte „\($0)“" } ?? ""
        return switch kind {
        case .missingColumn: "Zeile \(lineNumber): Spalte „\(column ?? "?")“ fehlt."
        case .missingValue: "Zeile \(lineNumber): Pflichtwert\(where_) ist leer."
        case .unparseableDate: "Zeile \(lineNumber): „\(value ?? "")“\(where_) ist kein Datum."
        case .unparseableAmount: "Zeile \(lineNumber): „\(value ?? "")“\(where_) ist kein Betrag."
        }
    }
}

/// A line the format itself says is not a booking, such as a Revolut
/// `REVERTED` row. Reported so nothing disappears silently.
public struct SkippedStatementRow: Sendable, Equatable, Codable {
    public enum Reason: String, Sendable, Codable {
        case filteredByState
        case duplicateInFile
    }

    public let lineNumber: Int
    public let reason: Reason
    public let value: String?

    public init(lineNumber: Int, reason: Reason, value: String?) {
        self.lineNumber = lineNumber
        self.reason = reason
        self.value = value
    }
}

/// Result of the running-balance cross-check, the CSV counterpart of the
/// closing-balance control the spec requires for PDF statements. Only exports
/// that carry a balance column can be checked.
public struct BalanceContinuity: Sendable, Equatable {
    public struct Break: Sendable, Equatable {
        public let lineNumber: Int
        public let expectedMinor: Int64
        public let foundMinor: Int64
    }

    public let isConsistent: Bool
    public let firstBreak: Break?

    public static let notAvailable = BalanceContinuity(isConsistent: true, firstBreak: nil)
}

/// Everything one CSV statement produced.
public struct StatementImportResult: Sendable, Equatable {
    /// The account these lines belong to: an IBAN when one could be found or
    /// confirmed, otherwise the key the caller supplied.
    public let accountKey: String
    /// The own IBAN read out of the file, for the caller to confirm against.
    public let detectedAccountIBAN: String?
    public let formatID: String?
    public let isHeuristicMapping: Bool
    public let headerFingerprint: String
    public let headerColumns: [String]
    public let mapping: StatementColumnMapping
    public let drafts: [StatementLineDraft]
    public let errors: [StatementLineError]
    public let skippedRows: [SkippedStatementRow]
    public let balance: BalanceContinuity

    /// Lines dropped because an identical line was already in this file. The
    /// database enforces the same identity via `UNIQUE(account_iban,
    /// line_fingerprint)`, so keeping them would only move the loss.
    public var duplicatesInFile: Int {
        skippedRows.count { $0.reason == .duplicateInFile }
    }
}

/// A header the catalog and the heuristic both failed on. The next step hands
/// this to the model, which must answer with a ``StatementColumnMapping``
/// naming columns exactly as they appear in `columns`.
public struct UnmappedHeader: Sendable, Equatable, Codable {
    public let headerFingerprint: String
    public let columns: [String]
    /// A few data rows, so the model can see value shapes, not only names.
    public let sampleRows: [[String]]
    public let delimiter: String
    public let headerLineNumber: Int
}

/// A file that parsed, but whose account could not be determined. The caller
/// asks the user and calls the importer again with an account key.
public struct AccountKeyRequest: Sendable, Equatable {
    public let formatID: String?
    public let headerFingerprint: String
    public let columns: [String]
    public let lineCount: Int
}

public enum StatementImportOutcome: Sendable, Equatable {
    case imported(StatementImportResult)
    case unmappedHeader(UnmappedHeader)
    case accountKeyRequired(AccountKeyRequest)
}

public enum StatementImportError: Error, Equatable, Sendable, LocalizedError {
    case reader(CSVReaderError)
    case noDataRows
    /// A model- or user-supplied mapping names columns the header lacks.
    case mappingDoesNotFitHeader([String])

    public var errorDescription: String? {
        switch self {
        case let .reader(error): error.errorDescription
        case .noDataRows: "Die Datei enthält keine Buchungszeilen."
        case let .mappingDoesNotFitHeader(columns):
            "Die Spaltenzuordnung passt nicht zur Kopfzeile: \(columns.joined(separator: ", "))."
        }
    }
}

// MARK: - Importer

/// Bank-independent CSV statement importer.
///
/// One entry point, three possible answers: the lines, a header the model has
/// to map, or a request for the account this file belongs to. Nothing here
/// touches the database or the network.
public enum CSVStatementImporter {
    /// - Parameters:
    ///   - accountKey: supplied or confirmed by the caller. Wins over an IBAN
    ///     detected in the file, because the user has the last word.
    ///   - knownAccountKeys: account keys already present in `statement_lines`,
    ///     used to recognize transfers between the user's own accounts.
    ///   - cachedMappings: mappings remembered per header fingerprint, from an
    ///     earlier model answer or a user correction.
    public static func run(
        data: Data,
        accountKey: String? = nil,
        knownAccountKeys: Set<String> = [],
        cachedMappings: [String: StatementColumnMapping] = [:]
    ) throws -> StatementImportOutcome {
        let file: CSVFile
        do {
            file = try CSVReader.read(data)
        } catch let error as CSVReaderError {
            throw StatementImportError.reader(error)
        }
        return try run(
            file: file,
            accountKey: accountKey,
            knownAccountKeys: knownAccountKeys,
            cachedMappings: cachedMappings
        )
    }

    public static func run(
        contentsOf url: URL,
        accountKey: String? = nil,
        knownAccountKeys: Set<String> = [],
        cachedMappings: [String: StatementColumnMapping] = [:]
    ) throws -> StatementImportOutcome {
        try run(
            data: Data(contentsOf: url),
            accountKey: accountKey,
            knownAccountKeys: knownAccountKeys,
            cachedMappings: cachedMappings
        )
    }

    /// Reruns an unmapped file with the mapping the model produced.
    public static func run(
        data: Data,
        mapping: StatementColumnMapping,
        accountKey: String? = nil,
        knownAccountKeys: Set<String> = []
    ) throws -> StatementImportOutcome {
        let file: CSVFile
        do {
            file = try CSVReader.read(data)
        } catch let error as CSVReaderError {
            throw StatementImportError.reader(error)
        }
        guard let header = HeaderMappingCatalog.likelyHeaderRow(file.rows),
              let index = file.rows.firstIndex(where: { $0.lineNumber == header.lineNumber })
        else { throw StatementImportError.noDataRows }
        let missing = mapping.missingColumns(in: header.fields)
        guard missing.isEmpty else { throw StatementImportError.mappingDoesNotFitHeader(missing) }
        return try build(
            file: file,
            resolution: HeaderResolution(
                rowIndex: index,
                columns: header.fields,
                mapping: mapping,
                isHeuristic: mapping.formatID == nil
            ),
            accountKey: accountKey,
            knownAccountKeys: knownAccountKeys
        )
    }

    static func run(
        file: CSVFile,
        accountKey: String?,
        knownAccountKeys: Set<String>,
        cachedMappings: [String: StatementColumnMapping]
    ) throws -> StatementImportOutcome {
        if let cached = cachedResolution(file: file, cachedMappings: cachedMappings) {
            return try build(
                file: file,
                resolution: cached,
                accountKey: accountKey,
                knownAccountKeys: knownAccountKeys
            )
        }
        guard let resolution = HeaderMappingCatalog.resolve(rows: file.rows) else {
            let header = HeaderMappingCatalog.likelyHeaderRow(file.rows)
            let columns = header?.fields ?? []
            let samples = file.rows
                .drop { $0.lineNumber <= (header?.lineNumber ?? 0) }
                .filter { !$0.isBlank }
                .prefix(3)
                .map(\.fields)
            return .unmappedHeader(UnmappedHeader(
                headerFingerprint: HeaderFingerprint.make(columns),
                columns: columns,
                sampleRows: Array(samples),
                delimiter: String(file.delimiter),
                headerLineNumber: header?.lineNumber ?? 0
            ))
        }
        return try build(
            file: file,
            resolution: resolution,
            accountKey: accountKey,
            knownAccountKeys: knownAccountKeys
        )
    }

    static func cachedResolution(
        file: CSVFile,
        cachedMappings: [String: StatementColumnMapping]
    ) -> HeaderResolution? {
        guard !cachedMappings.isEmpty else { return nil }
        for (index, row) in file.rows.prefix(HeaderMappingCatalog.maximumPreambleRows).enumerated()
            where !row.isBlank
        {
            guard let mapping = cachedMappings[HeaderFingerprint.make(row.fields)],
                  mapping.missingColumns(in: row.fields).isEmpty
            else { continue }
            return HeaderResolution(
                rowIndex: index,
                columns: row.fields,
                mapping: mapping,
                isHeuristic: mapping.formatID == nil
            )
        }
        return nil
    }

    // MARK: - Building the lines

    static func build(
        file: CSVFile,
        resolution: HeaderResolution,
        accountKey: String?,
        knownAccountKeys: Set<String>
    ) throws -> StatementImportOutcome {
        let header = resolution.columns
        let mapping = resolution.mapping
        let fingerprint = HeaderFingerprint.make(header)
        let dataRows = file.rows[(resolution.rowIndex + 1)...].filter { !$0.isBlank }
        guard !dataRows.isEmpty else { throw StatementImportError.noDataRows }

        let reader = RowReader(header: header, mapping: mapping)
        let detected = detectAccountIBAN(
            preamble: Array(file.rows[..<resolution.rowIndex]),
            dataRows: Array(dataRows),
            reader: reader
        )
        guard let resolvedKey = accountKey ?? detected else {
            return .accountKeyRequired(AccountKeyRequest(
                formatID: mapping.formatID,
                headerFingerprint: fingerprint,
                columns: header,
                lineCount: dataRows.count
            ))
        }

        var drafts: [StatementLineDraft] = []
        var errors: [StatementLineError] = []
        var skipped: [SkippedStatementRow] = []
        var seen: Set<String> = []
        var movements: [Movement] = []

        for row in dataRows {
            if let filter = mapping.rowFilter {
                let state = reader.value(filter.column, in: row) ?? ""
                guard filter.keeps(state) else {
                    skipped.append(SkippedStatementRow(
                        lineNumber: row.lineNumber,
                        reason: .filteredByState,
                        value: state
                    ))
                    continue
                }
            }

            switch reader.line(from: row, accountKey: resolvedKey) {
            case let .failure(rowErrors):
                errors.append(contentsOf: rowErrors)
            case var .success(parsed):
                guard seen.insert(parsed.draft.lineFingerprint).inserted else {
                    skipped.append(SkippedStatementRow(
                        lineNumber: row.lineNumber,
                        reason: .duplicateInFile,
                        value: nil
                    ))
                    continue
                }
                errors.append(contentsOf: parsed.softErrors)
                parsed.draft.classification = StatementLineClassifier.classify(
                    parsed.draft,
                    knownAccountKeys: knownAccountKeys
                )
                movements.append(Movement(
                    line: row.lineNumber,
                    currency: parsed.draft.currency.rawValue,
                    amount: parsed.draft.amountMinor,
                    balance: parsed.balanceMinor
                ))
                drafts.append(parsed.draft)
            }
        }

        return .imported(StatementImportResult(
            accountKey: resolvedKey,
            detectedAccountIBAN: detected,
            formatID: mapping.formatID,
            isHeuristicMapping: resolution.isHeuristic,
            headerFingerprint: fingerprint,
            headerColumns: header,
            mapping: mapping,
            drafts: drafts,
            errors: errors,
            skippedRows: skipped,
            balance: continuity(of: movements)
        ))
    }

    /// The own account: a dedicated column first, then any IBAN-shaped cell in
    /// the preamble, which is where DKB and ING put it.
    static func detectAccountIBAN(preamble: [CSVRow], dataRows: [CSVRow], reader: RowReader) -> String? {
        if let column = reader.mapping.ownIBANColumn {
            for row in dataRows {
                guard let raw = reader.value(column, in: row),
                      StatementValueParser.looksLikeIBAN(raw)
                else { continue }
                return StatementValueParser.normalizedIBAN(raw)
            }
        }
        for row in preamble {
            for cell in row.fields {
                for token in cell.split(whereSeparator: { $0 == " " || $0 == ";" || $0 == "," }) {
                    if StatementValueParser.looksLikeIBAN(String(token)) {
                        return StatementValueParser.normalizedIBAN(String(token))
                    }
                }
                if StatementValueParser.looksLikeIBAN(cell) {
                    return StatementValueParser.normalizedIBAN(cell)
                }
            }
        }
        return nil
    }

    /// One imported movement, for the running-balance cross-check.
    struct Movement {
        let line: Int
        let currency: String
        let amount: Int64
        /// The balance after this booking, when the export reports one.
        let balance: Int64?
    }

    /// Each reported balance must equal the previous one plus everything that
    /// moved in between.
    ///
    /// Two things keep this from crying wolf on a real export: each currency
    /// is a series of its own, because a multi-currency account reports a
    /// separate balance per currency; and rows without a balance are carried
    /// forward instead of breaking the chain. An export sorted newest-first
    /// satisfies the same rule read backwards, so it is checked in reverse
    /// before a break is reported.
    static func continuity(of movements: [Movement]) -> BalanceContinuity {
        let series = Dictionary(grouping: movements, by: \.currency).values
            .filter { $0.count { $0.balance != nil } >= 2 }
        guard !series.isEmpty else { return .notAvailable }

        func firstBreak(_ list: [Movement]) -> BalanceContinuity.Break? {
            var previous: Int64?
            var moved: Int64 = 0
            for movement in list {
                moved += movement.amount
                guard let balance = movement.balance else { continue }
                if let previous {
                    let expected = previous + moved
                    if expected != balance {
                        return BalanceContinuity.Break(
                            lineNumber: movement.line,
                            expectedMinor: expected,
                            foundMinor: balance
                        )
                    }
                }
                previous = balance
                moved = 0
            }
            return nil
        }

        for list in series {
            guard let ascending = firstBreak(list) else { continue }
            if firstBreak(list.reversed()) == nil {
                continue
            }
            return BalanceContinuity(isConsistent: false, firstBreak: ascending)
        }
        return BalanceContinuity(isConsistent: true, firstBreak: nil)
    }
}
