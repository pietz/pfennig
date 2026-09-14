import Database
import Domain
import Foundation
import StatementImport
import Testing

@Suite("Statement line repository")
struct StatementLineRepositoryTests {
    static func database() throws -> AppDatabase {
        try AppDatabase(inMemoryNamed: UUID().uuidString)
    }

    /// A Sparkasse CSV-CAMT file built from single rows, so the overlap
    /// between two exports can be stated exactly.
    static func sparkasse(_ rows: [String]) -> Data {
        let header = "\"Auftragskonto\";\"Buchungstag\";\"Valutadatum\";\"Buchungstext\";" +
            "\"Verwendungszweck\";\"Glaeubiger ID\";\"Mandatsreferenz\";\"Kundenreferenz (End-to-End)\";" +
            "\"Sammlerreferenz\";\"Lastschrift Ursprungsbetrag\";\"Auslagenersatz Ruecklastschrift\";" +
            "\"Beguenstigter/Zahlungspflichtiger\";\"Kontonummer/IBAN\";\"BIC (SWIFT-Code)\";" +
            "\"Betrag\";\"Waehrung\";\"Info\""
        return Support.csv([header] + rows)
    }

    static func row(day: Int, purpose: String, counterparty: String, iban: String, amount: String) -> String {
        "\"DE00500105170001234567\";\"\(String(format: "%02d", day)).08.26\";" +
            "\"\(String(format: "%02d", day)).08.26\";\"UEBERWEISUNG\";\"\(purpose)\";\"\";\"\";\"\";" +
            "\"\";\"\";\"\";\"\(counterparty)\";\"\(iban)\";\"TESTDEFFXXX\";\"\(amount)\";\"EUR\";\"\""
    }

    @Test("Drafts land in statement_lines unclassified and unpaid")
    func insert() throws {
        let database = try Self.database()
        let repository = StatementLineRepository(database)
        let result = try Support.run("sparkasse-camt")

        let report = try repository.insert(result.drafts, accountKey: result.accountKey)
        #expect(report.inserted == 9)
        #expect(report.alreadyKnown == 0)

        let lines = try repository.lines(accountKey: result.accountKey)
        #expect(lines.count == 9)
        #expect(lines.allSatisfy { $0.accountIban == "DE00500105170001234567" })
        #expect(lines.allSatisfy { $0.paymentId == nil })
        #expect(lines.allSatisfy { $0.classificationSubtype == nil })
        // Business versus private is decided later; only the two deterministic
        // classes may already be set.
        #expect(lines.allSatisfy { [.unknown, .taxPayment, .internalTransfer].contains($0.classification) })
        #expect(lines.count { $0.classification == .unknown } == 8)
        #expect(lines.count { $0.classification == .taxPayment } == 1)
        #expect(lines.allSatisfy { $0.currency == "EUR" })
        #expect(lines.allSatisfy { $0.rawJson?.isEmpty == false })
        #expect(lines.contains { $0.counterpartyIban == "IE00TEST12345612345678" })
    }

    @Test("The archived document id is kept on every line")
    func documentLink() throws {
        let database = try Self.database()
        let documentID = try database.writer.write { db -> String in
            let record = DocumentRecord(
                originalFilename: "auszug.csv",
                storedFilename: "auszug.csv",
                relativePath: "Documents/2026/auszug.csv",
                mimeType: "text/csv",
                sha256: String(repeating: "a", count: 64),
                byteSize: 1234,
                documentType: .statement,
                source: .dragDrop
            )
            try record.insert(db)
            return record.id
        }
        let repository = StatementLineRepository(database)
        let result = try Support.run("sparkasse-camt")
        try repository.insert(result.drafts, accountKey: result.accountKey, documentID: documentID)

        let lines = try repository.lines(accountKey: result.accountKey)
        #expect(lines.allSatisfy { $0.documentId == documentID })
    }

    @Test("Re-importing the same file adds nothing")
    func reimport() throws {
        let database = try Self.database()
        let repository = StatementLineRepository(database)
        let result = try Support.run("sparkasse-camt")

        _ = try repository.insert(result.drafts, accountKey: result.accountKey)
        let second = try repository.insert(result.drafts, accountKey: result.accountKey)
        #expect(second.inserted == 0)
        #expect(second.alreadyKnown == 9)
        #expect(try repository.count() == 9)
    }

    @Test("An overlapping second export adds only its new lines")
    func overlappingPeriod() throws {
        let database = try Self.database()
        let repository = StatementLineRepository(database)

        let august = Self.sparkasse([
            Self.row(day: 3, purpose: "Abo A", counterparty: "Adobe", iban: "IE00TEST12345612345678", amount: "-23,79"),
            Self.row(
                day: 5,
                purpose: "RE-2026-0042",
                counterparty: "Nordwind",
                iban: "DE00300000001234567890",
                amount: "3570,00"
            ),
            Self.row(day: 8, purpose: "Abo B", counterparty: "Google", iban: "IE00TEST98765432109876", amount: "-6,80")
        ])
        let overlap = Self.sparkasse([
            // The last two lines of the first export, then two new ones.
            Self.row(
                day: 5,
                purpose: "RE-2026-0042",
                counterparty: "Nordwind",
                iban: "DE00300000001234567890",
                amount: "3570,00"
            ),
            Self.row(day: 8, purpose: "Abo B", counterparty: "Google", iban: "IE00TEST98765432109876", amount: "-6,80"),
            Self.row(day: 12, purpose: "Entgelt", counterparty: "Sparkasse", iban: "", amount: "-11,90"),
            Self.row(
                day: 15,
                purpose: "RE-2026-0051",
                counterparty: "Nordwind",
                iban: "DE00300000001234567890",
                amount: "850,00"
            )
        ])

        guard case let .imported(first) = try CSVStatementImporter.run(data: august),
              case let .imported(second) = try CSVStatementImporter.run(data: overlap)
        else {
            Issue.record("expected two imports")
            return
        }
        let firstReport = try repository.insert(first.drafts, accountKey: first.accountKey)
        #expect(firstReport.inserted == 3)

        let secondReport = try repository.insert(second.drafts, accountKey: second.accountKey)
        #expect(secondReport.inserted == 2)
        #expect(secondReport.alreadyKnown == 2)
        #expect(try repository.count() == 5)
    }

    @Test("The same line on a different account is a different line")
    func perAccountIdentity() throws {
        let database = try Self.database()
        let repository = StatementLineRepository(database)
        let result = try Support.run("sparkasse-camt")

        _ = try repository.insert(result.drafts, accountKey: result.accountKey)
        // Fingerprints include the account, so a second account never collides.
        guard case let .imported(other) = try CSVStatementImporter.run(
            data: Support.fixture("sparkasse-camt"),
            accountKey: "DE00999999999999999999"
        ) else {
            Issue.record("expected an import")
            return
        }
        let report = try repository.insert(other.drafts, accountKey: other.accountKey)
        #expect(report.inserted == 9)
        #expect(try repository.count() == 18)
    }

    /// Two identical rows in one file are two real movements - the same
    /// amount to the same shop on the same day happens - so both are kept and
    /// told apart by their occurrence index.
    @Test("Two identical lines in one file are both kept")
    func duplicateInsideOneFile() throws {
        let duplicated = Self.sparkasse([
            Self.row(day: 3, purpose: "Abo A", counterparty: "Adobe", iban: "IE00TEST12345612345678", amount: "-23,79"),
            Self.row(day: 3, purpose: "Abo A", counterparty: "Adobe", iban: "IE00TEST12345612345678", amount: "-23,79")
        ])
        guard case let .imported(result) = try CSVStatementImporter.run(data: duplicated) else {
            Issue.record("expected an import")
            return
        }
        #expect(result.drafts.count == 2)
        #expect(result.skippedRows.isEmpty)
        #expect(Set(result.drafts.map(\.lineFingerprint)).count == 2)

        let database = try Self.database()
        let repository = StatementLineRepository(database)
        #expect(try repository.insert(result.drafts, accountKey: result.accountKey).inserted == 2)
        // And the same file dropped a second time still adds nothing.
        #expect(try repository.insert(result.drafts, accountKey: result.accountKey).inserted == 0)
        #expect(try repository.count() == 2)
    }

    /// The overlap case behind the occurrence index: the follow-up export
    /// repeats one of the two identical lines and adds a third. Only the new
    /// one is stored.
    @Test("An overlapping export of a file with identical lines adds only the new line")
    func duplicateAcrossOverlappingFiles() throws {
        let adobe = Self.row(
            day: 3,
            purpose: "Abo A",
            counterparty: "Adobe",
            iban: "IE00TEST12345612345678",
            amount: "-23,79"
        )
        let google = Self.row(
            day: 8,
            purpose: "Abo B",
            counterparty: "Google",
            iban: "IE00TEST98765432109876",
            amount: "-6,80"
        )
        guard case let .imported(first) = try CSVStatementImporter.run(data: Self.sparkasse([adobe, adobe])),
              case let .imported(second) = try CSVStatementImporter.run(data: Self.sparkasse([adobe, adobe, google]))
        else {
            Issue.record("expected two imports")
            return
        }
        let database = try Self.database()
        let repository = StatementLineRepository(database)
        #expect(try repository.insert(first.drafts, accountKey: first.accountKey).inserted == 2)
        let report = try repository.insert(second.drafts, accountKey: second.accountKey)
        #expect(report.inserted == 1)
        #expect(report.alreadyKnown == 2)
    }

    @Test("A separately reported fee is stored with the line")
    func feeIsStored() throws {
        let database = try Self.database()
        let repository = StatementLineRepository(database)
        let result = try Support.run("paypal", accountKey: "paypal:julia.beispiel@beispiel-design.test")
        try repository.insert(result.drafts, accountKey: result.accountKey)

        let lines = try repository.lines(accountKey: result.accountKey)
        let charged = try #require(lines.first { $0.externalId == "2TB34567BC890123D" })
        #expect(charged.feeMinor == 5855)
        #expect(charged.amountMinor == 351_145)
        // A line without a reported fee keeps NULL rather than a zero.
        #expect(lines.contains { $0.feeMinor == nil })
        #expect(lines.allSatisfy { ($0.feeMinor ?? 0) >= 0 })
    }

    @Test("Known account keys come from the lines already stored")
    func knownAccountKeys() throws {
        let database = try Self.database()
        let repository = StatementLineRepository(database)
        #expect(try repository.knownAccountKeys().isEmpty)

        let sparkasse = try Support.run("sparkasse-camt")
        _ = try repository.insert(sparkasse.drafts, accountKey: sparkasse.accountKey)
        #expect(try repository.knownAccountKeys() == ["DE00500105170001234567"])

        // The DKB export transfers to the Sparkasse account, which is now known.
        let dkb = try Support.run("dkb", knownAccountKeys: repository.knownAccountKeys())
        #expect(dkb.drafts.contains { $0.classification == .internalTransfer } == false)

        let sparkasseKeys: Set = ["DE00500105170009876543"]
        let dkbWithSibling = try Support.run("dkb", knownAccountKeys: sparkasseKeys)
        #expect(dkbWithSibling.drafts.count { $0.classification == .internalTransfer } == 1)
    }
}

/// What makes two statement lines the same line (`LineFingerprint`).
@Suite("Line identity")
struct LineFingerprintTests {
    static func draft(
        amount: Int64 = -2379,
        reference: String? = "Rechnung RE-2026-0042",
        counterparty: String? = "Nordwind Handels GmbH",
        externalID: String? = nil
    ) -> StatementLineDraft {
        StatementLineDraft(
            sourceLineNumber: 1,
            lineFingerprint: "",
            bookingDate: LocalDate(year: 2026, month: 8, day: 3),
            amountMinor: amount,
            counterpartyRaw: counterparty,
            reference: reference,
            externalId: externalID
        )
    }

    @Test("The export's own transaction id is the identity")
    func externalIDWins() {
        let first = LineFingerprint.make(accountID: "a", line: Self.draft(externalID: "1TA23456AB789012C"))
        // The same movement, exported again with a reworded purpose and name.
        let second = LineFingerprint.make(accountID: "a", line: Self.draft(
            reference: "RE-2026-0042 Webdesign",
            counterparty: "NORDWIND HANDELS GMBH",
            externalID: "1TA23456AB789012C"
        ))
        #expect(first == second)
        // A different transaction id is a different line, even with the same
        // date, amount and text.
        #expect(first != LineFingerprint.make(accountID: "a", line: Self.draft(externalID: "2TB34567BC890123D")))
    }

    @Test("Without a transaction id the facts of the line decide")
    func textFields() {
        let line = LineFingerprint.make(accountID: "a", line: Self.draft())
        #expect(line == LineFingerprint.make(accountID: "a", line: Self.draft(
            reference: "  RECHNUNG   RE-2026-0042 ",
            counterparty: "nordwind handels gmbh"
        )))
        #expect(line != LineFingerprint.make(accountID: "b", line: Self.draft()))
        #expect(line != LineFingerprint.make(accountID: "a", line: Self.draft(amount: -2380)))
        #expect(line != LineFingerprint.make(accountID: "a", line: Self.draft(reference: "Rechnung RE-2026-0051")))
    }

    @Test("A repeated occurrence is a line of its own")
    func occurrence() {
        let first = LineFingerprint.make(accountID: "a", line: Self.draft())
        #expect(LineFingerprint.make(accountID: "a", line: Self.draft(), occurrence: 1) == first)
        #expect(LineFingerprint.make(accountID: "a", line: Self.draft(), occurrence: 2) != first)
        #expect(
            LineFingerprint.make(accountID: "a", line: Self.draft(), occurrence: 2)
                != LineFingerprint.make(accountID: "a", line: Self.draft(), occurrence: 3)
        )
    }
}
