import Domain
import Foundation
import StatementImport
import Testing

/// Every documented format, end to end: the header is recognized, the lines
/// come out with the right count, and the first and last line carry the
/// values the fixture shows.
@Suite("Fixtures")
struct FixtureImportTests {
    @Test("Every fixture is recognized and yields its lines", arguments: [
        ("sparkasse-camt", "sparkasse-camt", 9),
        ("sparkasse-mt940", "sparkasse-mt940", 9),
        ("volksbank-vr", "volksbank-vr", 9),
        ("dkb", "dkb", 9),
        ("n26", "n26-de", 9),
        ("ing", "ing-de", 9),
        ("comdirect", "comdirect", 9),
        ("paypal", "paypal-de", 9),
        ("stripe-balance-transactions", "stripe-balance", 9),
        ("amex-de", "amex-de", 9),
        ("revolut", "revolut", 7)
    ])
    func everyFixture(fixture: String, formatID: String, lines: Int) throws {
        let result = try Support.run(fixture, accountKey: "TEST")
        #expect(result.formatID == formatID)
        #expect(result.isHeuristicMapping == false)
        #expect(result.drafts.count == lines)
        #expect(result.errors.isEmpty)
        #expect(result.balance.isConsistent)
        #expect(result.drafts.allSatisfy { $0.currency == .eur })
        #expect(result.drafts.allSatisfy { $0.rawJson?.isEmpty == false })
        // Every line must have a distinct identity, or the archive loses one.
        #expect(Set(result.drafts.map(\.lineFingerprint)).count == lines)
    }

    @Test("Own IBAN is detected from a column or the preamble", arguments: [
        ("sparkasse-camt", "DE00500105170001234567"),
        ("sparkasse-mt940", "DE00500105170001234567"),
        ("volksbank-vr", "DE00680900000012345678"),
        ("dkb", "DE00120300009876543210"),
        ("ing", "DE00170199991234567890")
    ])
    func ownIBAN(fixture: String, iban: String) throws {
        let result = try Support.run(fixture)
        #expect(result.detectedAccountIBAN == iban)
        #expect(result.accountKey == iban)
    }

    @Test("Formats without an account identity ask the caller", arguments: [
        "n26", "comdirect", "paypal", "stripe-balance-transactions", "amex-de", "revolut"
    ])
    func accountKeyRequired(fixture: String) throws {
        guard case let .accountKeyRequired(request) = try Support.outcome(fixture) else {
            Issue.record("expected accountKeyRequired for \(fixture)")
            return
        }
        #expect(request.lineCount > 0)
        #expect(!request.headerFingerprint.isEmpty)
    }

    @Test("A supplied account key wins over a detected IBAN")
    func suppliedKeyWins() throws {
        let result = try Support.run("dkb", accountKey: "dkb:girokonto")
        #expect(result.accountKey == "dkb:girokonto")
        #expect(result.detectedAccountIBAN == "DE00120300009876543210")
    }

    // MARK: - First and last line per format

    @Test("Sparkasse CSV-CAMT values")
    func sparkasseCAMT() throws {
        let result = try Support.run("sparkasse-camt")
        let first = try #require(result.drafts.first)
        #expect(first.sourceLineNumber == 2)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 8, day: 3))
        #expect(first.valueDate == LocalDate(year: 2026, month: 8, day: 3))
        #expect(first.amountMinor == -2379)
        #expect(first.counterpartyRaw == "Adobe Systems Software Ireland Limited")
        #expect(first.counterpartyIban == "IE00TEST12345612345678")
        #expect(first.reference == "Adobe Creative Cloud Abo 08/2026 Rechnung ADB-2026-88213")
        #expect(first.bookingText == "FOLGELASTSCHRIFT")

        let last = try #require(result.drafts.last)
        #expect(last.bookingDate == LocalDate(year: 2026, month: 8, day: 27))
        #expect(last.amountMinor == 85000)
        #expect(last.counterpartyRaw == "Nordwind Handels GmbH")
        #expect(last.reference == "Anzahlung Rechnung RE-2026-0051 Logo Design")
    }

    @Test("Sparkasse CSV-MT940 keeps the raw SEPA tags and drops the non-IBAN account number")
    func sparkasseMT940() throws {
        let result = try Support.run("sparkasse-mt940")
        let first = try #require(result.drafts.first)
        #expect(first.amountMinor == -2379)
        #expect(first.reference?.hasPrefix("EREF+ADB-2026-88213") == true)
        // "Kontonummer" holds 12345678, which is not an IBAN.
        #expect(result.drafts.allSatisfy { $0.counterpartyIban == nil })
    }

    @Test("Volksbank running balance is continuous")
    func volksbank() throws {
        let result = try Support.run("volksbank-vr")
        let first = try #require(result.drafts.first)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 8, day: 3))
        #expect(first.amountMinor == -2379)
        #expect(first.counterpartyIban == "IE00TEST12345612345678")
        #expect(result.balance.isConsistent)
        #expect(result.balance.firstBreak == nil)
    }

    @Test("DKB picks the counterparty by the sign and accepts short decimals")
    func dkb() throws {
        let result = try Support.run("dkb")
        let outgoing = try #require(result.drafts.first)
        #expect(outgoing.sourceLineNumber == 6)
        #expect(outgoing.counterpartyRaw == "Adobe Systems Software Ireland Limited")

        let incoming = try #require(result.drafts.first { $0.amountMinor > 0 })
        #expect(incoming.counterpartyRaw == "Nordwind Handels GmbH")

        // "-2000", "-11,9", "312,4" are all legal in this export.
        #expect(result.drafts.contains { $0.amountMinor == -200_000 })
        #expect(result.drafts.contains { $0.amountMinor == -1190 })
        #expect(result.drafts.contains { $0.amountMinor == 31240 })
    }

    @Test("N26 uses ISO dates and decimal points in the German export")
    func n26() throws {
        let result = try Support.run("n26", accountKey: "n26:giro")
        let first = try #require(result.drafts.first)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 8, day: 3))
        #expect(first.valueDate == nil)
        #expect(first.amountMinor == -2379)
        #expect(first.bookingText == "Lastschrift")
        #expect(result.drafts.contains { $0.counterpartyIban == "DE00300000001234567890" })
    }

    @Test("ING skips its 13-line preamble and reads dot-grouped amounts")
    func ing() throws {
        let result = try Support.run("ing")
        let first = try #require(result.drafts.first)
        #expect(first.sourceLineNumber == 15)
        #expect(first.amountMinor == -2379)
        // "3.570,00" and "-1.850,00" carry a thousands separator here.
        #expect(result.drafts.contains { $0.amountMinor == 357_000 })
        #expect(result.drafts.contains { $0.amountMinor == -185_000 })
    }

    @Test("comdirect splits the labelled Buchungstext field")
    func comdirect() throws {
        let result = try Support.run("comdirect", accountKey: "comdirect:giro")
        let card = try #require(result.drafts.first)
        #expect(card.sourceLineNumber == 5)
        #expect(card.counterpartyRaw == nil) // card payments carry no label
        #expect(card.reference == "Adobe Creative Cloud Abo 08/2026 Rechnung ADB-2026-88213")
        #expect(card.bookingText == "Kartenzahlung")

        let incoming = try #require(result.drafts.first { $0.amountMinor == 357_000 })
        #expect(incoming.counterpartyRaw == "Nordwind Handels GmbH")
        #expect(incoming.reference == "Rechnung RE-2026-0042 Webdesign Relaunch Projekt Phase 2")

        let outgoing = try #require(result.drafts.first { $0.amountMinor == -185_000 })
        #expect(outgoing.counterpartyRaw == "Finanzamt Muenchen")
    }

    @Test("PayPal books the net amount and keeps the fee and transaction code")
    func paypal() throws {
        let result = try Support.run("paypal", accountKey: "paypal:julia.beispiel@beispiel-design.test")
        let first = try #require(result.drafts.first)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 8, day: 3))
        #expect(first.amountMinor == -2379)
        #expect(first.counterpartyRaw == "Adobe Systems Software Ireland Limited")
        #expect(first.reference == "ADB-2026-88213")
        #expect(first.externalId == "1TA23456AB789012C")

        let invoice = try #require(result.drafts.first { $0.externalId == "2TB34567BC890123D" })
        #expect(invoice.amountMinor == 351_145) // Netto, not Brutto
        #expect(invoice.feeMinor == 5855)
        #expect(invoice.reference == "RE-2026-0042")

        let last = try #require(result.drafts.last)
        #expect(last.amountMinor == 2395)
        #expect(last.feeMinor == 105)
    }

    @Test("Stripe reads snake_case columns and major-unit amounts")
    func stripe() throws {
        let result = try Support.run("stripe-balance-transactions", accountKey: "stripe:acct_1PBeispiel")
        let first = try #require(result.drafts.first)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 8, day: 5))
        #expect(first.valueDate == LocalDate(year: 2026, month: 8, day: 7))
        #expect(first.amountMinor == 346_620)
        #expect(first.feeMinor == 10380)
        #expect(first.externalId == "txn_1PBeispiel00001")
        #expect(first.bookingText == "charge")
        #expect(first.reference == "Invoice RE-2026-0042 - Nordwind Handels GmbH")

        let last = try #require(result.drafts.last)
        #expect(last.amountMinor == -100)
        #expect(last.externalId == "txn_1PBeispiel00009")
    }

    @Test("Amex inverts the sign so a purchase is money out")
    func amex() throws {
        let result = try Support.run("amex-de", accountKey: "amex:1006")
        let first = try #require(result.drafts.first)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 8, day: 3))
        #expect(first.amountMinor == -2379)
        #expect(first.counterpartyRaw == "ADOBE SYSTEMS SOFTWARE IE DUBLIN")

        // "ZAHLUNG - BESTEN DANK" is exported as -1850,00 and pays the card.
        #expect(result.drafts.contains { $0.amountMinor == 185_000 })
        let last = try #require(result.drafts.last)
        #expect(last.amountMinor == -825)
    }

    @Test("Revolut subtracts the fee, skips non-completed rows and checks the balance")
    func revolut() throws {
        let result = try Support.run("revolut", accountKey: "revolut:eur")
        #expect(result.drafts.count == 7)
        #expect(result.skippedRows.map(\.lineNumber) == [6, 9])
        #expect(result.skippedRows.allSatisfy { $0.reason == .filteredByState })
        #expect(result.skippedRows.map(\.value) == ["REVERTED", "PENDING"])

        let first = try #require(result.drafts.first)
        #expect(first.bookingDate == LocalDate(year: 2026, month: 8, day: 1))
        #expect(first.valueDate == LocalDate(year: 2026, month: 8, day: 1))
        #expect(first.amountMinor == 250_000)
        #expect(first.bookingText == "Deposit")

        let refund = try #require(result.drafts.first { $0.bookingText == "Card Refund" })
        #expect(refund.amountMinor == 5000)
        #expect(refund.bookingDate == LocalDate(year: 2026, month: 8, day: 1))
        #expect(refund.valueDate == LocalDate(year: 2026, month: 7, day: 30))

        // -500.00 with a 4.25 fee moves the balance by -504.25.
        let exchange = try #require(result.drafts.first { $0.bookingText == "Exchange" })
        #expect(exchange.amountMinor == -50425)
        #expect(exchange.feeMinor == 425)

        #expect(result.balance.isConsistent)
        let last = try #require(result.drafts.last)
        #expect(last.classification == .taxPayment)
    }

    @Test("A broken running balance is reported with the first break")
    func brokenBalance() throws {
        let data = Support.csv([
            "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance",
            "Deposit,Current,2026-08-01 08:07:42,2026-08-01 08:07:43,Payment from MAX MUSTER,100.00,0.00,EUR,COMPLETED,100.00",
            "Card Payment,Current,2026-08-02 10:11:12,2026-08-02 10:11:13,Amazon,-10.00,0.00,EUR,COMPLETED,90.00",
            "Card Payment,Current,2026-08-03 10:11:12,2026-08-03 10:11:13,Amazon,-10.00,0.00,EUR,COMPLETED,70.00"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "revolut:eur") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.balance.isConsistent == false)
        let firstBreak = try #require(result.balance.firstBreak)
        #expect(firstBreak.lineNumber == 4)
        #expect(firstBreak.expectedMinor == 8000)
        #expect(firstBreak.foundMinor == 7000)
    }

    @Test("A newest-first export is not reported as a broken balance")
    func descendingBalance() throws {
        let data = Support.csv([
            "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance",
            "Card Payment,Current,2026-08-03 10:11:12,2026-08-03 10:11:13,Amazon,-10.00,0.00,EUR,COMPLETED,80.00",
            "Card Payment,Current,2026-08-02 10:11:12,2026-08-02 10:11:13,Amazon,-10.00,0.00,EUR,COMPLETED,90.00",
            "Deposit,Current,2026-08-01 08:07:42,2026-08-01 08:07:43,Payment from MAX MUSTER,100.00,0.00,EUR,COMPLETED,100.00"
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: data, accountKey: "revolut:eur") else {
            Issue.record("expected an import")
            return
        }
        #expect(result.balance.isConsistent)
    }
}
