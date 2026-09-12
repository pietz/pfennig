import Database
import Domain
import SwiftUI

/// The main table (spec 6.2) plus the inspector (spec 6.4).
/// Rows come straight from the database and refresh on every write.
struct TransactionsView: View {
    let database: AppDatabase

    @Environment(AppModel.self) private var model
    @State private var rows: [TransactionListItem] = []
    @State private var selection: TransactionListItem.ID?
    @State private var detail: TransactionDetail?
    @State private var editing: TransactionDraft?
    @State private var deletingID: String?
    @State private var search = ""
    @State private var showsInspector = true

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Gegenpartei") { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.displayName)
                    if let title = row.title, row.counterpartyName != nil {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Datum") { row in
                Text(row.relevantDate.formattedShort)
                    .monospacedDigit()
                    .help(Text("Herkunft: \(row.relevantDateOrigin)"))
            }
            .width(90)

            TableColumn("Betrag") { row in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(row.bookedAmount?.formatted(locale: Format.german) ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(row.direction == .expense ? .primary : Color.green)
                    if let original = row.originalAmount {
                        Text(original.formatted(locale: Format.german))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(110)

            TableColumn("Zahlung") { row in
                Label(row.paymentStatus.label, systemImage: row.paymentStatus.symbol)
                    .foregroundStyle(row.paymentStatus.tint)
            }
            .width(140)

            TableColumn("Steuer") { row in
                Text(row.taxTreatment?.label ?? "–")
            }
            .width(140)

            TableColumn("Status") { row in
                Label(row.displayStatus.label, systemImage: row.displayStatus.symbol)
                    .foregroundStyle(row.displayStatus.tint)
            }
            .width(130)
        }
        .contextMenu(forSelectionType: TransactionListItem.ID.self) { ids in
            if let id = ids.first {
                Button("Bearbeiten") { edit(id) }
                Button("Löschen", role: .destructive) { deletingID = id }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                edit(id)
            }
        }
        .searchable(text: $search, prompt: Text("Gegenpartei, Titel, Rechnungsnummer, Betrag"))
        .navigationTitle("Buchungen")
        .navigationSubtitle(Text("\(rows.count) Buchungen"))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editing = model.newDraft()
                } label: {
                    Label("Neue Buchung", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    if let selection {
                        edit(selection)
                    }
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                .disabled(detail == nil)

                Button {
                    deletingID = selection
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
                .disabled(selection == nil)

                Button {
                    showsInspector.toggle()
                } label: {
                    Label("Informationen", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $showsInspector) {
            TransactionInspector(detail: detail)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .sheet(item: $editing) { draft in
            TransactionEditor(draft: draft)
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
        .task(id: search) {
            do {
                let observation = TransactionListQuery.observation(search: search)
                for try await items in observation.values(in: database.reader) {
                    rows = items
                }
            } catch {
                rows = []
            }
        }
        .task(id: selection) {
            guard let selection else {
                detail = nil
                return
            }
            do {
                for try await value in TransactionDetail.observation(id: selection).values(in: database.reader) {
                    detail = value
                }
            } catch {
                detail = nil
            }
        }
    }

    private func edit(_ id: String) {
        selection = id
        editing = (try? model.repository?.detail(id: id))??.draft
    }
}

/// One compact status per row, derived from the stored review status and the
/// derived payment status (spec 19).
struct DisplayStatus {
    let label: LocalizedStringKey
    let symbol: String
    let tint: Color
}

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

    var symbol: String {
        switch self {
        case .unreviewed: "circle.dashed"
        case .needsReview: "exclamationmark.triangle"
        case .confirmed: "checkmark.seal.fill"
        case .conflict: "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .unreviewed: .secondary
        case .needsReview: .orange
        case .confirmed: .green
        case .conflict: .red
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
