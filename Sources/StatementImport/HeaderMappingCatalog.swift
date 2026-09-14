import Domain
import Foundation

/// A statement export the catalog recognizes by its header row.
public struct StatementFormat: Sendable, Hashable {
    public let id: String
    public let displayName: String
    /// Header cells that must all be present, in compacted form.
    public let signature: [String]
    public let mapping: StatementColumnMapping

    init(id: String, displayName: String, signature: [String], mapping: StatementColumnMapping) {
        self.id = id
        self.displayName = displayName
        self.signature = signature.map(HeaderNormalization.compact)
        var mapping = mapping
        mapping.formatID = id
        self.mapping = mapping
    }

    func matches(_ header: [String]) -> Bool {
        let cells = Set(header.map(HeaderNormalization.compact))
        return signature.allSatisfy(cells.contains)
    }
}

/// Where the table starts and how to read it.
public struct HeaderResolution: Sendable, Equatable {
    /// Index into `CSVFile.rows`, not a line number.
    public let rowIndex: Int
    public let columns: [String]
    public let mapping: StatementColumnMapping
    /// `true` when the mapping came from the generic header heuristic rather
    /// than from a known format.
    public let isHeuristic: Bool
}

/// Recognizes the documented bank and processor exports by their header, and
/// falls back to a generic heuristic over German and English column names.
///
/// Deliberately deterministic and offline: the model is only asked when this
/// returns nothing (see ``UnmappedHeader``).
public enum HeaderMappingCatalog {
    /// How far into a file a header row may sit. ING's preamble is 13 lines;
    /// 40 leaves room without scanning a whole export.
    public static let maximumPreambleRows = 40

    public static func format(id: String) -> StatementFormat? {
        formats.first { $0.id == id }
    }

    /// Finds the header row and the mapping for it. Known formats win over
    /// the heuristic, wherever in the preamble they sit.
    public static func resolve(rows: [CSVRow]) -> HeaderResolution? {
        let candidates = Array(rows.prefix(maximumPreambleRows))

        for (index, row) in candidates.enumerated() where !row.isBlank {
            let matches = formats.filter { $0.matches(row.fields) }
            if let best = matches.max(by: { $0.signature.count < $1.signature.count }) {
                return HeaderResolution(
                    rowIndex: index,
                    columns: row.fields,
                    mapping: best.mapping,
                    isHeuristic: false
                )
            }
        }

        let width = modalWidth(rows)
        for (index, row) in candidates.enumerated() {
            guard row.fields.count == width, index + 1 < rows.count else { continue }
            guard row.fields.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count >= 3 else { continue }
            guard let mapping = heuristicMapping(for: row.fields) else { continue }
            // A header is only a header when the row below it parses as data.
            let lookahead = rows[(index + 1)...].prefix(3).filter { !$0.isBlank }
            let index0 = columnIndex(of: mapping.bookingDate, in: row.fields)
            guard let index0, lookahead.contains(where: { row in
                guard let value = row.field(index0) else { return false }
                return (try? StatementValueParser.date(value, format: mapping.bookingDateFormat)) != nil
            }) else { continue }
            return HeaderResolution(rowIndex: index, columns: row.fields, mapping: mapping, isHeuristic: true)
        }
        return nil
    }

    /// The header row to show the model when nothing matched: the first row
    /// as wide as the table itself.
    public static func likelyHeaderRow(_ rows: [CSVRow]) -> CSVRow? {
        let width = modalWidth(rows)
        return rows.prefix(maximumPreambleRows).first {
            $0.fields.count == width && $0.fields.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } ?? rows.first
    }

    /// The field count most rows share — the width of the actual table.
    static func modalWidth(_ rows: [CSVRow]) -> Int {
        var histogram: [Int: Int] = [:]
        for row in rows where !row.isBlank {
            histogram[row.fields.count, default: 0] += 1
        }
        return histogram.max { left, right in (left.value, left.key) < (right.value, right.key) }?.key ?? 0
    }

    /// Resolves a mapping's column name against a header row: exact
    /// normalized match first, then the compacted form.
    public static func columnIndex(of name: String, in header: [String]) -> Int? {
        let normalized = HeaderNormalization.normalize(name)
        if let index = header.firstIndex(where: { HeaderNormalization.normalize($0) == normalized }) {
            return index
        }
        let compact = HeaderNormalization.compact(name)
        return header.firstIndex { HeaderNormalization.compact($0) == compact }
    }

    // MARK: - Generic heuristic

    /// Builds a mapping from header names alone, for an export the catalog
    /// does not know. German and English synonyms, ordered by how specific
    /// they are; a bare `Datum`/`Date` only wins when nothing better is there.
    public static func heuristicMapping(for header: [String]) -> StatementColumnMapping? {
        let finder = ColumnFinder(header: header)

        guard let bookingDate = finder.find([
            "buchungstag", "buchungsdatum", "booking date", "completed date", "transaction date",
            "posting date", "buchung", "datum", "date"
        ]) else { return nil }

        let valueDate = finder.find([
            "valutadatum", "wertstellungsdatum", "wertstellung", "wertstellung (valuta)",
            "value date", "valuta", "started date"
        ], excluding: [bookingDate])

        guard let amount = heuristicAmount(finder) else { return nil }
        return heuristicRest(finder, bookingDate: bookingDate, valueDate: valueDate, amount: amount)
    }

    static let amountSynonyms = [
        "betrag", "betrag (eur)", "betrag (€)", "amount", "amount (eur)", "umsatz",
        "umsatz in eur", "wert", "value", "netto", "net"
    ]

    static func heuristicAmount(_ finder: ColumnFinder) -> StatementColumnMapping.AmountSource? {
        // A combined sign column is checked first: "Soll/Haben" would
        // otherwise look like both halves of a debit/credit pair.
        if let indicator = finder.find(["soll/haben", "soll/haben-kennzeichen", "s/h", "vorzeichen", "debit/credit"]),
           let column = finder.find(amountSynonyms, excluding: [indicator])
        {
            return .indicated(
                amount: column,
                indicator: indicator,
                debitValues: ["s", "soll", "d", "debit", "ausgang", "-"],
                creditValues: ["h", "haben", "c", "credit", "eingang", "+"]
            )
        }
        let debit = finder.find(["soll", "belastung", "debit", "ausgang", "auszahlung"])
        let credit = finder.find(["haben", "gutschrift", "credit", "eingang", "einzahlung"])
        if let debit, let credit, debit != credit {
            return .debitCredit(debit: debit, credit: credit)
        }
        guard let column = finder.find(amountSynonyms) else { return nil }
        return .signed(column: column)
    }

    static func heuristicRest(
        _ finder: ColumnFinder,
        bookingDate: String,
        valueDate: String?,
        amount: StatementColumnMapping.AmountSource
    ) -> StatementColumnMapping? {
        guard !amount.columns.contains(where: \.isEmpty) else { return nil }

        let counterpartyIBAN = finder.find([
            "iban zahlungsbeteiligter", "partner iban", "gegenkonto", "kontonummer/iban",
            "counterparty iban", "iban"
        ], rejecting: ["auftragskonto", "eigene", "own"])

        let counterparty = finder.find([
            "name zahlungsbeteiligter", "beguenstigter/zahlungspflichtiger", "auftraggeber/empfaenger",
            "empfaenger", "beguenstigter", "zahlungspflichtiger", "auftraggeber", "zahlungsbeteiligter",
            "partner name", "payee", "payer", "counterparty", "gegenpartei", "merchant",
            "beschreibung", "description", "name"
        ])

        var references = finder.findAll([
            "verwendungszweck", "zweck", "payment reference", "reference", "purpose", "betreff",
            "description", "details", "memo", "note", "rechnungsnummer", "invoice number"
        ])
        references.removeAll { $0 == counterparty }
        if references.isEmpty, let counterparty {
            references = [counterparty]
        }

        return StatementColumnMapping(
            bookingDate: bookingDate,
            bookingDateFormat: .auto,
            valueDate: valueDate,
            valueDateFormat: valueDate == nil ? nil : .auto,
            amount: amount,
            currencyColumn: finder.find(["waehrung", "currency", "wkz"]),
            counterparty: counterparty.map { .column($0) },
            counterpartyIBAN: counterpartyIBAN,
            reference: references.isEmpty ? nil : .columns(references),
            bookingText: finder.find(["buchungstext", "transaktionstyp", "umsatztyp", "vorgang", "type", "typ"]),
            externalID: finder.find(["transaktionscode", "transaction id", "external id"]),
            ownIBANColumn: finder.find(["iban auftragskonto", "auftragskonto", "kontonummer auftragskonto"])
        )
    }

    /// Ordered synonym lookup over one header row.
    struct ColumnFinder {
        let header: [String]
        private let normalized: [String]
        private let compact: [String]

        init(header: [String]) {
            self.header = header
            normalized = header.map(HeaderNormalization.normalize)
            compact = header.map(HeaderNormalization.compact)
        }

        /// Exact matches over the whole synonym list first, then prefix and
        /// containment, so `Datum` never outranks `Buchungstag`.
        func find(_ synonyms: [String], excluding: [String] = [], rejecting: [String] = []) -> String? {
            let excluded = Set(excluding.map(HeaderNormalization.normalize))
            func allowed(_ index: Int) -> Bool {
                !excluded.contains(normalized[index]) && !rejecting.contains { compact[index].contains($0) }
            }
            for synonym in synonyms {
                let target = HeaderNormalization.compact(synonym)
                if let index = compact.indices.first(where: { compact[$0] == target && allowed($0) }) {
                    return header[index]
                }
            }
            for synonym in synonyms {
                let target = HeaderNormalization.compact(synonym)
                guard target.count >= 4 else { continue }
                if let index = compact.indices.first(where: { compact[$0].contains(target) && allowed($0) }) {
                    return header[index]
                }
            }
            return nil
        }

        /// Every column matching any synonym, in header order.
        func findAll(_ synonyms: [String]) -> [String] {
            let targets = synonyms.map(HeaderNormalization.compact)
            return header.indices
                .filter { index in targets.contains { !$0.isEmpty && compact[index].contains($0) } }
                .map { header[$0] }
        }
    }
}
