import Database
import Domain
import SwiftUI

/// The main table (spec 6.2) plus the inspector (spec 6.4).
/// Rows come straight from the database and refresh on every write.
struct TransactionsView: View {
    let database: AppDatabase

    @State private var rows: [TransactionListItem] = []
    @State private var selection: TransactionListItem.ID?
    @State private var search = ""
    @State private var showsInspector = true

    private var selected: TransactionListItem? {
        rows.first { $0.id == selection }
    }

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
                    Text(row.bookedAmount?.formatted() ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(row.direction == .expense ? .primary : Color.green)
                    if let original = row.originalAmount {
                        Text(original.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(110)

            TableColumn("Zahlung") { row in
                Label(row.paymentStatus.label, systemImage: row.paymentStatus.symbol)
                    .foregroundStyle(row.paymentStatus.tint)
            }
            .width(120)

            TableColumn("Steuer") { row in
                Text(row.taxTreatment?.label ?? "–")
            }
            .width(140)

            TableColumn("Status") { row in
                Label(row.reviewStatus.label, systemImage: row.reviewStatus.symbol)
                    .foregroundStyle(row.reviewStatus.tint)
            }
            .width(130)
        }
        .searchable(text: $search, prompt: Text("Gegenpartei, Titel, Rechnungsnummer, Betrag"))
        .navigationTitle("Buchungen")
        .navigationSubtitle(Text("\(rows.count) Buchungen"))
        .toolbar {
            ToolbarItem {
                Button {
                    showsInspector.toggle()
                } label: {
                    Label("Informationen", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $showsInspector) {
            TransactionInspector(item: selected)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
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
    }
}

extension LocalDate {
    var formattedShort: String {
        date().formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
    }
}

extension PaymentStatus {
    var label: LocalizedStringKey {
        switch self {
        case .paid: "Bezahlt"
        case .partiallyPaid: "Teilweise"
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
