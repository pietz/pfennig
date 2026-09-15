import Agent
import Core
import SwiftUI

/// The one window: the table of bookings, the footer under it and the
/// inspector on the right.
struct MainWindow: View {
    @Bindable var modell: AppModel
    @State private var toDelete: Buchung?
    /// True while a drag hangs over the window.
    @State private var zielt = false
    @SceneStorage("spalten") private var spalten: TableColumnCustomization<Buchung>

    var body: some View {
        let rows = modell.visible
        VStack(spacing: 0) {
            if modell.messages.isEmpty == false {
                IntakeMessages(modell: modell)
                Divider()
            }
            tabelle(rows)
                .overlay {
                    if zielt {
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
            modell.acceptFiles(urls)
            return true
        } isTargeted: { zielt = $0 }
        .searchable(text: $modell.search, prompt: "Suchen")
        .toolbar { werkzeuge }
        // Keep the table content wide enough for its five default columns before
        // the ancestor-hosted inspector takes its own native column.
        .frame(minWidth: 580, minHeight: 520)
        .inspector(isPresented: $modell.inspectorVisible) {
            inspektor
                .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
        }
        // The Delete key and the context menu take the same way out.
        .onDeleteCommand { toDelete = modell.ausgewaehlt }
        .confirmationDialog(
            "Buchung löschen?",
            isPresented: deleteConfirmationPresented,
            presenting: toDelete
        ) { buchung in
            Button("Löschen", role: .destructive) { modell.delete(buchung) }
        } message: { buchung in
            Text("„\(buchung.titel)“ wird endgültig entfernt.")
        }
        .sheet(isPresented: $modell.exportVisible) {
            ExportSheet(modell: modell)
        }
        .alert("Fehler", isPresented: $modell.showsError, presenting: modell.fehler) { _ in
            Button("OK") {}
        } message: { text in
            Text(text)
        }
    }

    private func tabelle(_ rows: [Buchung]) -> some View {
        Table(rows, selection: selectionBinding, sortOrder: $modell.sortOrder, columnCustomization: $spalten) {
            TableColumn("Firma", value: \.firma) { buchung in
                HStack(spacing: 8) {
                    Image(systemName: buchung.categorySymbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .help(buchung.categoryName.isEmpty ? "Keine Kategorie" : buchung.categoryName)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(buchung.firma)
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
                .frame(minHeight: 40, alignment: .leading)
            }
            .width(min: 190, ideal: 270)
            .customizationID("firma")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Datum", value: \.datum) { buchung in
                Text(buchung.datum.formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 40, alignment: .leading)
            }
            .width(min: 80, ideal: 90, max: 110)
            .customizationID("datum")

            TableColumn("Betrag", value: \.signedAmount) { buchung in
                Text(buchung.signedAmount.formatted)
                    .monospacedDigit()
                    // Income is green; expenses stay in the primary text color.
                    .foregroundStyle(buchung.richtung == .einnahme ? Color.green : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .trailing)
            }
            .width(min: 90, ideal: 105, max: 160)
            .alignment(.trailing)
            .customizationID("betrag")

            // The label remains a button so clicking it keeps the existing
            // one-click payment behavior without taking selection from the row.
            TableColumn("Bezahlt") { buchung in
                Button {
                    modell.togglePayment(buchung)
                } label: {
                    PaymentLabel(status: buchung.zahlungsstand)
                }
                .buttonStyle(.borderless)
                .help(buchung.zahlungsstand.name)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            .width(min: 90, ideal: 105, max: 140)
            .customizationID("zahlung")

            TableColumn("Status") { buchung in
                ReviewStatusLabel(status: buchung.reviewStatus)
                    .frame(minHeight: 40, alignment: .leading)
            }
            .width(min: 95, ideal: 110, max: 150)
            .customizationID("status")
            .defaultVisibility(.visible)

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
                    modell.selection = id
                    toDelete = modell.buchungen.first { $0.id == id }
                }
            }
        }
    }

    /// `Buchung.ID` is the optional row id of the record, the table selection
    /// therefore one optional deeper than the id the app works with.
    private var selectionBinding: Binding<Buchung.ID?> {
        Binding(
            get: { modell.selection.map { Optional($0) } },
            set: { modell.selection = $0 ?? nil }
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

    @ViewBuilder private var inspektor: some View {
        if let buchung = modell.ausgewaehlt {
            Inspector(modell: modell, buchung: buchung)
                .id(buchung.id)
        } else {
            ContentUnavailableView("Keine Buchung ausgewählt", systemImage: "list.bullet.rectangle")
        }
    }

    @ToolbarContentBuilder private var werkzeuge: some ToolbarContent {
        // Visible for as long as there is something in the queue.
        if modell.fortschritt.visible {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(modell.fortschritt.text)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Richtung", selection: $modell.filter) {
                ForEach(BookingFilter.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Prüfung", selection: $modell.reviewFilter) {
                ForEach(ReviewFilter.allCases) { Text($0.menuTitle).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Neue Buchung", systemImage: "plus") { modell.createBooking() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Export", systemImage: "square.and.arrow.up") { modell.exportVisible = true }
        }
        ToolbarItem(placement: .primaryAction) {
            SettingsLink { Label("Einstellungen", systemImage: "gearshape") }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.trailing") { modell.inspectorVisible.toggle() }
        }
    }
}

/// What the intake had to say: files that stayed in the inbox and short notes
/// about files that were already there. The strip is only there while there is
/// something in it.
private struct IntakeMessages: View {
    let modell: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(modell.messages) { meldung in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: meldung.art == .fehler ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(meldung.art == .fehler ? Color.orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meldung.name).fontWeight(.medium)
                        Text(meldung.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if meldung.art == .fehler {
                        Button("Erneut versuchen") { modell.retry(meldung) }
                        Button("Verwerfen") { modell.discard(meldung) }
                    } else {
                        Button("Schließen", systemImage: "xmark") { modell.discard(meldung) }
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
    /// The first line of the Firma column: the counterparty, or the title when
    /// there is none.
    var firma: String {
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
        switch kategorie {
        case nil: "doc.text"
        case "umsatz_dienstleistung": "banknote"
        case "umsatz_waren": "shippingbox"
        case "umsatz_lizenzen": "key"
        case "sonstige_einnahme": "doc.text"
        case "ust_erstattung": "building.columns"
        case "zinsen": "percent"
        case "software": "app"
        case "hosting": "cloud"
        case "telekommunikation": "phone"
        case "buerobedarf": "pencil.and.ruler"
        case "miete": "building.2"
        case "hardware": "desktopcomputer"
        case "werbung": "megaphone"
        case "beratung": "person.circle"
        case "fremdleistung": "person.2"
        case "reise_fahrt": "suitcase"
        case "reise_uebernachtung": "bed.double"
        case "bewirtung": "fork.knife"
        case "fortbildung": "book"
        case "versicherung": "shield"
        case "bankgebuehren": "banknote"
        case "zahlungsanbieter": "creditcard"
        case "mitgliedschaft": "person.3"
        case "porto": "envelope"
        case "ust_zahlung": "building.columns"
        case "sonstige_ausgabe": "doc.text"
        default: "doc.text"
        }
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
        case .teilweise: "circle.lefthalf.filled"
        case .bezahlt: "checkmark.circle.fill"
        }
    }

    var name: String {
        switch self {
        case .offen: "Offen"
        case .teilweise: "Teilweise bezahlt"
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
