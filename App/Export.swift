import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

/// The export sheet: the values of one period, and the file the user takes to
/// Mein ELSTER or types into the Anlage EÜR. It computes on demand and keeps
/// no state beyond the chosen period.
struct ExportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var close

    private let profile: Profil
    @State private var art: Zeitraumart = .ustva
    @State private var jahr: Int
    @State private var nummer: Int

    /// `preselected` is the period the start page asked for, if it came
    /// from there.
    init(model: AppModel, preselected: Zeitraum? = nil) {
        self.model = model
        let profile = model.profile()
        self.profile = profile
        let selection = preselected ?? Zeitraum.naechsteUStVA(
            rhythmus: profile.rhythmus,
            dauerfristverlaengerung: profile.dauerfristverlaengerung
        )
        _art = State(initialValue: selection.art)
        _jahr = State(initialValue: selection.jahr)
        _nummer = State(initialValue: selection.nummer)
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
        UStVA.calculate(model.buchungen, zeitraum: zeitraum, profile: profile)
    }

    private var euer: EUeR {
        EUeR.calculate(model.buchungen, jahr: jahr, profile: profile)
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
        .alert("Fehler", isPresented: $model.showsError, presenting: model.errorMessage) { _ in
            Button("OK") {}
        } message: { text in
            Text(text)
        }
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
    /// export is for. A deadline the start page hands over may be older and
    /// still has to be visible in the picker.
    private var years: [Int] {
        let today = LocalDate.today().jahr
        return Array((min(today - 3, jahr) ... today).reversed())
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
        let values = ustva
        if values.zeilen.isEmpty {
            Text("Keine Werte in diesem Zeitraum.").foregroundStyle(.secondary)
        }
        ForEach(values.zeilen) { zeile in
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
            values.zahllast < .null ? "Verbleibender Überschuss" : "Verbleibende Vorauszahlung",
            values.zahllast,
            highlighted: true
        )
    }

    @ViewBuilder private var euerLines: some View {
        let values = euer
        if values.zeilen.isEmpty {
            Text("Keine Werte in diesem Jahr.").foregroundStyle(.secondary)
        }
        ForEach(values.zeilen) { zeile in
            value("Zeile \(zeile.zeile)", zeile.bezeichnung, zeile.betrag)
        }
        value("Summe", "Einnahmen", values.einnahmen)
        value("Summe", "Ausgaben", values.ausgaben)
        value("Summe", "Gewinn", values.ergebnis, highlighted: true)
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
        let offen = zeitraum.ungeprueft(model.buchungen)
        let unklar = zeitraum.unklareSteuerbehandlungen(model.buchungen)
        let exportiert = model.exportedPeriods[zeitraum]
        if offen > 0 || unklar > 0 || exportiert != nil {
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
                if unklar > 0 {
                    Label {
                        VStack(alignment: .leading) {
                            Text(unklar == 1
                                ? "Bei einer Buchung ist die Steuerbehandlung unklar."
                                : "Bei \(unklar) Buchungen ist die Steuerbehandlung unklar.")
                            Text(art == .ustva
                                ? "Nicht in den UStVA-Werten enthalten. Vor der Abgabe prüfen."
                                : "EÜR-Werte basieren auf den vorhandenen Angaben. Vor der Abgabe prüfen.")
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
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
        do {
            try ExportError.validate(year: zeitraum.jahr)

            let panel = NSSavePanel()
            panel.nameFieldStringValue = zeitraum.dateiname
            panel.allowedContentTypes = [art == .ustva ? .xml : .commaSeparatedText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            switch art {
            case .ustva: try UStVAXml.daten(ustva).write(to: destination)
            case .euer: try Data(euer.csv.utf8).write(to: destination)
            }
            model.markExported(zeitraum)
            close()
        } catch let error as ExportError {
            model.errorMessage = error.localizedDescription
        } catch {
            model.errorMessage = "Die Datei ließ sich nicht schreiben: \(error.localizedDescription)"
        }
    }
}
