import Agent
import Core
import SwiftUI

/// The ledger: the table of bookings with the intake strip above and the
/// totals footer below. The inspector beside it belongs to `WorkspaceView`.
struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var toDelete: Buchung?
    /// True while a drag hangs over the window.
    @State private var isDropTarget = false
    @SceneStorage("columns") private var columns: TableColumnCustomization<Buchung>

    var body: some View {
        let rows = model.visible
        VStack(spacing: 0) {
            if model.messages.isEmpty == false {
                IntakeMessages(model: model)
                Divider()
            }
            ledgerTable(rows)
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(3)
                            .allowsHitTesting(false)
                    }
                }
            Divider()
            Footer(totals: Overview.totals(rows))
        }
        // Drag and drop counts for the whole window.
        .dropDestination(for: URL.self) { urls, _ in
            model.acceptFiles(urls)
            return true
        } isTargeted: { isDropTarget = $0 }
        .searchable(text: $model.search, prompt: "Suchen")
        .toolbar { toolbarItems }
        // The table shrinks with the inspector; only the Unternehmen column gives.
        .frame(minWidth: WorkspaceView.tableMinimumWidth)
        // The Delete key and the context menu take the same way out.
        .onDeleteCommand { toDelete = model.selected }
        .confirmationDialog(
            "Buchung löschen?",
            isPresented: deleteConfirmationPresented,
            presenting: toDelete
        ) { buchung in
            Button("Löschen", role: .destructive) { model.delete(buchung) }
        } message: { buchung in
            Text("„\(buchung.titel)“ wird endgültig entfernt.")
        }
        .sheet(isPresented: $model.exportVisible) {
            ExportSheet(model: model)
        }
        .alert("Fehler", isPresented: $model.showsError, presenting: model.errorMessage) { _ in
            Button("OK") {}
        } message: { text in
            Text(text)
        }
    }

    private func ledgerTable(_ rows: [Buchung]) -> some View {
        Table(rows, selection: selectionBinding, sortOrder: $model.sortOrder, columnCustomization: $columns) {
            TableColumn("Unternehmen", value: \.unternehmen) { buchung in
                HStack(spacing: 8) {
                    Image(systemName: buchung.categorySymbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .help(buchung.categoryName.isEmpty ? "Keine Kategorie" : buchung.categoryName)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(buchung.unternehmen)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            if buchung.belege.isEmpty == false {
                                Image(systemName: "paperclip")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help("Beleg vorhanden")
                            }
                        }
                        Text(buchung.secondaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .ledgerCell()
            }
            .width(min: 160, ideal: 270)
            .customizationID("unternehmen")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Datum", value: \.datum) { buchung in
                Text(buchung.datum.formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .ledgerCell()
            }
            .width(84)
            .customizationID("datum")

            TableColumn("Betrag", value: \.signedAmount) { buchung in
                Text(buchung.signedAmount.formatted)
                    .monospacedDigit()
                    // Income is green; expenses stay in the primary text color.
                    .foregroundStyle(buchung.richtung == .einnahme ? Color.green : Color.primary)
                    .ledgerCell(.trailing)
            }
            .width(84)
            .alignment(.trailing)
            .customizationID("betrag")

            // The label remains a button so clicking it keeps the existing
            // one-click payment behavior without taking selection from the row.
            TableColumn("Bezahlt") { buchung in
                Button {
                    model.togglePayment(buchung)
                } label: {
                    PaymentLabel(status: buchung.zahlungsstand)
                }
                .buttonStyle(.borderless)
                .help(buchung.zahlungsstand.name)
                .ledgerCell()
            }
            .width(84)
            .customizationID("zahlung")

            TableColumn("Status") { buchung in
                ReviewStatusLabel(status: buchung.reviewStatus)
                    .ledgerCell()
            }
            .width(84)
            .customizationID("status")

            TableColumn("Kategorie", value: \.categoryName)
                .width(min: 100, ideal: 150)
                .customizationID("kategorie")
                .defaultVisibility(.hidden)

            TableColumn("Steuersatz", value: \.highestTaxRate) { buchung in
                Text(buchung.taxRateText).monospacedDigit()
            }
            .width(90)
            .customizationID("steuersatz")
            .defaultVisibility(.hidden)

            TableColumn("Art", value: \.art.name)
                .width(110)
                .customizationID("art")
                .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: Buchung.ID.self) { ids in
            if let id = ids.compactMap(\.self).first {
                Button("Löschen", role: .destructive) {
                    model.selection = id
                    toDelete = model.buchungen.first { $0.id == id }
                }
            }
        }
    }

    /// `Buchung.ID` is the optional row id of the record, the table selection
    /// therefore one optional deeper than the id the app works with.
    private var selectionBinding: Binding<Buchung.ID?> {
        Binding(
            get: { model.selection.map { Optional($0) } },
            set: { model.selection = $0 ?? nil }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { toDelete != nil },
            set: {
                if $0 == false {
                    toDelete = nil
                }
            }
        )
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        // Visible for as long as there is something in the queue.
        if model.progress.visible {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.progress.text)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Richtung", selection: $model.filter) {
                ForEach(BookingFilter.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Prüfung", selection: $model.reviewFilter) {
                ForEach(ReviewFilter.allCases) { Text($0.menuTitle).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Neue Buchung", systemImage: "plus") { model.createBooking() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Export", systemImage: "square.and.arrow.up") { model.exportVisible = true }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.trailing") { model.inspectorVisible.toggle() }
        }
    }
}

private extension View {
    /// The table has no row height of its own, every cell carries it.
    func ledgerCell(_ alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, minHeight: 40, alignment: alignment)
    }
}

/// What the intake had to say: files that stayed in the inbox and short notes
/// about files that were already there. The strip is only there while there is
/// something in it.
private struct IntakeMessages: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.messages) { message in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: message.kind == .failure ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(message.kind == .failure ? Color.orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.name).fontWeight(.medium)
                        Text(message.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if message.kind == .failure {
                        Button("Erneut versuchen") { model.retry(message) }
                        Button("Verwerfen") { model.discard(message) }
                    } else {
                        Button("Schließen", systemImage: "xmark") { model.discard(message) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
    }
}

private struct PaymentLabel: View {
    let status: Zahlungsstand

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .foregroundStyle(status == .bezahlt ? Color.green : Color.secondary)
            Text(status.name)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ReviewStatusLabel: View {
    let status: ReviewStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.color)
            Text(status.name)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

private extension ReviewStatus {
    var symbol: String {
        switch self {
        case .geprueft: "checkmark.circle.fill"
        case .zuPruefen: "exclamationmark.circle.fill"
        case .belegFehlt: "xmark.circle.fill"
        }
    }

    var name: String {
        switch self {
        case .geprueft: "Geprüft"
        case .zuPruefen: "Zu prüfen"
        case .belegFehlt: "Beleg fehlt"
        }
    }

    var color: Color {
        switch self {
        case .geprueft: .green
        case .zuPruefen: .yellow
        case .belegFehlt: .red
        }
    }
}

/// Income, expenses and balance of the rows the table currently shows.
private struct Footer: View {
    let totals: Totals

    var body: some View {
        HStack(spacing: 24) {
            Spacer()
            value("Einnahmen", totals.einnahmen)
            value("Ausgaben", totals.ausgaben)
            value("Saldo", totals.saldo)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func value(_ titel: String, _ betrag: Cent) -> some View {
        HStack(spacing: 6) {
            Text(titel).foregroundStyle(.secondary)
            Text(betrag.formatted).monospacedDigit()
        }
    }
}

extension Buchung {
    /// The first line of the Unternehmen column: the counterparty, or the title when
    /// there is none.
    var unternehmen: String {
        if let name = gegenparteiName, name.isEmpty == false {
            return name
        }
        return titel.isEmpty ? "Ohne Titel" : titel
    }

    /// The caption under it. It is always there, so every row keeps the same
    /// height; a space holds the line when the title is already the first one.
    var secondaryLine: String {
        guard let name = gegenparteiName, name.isEmpty == false else { return " " }
        return titel.isEmpty ? "Ohne Titel" : titel
    }

    /// Income counts positive and an expense negative, in the column as in the
    /// sort order.
    var signedAmount: Cent {
        richtung == .einnahme ? brutto : -brutto
    }

    var categoryName: String {
        kategorie.map(Kategorie.name) ?? ""
    }

    var categorySymbol: String {
        Kategorie.symbol(kategorie)
    }

    var highestTaxRate: Decimal {
        positionen.map(\.steuersatz).max() ?? 0
    }

    var taxRateText: String {
        let saetze = Set(positionen.map(\.steuersatz)).sorted()
        return saetze.isEmpty ? "" : saetze.map { "\($0)" }.joined(separator: "/") + " %"
    }
}

extension Zahlungsstand {
    var symbol: String {
        switch self {
        case .offen: "circle"
        case .bezahlt: "checkmark.circle.fill"
        }
    }

    var name: String {
        switch self {
        case .offen: "Offen"
        case .bezahlt: "Bezahlt"
        }
    }
}

extension Art {
    var name: String {
        switch self {
        case .rechnung: "Rechnung"
        case .beleg: "Beleg"
        case .gutschrift: "Gutschrift"
        case .steuerzahlung: "Steuerzahlung"
        case .nurZahlung: "Nur Zahlung"
        case .ignoriert: "Ignoriert"
        case .sonstiges: "Sonstiges"
        }
    }
}
