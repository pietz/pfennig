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
    @State private var pendingSelection: LedgerRow.ID?
    /// Whether `pendingSelection` came from another window rather than from a
    /// click in the table: those have to be revealed, not merely selected.
    @State private var pendingSelectionIsRequest = false
    @State private var isConfirmingDiscard = false
    @Binding private var inspectorHasChanges: Bool
    @State private var search = ""
    @Binding private var filter: TransactionListFilter
    @State private var showsInspector = true
    @State private var isTargeted = false

    init(
        database: AppDatabase,
        filter: Binding<TransactionListFilter>,
        inspectorHasChanges: Binding<Bool>
    ) {
        self.database = database
        _filter = filter
        _inspectorHasChanges = inspectorHasChanges
    }

    private var directionFilter: DirectionFilter {
        DirectionFilter(direction: filter.direction)
    }

    private var showsProposals: Bool {
        filter.year == nil && directionFilter == .all && !filter.needsAttention && !filter.missingDocumentsOnly
    }

    private var visibleProposals: [ProposalRecord] {
        showsProposals ? proposals : []
    }

    private var rows: [LedgerRow] {
        visibleProposals.map(LedgerRow.init) + items.map(LedgerRow.init)
    }

    private var selectedProposal: ProposalRecord? {
        visibleProposals.first { $0.id == selection }
    }

    private var hasActiveFilters: Bool {
        filter.year != nil || directionFilter != .all || filter.needsAttention || filter.missingDocumentsOnly
    }

    var body: some View {
        table
            .searchable(text: $search, prompt: Text("Firma, Titel, Rechnungsnummer, Betrag"))
            .navigationTitle("Buchungen")
            .navigationSubtitle(Text(subtitle))
            .toolbar { toolbar }
            .inspector(isPresented: guardedInspectorPresentation) {
                TransactionInspector(
                    subject: subject,
                    newDraft: $newDraft,
                    hasUnsavedChanges: $inspectorHasChanges
                )
                .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
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
                "Ungespeicherte Änderungen verwerfen?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Änderungen verwerfen", role: .destructive) {
                    if pendingSelection == nil, newDraft != nil {
                        newDraft = nil
                    }
                    if pendingSelectionIsRequest, let id = pendingSelection {
                        reveal(id)
                    } else {
                        selection = pendingSelection
                    }
                    pendingSelection = nil
                    pendingSelectionIsRequest = false
                }
                Button("Weiter bearbeiten", role: .cancel) {
                    // The request is not remembered: the user stays in the
                    // booking they were editing.
                    pendingSelection = nil
                    pendingSelectionIsRequest = false
                }
            } message: {
                Text("Speichern Sie die aktuelle Buchung zuerst, wenn Sie Ihre Änderungen behalten möchten.")
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
            .task(id: ObservationKey(
                search: search,
                year: filter.year,
                direction: filter.direction,
                needsAttention: filter.needsAttention,
                missingDocumentsOnly: filter.missingDocumentsOnly
            )) { await observeTransactions() }
            .task { await observeProposals() }
            .task { await observeImports() }
            .task(id: selection) { await observeDetail() }
            .onChange(of: model.requestedTransactionID, initial: true) { _, id in
                guard let id else { return }
                openRequestedTransaction(id)
            }
    }

    /// Selects a booking another view asked for - the rows of "Prüfen" and
    /// the UStVA task window's exception list - and shows the inspector for
    /// it. Unsaved edits get the same confirmation as the sidebar first, and
    /// keeping them drops the request instead of queueing it.
    private func openRequestedTransaction(_ id: String) {
        model.requestedTransactionID = nil
        guard !inspectorHasChanges else {
            pendingSelection = id
            pendingSelectionIsRequest = true
            isConfirmingDiscard = true
            return
        }
        reveal(id)
    }

    /// Brings one booking on screen whatever was filtered or searched before.
    private func reveal(_ id: String) {
        filter = TransactionListFilter()
        search = ""
        showsInspector = true
        selection = id
    }

    // MARK: - Table

    private var table: some View {
        VStack(spacing: 0) {
            Table(rows, selection: guardedSelection) {
                TableColumn("Firma") { row in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.name)
                            if row.isProposal {
                                Image(systemName: row.status.symbol)
                                    .font(.caption)
                                    .foregroundStyle(row.status.tint)
                                    .help(Text(row.status.label))
                                    .accessibilityLabel(Text(row.status.label))
                            }
                        }
                        if let subtitle = row.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 120, ideal: 220)

                TableColumn("Datum") { row in
                    Text(row.date.map(Format.date) ?? "–")
                        .monospacedDigit()
                        .help(Text("Herkunft: \(row.dateOrigin)"))
                }
                .width(80)

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
                .width(min: 80, ideal: 100)

                TableColumn("Zahlung") { row in
                    Group {
                        if let status = row.paymentStatus {
                            Image(systemName: status.symbol)
                                .foregroundStyle(status.tint)
                                .help(Text(status.label))
                                .accessibilityLabel(Text(status.label))
                        } else {
                            Text("–").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu(forSelectionType: LedgerRow.ID.self) { ids in
                if let id = ids.first, !rows.contains(where: { $0.id == id && $0.isProposal }) {
                    Button("Löschen", role: .destructive) { deletingID = id }
                }
            }

            Divider()
            tableFooter
        }
    }

    private var tableFooter: some View {
        HStack(spacing: 8) {
            Text(filteredRowCountLabel)

            Spacer(minLength: 12)

            if let filteredTotal {
                Text("Summe")
                Text(filteredTotal.formatted(locale: Format.german))
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var committedRows: [LedgerRow] {
        rows.filter { !$0.isProposal }
    }

    private var filteredRowCountLabel: String {
        let bookings = "\(committedRows.count) \(committedRows.count == 1 ? "Buchung" : "Buchungen")"
        let proposalCount = rows.count - committedRows.count
        guard proposalCount > 0 else { return bookings }
        return "\(bookings) · \(proposalCount) \(proposalCount == 1 ? "Vorschlag" : "Vorschläge")"
    }

    /// Pending proposals are deliberately excluded: they are not booked yet.
    /// A total is shown only when every visible booking has one currency.
    private var filteredTotal: Money? {
        guard let firstAmount = committedRows.first?.amount else { return nil }
        var totalMinorUnits: Int64 = 0

        for row in committedRows {
            guard let amount = row.amount, amount.currency == firstAmount.currency else {
                return nil
            }
            let result = totalMinorUnits.addingReportingOverflow(amount.minorUnits)
            guard !result.overflow else { return nil }
            totalMinorUnits = result.partialValue
        }

        return Money(minorUnits: totalMinorUnits, currency: firstAmount.currency)
    }

    private var subtitle: String {
        var parts = ["\(items.count) Buchungen"]
        if let year = filter.year {
            parts.append(String(year))
        }
        if filter.needsAttention {
            parts.append("Offen")
        }
        if filter.missingDocumentsOnly {
            parts.append("Belege fehlen")
        }
        if !visibleProposals.isEmpty {
            parts.append("\(visibleProposals.count) zu prüfen")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                ForEach(DirectionFilter.allCases) { filter in
                    Button {
                        self.filter.direction = filter.direction
                    } label: {
                        Label(filter.label, systemImage: filter.symbol)
                    }
                }
            } label: {
                Text(directionFilter.label)
            }
            .fixedSize()
        }

        ToolbarItemGroup {
            if hasActiveFilters {
                Button {
                    filter = TransactionListFilter()
                    selection = nil
                } label: {
                    Label("Filter zurücksetzen", systemImage: "xmark.circle")
                }
                .disabled(inspectorHasChanges)
                .help(Text(inspectorHasChanges ? "Änderungen zuerst speichern oder verwerfen" : "Filter zurücksetzen"))
            }

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
            .disabled(inspectorHasChanges)
            .help(Text(inspectorHasChanges ? "Änderungen zuerst speichern oder verwerfen" : "Neue Buchung"))

            Button(action: chooseFiles) {
                Label("Importieren", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("i", modifiers: .command)
            .help(Text("Belege importieren"))

            Button {
                showsInspector.toggle()
            } label: {
                Label("Informationen", systemImage: "sidebar.trailing")
            }
            .disabled(inspectorHasChanges)
            .help(Text(inspectorHasChanges ? "Änderungen zuerst speichern oder verwerfen" :
                    "Informationen ein-/ausblenden"))
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

    private var guardedInspectorPresentation: Binding<Bool> {
        Binding(
            get: { showsInspector },
            set: { isPresented in
                guard isPresented || !inspectorHasChanges else { return }
                showsInspector = isPresented
            }
        )
    }

    private var guardedSelection: Binding<LedgerRow.ID?> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard inspectorHasChanges, newSelection != selection else {
                    selection = newSelection
                    return
                }
                pendingSelection = newSelection
                isConfirmingDiscard = true
            }
        )
    }

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
            let observation = TransactionListQuery.observation(
                search: search,
                listFilter: filter
            )
            for try await value in observation.values(in: database.reader) {
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

// MARK: - Direction filter

/// The "Alle / Einnahmen / Ausgaben" direction menu in the toolbar. Its own
/// label is the selected word, so the current filter is readable without
/// decoding an icon; the menu entries keep their symbols.
enum DirectionFilter: String, CaseIterable, Identifiable {
    case all, income, expense

    init(direction: Direction?) {
        switch direction {
        case .income: self = .income
        case .expense: self = .expense
        case .unknown, nil: self = .all
        }
    }

    var id: String {
        rawValue
    }

    var label: LocalizedStringKey {
        switch self {
        case .all: "Alle"
        case .income: "Einnahmen"
        case .expense: "Ausgaben"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        }
    }

    /// `nil` means "no filter", matching every direction.
    var direction: Direction? {
        switch self {
        case .all: nil
        case .income: .income
        case .expense: .expense
        }
    }
}

/// Identifies one (search, direction) combination so a single `.task`
/// restarts the observation whenever either changes.
private struct ObservationKey: Equatable {
    var search: String
    var year: Int?
    var direction: Direction?
    var needsAttention: Bool
    var missingDocumentsOnly: Bool
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
