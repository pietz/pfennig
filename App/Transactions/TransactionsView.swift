import AppKit
import Database
import DocumentStore
import Domain
import GRDB
import SwiftUI
import UniformTypeIdentifiers

/// The main table (spec 6.2) plus the inspector (spec 6.4). Committed
/// transactions and pending AI proposals share the table; dropping a document
/// anywhere in the window starts an import (spec 7.1).
struct TransactionsView: View {
    let database: AppDatabase

    @Environment(AppModel.self) private var model
    @State private var items: [TransactionListItem] = []
    @State private var proposals: [ProposalRecord] = []
    @State private var activeImports = 0
    @State private var selection: LedgerRow.ID?
    @State private var detail: TransactionDetail?
    @State private var newDraft: TransactionDraft?
    @State private var deletingID: String?
    @State private var search = ""
    @State private var showsInspector = true
    @State private var isTargeted = false

    private var rows: [LedgerRow] {
        proposals.map(LedgerRow.init) + items.map(LedgerRow.init)
    }

    private var selectedProposal: ProposalRecord? {
        proposals.first { $0.id == selection }
    }

    var body: some View {
        table
            .searchable(text: $search, prompt: Text("Gegenpartei, Titel, Rechnungsnummer, Betrag"))
            .navigationTitle("Buchungen")
            .navigationSubtitle(Text(subtitle))
            .toolbar { toolbar }
            .inspector(isPresented: $showsInspector) {
                TransactionInspector(subject: subject, newDraft: $newDraft)
                    .inspectorColumnWidth(min: 320, ideal: 420, max: 600)
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.importFiles(urls)
                return true
            } isTargeted: { isTargeted = $0 }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .confirmationDialog(
                "Buchung löschen?",
                isPresented: Binding(get: { deletingID != nil }, set: {
                    if !$0 {
                        deletingID = nil
                    }
                }),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let deletingID {
                        model.delete(deletingID)
                        if selection == deletingID {
                            selection = nil
                        }
                    }
                    deletingID = nil
                }
                Button("Abbrechen", role: .cancel) { deletingID = nil }
            } message: {
                Text("Die Buchung wird archiviert und aus der Liste entfernt. Die Daten bleiben im Archiv erhalten.")
            }
            .task(id: search) { await observeTransactions() }
            .task { await observeProposals() }
            .task { await observeImports() }
            .task(id: selection) { await observeDetail() }
    }

    // MARK: - Table

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Gegenpartei") { row in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if row.isProposal {
                            Image(systemName: "sparkles").foregroundStyle(.orange)
                        }
                        Text(row.name)
                    }
                    if let subtitle = row.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Datum") { row in
                Text(row.date.map(Format.date) ?? "–")
                    .monospacedDigit()
                    .help(Text("Herkunft: \(row.dateOrigin)"))
            }
            .width(90)

            TableColumn("Betrag") { row in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(row.amount?.formatted(locale: Format.german) ?? "–")
                        .monospacedDigit()
                        .foregroundStyle((row.amount?.minorUnits ?? 0) < 0 ? Color.primary : Color.green)
                    if let secondary = row.secondaryAmount {
                        Text(secondary.formatted(locale: Format.german))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(110)

            TableColumn("Zahlung") { row in
                if let status = row.paymentStatus {
                    Label(status.label, systemImage: status.symbol).foregroundStyle(status.tint)
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
            }
            .width(140)

            TableColumn("Steuer") { row in
                Text(row.treatment?.label ?? "–")
            }
            .width(140)

            TableColumn("Status") { row in
                Label(row.status.label, systemImage: row.status.symbol)
                    .foregroundStyle(row.status.tint)
            }
            .width(130)
        }
        .contextMenu(forSelectionType: LedgerRow.ID.self) { ids in
            if let id = ids.first, !rows.contains(where: { $0.id == id && $0.isProposal }) {
                Button("Löschen", role: .destructive) { deletingID = id }
            }
        }
    }

    private var subtitle: String {
        var parts = ["\(items.count) Buchungen"]
        if !proposals.isEmpty {
            parts.append("\(proposals.count) zu prüfen")
        }
        if activeImports > 0 {
            parts.append("\(activeImports) \(activeImports == 1 ? "Dokument wird" : "Dokumente werden") analysiert")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if activeImports > 0 {
                ProgressView().controlSize(.small)
            }
            Button {
                newDraft = model.newDraft()
                selection = nil
            } label: {
                Label("Neue Buchung", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(action: chooseFiles) {
                Label("Importieren", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("i", modifiers: .command)

            Button {
                deletingID = selection
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .disabled(detail == nil)

            Button {
                showsInspector.toggle()
            } label: {
                Label("Informationen", systemImage: "sidebar.trailing")
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .jpeg, .png, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Importieren"
        panel.message = "Belege auswählen"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls)
    }

    // MARK: - State

    private var subject: InspectorSubject {
        if let proposal = selectedProposal {
            return .proposal(proposal)
        }
        if let detail {
            return .transaction(detail)
        }
        if newDraft != nil {
            return .draft
        }
        return .none
    }

    private func observeTransactions() async {
        do {
            for try await value in TransactionListQuery.observation(search: search).values(in: database.reader) {
                items = value
            }
        } catch {
            items = []
        }
    }

    private func observeProposals() async {
        do {
            for try await value in ImportRepository.pendingProposalsObservation().values(in: database.reader) {
                proposals = value
            }
        } catch {
            proposals = []
        }
    }

    private func observeImports() async {
        do {
            for try await value in ImportRepository.activeItemsObservation().values(in: database.reader) {
                activeImports = value.count
            }
        } catch {
            activeImports = 0
        }
    }

    private func observeDetail() async {
        guard let selection, selectedProposal == nil else {
            detail = nil
            return
        }
        newDraft = nil
        do {
            for try await value in TransactionDetail.observation(id: selection).values(in: database.reader) {
                detail = value
            }
        } catch {
            detail = nil
        }
    }
}

// MARK: - Row status

extension TransactionListItem {
    var displayStatus: DisplayStatus {
        switch reviewStatus {
        case .conflict:
            DisplayStatus(label: "Konflikt", symbol: "xmark.octagon", tint: .red)
        case .needsReview:
            DisplayStatus(label: "Prüfen", symbol: "exclamationmark.triangle", tint: .orange)
        case .unreviewed:
            DisplayStatus(label: "Ungeprüft", symbol: "circle.dashed", tint: .secondary)
        case .confirmed:
            paymentStatus == .paid
                ? DisplayStatus(label: "Abgeschlossen", symbol: "checkmark.seal.fill", tint: .green)
                : DisplayStatus(label: "Bestätigt", symbol: "checkmark.seal", tint: .green)
        }
    }
}

extension LocalDate {
    var formattedShort: String {
        date().formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Format.german))
    }
}

extension PaymentStatus {
    var label: LocalizedStringKey {
        switch self {
        case .paid: "Bezahlt"
        case .partiallyPaid: "Teilweise bezahlt"
        case .unpaid: "Offen"
        case .unknown: "Unbekannt"
        }
    }

    var symbol: String {
        switch self {
        case .paid: "checkmark.circle.fill"
        case .partiallyPaid: "circle.lefthalf.filled"
        case .unpaid: "circle"
        case .unknown: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .paid: .green
        case .partiallyPaid: .orange
        case .unpaid, .unknown: .secondary
        }
    }
}

extension ReviewStatus {
    var label: LocalizedStringKey {
        switch self {
        case .unreviewed: "Ungeprüft"
        case .needsReview: "Prüfen"
        case .confirmed: "Bestätigt"
        case .conflict: "Konflikt"
        }
    }
}

extension TaxTreatment {
    var label: LocalizedStringKey {
        switch self {
        case .domesticVAT: "Umsatzsteuer (DE)"
        case .reverseCharge: "Reverse Charge"
        case .intraCommunityAcquisition: "Innergem. Erwerb"
        case .intraCommunitySupply: "Innergem. Lieferung"
        case .export: "Ausfuhr"
        case .importVAT: "Einfuhrumsatzsteuer"
        case .nonTaxable: "Nicht steuerbar"
        case .exempt: "Steuerfrei"
        case .smallBusiness: "Kleinunternehmer"
        case .unknown: "Unbekannt"
        }
    }
}

extension Direction {
    var label: LocalizedStringKey {
        switch self {
        case .income: "Einnahme"
        case .expense: "Ausgabe"
        case .unknown: "Unbekannt"
        }
    }
}

extension DocumentStatus {
    var label: LocalizedStringKey {
        switch self {
        case .complete: "Vorhanden"
        case .missing: "Fehlt"
        case .notRequired: "Nicht nötig"
        }
    }
}
