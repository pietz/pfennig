import Kern
import SwiftUI

/// The one window: the table of bookings, the footer under it and the
/// inspector on the right.
struct Fenster: View {
    @Bindable var modell: AppModell
    @State private var loeschenBestaetigen = false

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
        .onDeleteCommand {
            loeschenBestaetigen = modell.ausgewaehlt != nil
        }
        .confirmationDialog("Buchung löschen?", isPresented: $loeschenBestaetigen, presenting: modell.ausgewaehlt) {
            buchung in
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
        Table(zeilen, selection: $modell.auswahl, sortOrder: $modell.sortierung) {
            TableColumn("Datum", value: \.datum) { buchung in
                HStack(spacing: 6) {
                    // An unreviewed booking carries a dot until the user confirms it.
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(buchung.geprueftAm == nil ? Color.orange : .clear)
                    Text(buchung.datum.formatiert)
                }
            }
            .width(110)

            TableColumn("Gegenpartei", value: \.gegenpartei)

            TableColumn("Titel", value: \.titel)

            TableColumn("Betrag", value: \.vorzeichenbetrag) { buchung in
                Text(buchung.vorzeichenbetrag.formatiert)
                    .monospacedDigit()
                    .foregroundStyle(buchung.richtung == .einnahme ? Color.green : Color.primary)
            }
            .width(110)
            .alignment(.trailing)

            TableColumn("Zahlung") { buchung in
                Image(systemName: symbol(buchung.zahlungsstand))
                    .foregroundStyle(buchung.zahlungsstand == .bezahlt ? Color.green : .secondary)
                    .help(beschriftung(buchung.zahlungsstand))
            }
            .width(60)

            TableColumn("Beleg") { buchung in
                if buchung.belege.isEmpty == false {
                    Image(systemName: "paperclip").foregroundStyle(.secondary)
                }
            }
            .width(50)
        }
        .contextMenu(forSelectionType: Buchung.ID.self) { ids in
            if ids.isEmpty == false {
                Button("Löschen", role: .destructive) {
                    modell.auswahl = ids.first
                    loeschenBestaetigen = true
                }
            }
        }
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
        ToolbarItem(placement: .navigation) {
            Picker("Filter", selection: $modell.filter) {
                ForEach(Buchungsfilter.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        ToolbarItem {
            Button("Neue Buchung", systemImage: "plus") { modell.neueBuchung() }
        }
        ToolbarItem {
            SettingsLink { Label("Einstellungen", systemImage: "gearshape") }
        }
        ToolbarItem {
            Button("Inspector", systemImage: "sidebar.trailing") { modell.inspektorSichtbar.toggle() }
        }
    }

    private func symbol(_ stand: Zahlungsstand) -> String {
        switch stand {
        case .offen: "circle"
        case .teilweise: "circle.lefthalf.filled"
        case .bezahlt: "checkmark.circle.fill"
        }
    }

    private func beschriftung(_ stand: Zahlungsstand) -> String {
        switch stand {
        case .offen: "Offen"
        case .teilweise: "Teilweise bezahlt"
        case .bezahlt: "Bezahlt"
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
    /// The table column never shows an empty optional.
    var gegenpartei: String {
        gegenparteiName ?? ""
    }

    /// Income counts positive and an expense negative, in the column as in the
    /// sort order.
    var vorzeichenbetrag: Cent {
        richtung == .einnahme ? brutto : -brutto
    }
}
