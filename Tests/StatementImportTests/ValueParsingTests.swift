import Domain
import Foundation
import StatementImport
import Testing

@Suite("Value parsing")
struct ValueParsingTests {
    @Test("German, English and plain amounts", arguments: [
        ("1.234,56", Int64(123_456)),
        ("-1234.56", -123_456),
        ("1,234.56", 123_456),
        ("1.234.567,89", 123_456_789),
        ("3570,00", 357_000),
        ("-23.79", -2379),
        ("-2000", -200_000),
        ("-11,9", -1190),
        ("312,4", 31240),
        ("0,00", 0),
        ("+12,05", 1205),
        ("12,05-", -1205)
    ])
    func amounts(raw: String, expected: Int64) throws {
        #expect(try StatementValueParser.amountMinor(raw, currency: .eur) == expected)
    }

    @Test("Currency marks, spaces and parentheses", arguments: [
        ("€ 12,00", Int64(1200)),
        ("12,00 €", 1200),
        ("EUR 1.234,56", 123_456),
        ("$1,234.56", 123_456),
        ("(1.234,56)", -123_456),
        ("(12.00)", -1200),
        ("1 234,56", 123_456),
        ("1\u{00A0}234,56", 123_456)
    ])
    func decoratedAmounts(raw: String, expected: Int64) throws {
        #expect(try StatementValueParser.amountMinor(raw, currency: .eur) == expected)
    }

    @Test("Malformed amounts throw rather than guess", arguments: ["", "   ", "abc", "1.2.3,4,5", "-", "€"])
    func malformedAmounts(raw: String) {
        #expect(throws: StatementValueParser.AmountError.self) {
            try StatementValueParser.amountMinor(raw, currency: .eur)
        }
    }

    @Test("Currency exponent is respected")
    func exponent() throws {
        #expect(try StatementValueParser.amountMinor("1.234", currency: CurrencyCode("KWD")) == 1234)
        #expect(try StatementValueParser.amountMinor("100", currency: .jpy) == 100)
    }

    @Test("Declared date layouts", arguments: [
        ("31.08.2026", StatementDateFormat.dayMonthYear, LocalDate(year: 2026, month: 8, day: 31)),
        ("03.08.26", .dayMonthYear, LocalDate(year: 2026, month: 8, day: 3)),
        ("2026-08-31", .iso, LocalDate(year: 2026, month: 8, day: 31)),
        ("2026-08-05 10:14:22", .iso, LocalDate(year: 2026, month: 8, day: 5)),
        ("2026-08-05T10:14:22Z", .iso, LocalDate(year: 2026, month: 8, day: 5)),
        ("03/08/2026", .dayMonthYearSlash, LocalDate(year: 2026, month: 8, day: 3)),
        ("08/31/2026", .monthDayYearSlash, LocalDate(year: 2026, month: 8, day: 31))
    ])
    func dates(raw: String, format: StatementDateFormat, expected: LocalDate) throws {
        #expect(try StatementValueParser.date(raw, format: format) == expected)
    }

    /// The dotted layout takes both year lengths. They cannot be confused
    /// with each other, and an export that gains or loses the century - DKB
    /// and Sparkasse both write the short form today - keeps importing.
    @Test("The dotted layout reads both year lengths")
    func yearLength() throws {
        #expect(try StatementValueParser.date("03.08.2026", format: .dayMonthYear)
            == LocalDate(year: 2026, month: 8, day: 3))
        #expect(try StatementValueParser.date("03.08.26", format: .dayMonthYear)
            == LocalDate(year: 2026, month: 8, day: 3))
        // A three-digit year is neither and stays an error.
        #expect(throws: StatementValueParser.DateError.self) {
            try StatementValueParser.date("03.08.202", format: .dayMonthYear)
        }
    }

    @Test("Impossible and malformed dates throw", arguments: [
        "31.02.2026", "2026-13-01", "00.08.2026", "", "morgen", "2026/08/31"
    ])
    func impossibleDates(raw: String) {
        #expect(throws: StatementValueParser.DateError.self) {
            try StatementValueParser.date(raw, format: .auto)
        }
    }

    @Test("auto sniffs the layout and reads dd/MM before MM/dd")
    func autoDates() throws {
        #expect(try StatementValueParser.date("2026-08-31", format: .auto) == LocalDate(year: 2026, month: 8, day: 31))
        #expect(try StatementValueParser.date("31.08.2026", format: .auto) == LocalDate(year: 2026, month: 8, day: 31))
        #expect(try StatementValueParser.date("03.08.26", format: .auto) == LocalDate(year: 2026, month: 8, day: 3))
        #expect(try StatementValueParser.date("03/08/2026", format: .auto) == LocalDate(year: 2026, month: 8, day: 3))
    }

    @Test("IBAN shape")
    func ibans() {
        #expect(StatementValueParser.looksLikeIBAN("DE00500105170001234567"))
        #expect(StatementValueParser.looksLikeIBAN("de00 5001 0517 0001 2345 67"))
        #expect(StatementValueParser.looksLikeIBAN("12345678") == false)
        #expect(StatementValueParser.looksLikeIBAN("Nordwind Handels GmbH") == false)
        #expect(StatementValueParser.looksLikeIBAN("") == false)
        #expect(StatementValueParser.normalizedIBAN("de00 5001") == "DE005001")
    }

    @Test("Header normalization folds quoting, casing and umlauts")
    func headerNormalization() {
        #expect(HeaderNormalization.normalize("  Buchungstag  ") == "buchungstag")
        #expect(HeaderNormalization.normalize("Empfänger") == HeaderNormalization.normalize("Empfaenger"))
        #expect(HeaderNormalization.normalize("\u{FEFF}Datum") == "datum")
        #expect(HeaderNormalization.compact("Betrag (EUR)") == "betrageur")
        #expect(HeaderNormalization.compact("Zahlungsempfänger*in") == "zahlungsempfaengerin")
    }

    @Test("A header fingerprint is stable and ignores presentation")
    func fingerprint() {
        let one = HeaderFingerprint.make(["Buchungstag", "Betrag"])
        #expect(one == HeaderFingerprint.make([" buchungstag ", "BETRAG"]))
        #expect(one != HeaderFingerprint.make(["Buchungstag", "Betrag", "Waehrung"]))
        #expect(one.count == 64)
    }

    @Test("Labelled segments of one packed field")
    func labelledSegments() {
        let text = "Auftraggeber: Nordwind Handels GmbH Buchungstext: Rechnung RE-2026-0042 Karte Nr. 4532"
        let segments = StatementValueParser.labelledSegments(
            text,
            vocabulary: ["Auftraggeber:", "Empfänger:", "Buchungstext:", "Karte Nr."]
        )
        #expect(segments["Auftraggeber:"] == "Nordwind Handels GmbH")
        #expect(segments["Buchungstext:"] == "Rechnung RE-2026-0042")
        #expect(segments["Karte Nr."] == "4532")
        #expect(segments["Empfänger:"] == nil)
    }
}
