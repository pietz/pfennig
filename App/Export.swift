import AppKit
import Kern
import SwiftUI

/// The export sheet: the values of one period, and the file the user takes to
/// Mein ELSTER or types into the Anlage EÜR. It computes on demand and keeps
/// no state beyond the chosen period.
struct Exportblatt: View {
    let modell: AppModell
    @Environment(\.dismiss) private var schliessen

    private let profil: Profil
    @State private var art: Zeitraumart = .ustva
    @State private var jahr: Int
    @State private var nummer: Int

    init(modell: AppModell) {
        self.modell = modell
        let profil = modell.profil()
        self.profil = profil
        let vorgabe = Zeitraum.naechsteUStVA(
            rhythmus: profil.rhythmus,
            dauerfristverlaengerung: profil.dauerfristverlaengerung
        )
        _jahr = State(initialValue: vorgabe.jahr)
        _nummer = State(initialValue: vorgabe.nummer)
    }

    private var zeitraum: Zeitraum {
        switch art {
        case .ustva:
            Zeitraum(
                jahr: jahr,
                einteilung: profil.rhythmus == .monatlich ? .monat(nummer) : .quartal(nummer)
            )
        case .euer:
            Zeitraum(jahr: jahr, einteilung: .jahr)
        }
    }

    private var ustva: UStVA {
        UStVA.berechnen(modell.buchungen, zeitraum: zeitraum, profil: profil)
    }

    private var euer: EUeR {
        EUeR.berechnen(modell.buchungen, jahr: jahr, profil: profil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                auswahl
                Section(art == .ustva ? "UStVA \(zeitraum.name)" : "Anlage EÜR \(zeitraum.name)") {
                    if art == .ustva {
                        kennzahlen
                    } else {
                        euerzeilen
                    }
                }
                hinweise
            }
            .formStyle(.grouped)
            Divider()
            fusszeile
        }
        .frame(width: 560, height: 600)
    }

    // MARK: - Auswahl

    private var auswahl: some View {
        Section {
            Picker("Art", selection: $art) {
                Text("UStVA").tag(Zeitraumart.ustva)
                Text("EÜR").tag(Zeitraumart.euer)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Jahr", selection: $jahr) {
                ForEach(jahre, id: \.self) { Text(String($0)).tag($0) }
            }

            if art == .ustva {
                if profil.rhythmus == .monatlich {
                    Picker("Monat", selection: $nummer) {
                        ForEach(1 ... 12, id: \.self) { Text(Zeitraum.monatsname($0)).tag($0) }
                    }
                } else {
                    Picker("Quartal", selection: $nummer) {
                        ForEach(1 ... 4, id: \.self) { Text("Q\($0)").tag($0) }
                    }
                }
            }
        }
        .onChange(of: art) { vorgabe() }
    }

    /// The current year and the three before it; older periods are not what an
    /// export is for.
    private var jahre: [Int] {
        let heute = Datum.heute().jahr
        return Array((heute - 3 ... heute).reversed())
    }

    /// Switching between the two forms picks the period each of them opens on.
    private func vorgabe() {
        switch art {
        case .ustva:
            let naechster = Zeitraum.naechsteUStVA(
                rhythmus: profil.rhythmus,
                dauerfristverlaengerung: profil.dauerfristverlaengerung
            )
            jahr = naechster.jahr
            nummer = naechster.nummer
        case .euer:
            jahr = Zeitraum.naechsteEUeR().jahr
        }
    }

    // MARK: - Werte

    @ViewBuilder private var kennzahlen: some View {
        let werte = ustva
        if werte.zeilen.isEmpty {
            Text("Keine Werte in diesem Zeitraum.").foregroundStyle(.secondary)
        }
        ForEach(werte.zeilen) { zeile in
            wert(
                "Kz \(zeile.kennzahl.nummer)",
                zeile.kennzahl.titel,
                // A Bemessungsgrundlage goes into the form in whole euros, and
                // that is what the file writes, so that is what is shown.
                zeile.kennzahl.istBemessung
                    ? Cent(Kennzahl.volleEuro(zeile.betrag) * 100)
                    : zeile.betrag
            )
        }
        wert(
            "Kz 83",
            werte.zahllast < .null ? "Verbleibender Überschuss" : "Verbleibende Vorauszahlung",
            werte.zahllast,
            hervorgehoben: true
        )
    }

    @ViewBuilder private var euerzeilen: some View {
        let werte = euer
        if werte.zeilen.isEmpty {
            Text("Keine Werte in diesem Jahr.").foregroundStyle(.secondary)
        }
        ForEach(werte.zeilen) { zeile in
            wert("Zeile \(zeile.zeile)", zeile.bezeichnung, zeile.betrag)
        }
        wert("Summe", "Einnahmen", werte.einnahmen)
        wert("Summe", "Ausgaben", werte.ausgaben)
        wert("Summe", "Gewinn", werte.ergebnis, hervorgehoben: true)
    }

    private func wert(_ marke: String, _ titel: String, _ betrag: Cent, hervorgehoben: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(marke)
                .monospacedDigit()
                .frame(width: 70, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(titel)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 12)
            Text(betrag.formatiert)
                .monospacedDigit()
                .fontWeight(hervorgehoben ? .semibold : .regular)
        }
    }

    // MARK: - Hinweise

    @ViewBuilder private var hinweise: some View {
        let offen = zeitraum.ungeprueft(modell.buchungen)
        let exportiert = modell.exportierteZeitraeume[zeitraum]
        if offen > 0 || exportiert != nil {
            Section {
                if offen > 0 {
                    Label(
                        offen == 1
                            ? "Eine Buchung im Zeitraum ist noch ungeprüft."
                            : "\(offen) Buchungen im Zeitraum sind noch ungeprüft.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
                if let exportiert {
                    Label(
                        "Bereits exportiert am \(Datum(exportiert).formatiert).",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Fußzeile

    private var fusszeile: some View {
        HStack {
            if art == .ustva {
                Link(
                    "In Mein ELSTER hochladen",
                    destination: URL(
                        string: "https://www.elster.de/eportal/formulare-leistungen/alleformulare/ustvaeru"
                    )!
                )
            }
            Spacer()
            Button("Schließen") { schliessen() }
            Button(art == .ustva ? "XML speichern…" : "CSV speichern…", action: sichern)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    /// Writes the file where the user wants it and notes the period as
    /// exported. Pfennig does not transmit; the upload happens in Mein ELSTER.
    private func sichern() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = zeitraum.dateiname
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let ziel = panel.url else { return }
        do {
            switch art {
            case .ustva: try UStVAXml.daten(ustva).write(to: ziel)
            case .euer: try Data(euer.csv.utf8).write(to: ziel)
            }
            modell.exportVermerken(zeitraum)
            schliessen()
        } catch {
            modell.fehler = "Die Datei ließ sich nicht schreiben: \(error.localizedDescription)"
        }
    }
}
