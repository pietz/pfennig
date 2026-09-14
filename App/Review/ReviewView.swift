import Database
import Domain
import GRDB
import SwiftUI

/// "Prüfen" is the single page for everything that still needs a decision
/// (spec 7.2, 27): import proposals, failed imports, bookings whose review is
/// open, and bookings without the document they expect. Every row leads to the
/// place where the decision is made; the page is empty when nothing is open.
struct ReviewView: View {
    let database: AppDatabase
    let onOpenLedger: (TransactionListFilter) -> Void

    @Environment(AppModel.self) private var model
    @State private var queue = ReviewQueue()

    init(database: AppDatabase, onOpenLedger: @escaping (TransactionListFilter) -> Void = { _ in }) {
        self.database = database
        self.onOpenLedger = onOpenLedger
    }

    var body: some View {
        Group {
            if queue.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Prüfen")
        .navigationSubtitle(Text(subtitle))
        .task { await observe() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nichts zu prüfen", systemImage: "checkmark.circle")
        } description: {
            VStack(spacing: 8) {
                if let lastImport = queue.lastImportAt {
                    Text("Letzter Import: \(Format.timestamp(lastImport))")
                }
                if !model.hasAPIKey {
                    Label(
                        "Für die Belegerkennung fehlt der OpenAI-Schlüssel. Er wird in den Einstellungen hinterlegt.",
                        systemImage: "key"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var list: some View {
        List {
            if !model.hasAPIKey {
                Section {
                    Label(
                        "Für die Belegerkennung fehlt der OpenAI-Schlüssel. Er wird in den Einstellungen hinterlegt.",
                        systemImage: "key"
                    )
                    .foregroundStyle(.orange)
                }
            }
            if !queue.proposals.isEmpty {
                Section("Importvorschläge") {
                    ForEach(queue.proposals) { proposal in
                        row(proposal)
                    }
                }
            }
            if !queue.failed.isEmpty {
                Section("Fehlgeschlagen") {
                    ForEach(queue.failed) { item in
                        failedRow(item)
                    }
                }
            }
            if !queue.toReview.isEmpty {
                Section {
                    ForEach(queue.toReview) { item in
                        transactionRow(item, reason: reason(item.reviewStatus))
                    }
                } header: {
                    sectionHeader("Buchungen prüfen", filter: TransactionListFilter(needsAttention: true))
                }
            }
            if !queue.missingDocuments.isEmpty {
                Section {
                    ForEach(queue.missingDocuments) { item in
                        transactionRow(item, reason: "Beleg fehlt")
                    }
                } header: {
                    sectionHeader("Belege fehlen", filter: TransactionListFilter(missingDocumentsOnly: true))
                }
            }
        }
    }

    /// The ledger keeps the same list behind a filter, for sorting, search and
    /// bulk work; the section header is the way there.
    private func sectionHeader(_ title: String, filter: TransactionListFilter) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Button("In Buchungen öffnen") { onOpenLedger(filter) }
                .buttonStyle(.link)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !queue.proposals.isEmpty {
            parts.append("\(queue.proposals.count) Vorschläge")
        }
        if !queue.failed.isEmpty {
            parts.append("\(queue.failed.count) Fehler")
        }
        if !queue.toReview.isEmpty {
            parts.append("\(queue.toReview.count) prüfen")
        }
        if !queue.missingDocuments.isEmpty {
            parts.append("\(queue.missingDocuments.count) ohne Beleg")
        }
        return parts.joined(separator: " · ")
    }

    private func reason(_ status: ReviewStatus) -> String {
        switch status {
        case .unreviewed: "Ungeprüft"
        case .needsReview: "Prüfen"
        case .conflict: "Konflikt"
        case .confirmed: "Bestätigt"
        }
    }

    private func row(_ proposal: ProposalRecord) -> some View {
        let summary = proposal.summary
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary?.counterpartyName ?? "Unbekannte Firma").font(.headline)
                Text(line(summary)).foregroundStyle(.secondary)
                ForEach(proposal.issues.indices, id: \.self) { index in
                    IssueRow(severity: proposal.issues[index].severity, message: proposal.issues[index].message)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Button("Bestätigen") { model.acceptProposal(proposal.id, draft: nil) }
                    .buttonStyle(.borderedProminent)
                    .disabled(proposal.policyDecision == .blocked)
                Button("Ablehnen", role: .destructive) { model.rejectProposal(proposal.id) }
            }
        }
        .padding(.vertical, 4)
    }

    /// The summary line of spec 27: amount, category, tax treatment.
    private func line(_ summary: ProposalSummary?) -> String {
        guard let summary else { return "–" }
        return [
            summary.amount?.formatted(locale: Format.german),
            summary.categoryName,
            summary.treatment.text,
            summary.invoiceNumber,
            summary.invoiceDate.map(Format.date)
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    private func failedRow(_ item: ImportItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.originalFilename).font(.headline)
                Text(item.errorMessage ?? item.errorCode ?? "Unbekannter Fehler")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Erneut versuchen") { model.retryImport(itemID: item.id) }
                .disabled(item.documentId == nil)
        }
        .padding(.vertical, 4)
    }

    /// One booking that waits for a decision. Clicking it opens the booking in
    /// "Buchungen" with the inspector, where the decision is actually made.
    private func transactionRow(_ item: TransactionListItem, reason: String) -> some View {
        Button {
            model.showTransaction(item.id)
        } label: {
            HStack(spacing: 12) {
                Text(Format.date(item.relevantDate))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                    if let title = item.title, title != item.displayName {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(item.bookedAmount?.formatted(locale: Format.german) ?? "–")
                    .monospacedDigit()
                    .frame(minWidth: 90, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func observe() async {
        do {
            let observation = ValueObservation.tracking { db in
                try ReviewQueue(
                    proposals: ImportRepository.pendingProposals(db),
                    failed: ImportRepository.failedItems(db),
                    toReview: TransactionListQuery.fetch(
                        db,
                        listFilter: TransactionListFilter(needsAttention: true)
                    ),
                    missingDocuments: TransactionListQuery.fetch(
                        db,
                        listFilter: TransactionListFilter(missingDocumentsOnly: true)
                    ),
                    lastImportAt: ImportRepository.lastImportAt(db)
                )
            }
            for try await value in observation.values(in: database.reader) {
                queue = value
            }
        } catch {
            queue = ReviewQueue()
        }
    }
}

/// Everything "Prüfen" shows, read in one observation so the page never shows
/// two states of the archive at once.
private struct ReviewQueue {
    var proposals: [ProposalRecord] = []
    var failed: [ImportItem] = []
    var toReview: [TransactionListItem] = []
    var missingDocuments: [TransactionListItem] = []
    var lastImportAt: String?

    var isEmpty: Bool {
        proposals.isEmpty && failed.isEmpty && toReview.isEmpty && missingDocuments.isEmpty
    }
}
