import Database
import Domain
import SwiftUI

/// Placeholder inspector: shows the stored fields of the selected transaction.
/// Document preview, payments, tax details and actions follow in M3/M4.
struct TransactionInspector: View {
    let item: TransactionListItem?

    var body: some View {
        if let item {
            Form {
                Section("Buchung") {
                    row("Gegenpartei", item.displayName)
                    if let title = item.title {
                        row("Titel", title)
                    }
                    row("Art", Text(item.direction.label))
                    row("Datum", "\(item.relevantDate.formattedShort) · \(item.relevantDateOrigin)")
                }
                Section("Beträge") {
                    row("Gebucht", item.bookedAmount?.formatted() ?? "–")
                    if let original = item.originalAmount {
                        row("Original", original.formatted())
                    }
                }
                Section("Status") {
                    row("Zahlung", Label(item.paymentStatus.label, systemImage: item.paymentStatus.symbol))
                    row("Beleg", Label(item.documentStatus.label, systemImage: "doc"))
                    row("Steuer", Text(item.taxTreatment?.label ?? "–"))
                    row("Prüfung", Label(item.reviewStatus.label, systemImage: item.reviewStatus.symbol))
                }
                Section {
                    Text(
                        "Belegvorschau, Zahlungen, Steuerdetails und Hinweise folgen mit den nächsten Meilensteinen."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "Keine Buchung ausgewählt",
                systemImage: "sidebar.trailing",
                description: Text("Wählen Sie eine Zeile, um Details zu sehen.")
            )
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        row(label, Text(value))
    }

    private func row(_ label: LocalizedStringKey, _ value: some View) -> some View {
        LabeledContent {
            value.multilineTextAlignment(.trailing)
        } label: {
            Text(label)
        }
    }
}
