import Domain
import Foundation
import StatementImport
import Testing

/// Only the two classifications that follow from the data. Business versus
/// private stays a user decision, so everything else must stay `unknown`.
@Suite("Classification")
struct ClassificationTests {
    static func draft(
        amount: Int64 = -100,
        counterparty: String? = nil,
        iban: String? = nil,
        reference: String? = nil,
        bookingText: String? = nil
    ) -> StatementLineDraft {
        StatementLineDraft(
            sourceLineNumber: 1,
            lineFingerprint: "f",
            bookingDate: LocalDate(year: 2026, month: 8, day: 1),
            amountMinor: amount,
            counterpartyRaw: counterparty,
            counterpartyIban: iban,
            reference: reference,
            bookingText: bookingText
        )
    }

    @Test("A counterparty IBAN that is one of the user's own accounts is an internal transfer")
    func internalTransfer() {
        let line = Self.draft(counterparty: "Julia Beispiel", iban: "DE00500105170009876543")
        #expect(StatementLineClassifier.classify(line, knownAccountKeys: ["DE00500105170009876543"])
            == .internalTransfer)
        #expect(StatementLineClassifier.classify(line, knownAccountKeys: ["DE00999999999999999999"]) == .unknown)
        #expect(StatementLineClassifier.classify(line, knownAccountKeys: []) == .unknown)
    }

    @Test("Spacing and casing of an IBAN do not decide it")
    func ibanNormalization() {
        let line = Self.draft(iban: "DE00 5001 0517 0009 8765 43")
        #expect(StatementLineClassifier.classify(line, knownAccountKeys: ["de00500105170009876543"])
            == .internalTransfer)
    }

    @Test("A Finanzamt counterparty is a tax payment")
    func finanzamt() {
        #expect(StatementLineClassifier.classify(
            Self.draft(counterparty: "Finanzamt Muenchen"),
            knownAccountKeys: []
        ) == .taxPayment)
        #expect(StatementLineClassifier.classify(
            Self.draft(counterparty: "FINANZAMT BERLIN-MITTE"),
            knownAccountKeys: []
        ) == .taxPayment)
    }

    @Test("A Steuernummer together with a VAT keyword is a tax payment", arguments: [
        "UStVA 07/2026 St-Nr 143/815/09211",
        "Umsatzsteuer-Vorauszahlung 12/345/67890",
        "Umsatzsteuervoranmeldung 08/2026, Steuernummer 143/815/09211",
        "USt 07/2026 143/815/09211"
    ])
    func steuernummerWithVAT(reference: String) {
        #expect(StatementLineClassifier.classify(
            Self.draft(counterparty: "Landeshauptkasse", reference: reference),
            knownAccountKeys: []
        ) == .taxPayment)
    }

    @Test("A Steuernummer alone, or a VAT word alone, is not enough", arguments: [
        "Zahlung 143/815/09211",
        "Umsatzsteuer aus Rechnung RE-2026-0042",
        "Ruecklage Steuern Q3 2026"
    ])
    func notTaxPayment(reference: String) {
        #expect(StatementLineClassifier.classify(
            Self.draft(counterparty: "Nordwind Handels GmbH", reference: reference),
            knownAccountKeys: []
        ) == .unknown)
    }

    @Test("A month name does not count as a VAT keyword")
    func augustIsNotUSt() {
        // "August" contains "ust"; whole-word matching is what keeps this out.
        #expect(StatementLineClassifier.classify(
            Self.draft(counterparty: "Nordwind", reference: "Miete August 143/815/09211"),
            knownAccountKeys: []
        ) == .unknown)
    }

    @Test("Everything else stays unknown, including obvious private spending")
    func staysUnknown() {
        #expect(StatementLineClassifier.classify(
            Self.draft(counterparty: "REWE SAGT DANKE"),
            knownAccountKeys: []
        ) == .unknown)
        #expect(StatementLineClassifier.classify(
            Self.draft(amount: 357_000, counterparty: "Nordwind Handels GmbH", reference: "RE-2026-0042"),
            knownAccountKeys: []
        ) == .unknown)
    }

    @Test("Classification runs as part of the import")
    func inTheImport() throws {
        let result = try Support.run(
            "sparkasse-camt",
            knownAccountKeys: ["DE00500105170009876543"]
        )
        let tax = try #require(result.drafts.first { $0.counterpartyRaw == "Finanzamt Muenchen" })
        #expect(tax.classification == .taxPayment)

        let transfer = try #require(result.drafts.first { $0.reference == "Ruecklage Steuern Q3 2026" })
        #expect(transfer.classification == .internalTransfer)

        #expect(result.drafts.count { $0.classification == .unknown } == 7)
    }

    @Test("Without the other account, the same transfer is not internal")
    func withoutKnownAccounts() throws {
        let result = try Support.run("sparkasse-camt")
        let transfer = try #require(result.drafts.first { $0.reference == "Ruecklage Steuern Q3 2026" })
        #expect(transfer.classification == .unknown)
    }

    @Test("The batch form classifies every draft")
    func batch() {
        let drafts = [
            Self.draft(counterparty: "Finanzamt Muenchen"),
            Self.draft(counterparty: "REWE")
        ]
        let classified = StatementLineClassifier.classify(drafts, knownAccountKeys: [])
        #expect(classified.map(\.classification) == [.taxPayment, .unknown])
    }
}
