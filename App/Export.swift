import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

/// The export sheet: the values of one period, and the file the user takes to
/// Mein ELSTER or types into the Anlage EÜR. It computes on demand and keeps
/// no state beyond the chosen period.
struct ExportSheet: View {
    let modell: AppModel
    @Environment(\.dismiss) private var close

    private let profile: Profil
    @State private var art: Zeitraumart = .ustva
    @State private var jahr: Int
    @State private var nummer: Int

    init(modell: AppModel) {
        self.modell = modell
        let profile = modell.profile()
        self.profile = profile
        let defaultSelection = Zeitraum.naechsteUStVA(
            rhythmus: profile.rhythmus,
            dauerfristverlaengerung: profile.dauerfristverlaengerung
        )
        _jahr = State(initialValue: defaultSelection.jahr)
        _nummer = State(initialValue: defaultSelection.nummer)
    }

    private var zeitraum: Zeitraum {
        switch art {
        case .ustva:
            Zeitraum(
                jahr: jahr,
                einteilung: profile.rhythmus == .monatlich ? .monat(nummer) : .quartal(nummer)
            )
        case .euer:
            Zeitraum(jahr: jahr, einteilung: .jahr)
        }
    }

    private var ustva: UStVA {
        UStVA.calculate(modell.buchungen, zeitraum: zeitraum, profile: profile)
    }

    private var euer: EUeR {
        EUeR.calculate(modell.buchungen, jahr: jahr, profile: profile)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                selection
                Section(art == .ustva ? "UStVA \(zeitraum.name)" : "Anlage EÜR \(zeitraum.name)") {
                    if art == .ustva {
                        taxNumbers
                    } else {
                        euerLines
                    }
                }
                hints
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 560, height: 600)
    }

    // MARK: - Auswahl

    private var selection: some View {
        Section {
            Picker("Art", selection: $art) {
                Text("UStVA").tag(Zeitraumart.ustva)
                Text("EÜR").tag(Zeitraumart.euer)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Jahr", selection: $jahr) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }

            if art == .ustva {
                if profile.rhythmus == .monatlich {
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
        .onChange(of: art) { defaultSelection() }
    }

    /// The current year and the three before it; older periods are not what an
    /// export is for.
    private var years: [Int] {
        let today = LocalDate.today().jahr
        return Array((today - 3 ... today).reversed())
    }

    /// Switching between the two forms picks the period each of them opens on.
    private func defaultSelection() {
        switch art {
        case .ustva:
            let next = Zeitraum.naechsteUStVA(
                rhythmus: profile.rhythmus,
                dauerfristverlaengerung: profile.dauerfristverlaengerung
            )
            jahr = next.jahr
            nummer = next.nummer
        case .euer:
            jahr = Zeitraum.naechsteEUeR().jahr
        }
    }

    // MARK: - Werte

    @ViewBuilder private var taxNumbers: some View {
        let werte = ustva
        if werte.zeilen.isEmpty {
            Text("Keine Werte in diesem Zeitraum.").foregroundStyle(.secondary)
        }
        ForEach(werte.zeilen) { zeile in
            value(
                "Kz \(zeile.kennzahl.nummer)",
                zeile.kennzahl.titel,
                // A Bemessungsgrundlage goes into the form in whole euros, and
                // that is what the file writes, so that is what is shown.
                zeile.kennzahl.istBemessung
                    ? Cent(Kennzahl.volleEuro(zeile.betrag) * 100)
                    : zeile.betrag
            )
        }
        value(
            "Kz 83",
            werte.zahllast < .null ? "Verbleibender Überschuss" : "Verbleibende Vorauszahlung",
            werte.zahllast,
            highlighted: true
        )
    }

    @ViewBuilder private var euerLines: some View {
        let werte = euer
        if werte.zeilen.isEmpty {
            Text("Keine Werte in diesem Jahr.").foregroundStyle(.secondary)
        }
        ForEach(werte.zeilen) { zeile in
            value("Zeile \(zeile.zeile)", zeile.bezeichnung, zeile.betrag)
        }
        value("Summe", "Einnahmen", werte.einnahmen)
        value("Summe", "Ausgaben", werte.ausgaben)
        value("Summe", "Gewinn", werte.ergebnis, highlighted: true)
    }

    private func value(_ label: String, _ titel: String, _ betrag: Cent, highlighted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .monospacedDigit()
                .frame(width: 70, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(titel)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 12)
            Text(betrag.formatted)
                .monospacedDigit()
                .fontWeight(highlighted ? .semibold : .regular)
        }
    }

    // MARK: - Hinweise

    @ViewBuilder private var hints: some View {
        let offen = zeitraum.ungeprueft(modell.buchungen)
        let exportiert = modell.exportedPeriods[zeitraum]
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
                        "Bereits exportiert am \(LocalDate(exportiert).formatted).",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Fußzeile

    private var footer: some View {
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
            Button("Schließen") { close() }
                .keyboardShortcut(.cancelAction)
            Button(art == .ustva ? "XML speichern…" : "CSV speichern…", action: save)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    /// Writes the file where the user wants it and notes the period as
    /// exported. Pfennig does not transmit; the upload happens in Mein ELSTER.
    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = zeitraum.dateiname
        panel.allowedContentTypes = [art == .ustva ? .xml : .commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let ziel = panel.url else { return }
        do {
            switch art {
            case .ustva: try UStVAXml.daten(ustva).write(to: ziel)
            case .euer: try Data(euer.csv.utf8).write(to: ziel)
            }
            modell.markExported(zeitraum)
            close()
        } catch {
            modell.fehler = "Die Datei ließ sich nicht schreiben: \(error.localizedDescription)"
        }
    }
}
