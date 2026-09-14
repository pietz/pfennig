import Analysis
@testable import Database
import Domain
import Foundation
import GRDB
import Tax
import Testing

@Suite("UStVA-Aufgaben")
struct UStVATaskTests {
    // MARK: - Fixtures

    private func database(
        smallBusiness: Bool = false,
        period: UStVAPeriodicity = .quarterly
    ) throws -> (AppDatabase, BusinessProfile) {
        let database = try AppDatabase(inMemoryNamed: "ustva-tasks-\(UUID().uuidString)")
        let profile = BusinessProfile(
            name: "Testbetrieb",
            taxNumber: "1096081508187",
            vatStatus: smallBusiness ? .smallBusiness : .taxable,
            ustvaPeriod: period
        )
        try database.writer.write { try profile.insert($0) }
        return (database, profile)
    }

    /// A paid 19 % income invoice, the ordinary case behind Kz 81.
    @discardableResult
    private func income(
        _ database: AppDatabase,
        _ profile: BusinessProfile,
        net: Int64,
        on date: LocalDate
    ) throws -> TransactionRecord {
        try insert(
            database, profile, direction: .income, treatment: .domesticVAT,
            invoiceDate: date, net: net, tax: net * 19 / 100, paidOn: date
        )
    }

    /// A §13b expense: it creates a filing duty even without regular Voranmeldungen.
    @discardableResult
    private func reverseCharge(
        _ database: AppDatabase,
        _ profile: BusinessProfile,
        net: Int64,
        on date: LocalDate
    ) throws -> TransactionRecord {
        try insert(
            database, profile, direction: .expense, treatment: .reverseCharge,
            invoiceDate: date, net: net, tax: 0, paidOn: nil,
            counterpartyCountry: "IE", selfAssessedVatMinor: net * 19 / 100
        )
    }

    @discardableResult
    private func insert(
        _ database: AppDatabase,
        _ profile: BusinessProfile,
        direction: Direction,
        treatment: TaxTreatment?,
        invoiceDate: LocalDate?,
        net: Int64,
        tax: Int64,
        paidOn: LocalDate?,
        counterpartyCountry: String? = nil,
        selfAssessedVatMinor: Int64? = nil,
        attachDocument: Bool = true
    ) throws -> TransactionRecord {
        var counterpartyID: String?
        if let counterpartyCountry {
            let counterparty = Counterparty(
                displayName: "Cloud Ltd \(UUID().uuidString.prefix(6))",
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
            title: "Testvorgang",
            invoiceDate: invoiceDate,
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
            try TaxComponent(
                transactionId: transaction.id,
                kind: .standard,
                rate: tax == 0 ? "0" : "19",
                netMinor: net,
                taxMinor: tax,
                sortOrder: 0
            ).insert(db)
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
            if let paidOn {
                let payment = Payment(
                    direction: direction == .income ? .inflow : .outflow,
                    paymentDate: paidOn,
                    originalAmountMinor: net + tax,
                    bookedAmountMinor: net + tax
                )
                try payment.insert(db)
                try PaymentAllocation(
                    paymentId: payment.id,
                    transactionId: transaction.id,
                    allocatedMinor: net + tax,
                    matchMethod: .exact
                ).insert(db)
            }
        }
        return transaction
    }

    private func summaries(
        _ database: AppDatabase,
        _ profile: BusinessProfile,
        today: LocalDate
    ) throws -> [UStVATasks.Summary] {
        try database.reader.read { db in
            try UStVATasks.summaries(db, profile: profile, today: today)
        }
    }

    // MARK: - Periods

    @Test("Quartalsweise Zeiträume reichen bis zum Januar des Vorjahres zurück")
    func quarterlyCandidates() throws {
        let (_, profile) = try database()
        let periods = UStVATasks.candidatePeriods(profile: profile, today: LocalDate(year: 2026, month: 9, day: 14))

        #expect(periods.count == 7)
        #expect(periods.first == UStVAPeriod(year: 2025, quarter: 1))
        #expect(periods.last == UStVAPeriod(year: 2026, quarter: 3))
    }

    @Test("Monatliche Zeiträume folgen der Einstellung")
    func monthlyCandidates() throws {
        let (_, profile) = try database(period: .monthly)
        let periods = UStVATasks.candidatePeriods(profile: profile, today: LocalDate(year: 2026, month: 3, day: 2))

        #expect(UStVATasks.periodKind(for: profile) == .monthly)
        #expect(periods.count == 15)
        #expect(periods.first == UStVAPeriod(year: 2025, month: 1))
        #expect(periods.last == UStVAPeriod(year: 2026, month: 3))
    }

    @Test("Ohne regelmäßige Voranmeldungen werden nur zwei Zeiträume geprüft")
    func smallBusinessCandidatesStayCheap() throws {
        let (_, smallProfile) = try database(smallBusiness: true)
        let (_, yearlyProfile) = try database(period: .yearly)

        #expect(UStVATasks.mode(for: smallProfile) == .selfAssessedOnly)
        #expect(UStVATasks.mode(for: yearlyProfile) == .selfAssessedOnly)
        let periods = UStVATasks.candidatePeriods(
            profile: smallProfile,
            today: LocalDate(year: 2026, month: 1, day: 20)
        )
        #expect(periods == [UStVAPeriod(year: 2025, quarter: 4), UStVAPeriod(year: 2026, quarter: 1)])
    }

    // MARK: - Summaries

    @Test("Die Übersicht nennt Frist, Zahllast und offene Fälle des laufenden Zeitraums")
    func currentPeriodSummary() throws {
        let (database, profile) = try database()
        try income(database, profile, net: 100_000, on: LocalDate(year: 2026, month: 8, day: 1))
        // An expense without a document is an open case of the same period.
        try insert(
            database, profile, direction: .expense, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 2),
            net: 10000, tax: 1900, paidOn: LocalDate(year: 2026, month: 8, day: 2),
            attachDocument: false
        )

        let rows = try summaries(database, profile, today: LocalDate(year: 2026, month: 9, day: 14))
        let current = try #require(rows.first)

        #expect(current.period == UStVAPeriod(year: 2026, quarter: 3))
        #expect(current.isCurrent)
        #expect(current.dueDate == LocalDate(year: 2026, month: 10, day: 10))
        #expect(current.payableMinor == 1000 * 19 - 1900)
        #expect(current.exceptionCount == 1)
        #expect(current.isDraft)
        #expect(!current.isSubmitted)
        // Newest first, and the older quarters are still listed.
        #expect(rows.count == 7)
        #expect(rows.last?.period == UStVAPeriod(year: 2025, quarter: 1))
    }

    @Test("Dauerfristverlängerung aus den Einstellungen verschiebt die Frist um einen Monat")
    func dauerfristverlaengerungShiftsTheDueDate() throws {
        let (database, profile) = try database()
        let today = LocalDate(year: 2026, month: 9, day: 14)
        #expect(try summaries(database, profile, today: today).first?.dueDate
            == LocalDate(year: 2026, month: 10, day: 10))

        try database.setSetting(true, forKey: UStVATasks.dauerfristverlaengerungKey)

        #expect(try summaries(database, profile, today: today).first?.dueDate
            == LocalDate(year: 2026, month: 11, day: 10))
    }

    @Test("Der Zeitraum mit der nächsten Frist ist der laufende, auch nach Quartalsende")
    func nextDueDateWins() throws {
        let (database, profile) = try database(period: .monthly)
        let rows = try summaries(database, profile, today: LocalDate(year: 2026, month: 10, day: 5))

        // October is the current month, but September is due on 10 October.
        #expect(rows.first?.period == UStVAPeriod(year: 2026, month: 10))
        #expect(rows.first?.isCurrent == false)
        #expect(rows.first(where: \.isCurrent)?.period == UStVAPeriod(year: 2026, month: 9))
    }

    // MARK: - Start rows

    @Test("Übermittelte Zeiträume verschwinden, geänderte kommen zurück")
    func submittedPeriodsLeaveAndReturn() throws {
        let (database, profile) = try database()
        let today = LocalDate(year: 2026, month: 9, day: 14)
        try income(database, profile, net: 100_000, on: LocalDate(year: 2026, month: 5, day: 4))

        let q2 = try UStVACalculator.prepare(
            period: UStVAPeriod(year: 2026, quarter: 2),
            profile: profile,
            database: database
        )
        // Q3 as the current period, Q2 because the archive starts there.
        #expect(try UStVATasks.startRows(summaries(database, profile, today: today), mode: .regular).count == 2)

        try SubmittedReturnRepository.markSubmitted(database, profileID: profile.id, result: q2)
        let afterSubmission = try UStVATasks.startRows(summaries(database, profile, today: today), mode: .regular)
        #expect(afterSubmission.count == 1)
        #expect(!afterSubmission.contains { $0.period == UStVAPeriod(year: 2026, quarter: 2) })

        // A later booking inside the filed quarter brings it back with a note.
        try income(database, profile, net: 50000, on: LocalDate(year: 2026, month: 6, day: 4))
        let afterChange = try UStVATasks.startRows(summaries(database, profile, today: today), mode: .regular)
        let q2Row = try #require(afterChange.first { $0.period == UStVAPeriod(year: 2026, quarter: 2) })
        #expect(q2Row.changedSinceSubmission)
        #expect(q2Row.isSubmitted)
    }

    @Test("Der laufende Zeitraum bleibt sichtbar, auch wenn er übermittelt ist")
    func currentPeriodStaysVisible() throws {
        let (database, profile) = try database()
        let today = LocalDate(year: 2026, month: 9, day: 14)
        let q3 = try UStVACalculator.prepare(
            period: UStVAPeriod(year: 2026, quarter: 3),
            profile: profile,
            database: database
        )
        try SubmittedReturnRepository.markSubmitted(database, profileID: profile.id, result: q3)

        let rows = try UStVATasks.startRows(summaries(database, profile, today: today), mode: .regular)
        let current = try #require(rows.first)
        #expect(current.period == UStVAPeriod(year: 2026, quarter: 3))
        #expect(current.isSubmitted)
        #expect(!current.changedSinceSubmission)
    }

    @Test("Leere Zeiträume vor der ersten Buchung bleiben von Start fern")
    func emptyPeriodsBeforeTheFirstBookingStayOffStart() throws {
        let (database, profile) = try database()
        let today = LocalDate(year: 2026, month: 9, day: 14)
        try income(database, profile, net: 100_000, on: LocalDate(year: 2026, month: 8, day: 1))

        // Seven quarters are prepared, ...
        #expect(try summaries(database, profile, today: today).count == 7)
        // ... but the archive starts in Q3 2026, so nothing lies before it.
        let rows = try UStVATasks.startRows(summaries(database, profile, today: today), mode: .regular)
        #expect(rows.map(\.period) == [UStVAPeriod(year: 2026, quarter: 3)])
    }

    @Test("Leere Zeiträume nach der ersten Buchung bleiben als Nullmeldung stehen")
    func emptyPeriodsAfterTheFirstBookingStayVisible() throws {
        let (database, profile) = try database()
        let today = LocalDate(year: 2026, month: 9, day: 14)
        // The archive starts in Q1 2025; 2024 and earlier are not Pfennig's.
        try income(database, profile, net: 50000, on: LocalDate(year: 2025, month: 2, day: 3))
        try income(database, profile, net: 100_000, on: LocalDate(year: 2026, month: 8, day: 1))

        let rows = try UStVATasks.startRows(summaries(database, profile, today: today), mode: .regular)

        // Every quarter from the first booking on is listed, the empty ones
        // included: a regular filer owes a Nullmeldung for them.
        #expect(rows.map(\.period) == [
            UStVAPeriod(year: 2026, quarter: 3),
            UStVAPeriod(year: 2026, quarter: 2),
            UStVAPeriod(year: 2026, quarter: 1),
            UStVAPeriod(year: 2025, quarter: 4),
            UStVAPeriod(year: 2025, quarter: 3),
            UStVAPeriod(year: 2025, quarter: 2),
            UStVAPeriod(year: 2025, quarter: 1)
        ])
        let q3_2025 = try #require(rows.first { $0.period == UStVAPeriod(year: 2025, quarter: 3) })
        #expect(!q3_2025.hasValues)
        #expect(q3_2025.payableMinor == 0)
        #expect(!q3_2025.precedesArchive)
    }

    @Test("Ohne regelmäßige Voranmeldungen erscheint nur ein Zeitraum mit §13b")
    func smallBusinessOnlyShowsSelfAssessedPeriods() throws {
        let (database, profile) = try database(smallBusiness: true)
        let today = LocalDate(year: 2026, month: 9, day: 14)
        // §19 income alone creates no task.
        try insert(
            database, profile, direction: .income, treatment: .smallBusiness,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 1),
            net: 100_000, tax: 0, paidOn: LocalDate(year: 2026, month: 8, day: 1)
        )
        #expect(try UStVATasks.startRows(
            summaries(database, profile, today: today),
            mode: .selfAssessedOnly
        ).isEmpty)

        try reverseCharge(database, profile, net: 100_000, on: LocalDate(year: 2026, month: 8, day: 5))
        let rows = try UStVATasks.startRows(summaries(database, profile, today: today), mode: .selfAssessedOnly)
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.period == UStVAPeriod(year: 2026, quarter: 3))
        #expect(row.hasSelfAssessedLines)
        // Kleinunternehmer owe the §13b tax without the matching Vorsteuer.
        #expect(row.payableMinor == 19000)
    }

    // MARK: - Task window

    @Test("Das Aufgabenfenster kennt zu jeder Ausnahme den Vorgang")
    func detailResolvesExceptionSubjects() throws {
        let (database, profile) = try database()
        let expense = try insert(
            database, profile, direction: .expense, treatment: .domesticVAT,
            invoiceDate: LocalDate(year: 2026, month: 8, day: 2),
            net: 10000, tax: 1900, paidOn: LocalDate(year: 2026, month: 8, day: 2),
            attachDocument: false
        )

        let detail = try database.reader.read { db in
            try UStVATasks.detail(db, period: UStVAPeriod(year: 2026, quarter: 3), profile: profile)
        }

        #expect(detail.result.isDraft)
        #expect(detail.submittedAt == nil)
        #expect(!detail.changedSinceSubmission)
        let subject = try #require(detail.subjects[expense.id])
        #expect(subject.displayName == "Testvorgang")
        #expect(subject.amount == Money(minorUnits: -11900, currency: .eur))
    }

    @Test("Das Aufgabenfenster meldet eine Übermittlung und ihre spätere Änderung")
    func detailTracksSubmission() throws {
        let (database, profile) = try database()
        let period = UStVAPeriod(year: 2026, quarter: 3)
        try income(database, profile, net: 100_000, on: LocalDate(year: 2026, month: 8, day: 1))
        let result = try UStVACalculator.prepare(period: period, profile: profile, database: database)
        try SubmittedReturnRepository.markSubmitted(database, profileID: profile.id, result: result)

        var detail = try database.reader.read {
            try UStVATasks.detail($0, period: period, profile: profile)
        }
        #expect(detail.isSubmitted)
        #expect(!detail.changedSinceSubmission)

        try income(database, profile, net: 20000, on: LocalDate(year: 2026, month: 9, day: 1))
        detail = try database.reader.read {
            try UStVATasks.detail($0, period: period, profile: profile)
        }
        #expect(detail.changedSinceSubmission)
    }
}
