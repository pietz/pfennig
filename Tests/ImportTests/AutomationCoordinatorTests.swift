import AI
import Database
import Domain
import Foundation
import GRDB
import ImportPipeline
import Testing

/// What the automation level does to a real import: the same recorded model
/// responses the fixture replay uses, run once per level.
@Suite("Automatischer Import")
struct AutomationCoordinatorTests {
    private func recordedFixtures() throws -> [Support.Fixture] {
        let recorded = Support.fixtures().filter(\.hasRecording)
        try #require(!recorded.isEmpty, "Keine response.json aufgezeichnet - Live-Test einmal laufen lassen.")
        return recorded
    }

    private func run(_ fixture: Support.Fixture, at level: AutomationLevel) async throws -> Support.Workspace {
        let workspace = try Support.workspace()
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            RecordingProvider(responseURL: fixture.responseURL)
        }
        await coordinator.import([fixture.documentURL], automationLevel: level)
        return workspace
    }

    private func transactions(
        _ workspace: Support.Workspace,
        needsAttention: Bool = false
    ) throws -> [TransactionListItem] {
        try workspace.database.reader.read { db in
            try TransactionListQuery.fetch(db, listFilter: TransactionListFilter(needsAttention: needsAttention))
        }
    }

    @Test("Manuell legt einen Vorschlag an und bucht nichts")
    func manual() async throws {
        for fixture in try recordedFixtures() {
            let workspace = try await run(fixture, at: .manual)
            defer { workspace.cleanUp() }

            let proposals = try ImportRepository(workspace.database).pendingProposals()
            #expect(proposals.count == 1, "\(fixture.name)")
            #expect(proposals.first?.policyDecision == .needsReview, "\(fixture.name)")
            #expect(try transactions(workspace).isEmpty, "\(fixture.name): Manuell bucht nichts ohne Bestätigung")
        }
    }

    /// Fixture 01/03 are clean standard cases, fixture 06 carries a warning;
    /// the two branches of "Ausgewogen" are therefore both covered here.
    @Test("Ausgewogen übernimmt nur den warnungsfreien Standardfall")
    func balanced() async throws {
        var committed = 0
        var kept = 0
        for fixture in try recordedFixtures() {
            let reference = try await run(fixture, at: .manual)
            defer { reference.cleanUp() }
            let issues = try #require(try ImportRepository(reference.database).pendingProposals().first).issues
            let hasWarnings = issues.contains { !$0.isHard }

            let workspace = try await run(fixture, at: .balanced)
            defer { workspace.cleanUp() }
            let pending = try ImportRepository(workspace.database).pendingProposals()
            if hasWarnings {
                kept += 1
                #expect(pending.count == 1, "\(fixture.name): eine Warnung hält den Vorschlag in Prüfen")
                #expect(pending.first?.policyDecision == .needsReview, "\(fixture.name)")
                #expect(try transactions(workspace).isEmpty, "\(fixture.name)")
            } else {
                committed += 1
                #expect(pending.isEmpty, "\(fixture.name): der geprüfte Standardfall braucht keine Bestätigung")
                let booked = try transactions(workspace)
                #expect(booked.count == 1, "\(fixture.name)")
                #expect(booked.first?.reviewStatus == .confirmed, "\(fixture.name)")
                #expect(try transactions(workspace, needsAttention: true).isEmpty, "\(fixture.name)")
            }
        }
        #expect(committed > 0 && kept > 0, "Die Fixtures müssen beide Zweige abdecken")
    }

    @Test("Automatisch bucht jeden Fall ohne harten Fehler")
    func automatic() async throws {
        var withWarning = 0
        for fixture in try recordedFixtures() {
            let workspace = try await run(fixture, at: .automatic)
            defer { workspace.cleanUp() }

            let booked = try transactions(workspace)
            #expect(booked.count == 1, "\(fixture.name): automatisch bucht ohne Bestätigungsschritt")
            let transaction = try #require(booked.first)
            #expect(try ImportRepository(workspace.database).pendingProposals().isEmpty, "\(fixture.name)")

            // The proposal row keeps the pair that records an unconfirmed
            // commit: `policy_decision = autoCommit` next to `status = committed`.
            let proposals = try await workspace.database.reader.read { db in
                try ProposalRecord.fetchAll(db, sql: "SELECT * FROM proposals")
            }
            #expect(proposals.count == 1, "\(fixture.name)")
            #expect(proposals.first?.status == .committed, "\(fixture.name)")
            #expect(proposals.first?.policyDecision == .autoCommit, "\(fixture.name)")

            let items = try await workspace.database.reader.read { db in
                try ImportItem.fetchAll(db, sql: "SELECT * FROM import_items")
            }
            #expect(items.map(\.status) == [.committed], "\(fixture.name)")

            // The archived document is linked exactly as after a manual
            // confirmation, and a warning keeps the booking in "Prüfen".
            let detail = try #require(try BookkeepingRepository(workspace.database).detail(id: transaction.id))
            #expect(detail.documents.count == 1, "\(fixture.name)")
            if detail.openIssues.isEmpty {
                #expect(detail.transaction.reviewStatus == .confirmed, "\(fixture.name)")
                #expect(try transactions(workspace, needsAttention: true).isEmpty, "\(fixture.name)")
            } else {
                withWarning += 1
                #expect(detail.transaction.reviewStatus == .needsReview, "\(fixture.name)")
                #expect(try transactions(workspace, needsAttention: true).count == 1, "\(fixture.name)")
            }
        }
        #expect(withWarning > 0, "Ein Fixture mit Warnung muss den Prüfen-Fall abdecken")
    }

    @Test("Ein zweiter Lauf derselben Datei bucht nicht doppelt")
    func duplicateStaysSingle() async throws {
        let fixture = try #require(try recordedFixtures().first)
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            RecordingProvider(responseURL: fixture.responseURL)
        }
        await coordinator.import([fixture.documentURL], automationLevel: .automatic)
        await coordinator.import([fixture.documentURL], automationLevel: .automatic)

        #expect(try transactions(workspace).count == 1)
    }
}

/// Step 5 of the specification: an automatic commit must not make a warning
/// disappear. The booking is written, its validation issue stays open, and
/// "Prüfen" - "Buchungen prüfen" finds it through the same predicate the
/// ledger filter uses.
@Suite("Automatisch übernommene Warnungen bleiben sichtbar")
struct AutomaticCommitVisibilityTests {
    @Test("Eine Warnung hält die automatisch gebuchte Buchung in Buchungen prüfen")
    func softIssueStaysVisible() throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let database = workspace.database
        let categories = try database.categories()
        let category = try #require(categories.first { $0.kind == .expense })

        // No invoice number above the Kleinbetrag limit is a soft issue
        // (spec 14.2) and nothing else.
        let draft = TransactionDraft(
            businessProfileId: workspace.profile.id,
            counterpartyName: "Beispiel GmbH",
            counterpartyCountryCode: "DE",
            direction: .expense,
            transactionType: .invoice,
            title: "Wartung",
            invoiceDate: LocalDate(year: 2026, month: 3, day: 4),
            servicePeriodStart: LocalDate(year: 2026, month: 3, day: 1),
            servicePeriodEnd: LocalDate(year: 2026, month: 3, day: 31),
            netMinor: 100_000,
            taxMinor: 19000,
            grossMinor: 119_000,
            components: [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 100_000, taxMinor: 19000)],
            allocations: [AllocationDraft(categoryId: category.id, amountMinor: 100_000)]
        )
        let derived = BookkeepingEngine.derive(draft, profile: workspace.profile, categories: categories)
        try #require(derived.hardIssues.isEmpty)
        try #require(!derived.softIssues.isEmpty, "Der Fall muss eine Warnung erzeugen")

        let decision = AutomationPolicy.decide(
            level: .automatic,
            hardIssues: derived.hardIssues,
            softIssues: derived.softIssues
        )
        #expect(decision == .autoCommit)

        let repository = ImportRepository(database)
        let batch = try repository.createBatch(fileCount: 1)
        let item = try repository.createItem(batchID: batch.id, filename: "wartung.pdf")
        let proposalID = try repository.upsertProposal(
            importItemID: item.id,
            idempotencyKey: "\(item.id):test",
            kind: .createTransaction,
            operations: [.createTransaction(derived.draft)],
            summary: ProposalSummary(
                counterpartyName: "Beispiel GmbH",
                direction: .expense,
                amountMinor: 119_000,
                currency: "EUR"
            ),
            issues: derived.issues,
            policyDecision: decision
        )
        let transactionID = try CommitService(database).accept(
            proposalID: proposalID,
            reviewStatus: AutomationPolicy.reviewStatus(forAutoCommitWith: derived.softIssues)
        )

        // The warning is persisted and open on the booking.
        let detail = try #require(try BookkeepingRepository(database).detail(id: transactionID))
        #expect(!detail.openIssues.isEmpty)
        #expect(detail.openIssues.allSatisfy { $0.severity != .error })

        // And the exception list of "Prüfen" contains it.
        let open = try database.reader.read { db in
            try TransactionListQuery.fetch(db, listFilter: TransactionListFilter(needsAttention: true))
        }
        #expect(open.map(\.id) == [transactionID])
    }

    @Test("Ohne Warnung ist die automatische Buchung bestätigt und nicht in Prüfen")
    func cleanCaseIsConfirmed() throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let database = workspace.database
        let categories = try database.categories()
        let category = try #require(categories.first { $0.kind == .expense })

        let draft = TransactionDraft(
            businessProfileId: workspace.profile.id,
            counterpartyName: "Beispiel GmbH",
            counterpartyCountryCode: "DE",
            direction: .expense,
            transactionType: .invoice,
            title: "Wartung",
            invoiceNumber: "R-2026-0042",
            invoiceDate: LocalDate(year: 2026, month: 3, day: 4),
            servicePeriodStart: LocalDate(year: 2026, month: 3, day: 1),
            servicePeriodEnd: LocalDate(year: 2026, month: 3, day: 31),
            netMinor: 100_000,
            taxMinor: 19000,
            grossMinor: 119_000,
            components: [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 100_000, taxMinor: 19000)],
            allocations: [AllocationDraft(categoryId: category.id, amountMinor: 100_000)]
        )
        let derived = BookkeepingEngine.derive(draft, profile: workspace.profile, categories: categories)
        try #require(derived.issues.isEmpty, "Erwartet einen Fall ohne Befund: \(derived.issues.map(\.code))")

        let repository = ImportRepository(database)
        let batch = try repository.createBatch(fileCount: 1)
        let item = try repository.createItem(batchID: batch.id, filename: "wartung.pdf")
        let proposalID = try repository.upsertProposal(
            importItemID: item.id,
            idempotencyKey: "\(item.id):test",
            kind: .createTransaction,
            operations: [.createTransaction(derived.draft)],
            summary: ProposalSummary(
                counterpartyName: "Beispiel GmbH",
                direction: .expense,
                amountMinor: 119_000,
                currency: "EUR"
            ),
            issues: derived.issues,
            policyDecision: .autoCommit
        )
        let transactionID = try CommitService(database).accept(
            proposalID: proposalID,
            reviewStatus: AutomationPolicy.reviewStatus(forAutoCommitWith: derived.softIssues)
        )

        let detail = try #require(try BookkeepingRepository(database).detail(id: transactionID))
        #expect(detail.transaction.reviewStatus == .confirmed)
        let open = try database.reader.read { db in
            try TransactionListQuery.fetch(db, listFilter: TransactionListFilter(needsAttention: true))
        }
        #expect(open.isEmpty)
    }
}
