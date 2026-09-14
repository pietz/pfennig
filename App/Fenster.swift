import Kern
import SwiftUI

/// The one window: the table of bookings, the footer under it and the
/// inspector on the right.
struct Fenster: View {
    @Bindable var modell: AppModell
    @State private var zuLoeschen: Buchung?
    @SceneStorage("spalten") private var spalten: TableColumnCustomization<Buchung>

    var body: some View {
        let zeilen = modell.sichtbar
        VStack(spacing: 0) {
            tabelle(zeilen)
            Divider()
            Fusszeile(summen: Uebersicht.summen(zeilen))
        }
        .task { await modell.beobachten() }
        .searchable(text: $modell.suche, prompt: "Suchen")
        .toolbar { werkzeuge }
        .inspector(isPresented: $modell.inspektorSichtbar) {
            inspektor
                .inspectorColumnWidth(min: 280, ideal: 340)
        }
        // The Delete key and the context menu take the same way out.
        .onDeleteCommand { zuLoeschen = modell.ausgewaehlt }
        .confirmationDialog("Buchung löschen?", isPresented: loeschenLaeuft, presenting: zuLoeschen) { buchung in
            Button("Löschen", role: .destructive) { modell.loeschen(buchung) }
        } message: { buchung in
            Text("„\(buchung.titel)“ wird endgültig entfernt.")
        }
        .alert("Fehler", isPresented: $modell.zeigtFehler, presenting: modell.fehler) { _ in
            Button("OK") {}
        } message: { text in
            Text(text)
        }
    }

    private func tabelle(_ zeilen: [Buchung]) -> some View {
        Table(zeilen, selection: auswahlBindung, sortOrder: $modell.sortierung, columnCustomization: $spalten) {
            TableColumn("Firma", value: \.firma) { buchung in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(buchung.firma)
                        // An unreviewed booking carries a dot until the user confirms it.
                        if buchung.geprueftAm == nil {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(Color.orange)
                                .help("Ungeprüft")
                        }
                        if buchung.belege.isEmpty == false {
                            Image(systemName: "paperclip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Beleg vorhanden")
                        }
                    }
                    if let zweiteZeile = buchung.zweiteZeile {
                        Text(zweiteZeile).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 140, ideal: 240)
            .customizationID("firma")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Datum", value: \.datum) { buchung in
                Text(buchung.datum.formatiert).monospacedDigit()
            }
            .width(90)
            .customizationID("datum")

            TableColumn("Betrag", value: \.vorzeichenbetrag) { buchung in
                Text(buchung.vorzeichenbetrag.formatiert)
                    .monospacedDigit()
                    // Coloured by direction, not by sign.
                    .foregroundStyle(buchung.richtung == .einnahme ? Color.green : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 110)
            .alignment(.trailing)
            .customizationID("betrag")

            TableColumn("Zahlung") { buchung in
                Image(systemName: buchung.zahlungsstand.symbol)
                    .foregroundStyle(buchung.zahlungsstand == .bezahlt ? Color.green : .secondary)
                    .help(buchung.zahlungsstand.name)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(44)
            .customizationID("zahlung")

            TableColumn("Kategorie", value: \.kategorieName)
                .width(min: 100, ideal: 150)
                .customizationID("kategorie")
                .defaultVisibility(.hidden)

            TableColumn("Steuersatz", value: \.hoechsterSteuersatz) { buchung in
                Text(buchung.steuersatzText).monospacedDigit()
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
                    modell.auswahl = id
                    zuLoeschen = modell.buchungen.first { $0.id == id }
                }
            }
        }
    }

    /// `Buchung.ID` is the optional row id of the record, the table selection
    /// therefore one optional deeper than the id the app works with.
    private var auswahlBindung: Binding<Buchung.ID?> {
        Binding(
            get: { modell.auswahl.map { Optional($0) } },
            set: { modell.auswahl = $0 ?? nil }
        )
    }

    private var loeschenLaeuft: Binding<Bool> {
        Binding(
            get: { zuLoeschen != nil },
            set: {
                if $0 == false {
                    zuLoeschen = nil
                }
            }
        )
    }

    @ViewBuilder private var inspektor: some View {
        if let buchung = modell.ausgewaehlt {
            Inspektor(modell: modell, buchung: buchung)
                .id(buchung.id)
        } else {
            ContentUnavailableView("Keine Buchung ausgewählt", systemImage: "list.bullet.rectangle")
        }
    }

    @ToolbarContentBuilder private var werkzeuge: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Filter", selection: $modell.filter) {
                ForEach(Buchungsfilter.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Neue Buchung", systemImage: "plus") { modell.neueBuchung() }
        }
        ToolbarItem(placement: .primaryAction) {
            SettingsLink { Label("Einstellungen", systemImage: "gearshape") }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.trailing") { modell.inspektorSichtbar.toggle() }
        }
    }
}

/// Income, expenses and balance of the rows the table currently shows.
private struct Fusszeile: View {
    let summen: Summen

    var body: some View {
        HStack(spacing: 24) {
            Spacer()
            wert("Einnahmen", summen.einnahmen)
            wert("Ausgaben", summen.ausgaben)
            wert("Saldo", summen.saldo)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func wert(_ titel: String, _ betrag: Cent) -> some View {
        HStack(spacing: 6) {
            Text(titel).foregroundStyle(.secondary)
            Text(betrag.formatiert).monospacedDigit()
        }
    }
}

extension Buchung {
    /// The first line of the Firma column: the counterparty, or the title when
    /// there is none.
    var firma: String {
        gegenparteiName ?? titel
    }

    /// The caption under it, empty when the title is already the first line.
    var zweiteZeile: String? {
        gegenparteiName == nil || titel.isEmpty ? nil : titel
    }

    /// Income counts positive and an expense negative, in the column as in the
    /// sort order.
    var vorzeichenbetrag: Cent {
        richtung == .einnahme ? brutto : -brutto
    }

    var kategorieName: String {
        kategorie.map(Kategorie.name) ?? ""
    }

    var hoechsterSteuersatz: Decimal {
        positionen.map(\.steuersatz).max() ?? 0
    }

    var steuersatzText: String {
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
