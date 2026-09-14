import Database
import Domain
import GRDB
import SwiftUI

/// The review queue (spec 7.2, 27): every pending proposal with its summary
/// line, plus the imports that failed with their German error and a retry.
struct ReviewView: View {
    let database: AppDatabase

    @Environment(AppModel.self) private var model
    @State private var proposals: [ProposalRecord] = []
    @State private var failed: [ImportItem] = []

    var body: some View {
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
            if proposals.isEmpty, failed.isEmpty {
                Section {
                    Label("Nichts zu prüfen", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
            }
            if !proposals.isEmpty {
                Section("Vorschläge") {
                    ForEach(proposals) { proposal in
                        row(proposal)
                    }
                }
            }
            if !failed.isEmpty {
                Section("Fehlgeschlagen") {
                    ForEach(failed) { item in
                        failedRow(item)
                    }
                }
            }
        }
        .navigationTitle("Prüfen")
        .navigationSubtitle(Text(subtitle))
        .task { await observe() }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !proposals.isEmpty {
            parts.append("\(proposals.count) prüfen")
        }
        if !failed.isEmpty {
            parts.append("\(failed.count) Fehler")
        }
        return parts.joined(separator: " · ")
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

    private func observe() async {
        do {
            let observation = ValueObservation.tracking { db in
                try (ImportRepository.pendingProposals(db), ImportRepository.failedItems(db))
            }
            for try await value in observation.values(in: database.reader) {
                proposals = value.0
                failed = value.1
            }
        } catch {
            proposals = []
            failed = []
        }
    }
}
