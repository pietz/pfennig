import Foundation
import StatementImport
import Testing

@Suite("CSV reader")
struct CSVReaderTests {
    @Test("Delimiter is taken from the shape of the table", arguments: [
        ("sparkasse-camt", ";"),
        ("ing", ";"),
        ("comdirect", ";"),
        ("dkb", ";"),
        ("volksbank-vr", ";"),
        ("n26", ","),
        ("paypal", ","),
        ("amex-de", ","),
        ("stripe-balance-transactions", ","),
        ("revolut", ",")
    ])
    func delimiters(fixture: String, delimiter: String) throws {
        let file = try CSVReader.read(Support.fixture(fixture))
        #expect(String(file.delimiter) == delimiter)
    }

    @Test("Encodings of the fixtures", arguments: [
        ("dkb", String.Encoding.utf8, true),
        ("volksbank-vr", .utf8, true),
        ("paypal", .utf8, true),
        ("n26", .utf8, false),
        ("ing", .windowsCP1252, false)
    ])
    func encodings(fixture: String, encoding: String.Encoding, bom: Bool) throws {
        let file = try CSVReader.read(Support.fixture(fixture))
        #expect(file.encoding == encoding)
        #expect(file.hadByteOrderMark == bom)
    }

    @Test("Latin-1 is the fallback when the bytes are not valid UTF-8")
    func latin1Fallback() throws {
        var data = Data("Datum;Empfänger;Betrag\r\n".data(using: .isoLatin1) ?? Data())
        data.append("31.08.2026;Müller GmbH;-12,00\r\n".data(using: .isoLatin1) ?? Data())
        let file = try CSVReader.read(data)
        #expect(file.encoding != .utf8)
        #expect(file.rows[0].fields[1] == "Empfänger")
        #expect(file.rows[1].fields[1] == "Müller GmbH")
    }

    @Test("A tab-separated export is recognized")
    func tabs() throws {
        let data = Support.csv([
            "Buchungstag\tEmpfaenger\tVerwendungszweck\tBetrag",
            "31.08.2026\tNordwind\tRE-2026-0042\t100,00"
        ])
        let file = try CSVReader.read(data)
        #expect(file.delimiter == "\t")
        #expect(file.rows[1].fields.count == 4)
    }

    @Test("Quotes, doubled quotes and embedded newlines")
    func quoting() {
        let text = "a;b;c\r\n\"x;y\";\"he said \"\"hi\"\"\";\"two\r\nlines\"\r\n"
        let rows = CSVReader.parse(text, delimiter: ";")
        #expect(rows.count == 2)
        #expect(rows[1].fields == ["x;y", "he said \"hi\"", "two\nlines"])
        // The embedded newline does not shift the reported line number.
        #expect(rows[1].lineNumber == 2)
    }

    @Test("Every line ending style yields the same rows", arguments: ["\r\n", "\n", "\r"])
    func lineEndings(separator: String) throws {
        let file = try CSVReader.read(Support.csv(["a;b;c", "1;2;3", "4;5;6"], separator: separator))
        #expect(file.rows.count == 3)
        #expect(file.rows[2].fields == ["4", "5", "6"])
    }

    @Test("A missing final newline still ends the last row")
    func noTrailingNewline() throws {
        let file = try CSVReader.read(Data("a;b\r\n1;2".utf8))
        #expect(file.rows.count == 2)
        #expect(file.rows[1].fields == ["1", "2"])
    }

    @Test("An empty file is an error, not an empty import")
    func empty() {
        #expect(throws: CSVReaderError.empty) { try CSVReader.read(Data()) }
    }

    @Test("Preamble lines before the header are skipped", arguments: [
        ("ing", 14), ("dkb", 5), ("comdirect", 4), ("sparkasse-camt", 1)
    ])
    func preamble(fixture: String, headerLine: Int) throws {
        let file = try CSVReader.read(Support.fixture(fixture))
        let resolution = try #require(HeaderMappingCatalog.resolve(rows: file.rows))
        #expect(file.rows[resolution.rowIndex].lineNumber == headerLine)
    }

    @Test("A preamble whose width matches the table is still skipped")
    func widePreamble() throws {
        // comdirect pads its preamble with the table's own delimiter, so the
        // rows are as wide as the header and only the content tells them apart.
        let file = try CSVReader.read(Support.fixture("comdirect"))
        #expect(file.rows[0].fields.count == file.rows[4].fields.count)
        let resolution = try #require(HeaderMappingCatalog.resolve(rows: file.rows))
        #expect(resolution.rowIndex == 3)
    }
}
