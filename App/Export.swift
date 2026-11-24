import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

/// The export sheet: the values of one period, and the file the user takes to
/// Mein ELSTER or types into the Anlage EÜR. It computes on demand.
struct ExportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var close

    private let profile: Profil
    private let openBooking: (Int64) -> Void
    @State private var art: Zeitraumart = .ustva
    @State private var jahr: Int
    @State private var nummer: Int
    @State private var detail: TaxLineDetail?
    @State private var bookingToOpen: Int64?

    /// `preselected` is the period the start page asked for, if it came
    /// from there.
    init(model: AppModel, preselected: Zeitraum? = nil, openBooking: @escaping (Int64) -> Void) {
        self.model = model
        self.openBooking = openBooking
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
                Section {
                    Button("Zeitraum als anderweitig erledigt markieren") {
                        model.markExported(zeitraum)
                    }
                    .help(
                        "Entfernt die Erinnerung für diesen Zeitraum. Erstellt keine Datei und übermittelt keine Steuererklärung."
                    )
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 560, height: 600)
        .sheet(item: $detail, onDismiss: openSelectedBooking) { detail in
            TaxLineSheet(period: zeitraum.name, detail: detail) { id in
                bookingToOpen = id
                self.detail = nil
            }
        }
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
            drilldown(
                "Kz \(zeile.kennzahl.nummer)",
                zeile.kennzahl.titel,
                zeile.meldebetrag,
                detail: ustvaLineDetail(zeile)
            )
        }
        let zahllastTitel = values.zahllast < .null ? "Verbleibender Überschuss" : "Verbleibende Vorauszahlung"
        drilldown(
            "Kz 83",
            zahllastTitel,
            values.zahllast,
            detail: TaxLineDetail(
                title: "Kz 83 · \(zahllastTitel)",
                amount: values.zahllast,
                bookings: [],
                adjustments: values.zeilen.compactMap { zeile in
                    zeile.zahllastbeitrag.map { amount in
                        let prefix = Kennzahl.abgeleiteteSaetze[zeile.id] != nil ? "Steuer aus Kz \(zeile.id)" : "Kz \(zeile.id)"
                        return TaxLineDetail.Amount(
                            title: "\(prefix) · \(zeile.kennzahl.titel)",
                            amount: amount,
                            detail: ustvaLineDetail(zeile)
                        )
                    }
                }
            ),
            highlighted: true
        )
    }

    @ViewBuilder private var euerLines: some View {
        let values = euer
        if values.zeilen.isEmpty {
            Text("Keine Werte in diesem Jahr.").foregroundStyle(.secondary)
        }
        ForEach(values.zeilen) { zeile in
            drilldown(
                "Zeile \(zeile.zeile)",
                zeile.bezeichnung,
                zeile.betrag,
                detail: euerLineDetail(zeile)
            )
        }
        let einnahmenZeilen = values.zeilen.filter { $0.richtung == .einnahme }
        let ausgabenZeilen = values.zeilen.filter { $0.richtung == .ausgabe && $0.nichtAbziehbar == false }
        let gewinnZeilen = values.zeilen.filter { $0.richtung == .einnahme || $0.nichtAbziehbar == false }

        drilldown(
            "Summe",
            "Einnahmen",
            values.einnahmen,
            detail: TaxLineDetail(
                title: "Summe · Einnahmen",
                amount: values.einnahmen,
                bookings: [],
                adjustments: einnahmenZeilen.map { zeile in
                    TaxLineDetail.Amount(
                        title: "Zeile \(zeile.zeile) · \(zeile.bezeichnung)",
                        amount: zeile.betrag,
                        detail: euerLineDetail(zeile)
                    )
                },
                totalLabel: "Summe"
            )
        )
        drilldown(
            "Summe",
            "Ausgaben",
            values.ausgaben,
            detail: TaxLineDetail(
                title: "Summe · Ausgaben",
                amount: values.ausgaben,
                bookings: [],
                adjustments: ausgabenZeilen.map { zeile in
                    TaxLineDetail.Amount(
                        title: "Zeile \(zeile.zeile) · \(zeile.bezeichnung)",
                        amount: zeile.betrag,
                        detail: euerLineDetail(zeile)
                    )
                },
                totalLabel: "Summe"
            )
        )
        drilldown(
            "Summe",
            "Gewinn",
            values.ergebnis,
            detail: TaxLineDetail(
                title: "Summe · Gewinn",
                amount: values.ergebnis,
                bookings: [],
                adjustments: gewinnZeilen.map { zeile in
                    TaxLineDetail.Amount(
                        title: "Zeile \(zeile.zeile) · \(zeile.bezeichnung)",
                        amount: zeile.richtung == .einnahme ? zeile.betrag : -zeile.betrag,
                        detail: euerLineDetail(zeile)
                    )
                },
                totalLabel: "Gewinn"
            ),
            highlighted: true
        )
    }

    private func ustvaLineDetail(_ zeile: UStVA.Zeile) -> TaxLineDetail {
        TaxLineDetail(
            title: "Kz \(zeile.kennzahl.nummer) · \(zeile.kennzahl.titel)",
            amount: zeile.meldebetrag,
            bookings: zeile.buchungsbeitraege,
            adjustments: [
                zeile.profilbetrag
                    .map { TaxLineDetail.Amount(title: "Sondervorauszahlung laut Profil", amount: $0) },
                adjustment("Kürzung auf volle Euro", zeile.rundungsdifferenz)
            ].compactMap(\.self)
        )
    }

    private func euerLineDetail(_ zeile: EUeR.Zeile) -> TaxLineDetail {
        TaxLineDetail(
            title: "Zeile \(zeile.zeile) · \(zeile.bezeichnung)",
            amount: zeile.betrag,
            bookings: zeile.buchungsbeitraege,
            adjustments: [adjustment("Rundungsdifferenz der Zeile", zeile.rundungsdifferenz)].compactMap(\.self)
        )
    }

    private func adjustment(_ title: String, _ amount: Cent) -> TaxLineDetail.Amount? {
        amount == .null ? nil : TaxLineDetail.Amount(title: title, amount: amount)
    }

    private func drilldown(
        _ label: String, _ title: String, _ amount: Cent,
        detail lineDetail: TaxLineDetail, highlighted: Bool = false
    ) -> some View {
        Button {
            detail = lineDetail
        } label: {
            HStack(spacing: 8) {
                value(label, title, amount, highlighted: highlighted)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func openSelectedBooking() {
        guard let id = bookingToOpen else { return }
        bookingToOpen = nil
        openBooking(id)
        close()
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
        let offen = zeitraum.ungeprueft(model.buchungen, profile: profile)
        let fehlend = zeitraum.fehlendeSteuerbehandlungen(model.buchungen, profile: profile)
        let exportiert = model.exportedPeriods[zeitraum]
        if offen > 0 || fehlend > 0 || exportiert != nil {
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
                if fehlend > 0 {
                    Label {
                        VStack(alignment: .leading) {
                            Text(fehlend == 1
                                ? "Bei einer Buchung fehlt die Steuerbehandlung."
                                : "Bei \(fehlend) Buchungen fehlt die Steuerbehandlung.")
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
                        "Exportiert oder als erledigt markiert am \(LocalDate(exportiert).formatted).",
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

private struct TaxLineDetail: Identifiable {
    struct Amount {
        let title: String
        let amount: Cent
        let detail: TaxLineDetail?

        init(title: String, amount: Cent, detail: TaxLineDetail? = nil) {
            self.title = title
            self.amount = amount
            self.detail = detail
        }
    }

    let id = UUID()
    let title: String
    let amount: Cent
    let bookings: [Buchungsbeitrag]
    let adjustments: [Amount]
    let totalLabel: String

    init(
        title: String,
        amount: Cent,
        bookings: [Buchungsbeitrag],
        adjustments: [Amount],
        totalLabel: String = "Gemeldeter Betrag"
    ) {
        self.title = title
        self.amount = amount
        self.bookings = bookings
        self.adjustments = adjustments
        self.totalLabel = totalLabel
    }
}

private struct TaxLineSheet: View {
    @Environment(\.dismiss) private var close
    let period: String
    let detail: TaxLineDetail
    let openBooking: (Int64) -> Void

    @State private var stack: [TaxLineDetail] = []

    private var active: TaxLineDetail {
        stack.last ?? detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if !stack.isEmpty {
                    Button {
                        stack.removeLast()
                    } label: {
                        Label("Zurück", systemImage: "chevron.left")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                }
                Text(active.title).font(.headline)
                Text(period).foregroundStyle(.secondary)
            }
            .padding()
            Divider()
            Form {
                ForEach(active.bookings.indices, id: \.self) { index in
                    let booking = active.bookings[index]
                    if let id = booking.buchungId {
                        Button { openBooking(id) } label: {
                            bookingRow(booking)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    } else {
                        bookingRow(booking)
                    }
                }
                ForEach(active.adjustments.indices, id: \.self) { index in
                    let item = active.adjustments[index]
                    if let child = item.detail {
                        Button { stack.append(child) } label: {
                            HStack(spacing: 8) {
                                amountRow(item.title, item.amount)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    } else {
                        amountRow(item.title, item.amount)
                    }
                }
                if active.bookings.isEmpty, active.adjustments.isEmpty {
                    Text("Keine Beiträge in diesem Zeitraum.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                amountRow(active.totalLabel, active.amount).fontWeight(.semibold)
                Button("Schließen") { close() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 500, height: 380)
    }

    private func bookingRow(_ booking: Buchungsbeitrag) -> some View {
        HStack(spacing: 12) {
            Text(booking.datum.formatted)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            amountRow(booking.titel, booking.betrag)
            if booking.buchungId != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func amountRow(_ title: String, _ amount: Cent) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(amount.formatted).monospacedDigit().fixedSize()
        }
    }
}
