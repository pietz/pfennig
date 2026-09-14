import Analysis
@testable import Database
import Domain
import Foundation
import GRDB
import Tax
import Testing

@Suite("UStVA-Berechnung")
struct UStVACalculatorTests {
    // MARK: - Fixtures

    private func database(smallBusiness: Bool = false) throws -> (AppDatabase, BusinessProfile) {
        let database = try AppDatabase(inMemoryNamed: "ustva-\(UUID().uuidString)")
        let profile = BusinessProfile(
            name: "Testbetrieb",
            taxNumber: "1096081508187",
            vatStatus: smallBusiness ? .smallBusiness : .taxable
        )
        try database.writer.write { try profile.insert($0) }
        return (database, profile)
    }

    private struct Component {
        let rate: String?
        let kind: TaxComponentKind
        let net: Int64
        let tax: Int64
    }

    private func component(_ rate: String, net: Int64, tax: Int64) -> Component {
        Component(rate: rate, kind: rate == "7" ? .reduced : .standard, net: net, tax: tax)
    }

    /// Inserts a transaction with its assessment, components, an attached
    /// document (so expenses do not trip the "Ausgabe ohne Beleg" exception)
    /// and an optional counterparty.
    @discardableResult
    private func insert(
        _ database: AppDatabase,
        profile: BusinessProfile,
        direction: Direction,
        treatment: TaxTreatment?,
        title: String = "Testvorgang",
        invoiceDate: LocalDate?,
        net: Int64,
        tax: Int64,
        components: [Component] = [],
        counterpartyCountry: String? = nil,
        counterpartyName: String = "Testpartner",
        selfAssessedVatMinor: Int64? = nil,
        servicePeriodStart: LocalDate? = nil,
        attachDocument: Bool = true
    ) throws -> TransactionRecord {
        var counterpartyID: String?
        if counterpartyCountry != nil {
            let counterparty = Counterparty(
                displayName: "\(counterpartyName) \(UUID().uuidString.prefix(6))",
                countryCode: counterpartyCountry
            )
            try database.writer.write { try counterparty.insert($0) }
            counterpartyID = counterparty.id
        }

        let transaction = TransactionRecord(
            businessProfileId: profile.id,
            counterpartyId: counterpartyID,
            direction: direction,
            transactionType: .invoice,
            title: title,
            invoiceDate: invoiceDate,
            servicePeriodStart: servicePeriodStart,
            bookedNetMinor: net,
            bookedTaxMinor: tax,
            bookedGrossMinor: net + tax,
            reviewStatus: .confirmed
        )
        try database.writer.write { db in
            try transaction.insert(db)
            if let treatment {
                try TaxAssessment(
                    transactionId: transaction.id,
                    treatment: treatment,
                    taxableBaseMinor: net,
                    selfAssessedVatMinor: selfAssessedVatMinor,
                    status: .confirmed
                ).insert(db)
            }
            for (index, component) in components.enumerated() {
                try TaxComponent(
                    transactionId: transaction.id,
                    kind: component.kind,
                    rate: component.rate,
                    netMinor: component.net,
                    taxMinor: component.tax,
                    sortOrder: index
                ).insert(db)
            }
            if attachDocument {
                let document = DocumentRecord(
                    originalFilename: "beleg.pdf",
                    storedFilename: "beleg.pdf",
                    relativePath: "Documents/\(transaction.id).pdf",
                    sha256: UUID().uuidString,
                    byteSize: 1
                )
                try document.insert(db)
                try TransactionDocument(transactionId: transaction.id, documentId: document.id).insert(db)
            }
        }
        return transaction
    }

    private func pay(
        _ database: AppDatabase,
        _ transaction: TransactionRecord,
        amountMinor: Int64,
        on date: LocalDate,
        direction: PaymentDirection? = nil
    ) throws {
        try database.writer.write { db in
            let payment = Payment(
                direction: direction ?? transaction.direction.settlingPaymentDirection,
                paymentDate: date,
                originalAmountMinor: amountMinor,
                bookedAmountMinor: amountMinor
            )
            try payment.insert(db)
            try PaymentAllocation(
                paymentId: payment.id,
                transactionId: transaction.id,
                allocatedMinor: amountMinor,
                matchMethod: .exact
            ).insert(db)
        }
    }

    private func prepare(
        _ database: AppDatabase,
        _ profile: BusinessProfile,
        quarter: Int,
        year: Int = 2026
    ) throws -> UStVAReturn {
        try UStVACalculator.prepare(
            period: UStVAPeriod(year: year, quarter: quarter),
            profile: profile,
            database: database
        )
    }

    // MARK: - Abnahme

    @Test("Zwei Teilzahlungen erscheinen anteilig in Q3 und Q4 und summieren auf die Rechnung")
    func partialPaymentsAcrossQuarters() throws {
        let (database, profile) = try database()
        let invoice = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 1),
            net: 100_000, tax: 19000,
            components: [component("19", net: 100_000, tax: 19000)]
        )
        try pay(database, invoice, amountMinor: 50000, on: LocalDate(year: 2026, month: 8, day: 15))
        try pay(database, invoice, amountMinor: 69000, on: LocalDate(year: 2026, month: 10, day: 15))

        let q3 = try prepare(database, profile, quarter: 3)
        let q4 = try prepare(database, profile, quarter: 4)

        #expect(q3.line(81)?.amountMinor == 42017)
        #expect(q4.line(81)?.amountMinor == 57983)
        #expect((q3.line(81)?.amountMinor ?? 0) + (q4.line(81)?.amountMinor ?? 0) == 100_000)
        #expect(q3.exceptions.isEmpty)
        #expect(q3.isDraft == false)

        // Every line is reproducible from its own contributions.
        #expect(q3.line(81)?.contributions.reduce(Int64(0)) { $0 + $1.amountMinor } == 42017)
        #expect(q3.line(81)?.contributions.first?.transactionID == invoice.id)

        // Kz 83 is what ELSTER computes: 19 % of the whole-euro base.
        #expect(q3.payableMinor == 420 * 19)
        #expect(q4.payableMinor == 579 * 19)
    }

    @Test("Ein Mischbeleg 7 %/19 % verteilt Bemessungsgrundlagen centgenau")
    func mixedRateReceipt() throws {
        let (database, profile) = try database()
        let invoice = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 2),
            net: 15000, tax: 2250,
            components: [component("19", net: 10000, tax: 1900), component("7", net: 5000, tax: 350)]
        )
        try pay(database, invoice, amountMinor: 10000, on: LocalDate(year: 2026, month: 8, day: 1))
        try pay(database, invoice, amountMinor: 7250, on: LocalDate(year: 2026, month: 11, day: 1))

        let q3 = try prepare(database, profile, quarter: 3)
        let q4 = try prepare(database, profile, quarter: 4)

        let base19 = (q3.line(81)?.amountMinor ?? 0) + (q4.line(81)?.amountMinor ?? 0)
        let base7 = (q3.line(86)?.amountMinor ?? 0) + (q4.line(86)?.amountMinor ?? 0)
        #expect(base19 == 10000)
        #expect(base7 == 5000)

        // The Q3 slices together account for exactly the 100,00 EUR paid.
        let q3Gross = (q3.line(81)?.amountMinor ?? 0) + (q3.line(86)?.amountMinor ?? 0)
        #expect(q3Gross == 5797 + 2899)
        #expect(q3.line(81)?.amountMinor == 5797)
        #expect(q3.line(86)?.amountMinor == 2899)
    }

    @Test("Ausländisches SaaS erzeugt bei Regelbesteuerung Kz 46/47 und gleich hohe Kz 67")
    func reverseChargeForRegularBusiness() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .expense, treatment: .reverseCharge,
            title: "SaaS-Abo", invoiceDate: LocalDate(year: 2026, month: 8, day: 5),
            net: 100_000, tax: 0, counterpartyCountry: "IE", counterpartyName: "Cloud Ltd",
            selfAssessedVatMinor: 19000
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(46)?.amountMinor == 100_000)
        #expect(q3.line(47)?.amountMinor == 19000)
        #expect(q3.line(67)?.amountMinor == 19000)
        #expect(q3.payableMinor == 0)
        #expect(q3.exceptions.isEmpty)

        // No payment is needed: §13b arises with the invoice, not the transfer.
        #expect(q3.line(47)?.contributions.first?.paymentID == nil)
        #expect(q3.line(47)?.contributions.first?.date == LocalDate(year: 2026, month: 8, day: 5))
    }

    @Test("Kleinunternehmer schulden Kz 47 ohne Vorsteuerabzug")
    func reverseChargeForSmallBusiness() throws {
        let (database, profile) = try database(smallBusiness: true)
        try insert(
            database, profile: profile, direction: .expense, treatment: .reverseCharge,
            title: "SaaS-Abo", invoiceDate: LocalDate(year: 2026, month: 8, day: 5),
            net: 100_000, tax: 0, counterpartyCountry: "IE", counterpartyName: "Cloud Ltd",
            selfAssessedVatMinor: 19000
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.isSmallBusiness)
        #expect(q3.line(46)?.amountMinor == 100_000)
        #expect(q3.line(47)?.amountMinor == 19000)
        #expect(q3.line(67) == nil)
        #expect(q3.line(66) == nil)
        #expect(q3.payableMinor == 19000)
    }

    @Test("Kleinunternehmer melden ihre §19-Einnahmen nicht in Kz 48")
    func smallBusinessIncomeIsNotReported() throws {
        let (small, smallProfile) = try database(smallBusiness: true)
        let invoice = try insert(
            small, profile: smallProfile, direction: .income, treatment: .smallBusiness,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 1), net: 100_000, tax: 0
        )
        try pay(small, invoice, amountMinor: 100_000, on: LocalDate(year: 2026, month: 7, day: 20))

        let q3 = try prepare(small, smallProfile, quarter: 3)
        #expect(q3.line(48) == nil)
        #expect(q3.lines.isEmpty)
        #expect(q3.payableMinor == 0)
        #expect(q3.exceptions.isEmpty)

        // A regular business still reports exempt income in Kz 48.
        let (regular, regularProfile) = try database()
        let exempt = try insert(
            regular, profile: regularProfile, direction: .income, treatment: .exempt,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 1), net: 100_000, tax: 0
        )
        try pay(regular, exempt, amountMinor: 100_000, on: LocalDate(year: 2026, month: 7, day: 20))
        #expect(try prepare(regular, regularProfile, quarter: 3).line(48)?.amountMinor == 100_000)
    }

    @Test("§13b ohne Rechnungsdatum wird über das Leistungsdatum gefunden")
    func reverseChargeWithoutInvoiceDate() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .expense, treatment: .reverseCharge,
            title: "SaaS ohne Rechnungsdatum", invoiceDate: nil,
            net: 100_000, tax: 0, counterpartyCountry: "IE", counterpartyName: "Cloud Ltd",
            selfAssessedVatMinor: 19000,
            servicePeriodStart: LocalDate(year: 2026, month: 8, day: 5)
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(46)?.amountMinor == 100_000)
        #expect(q3.line(67)?.amountMinor == 19000)
        #expect(try prepare(database, profile, quarter: 2).lines.isEmpty)
    }

    @Test("§13b ganz ohne Datum wird zur Ausnahme statt zu einer Zeile")
    func reverseChargeWithoutAnyDate() throws {
        let (database, profile) = try database()
        let transaction = try insert(
            database, profile: profile, direction: .expense, treatment: .reverseCharge,
            title: "SaaS ohne Datum", invoiceDate: nil,
            net: 100_000, tax: 0, counterpartyCountry: "IE", counterpartyName: "Cloud Ltd",
            selfAssessedVatMinor: 19000
        )
        try pay(database, transaction, amountMinor: 100_000, on: LocalDate(year: 2026, month: 8, day: 5))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.lines.isEmpty)
        #expect(q3.exceptions.contains { $0.message == "Rechnungsdatum fehlt" })
    }

    @Test("Ein Anbieter aus dem Drittland gehört in Kz 84/85")
    func reverseChargeFromThirdCountry() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .expense, treatment: .reverseCharge,
            title: "US-SaaS", invoiceDate: LocalDate(year: 2026, month: 9, day: 30),
            net: 50000, tax: 0, counterpartyCountry: "US", counterpartyName: "Vendor Inc",
            selfAssessedVatMinor: 9500
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(84)?.amountMinor == 50000)
        #expect(q3.line(85)?.amountMinor == 9500)
        #expect(q3.line(67)?.amountMinor == 9500)
        #expect(q3.line(46) == nil)
        #expect(q3.payableMinor == 0)
    }

    @Test("Ein §13b-Vorgang ohne bekanntes Anbieterland bleibt Entwurf")
    func reverseChargeWithoutCountry() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .expense, treatment: .reverseCharge,
            title: "SaaS ohne Land", invoiceDate: LocalDate(year: 2026, month: 8, day: 5),
            net: 10000, tax: 0, selfAssessedVatMinor: 1900
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(46)?.amountMinor == 10000)
        #expect(q3.exceptions.contains { $0.kind == .reverseChargeUnclear })
        #expect(q3.isDraft)
    }

    @Test("Eine Bemessungsgrundlage ohne Steuerbetrag wird gemeldet statt still verworfen")
    func selfAssessedBaseWithoutTax() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .expense, treatment: .reverseCharge,
            title: "SaaS ohne Steuerbetrag", invoiceDate: LocalDate(year: 2026, month: 8, day: 5),
            net: 100_000, tax: 0, counterpartyCountry: "IE", counterpartyName: "Cloud Ltd",
            selfAssessedVatMinor: 0
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(46)?.amountMinor == 100_000)
        #expect(q3.line(47) == nil)
        #expect(q3.isDraft)
        #expect(q3.exceptions.contains {
            $0.kind == .other && $0.message.hasPrefix("Bemessungsgrundlage ohne Steuerbetrag")
        })
    }

    @Test("Ein innergemeinschaftlicher Erwerb unter einem Euro meldet die fehlende Steuer")
    func intraCommunityBaseWithoutTax() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .expense, treatment: .intraCommunityAcquisition,
            title: "Kleinteil aus NL", invoiceDate: LocalDate(year: 2026, month: 9, day: 1),
            net: 50, tax: 0, counterpartyCountry: "NL", counterpartyName: "Hardware BV"
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(89)?.amountMinor == 50)
        #expect(q3.line(61) == nil)
        #expect(q3.exceptions.contains {
            $0.kind == .other && $0.message.hasPrefix("Bemessungsgrundlage ohne Steuerbetrag")
        })
    }

    @Test("Eine Ausgabe mit Rechnung in Q3 und Zahlung in Q4 zählt zur Vorsteuer in Q4")
    func inputVATFollowsTheLaterOfInvoiceAndPayment() throws {
        let (database, profile) = try database()
        let bill = try insert(
            database, profile: profile, direction: .expense, treatment: .domesticVAT,
            title: "Bürobedarf", invoiceDate: LocalDate(year: 2026, month: 9, day: 20),
            net: 10000, tax: 1900,
            components: [component("19", net: 10000, tax: 1900)]
        )
        try pay(database, bill, amountMinor: 11900, on: LocalDate(year: 2026, month: 10, day: 5))

        let q3 = try prepare(database, profile, quarter: 3)
        let q4 = try prepare(database, profile, quarter: 4)
        #expect(q3.line(66) == nil)
        #expect(q3.lines.isEmpty)
        #expect(q3.exceptions.isEmpty)
        #expect(q4.line(66)?.amountMinor == 1900)
        #expect(q4.payableMinor == -1900)
    }

    @Test("Kleinunternehmer haben keine Kz 66")
    func smallBusinessHasNoInputVAT() throws {
        let (database, profile) = try database(smallBusiness: true)
        let bill = try insert(
            database, profile: profile, direction: .expense, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            net: 10000, tax: 1900,
            components: [component("19", net: 10000, tax: 1900)]
        )
        try pay(database, bill, amountMinor: 11900, on: LocalDate(year: 2026, month: 8, day: 2))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(66) == nil)
        #expect(q3.payableMinor == 0)
    }

    @Test("Ein Vorgang mit unbekannter Behandlung wird zur Ausnahme, die Werte bleiben berechnet")
    func unknownTreatmentBecomesAnException() throws {
        let (database, profile) = try database()
        let good = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 1),
            net: 10000, tax: 1900,
            components: [component("19", net: 10000, tax: 1900)]
        )
        try pay(database, good, amountMinor: 11900, on: LocalDate(year: 2026, month: 7, day: 5))
        let unclear = try insert(
            database, profile: profile, direction: .income, treatment: .unknown,
            title: "Unklar", invoiceDate: LocalDate(year: 2026, month: 7, day: 2),
            net: 5000, tax: 0
        )
        try pay(database, unclear, amountMinor: 5000, on: LocalDate(year: 2026, month: 7, day: 6))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.isDraft)
        #expect(q3.exceptions.contains { $0.kind == .unknownTreatment && $0.transactionID == unclear.id })
        #expect(q3.line(81)?.amountMinor == 10000)
        #expect(q3.payableMinor == 100 * 19)
    }

    @Test("Ein Vorgang ganz ohne Steuerbeurteilung ist ebenfalls eine Ausnahme")
    func missingAssessmentBecomesAnException() throws {
        let (database, profile) = try database()
        let orphan = try insert(
            database, profile: profile, direction: .income, treatment: nil,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1), net: 1000, tax: 0
        )
        try pay(database, orphan, amountMinor: 1000, on: LocalDate(year: 2026, month: 8, day: 2))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.exceptions.map(\.kind) == [.unknownTreatment])
        #expect(q3.lines.isEmpty)
    }

    @Test("Eine Ausgabe ohne Beleg wird gemeldet, ohne die Werte zu blockieren")
    func expenseWithoutDocument() throws {
        let (database, profile) = try database()
        let bill = try insert(
            database, profile: profile, direction: .expense, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            net: 10000, tax: 1900,
            components: [component("19", net: 10000, tax: 1900)],
            attachDocument: false
        )
        try pay(database, bill, amountMinor: 11900, on: LocalDate(year: 2026, month: 8, day: 2))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.exceptions.contains { $0.kind == .expenseWithoutDocument && $0.transactionID == bill.id })
        #expect(q3.line(66)?.amountMinor == 1900)
        #expect(q3.isDraft)
    }

    @Test("Eine Zahlung ohne Vorgang wird als Ausnahme sichtbar")
    func paymentWithoutTransaction() throws {
        let (database, profile) = try database()
        try database.writer.write { db in
            try Payment(
                direction: .inflow,
                paymentDate: LocalDate(year: 2026, month: 8, day: 9),
                originalAmountMinor: 5000,
                bookedAmountMinor: 5000,
                counterpartyNameRaw: "Unbekannt"
            ).insert(db)
        }

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.exceptions.map(\.kind) == [.paymentWithoutTransaction])
        #expect(q3.payableMinor == 0)
    }

    @Test("Ein leerer Zeitraum liefert Nullwerte ohne Fehler")
    func emptyPeriod() throws {
        let (database, profile) = try database()
        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.lines.isEmpty)
        #expect(q3.exceptions.isEmpty)
        #expect(q3.payableMinor == 0)
        #expect(q3.isDraft == false)
        #expect(q3.period.dueDate() == LocalDate(year: 2026, month: 10, day: 10))
        #expect(q3.taxNumber == "1096081508187")
        #expect(q3.formYear == 2026)
    }

    @Test("Eine Gutschrift mindert den Zeitraum ihres Geldflusses")
    func creditNoteReducesThePeriod() throws {
        let (database, profile) = try database()
        let invoice = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 1),
            net: 100_000, tax: 19000,
            components: [component("19", net: 100_000, tax: 19000)]
        )
        try pay(database, invoice, amountMinor: 119_000, on: LocalDate(year: 2026, month: 7, day: 10))

        let creditNote = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            title: "Gutschrift", invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            net: -20000, tax: -3800,
            components: [component("19", net: -20000, tax: -3800)]
        )
        try pay(database, creditNote, amountMinor: -23800, on: LocalDate(year: 2026, month: 8, day: 3))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(81)?.amountMinor == 80000)
        #expect(q3.line(81)?.contributions.count == 2)
        #expect(q3.payableMinor == 800 * 19)
    }

    @Test("Innergemeinschaftlicher Erwerb füllt Kz 89 und die gleich hohe Kz 61")
    func intraCommunityAcquisition() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .expense, treatment: .intraCommunityAcquisition,
            title: "Hardware aus NL", invoiceDate: LocalDate(year: 2026, month: 9, day: 1),
            net: 50000, tax: 0, counterpartyCountry: "NL", counterpartyName: "Hardware BV",
            selfAssessedVatMinor: 9500
        )

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(89)?.amountMinor == 50000)
        #expect(q3.line(61)?.amountMinor == 9500)
        #expect(q3.payableMinor == 0)
    }

    @Test("Reverse-Charge-Einnahmen und Ausfuhr gehen nach Kz 21 und Kz 43")
    func nonTaxableIncome() throws {
        let (database, profile) = try database()
        let euService = try insert(
            database, profile: profile, direction: .income, treatment: .reverseCharge,
            title: "EU-Beratung", invoiceDate: LocalDate(year: 2026, month: 7, day: 1),
            net: 200_000, tax: 0, counterpartyCountry: "FR", counterpartyName: "Client SARL"
        )
        try pay(database, euService, amountMinor: 200_000, on: LocalDate(year: 2026, month: 7, day: 20))
        let export = try insert(
            database, profile: profile, direction: .income, treatment: .export,
            title: "Drittland", invoiceDate: LocalDate(year: 2026, month: 7, day: 2),
            net: 30000, tax: 0, counterpartyCountry: "US", counterpartyName: "US Client"
        )
        try pay(database, export, amountMinor: 30000, on: LocalDate(year: 2026, month: 9, day: 30))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(21)?.amountMinor == 200_000)
        #expect(q3.line(43)?.amountMinor == 30000)
        #expect(q3.payableMinor == 0)
        #expect(q3.lines.map(\.kennzahl) == [43, 21]) // form order: Zeile 22 before Zeile 35
    }

    @Test("Unbezahlte Ausgangsrechnungen zählen nicht")
    func unpaidInvoicesDoNotCount() throws {
        let (database, profile) = try database()
        try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            net: 100_000, tax: 19000,
            components: [component("19", net: 100_000, tax: 19000)]
        )
        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.lines.isEmpty)
        #expect(q3.payableMinor == 0)
    }

    @Test("Steuerkomponenten, die nicht zur Bruttosumme passen, werden gemeldet")
    func componentMismatch() throws {
        let (database, profile) = try database()
        let invoice = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            net: 10000, tax: 1900,
            components: [component("19", net: 9000, tax: 1710)]
        )
        try pay(database, invoice, amountMinor: 11900, on: LocalDate(year: 2026, month: 8, day: 2))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.exceptions.contains { $0.kind == .componentMismatch })
        // Falls back to the transaction's own totals, which always add up.
        #expect(q3.line(81)?.amountMinor == 10000)
    }

    @Test("Ein Vorgang ohne EUR-Betrag wird nicht stillschweigend gemeldet")
    func missingEURAmount() throws {
        let (database, profile) = try database()
        let transaction = TransactionRecord(
            businessProfileId: profile.id,
            direction: .income,
            title: "USD-Rechnung",
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            bookedCurrency: "USD",
            bookedGrossMinor: 10000
        )
        try database.writer.write { db in
            try transaction.insert(db)
            try TaxAssessment(transactionId: transaction.id, treatment: .domesticVAT, status: .confirmed).insert(db)
        }

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.exceptions.map(\.kind) == [.missingEURAmount])
        #expect(q3.lines.isEmpty)
    }

    @Test("Archivierte und gelöschte Vorgänge bleiben außen vor")
    func archivedAndDeletedAreExcluded() throws {
        let (database, profile) = try database()
        let archived = TransactionRecord(
            businessProfileId: profile.id,
            direction: .income,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            bookedNetMinor: 10000, bookedTaxMinor: 1900, bookedGrossMinor: 11900,
            workflowStatus: .archived
        )
        try database.writer.write { db in
            try archived.insert(db)
            try TaxAssessment(transactionId: archived.id, treatment: .domesticVAT, status: .confirmed).insert(db)
        }
        try pay(database, archived, amountMinor: 11900, on: LocalDate(year: 2026, month: 8, day: 2))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.lines.isEmpty)
        #expect(q3.exceptions.isEmpty)
    }

    // MARK: - Erstattungen und Gutschriften

    @Test("Eine im Folgequartal erstattete Ausgabe hebt ihre Vorsteuer wieder auf")
    func refundedExpenseReversesInputVAT() throws {
        let (database, profile) = try database()
        let expense = try insert(
            database, profile: profile, direction: .expense, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 10),
            net: 10000, tax: 1900,
            components: [component("19", net: 10000, tax: 1900)],
            counterpartyCountry: "DE"
        )
        try pay(database, expense, amountMinor: 11900, on: LocalDate(year: 2026, month: 7, day: 20))
        // The money comes back: an inflow on an expense.
        try pay(
            database, expense, amountMinor: 11900,
            on: LocalDate(year: 2026, month: 10, day: 20), direction: .inflow
        )

        let q3 = try prepare(database, profile, quarter: 3)
        let q4 = try prepare(database, profile, quarter: 4)
        #expect(q3.line(66)?.amountMinor == 1900)
        #expect(q4.line(66)?.amountMinor == -1900)
        #expect((q3.line(66)?.amountMinor ?? 0) + (q4.line(66)?.amountMinor ?? 0) == 0)
        #expect(q3.payableMinor == -1900)
        #expect(q4.payableMinor == 1900)
    }

    @Test("Eine erstattete Einnahme hebt ihre Umsatzsteuer wieder auf")
    func refundedIncomeReversesOutputVAT() throws {
        let (database, profile) = try database()
        let invoice = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 7, day: 1),
            net: 100_000, tax: 19000,
            components: [component("19", net: 100_000, tax: 19000)]
        )
        try pay(database, invoice, amountMinor: 119_000, on: LocalDate(year: 2026, month: 8, day: 15))
        // Money returned to the customer: an outflow on an income.
        try pay(
            database, invoice, amountMinor: 119_000,
            on: LocalDate(year: 2026, month: 10, day: 15), direction: .outflow
        )

        let q3 = try prepare(database, profile, quarter: 3)
        let q4 = try prepare(database, profile, quarter: 4)
        #expect(q3.line(81)?.amountMinor == 100_000)
        #expect(q4.line(81)?.amountMinor == -100_000)
        #expect(q3.payableMinor == 1000 * 19)
        #expect(q4.payableMinor == -1000 * 19)
    }

    @Test("Eine bezahlte Gutschrift mindert die Vorsteuer im Quartal des Geldflusses")
    func creditNoteReducesInputVAT() throws {
        let (database, profile) = try database()
        let creditNote = try insert(
            database, profile: profile, direction: .expense, treatment: .domesticVAT,
            title: "Gutschrift Hosting",
            invoiceDate: LocalDate(year: 2026, month: 9, day: 5),
            net: -4000, tax: -760,
            components: [component("19", net: -4000, tax: -760)],
            counterpartyCountry: "DE"
        )
        // A supplier credit note is settled by money coming in.
        try pay(
            database, creditNote, amountMinor: 4760,
            on: LocalDate(year: 2026, month: 10, day: 2), direction: .inflow
        )

        let q3 = try prepare(database, profile, quarter: 3)
        let q4 = try prepare(database, profile, quarter: 4)
        #expect(q3.line(66) == nil)
        #expect(q4.line(66)?.amountMinor == -760)
        #expect(q4.line(66)?.contributions.first?.transactionID == creditNote.id)
        #expect(q4.payableMinor == 760)
    }

    @Test("Ohne gespeicherte Komponenten wird der Steuersatz aus den Beträgen erkannt")
    func rateIsRecoveredFromTotals() throws {
        let (database, profile) = try database()
        let reduced = try insert(
            database, profile: profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            net: 10000, tax: 700
        )
        try pay(database, reduced, amountMinor: 10700, on: LocalDate(year: 2026, month: 8, day: 2))

        let q3 = try prepare(database, profile, quarter: 3)
        #expect(q3.line(86)?.amountMinor == 10000)
        #expect(q3.line(81) == nil)
    }
}
