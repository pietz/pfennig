import Domain
import Foundation

/// Reads one data row through a ``StatementColumnMapping``.
///
/// Column names are resolved against the header once, in the initializer, so
/// a large export does not re-normalize the same strings per row. A row that
/// cannot yield a date and an amount fails; everything else degrades to `nil`
/// and, where it matters, to a reported error.
struct RowReader {
    struct Parsed {
        var draft: StatementLineDraft
        var balanceMinor: Int64?
        var softErrors: [StatementLineError]
    }

    enum Outcome {
        case success(Parsed)
        case failure([StatementLineError])
    }

    let header: [String]
    let mapping: StatementColumnMapping
    private let indices: [String: Int]

    init(header: [String], mapping: StatementColumnMapping) {
        self.header = header
        self.mapping = mapping
        var indices: [String: Int] = [:]
        for name in Set(mapping.referencedColumns) {
            indices[name] = HeaderMappingCatalog.columnIndex(of: name, in: header)
        }
        self.indices = indices
    }

    /// Trimmed cell value, `nil` when the column is absent or the cell empty.
    func value(_ column: String, in row: CSVRow) -> String? {
        guard let index = indices[column] ?? HeaderMappingCatalog.columnIndex(of: column, in: header),
              let raw = row.field(index)
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func line(from row: CSVRow, accountKey: String) -> Outcome {
        var errors: [StatementLineError] = []
        var soft: [StatementLineError] = []

        guard let bookingRaw = value(mapping.bookingDate, in: row) else {
            return .failure([StatementLineError(
                lineNumber: row.lineNumber,
                column: mapping.bookingDate,
                kind: indices[mapping.bookingDate] == nil ? .missingColumn : .missingValue,
                value: nil
            )])
        }
        let bookingDate: LocalDate
        do {
            bookingDate = try StatementValueParser.date(bookingRaw, format: mapping.bookingDateFormat)
        } catch {
            return .failure([StatementLineError(
                lineNumber: row.lineNumber,
                column: mapping.bookingDate,
                kind: .unparseableDate,
                value: bookingRaw
            )])
        }

        var valueDate: LocalDate?
        if let column = mapping.valueDate, let raw = value(column, in: row) {
            do {
                valueDate = try StatementValueParser.date(raw, format: mapping.valueDateFormat ?? .auto)
            } catch {
                // A broken value date never costs the line; the booking date
                // is the one the bookkeeping uses.
                soft.append(StatementLineError(
                    lineNumber: row.lineNumber,
                    column: column,
                    kind: .unparseableDate,
                    value: raw
                ))
            }
        }

        let currency = currency(in: row)
        guard var amountMinor = amount(in: row, currency: currency, errors: &errors) else {
            return .failure(errors)
        }
        if mapping.invertSign {
            amountMinor = -amountMinor
        }

        var feeMinor: Int64?
        if let column = mapping.feeColumn, let raw = value(column, in: row) {
            if let parsed = try? StatementValueParser.amountMinor(raw, currency: currency) {
                feeMinor = abs(parsed)
                if !mapping.feeIncludedInAmount {
                    amountMinor -= abs(parsed)
                }
            } else {
                soft.append(StatementLineError(
                    lineNumber: row.lineNumber,
                    column: column,
                    kind: .unparseableAmount,
                    value: raw
                ))
            }
        }

        var balanceMinor: Int64?
        if let column = mapping.balanceColumn, let raw = value(column, in: row) {
            balanceMinor = try? StatementValueParser.amountMinor(raw, currency: currency)
        }

        let reference = reference(in: row)
        let counterparty = counterparty(in: row, amountMinor: amountMinor)
        let counterpartyIBAN = mapping.counterpartyIBAN
            .flatMap { value($0, in: row) }
            .flatMap { StatementValueParser.looksLikeIBAN($0) ? StatementValueParser.normalizedIBAN($0) : nil }

        var draft = StatementLineDraft(
            sourceLineNumber: row.lineNumber,
            lineFingerprint: "",
            bookingDate: bookingDate,
            valueDate: valueDate,
            amountMinor: amountMinor,
            feeMinor: feeMinor == 0 ? nil : feeMinor,
            currency: currency,
            counterpartyRaw: counterparty,
            counterpartyIban: counterpartyIBAN,
            reference: reference,
            bookingText: mapping.bookingText.flatMap { value($0, in: row) },
            externalId: mapping.externalID.flatMap { value($0, in: row) },
            rawJson: rawJSON(of: row)
        )
        // The fingerprint is a function of the finished line, so it is set
        // once here and raised to a later occurrence by the importer when one
        // file reports the same movement twice.
        draft.lineFingerprint = LineFingerprint.make(accountID: accountKey, line: draft)
        return .success(Parsed(draft: draft, balanceMinor: balanceMinor, softErrors: soft))
    }

    // MARK: - Fields

    private func currency(in row: CSVRow) -> CurrencyCode {
        guard let column = mapping.currencyColumn, let raw = value(column, in: row) else {
            return mapping.defaultCurrency
        }
        let code = CurrencyCode(raw)
        return code.isWellFormed ? code : mapping.defaultCurrency
    }

    private func amount(in row: CSVRow, currency: CurrencyCode, errors: inout [StatementLineError]) -> Int64? {
        switch mapping.amount {
        case let .signed(column):
            guard let raw = value(column, in: row) else {
                errors.append(StatementLineError(
                    lineNumber: row.lineNumber,
                    column: column,
                    kind: indices[column] == nil ? .missingColumn : .missingValue,
                    value: nil
                ))
                return nil
            }
            guard let parsed = try? StatementValueParser.amountMinor(raw, currency: currency) else {
                errors.append(StatementLineError(
                    lineNumber: row.lineNumber,
                    column: column,
                    kind: .unparseableAmount,
                    value: raw
                ))
                return nil
            }
            return parsed

        case let .debitCredit(debitColumn, creditColumn):
            let debit = value(debitColumn, in: row)
            let credit = value(creditColumn, in: row)
            guard debit != nil || credit != nil else {
                errors.append(StatementLineError(
                    lineNumber: row.lineNumber,
                    column: "\(debitColumn)/\(creditColumn)",
                    kind: .missingValue,
                    value: nil
                ))
                return nil
            }
            var total: Int64 = 0
            for (raw, sign) in [(debit, Int64(-1)), (credit, Int64(1))] {
                guard let raw else { continue }
                guard let parsed = try? StatementValueParser.amountMinor(raw, currency: currency) else {
                    errors.append(StatementLineError(
                        lineNumber: row.lineNumber,
                        column: sign < 0 ? debitColumn : creditColumn,
                        kind: .unparseableAmount,
                        value: raw
                    ))
                    return nil
                }
                // A debit column normally holds a positive magnitude, but some
                // exports repeat the minus sign; respect it either way.
                total += sign < 0 ? -abs(parsed) : abs(parsed)
            }
            return total

        case let .indicated(amountColumn, indicatorColumn, debitValues, creditValues):
            guard let raw = value(amountColumn, in: row) else {
                errors.append(StatementLineError(
                    lineNumber: row.lineNumber,
                    column: amountColumn,
                    kind: .missingValue,
                    value: nil
                ))
                return nil
            }
            guard let parsed = try? StatementValueParser.amountMinor(raw, currency: currency) else {
                errors.append(StatementLineError(
                    lineNumber: row.lineNumber,
                    column: amountColumn,
                    kind: .unparseableAmount,
                    value: raw
                ))
                return nil
            }
            let indicator = (value(indicatorColumn, in: row) ?? "").lowercased()
            if debitValues.contains(where: { $0.lowercased() == indicator }) {
                return -abs(parsed)
            }
            if creditValues.contains(where: { $0.lowercased() == indicator }) {
                return abs(parsed)
            }
            errors.append(StatementLineError(
                lineNumber: row.lineNumber,
                column: indicatorColumn,
                kind: .missingValue,
                value: indicator.isEmpty ? nil : indicator
            ))
            return nil
        }
    }

    private func counterparty(in row: CSVRow, amountMinor: Int64) -> String? {
        switch mapping.counterparty {
        case .none:
            return nil
        case let .column(column):
            return value(column, in: row)
        case let .payerOrPayee(payer, payee):
            // Money out means the counterparty is the payee, money in the payer.
            return amountMinor < 0 ? value(payee, in: row) : value(payer, in: row)
        case let .labelled(column, labels):
            guard let text = value(column, in: row) else { return nil }
            let segments = StatementValueParser.labelledSegments(text, vocabulary: mapping.labelVocabulary)
            for label in labels {
                if let hit = segments.first(where: { $0.key.caseInsensitiveCompare(label) == .orderedSame }) {
                    return hit.value
                }
            }
            return nil
        }
    }

    private func reference(in row: CSVRow) -> String? {
        switch mapping.reference {
        case .none:
            return nil
        case let .columns(columns):
            let parts = columns.compactMap { value($0, in: row) }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        case let .labelled(column, label):
            guard let text = value(column, in: row) else { return nil }
            let segments = StatementValueParser.labelledSegments(text, vocabulary: mapping.labelVocabulary)
            if let hit = segments.first(where: { $0.key.caseInsensitiveCompare(label) == .orderedSame }) {
                return hit.value
            }
            // No label at all: the whole field is the reference.
            return segments.isEmpty ? text : nil
        }
    }

    /// The source row as a JSON object, so nothing the export carried is lost.
    private func rawJSON(of row: CSVRow) -> String? {
        var object: [String: String] = [:]
        for (index, name) in header.enumerated() {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, let cell = row.field(index) else { continue }
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            object[key] = trimmed
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(object) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
