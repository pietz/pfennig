import Domain
import Foundation
import StatementImport
import Testing

@Suite("Column mapping")
struct ColumnMappingTests {
    // MARK: - Catalog

    @Test("Every catalog entry has a unique id and a signature")
    func catalogIsWellFormed() {
        let formats = HeaderMappingCatalog.formats
        #expect(formats.count == 12)
        #expect(Set(formats.map(\.id)).count == formats.count)
        #expect(formats.allSatisfy { !$0.signature.isEmpty })
        #expect(formats.allSatisfy { $0.mapping.formatID == $0.id })
    }

    @Test("No two catalog signatures match the same header")
    func signaturesAreDisjoint() throws {
        for fixture in [
            "sparkasse-camt", "sparkasse-mt940", "volksbank-vr", "dkb", "n26", "ing",
            "comdirect", "paypal", "stripe-balance-transactions", "amex-de", "revolut"
        ] {
            let file = try CSVReader.read(Support.fixture(fixture))
            let header = try #require(HeaderMappingCatalog.resolve(rows: file.rows)).columns
            let matching = HeaderMappingCatalog.formats.filter { format in
                let cells = Set(header.map(HeaderNormalization.compact))
                return format.signature.allSatisfy(cells.contains)
            }
            #expect(matching.count == 1, "\(fixture) matched \(matching.map(\.id))")
        }
    }

    @Test("The N26 English variant is recognized too")
    func n26English() throws {
        let data = Support.csv([
            "Booking Date,Value Date,Partner Name,Partner Iban,Type,Payment Reference," +
                "Category,Account Name,Amount (EUR),Original Amount,Original Currency,Exchange Rate",
            "2026-08-05,2026-08-05,Nordwind Handels GmbH,DE00300000001234567890,Credit Transfer," +
                "Rechnung RE-2026-0042,Income,Main,3570.00,,,"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "n26:giro") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.formatID == "n26-en")
        let line = try #require(result.drafts.first)
        #expect(line.amountMinor == 357_000)
        #expect(line.counterpartyIban == "DE00300000001234567890")
        #expect(line.reference == "Rechnung RE-2026-0042")
    }

    // MARK: - Heuristic

    @Test("An unknown German header is mapped heuristically")
    func germanHeuristic() throws {
        let data = Support.csv([
            "Datum;Gegenpartei;Zweck;Betrag;Waehrung",
            "15.03.2026;Nordwind Handels GmbH;Rechnung RE-2026-0042;1.234,56;EUR",
            "16.03.2026;Adobe;Abo;-23,79;EUR"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "test") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.formatID == nil)
        #expect(result.isHeuristicMapping)
        #expect(result.drafts.count == 2)
        let first = try #require(result.drafts.first)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 3, day: 15))
        #expect(first.amountMinor == 123_456)
        #expect(first.counterpartyRaw == "Nordwind Handels GmbH")
        #expect(first.reference == "Rechnung RE-2026-0042")
    }

    @Test("An unknown English header is mapped heuristically")
    func englishHeuristic() throws {
        let data = Support.csv([
            "Transaction Date,Payee,Description,Amount,Currency",
            "2026-03-15,Nordwind Handels GmbH,Invoice RE-2026-0042,1234.56,EUR"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "test") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.isHeuristicMapping)
        let first = try #require(result.drafts.first)
        #expect(first.amountMinor == 123_456)
        #expect(first.counterpartyRaw == "Nordwind Handels GmbH")
        #expect(first.reference == "Invoice RE-2026-0042")
    }

    @Test("Buchungstag beats a bare Datum column")
    func mostSpecificDateWins() throws {
        let mapping = try #require(HeaderMappingCatalog.heuristicMapping(
            for: ["Datum", "Buchungstag", "Valutadatum", "Empfaenger", "Betrag"]
        ))
        #expect(mapping.bookingDate == "Buchungstag")
        #expect(mapping.valueDate == "Valutadatum")
    }

    @Test("A header without a date or an amount is not a header")
    func noHeuristic() {
        #expect(HeaderMappingCatalog.heuristicMapping(for: ["Alpha", "Beta", "Gamma"]) == nil)
        #expect(HeaderMappingCatalog.heuristicMapping(for: ["Buchungstag", "Empfaenger"]) == nil)
    }

    // MARK: - Amount shapes

    @Test("A debit and credit pair becomes one signed amount")
    func debitCreditPair() throws {
        let data = Support.csv([
            "Buchungstag;Empfaenger;Verwendungszweck;Soll;Haben;Waehrung",
            "15.03.2026;Adobe;Abo;23,79;;EUR",
            "16.03.2026;Nordwind;RE-2026-0042;;1.234,56;EUR",
            "17.03.2026;Sparkasse;Entgelt;-11,90;;EUR"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "test") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.mapping.amount == .debitCredit(debit: "Soll", credit: "Haben"))
        #expect(result.drafts.map(\.amountMinor) == [-2379, 123_456, -1190])
    }

    @Test("An amount with a separate Soll/Haben column")
    func indicatorColumn() throws {
        let data = Support.csv([
            "Buchungstag;Empfaenger;Verwendungszweck;Betrag;Soll/Haben",
            "15.03.2026;Adobe;Abo;23,79;S",
            "16.03.2026;Nordwind;RE-2026-0042;1.234,56;H"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "test") else {
            Issue.record("expected an import")
            return
        }
        guard case let .indicated(amount, indicator, _, _) = result.mapping.amount else {
            Issue.record("expected an indicated amount, got \(result.mapping.amount)")
            return
        }
        #expect(amount == "Betrag")
        #expect(indicator == "Soll/Haben")
        #expect(result.drafts.map(\.amountMinor) == [-2379, 123_456])
    }

    @Test("An unreadable sign indicator is reported per line")
    func unknownIndicator() throws {
        let data = Support.csv([
            "Buchungstag;Empfaenger;Verwendungszweck;Betrag;Soll/Haben",
            "15.03.2026;Adobe;Abo;23,79;S",
            "16.03.2026;Nordwind;RE-2026-0042;1.234,56;?"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "test") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.drafts.count == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.lineNumber == 3)
        #expect(result.errors.first?.column == "Soll/Haben")
    }

    // MARK: - Per-line errors

    @Test("A broken line is reported and the rest is still imported")
    func brokenLines() throws {
        let data = Support.csv([
            "Buchungstag;Empfaenger;Verwendungszweck;Betrag;Waehrung",
            "15.03.2026;Adobe;Abo;-23,79;EUR",
            "keinDatum;Adobe;Abo;-1,00;EUR",
            "17.03.2026;Adobe;Abo;abc;EUR",
            "18.03.2026;Adobe;Abo;;EUR",
            "19.03.2026;Nordwind;RE-2026-0042;1.234,56;EUR"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "test") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.drafts.count == 2)
        #expect(result.errors.count == 3)
        #expect(result.errors.map(\.lineNumber) == [3, 4, 5])
        #expect(result.errors.map(\.kind) == [.unparseableDate, .unparseableAmount, .missingValue])
        #expect(result.errors[0].column == "Buchungstag")
        #expect(result.errors[1].value == "abc")
        #expect(result.errors.allSatisfy { !$0.message.isEmpty })
    }

    @Test("A broken value date costs the value date, not the line")
    func softValueDate() throws {
        let data = Support.csv([
            "Buchungstag;Valutadatum;Empfaenger;Verwendungszweck;Betrag",
            "15.03.2026;kaputt;Adobe;Abo;-23,79"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "test") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.drafts.count == 1)
        #expect(result.drafts.first?.valueDate == nil)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.column == "Valutadatum")
    }

    // MARK: - Unmapped header and the model path

    @Test("A header nothing recognizes comes back as unmappedHeader")
    func unmappedHeader() throws {
        let data = Support.csv([
            "Alpha;Beta;Gamma;Delta",
            "1;2;3;4",
            "5;6;7;8"
        ])
        guard case let .unmapped(header) = try Outcome(CSVStatementImporter.run(data: data)) else {
            Issue.record("expected unmappedHeader")
            return
        }
        #expect(header.columns == ["Alpha", "Beta", "Gamma", "Delta"])
        #expect(header.sampleRows == [["1", "2", "3", "4"], ["5", "6", "7", "8"]])
        #expect(header.delimiter == ";")
        #expect(header.headerLineNumber == 1)
        #expect(header.headerFingerprint == HeaderFingerprint.make(["Alpha", "Beta", "Gamma", "Delta"]))
    }

    @Test("The mapping the model returns is the one the importer takes back")
    func modelSuppliedMapping() throws {
        let data = Support.csv([
            "Alpha;Beta;Gamma;Delta",
            "15.03.2026;Nordwind Handels GmbH;RE-2026-0042;1.234,56"
        ])
        let mapping = StatementColumnMapping(
            bookingDate: "Alpha",
            bookingDateFormat: .dayMonthYear,
            amount: .signed(column: "Delta"),
            counterparty: .column("Beta"),
            reference: .columns(["Gamma"])
        )
        // The mapping survives the round trip through JSON, which is how the
        // model will deliver it.
        let encoded = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(StatementColumnMapping.self, from: encoded)
        #expect(decoded == mapping)

        guard case let .imported(result) = try CSVStatementImporter.run(
            data: data,
            mapping: decoded,
            accountKey: "test"
        ) else {
            Issue.record("expected an import")
            return
        }
        let line = try #require(result.drafts.first)
        #expect(line.bookingDate == LocalDate(year: 2026, month: 3, day: 15))
        #expect(line.amountMinor == 123_456)
        #expect(line.counterpartyRaw == "Nordwind Handels GmbH")
        #expect(line.reference == "RE-2026-0042")
    }

    @Test("A mapping that names columns the header lacks is refused")
    func mappingDoesNotFit() throws {
        let data = Support.csv(["Alpha;Beta", "15.03.2026;1,00"])
        let mapping = StatementColumnMapping(bookingDate: "Alpha", amount: .signed(column: "Epsilon"))
        #expect(throws: StatementImportError.mappingDoesNotFitHeader(["Epsilon"])) {
            try CSVStatementImporter.run(data: data, mapping: mapping, accountKey: "test")
        }
    }

    @Test("A cached mapping is reused for the same header fingerprint")
    func cachedMapping() throws {
        let data = Support.csv([
            "Alpha;Beta;Gamma;Delta",
            "15.03.2026;Nordwind Handels GmbH;RE-2026-0042;1.234,56"
        ])
        let mapping = StatementColumnMapping(
            bookingDate: "Alpha",
            bookingDateFormat: .dayMonthYear,
            amount: .signed(column: "Delta"),
            counterparty: .column("Beta"),
            reference: .columns(["Gamma"])
        )
        let fingerprint = HeaderFingerprint.make(["Alpha", "Beta", "Gamma", "Delta"])
        guard case let .imported(result) = try CSVStatementImporter.run(
            data: data,
            accountKey: "test",
            cachedMappings: [fingerprint: mapping]
        ) else {
            Issue.record("expected an import")
            return
        }
        #expect(result.drafts.first?.amountMinor == 123_456)
    }

    /// Small helper so a `guard case` can name the interesting outcome.
    private enum Outcome {
        case unmapped(UnmappedHeader)
        case other

        init(_ outcome: StatementImportOutcome) {
            if case let .unmappedHeader(header) = outcome {
                self = .unmapped(header)
            } else {
                self = .other
            }
        }
    }
}
