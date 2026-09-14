import AppKit
import Combine
import Kern
import SwiftUI

/// The inspector of the selected booking. It edits a draft and writes it back
/// through the repository as soon as the user commits a field; there is no
/// save and no discard.
struct Inspektor: View {
    let modell: AppModell
    let buchung: Buchung

    @State private var entwurf: Buchung
    /// The last state that went to the database. It separates a real edit from
    /// the timestamps the repository sets with every write.
    @State private var gesichert: Buchung
    /// True once the user asked for the foreign currency line on a booking
    /// that does not carry one yet.
    @State private var fremdwaehrung = false
    /// A plain text field writes into the draft with every keystroke. The
    /// draft goes to the database when the field is submitted or loses focus,
    /// so the table shows the change right away.
    @FocusState private var fokus: Feld?

    private enum Feld {
        case titel
        case gegenpartei
        case land
        case ustid
        case waehrung
        case notizen
    }

    init(modell: AppModell, buchung: Buchung) {
        self.modell = modell
        self.buchung = buchung
        _entwurf = State(initialValue: buchung)
        _gesichert = State(initialValue: buchung)
    }

    var body: some View {
        Form {
            // An edit after the values of the period went to the tax office.
            if modell.nachExportGeaendert(buchung) {
                Label("Nach dem Export des Zeitraums geändert", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if buchung.belege.isEmpty == false {
                BelegAbschnitt(modell: modell, buchung: buchung)
            }
            grunddaten
            betraege
            steuer
            zahlungen
            notizen
        }
        .formStyle(.grouped)
        .onSubmit(sichern)
        .onChange(of: fokus) { sichern() }
        .onChange(of: buchung) { _, neu in
            // Follow the database unless the user has an unsaved edit in flight.
            if entwurf == gesichert {
                entwurf = neu
            }
            gesichert = neu
        }
        .onDisappear(perform: sichern)
        // Quitting must not swallow a field the user typed but never committed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            sichern()
        }
        // Controls other than the free text fields commit the moment they change.
        .onChange(of: entwurf.richtung) { sichern() }
        .onChange(of: entwurf.art) { sichern() }
        .onChange(of: entwurf.datum) { sichern() }
        .onChange(of: entwurf.kategorie) { sichern() }
        .onChange(of: entwurf.privatanteilProzent) { sichern() }
        .onChange(of: entwurf.positionen) { sichern() }
        .onChange(of: entwurf.originalbetrag) { sichern() }
        .onChange(of: entwurf.steuerbehandlung) { sichern() }
        .onChange(of: entwurf.zahlungen) { sichern() }
        .safeAreaInset(edge: .bottom) { bestaetigung }
    }

    private func sichern() {
        guard entwurf != gesichert else { return }
        guard modell.buchungen.contains(where: { $0.id == entwurf.id }) else { return }
        guard let gespeichert = modell.speichern(entwurf) else { return }
        entwurf = gespeichert
        gesichert = gespeichert
    }

    // MARK: - Grunddaten

    private var grunddaten: some View {
        Section("Grunddaten") {
            Picker("Richtung", selection: richtungBindung) {
                Text("Einnahme").tag(Richtung.einnahme)
                Text("Ausgabe").tag(Richtung.ausgabe)
            }
            .pickerStyle(.segmented)

            Picker("Art", selection: $entwurf.art) {
                ForEach(Art.allCases, id: \.self) { Text($0.name).tag($0) }
            }

            TextField("Datum", value: $entwurf.datum, format: .deutsch)
            TextField("Titel", text: $entwurf.titel)
                .focused($fokus, equals: .titel)
            TextField("Gegenpartei", text: text(\.gegenparteiName))
                .focused($fokus, equals: .gegenpartei)
            TextField("Land", text: text(\.gegenparteiLand))
                .focused($fokus, equals: .land)
            TextField("USt-IdNr.", text: text(\.gegenparteiUstid))
                .focused($fokus, equals: .ustid)

            Picker("Kategorie", selection: $entwurf.kategorie) {
                Text("Keine").tag(String?.none)
                ForEach(Kategorie.fuer(entwurf.richtung)) { Text($0.name).tag(String?.some($0.schluessel)) }
                // A key that is not in the list still needs an entry, otherwise
                // choosing anything else would drop it silently.
                if let fremde = fremdeKategorie {
                    Text(Kategorie.name(fremde)).tag(String?.some(fremde))
                }
            }

            TextField("Privatanteil in Prozent", value: $entwurf.privatanteilProzent, format: .number)
        }
    }

    /// Changing the direction drops a category of the other side; an unknown
    /// key stays where it is.
    private var richtungBindung: Binding<Richtung> {
        Binding(
            get: { entwurf.richtung },
            set: { neu in
                entwurf.richtung = neu
                if let bekannt = Kategorie.alle.first(where: { $0.schluessel == entwurf.kategorie }),
                   bekannt.richtung != neu
                {
                    entwurf.kategorie = nil
                }
            }
        )
    }

    private var fremdeKategorie: String? {
        guard let schluessel = entwurf.kategorie else { return nil }
        return Kategorie.fuer(entwurf.richtung).contains { $0.schluessel == schluessel } ? nil : schluessel
    }

    // MARK: - Beträge

    private var betraege: some View {
        Section("Beträge") {
            HStack {
                Text("Netto").frame(maxWidth: .infinity, alignment: .leading)
                Text("Satz").frame(width: 70, alignment: .leading)
                Text("Steuer").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 16)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(entwurf.positionen.indices), id: \.self) { i in
                HStack {
                    TextField("Netto", value: nettoBindung(i), format: .euro)
                        .labelsHidden()
                    HStack(spacing: 2) {
                        TextField("Satz", value: satzBindung(i), format: .number)
                            .labelsHidden()
                        Text("%").foregroundStyle(.secondary)
                    }
                    .frame(width: 70)
                    TextField("Steuer", value: position(i, \.steuer, sonst: .null), format: .euro)
                        .labelsHidden()
                    Button("Position entfernen", systemImage: "minus.circle") { positionEntfernen(i) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(entwurf.positionen.count == 1)
                }
            }

            Button("Position hinzufügen", systemImage: "plus") {
                entwurf.positionen.append(Position(netto: .null, steuersatz: 19, steuer: .null))
            }

            if entwurf.waehrung != nil || fremdwaehrung {
                LabeledContent("Original") {
                    HStack {
                        TextField("Betrag", value: originalbetragBindung, format: .number.precision(.fractionLength(2)))
                            .labelsHidden()
                        TextField("Währung", text: text(\.waehrung))
                            .labelsHidden()
                            .focused($fokus, equals: .waehrung)
                            .frame(width: 60)
                    }
                }
            } else {
                Button("Fremdwährung…") { fremdwaehrung = true }
            }

            LabeledContent("Brutto", value: entwurf.brutto.formatiert)
        }
    }

    /// The tax follows the net amount and the rate, until the user overwrites it.
    private func nettoBindung(_ i: Int) -> Binding<Cent> {
        Binding(
            get: { position(i, \.netto, sonst: .null).wrappedValue },
            set: { neu in
                guard entwurf.positionen.indices.contains(i) else { return }
                entwurf.positionen[i].netto = neu
                entwurf.positionen[i].steuer = Position.steuer(netto: neu, steuersatz: entwurf.positionen[i].steuersatz)
            }
        )
    }

    /// A percentage, any rate the document shows, foreign ones included.
    private func satzBindung(_ i: Int) -> Binding<Decimal> {
        Binding(
            get: { position(i, \.steuersatz, sonst: 0).wrappedValue },
            set: { neu in
                guard entwurf.positionen.indices.contains(i) else { return }
                let satz = min(max(neu, 0), 100)
                entwurf.positionen[i].steuersatz = satz
                entwurf.positionen[i].steuer = Position.steuer(netto: entwurf.positionen[i].netto, steuersatz: satz)
            }
        )
    }

    private func positionEntfernen(_ i: Int) {
        guard entwurf.positionen.indices.contains(i) else { return }
        entwurf.positionen.remove(at: i)
    }

    private var originalbetragBindung: Binding<Decimal> {
        Binding(
            get: { Decimal(entwurf.originalbetrag ?? 0) / 100 },
            set: { entwurf.originalbetrag = NSDecimalNumber(decimal: $0 * 100).int64Value }
        )
    }

    // MARK: - Steuer

    private var steuer: some View {
        Section("Steuer") {
            Picker("Behandlung", selection: $entwurf.steuerbehandlung) {
                ForEach(Steuerbehandlung.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            LabeledContent("davon USt", value: entwurf.steuer.formatiert)
        }
    }

    // MARK: - Zahlungen

    private var zahlungen: some View {
        Section("Zahlungen") {
            ForEach(Array(entwurf.zahlungen.indices), id: \.self) { i in
                HStack {
                    TextField("Datum", value: zahlung(i, \.datum, sonst: .heute()), format: .deutsch)
                        .labelsHidden()
                        .frame(width: 90)
                    TextField("Betrag", value: zahlung(i, \.betrag, sonst: .null), format: .euro)
                        .labelsHidden()
                    Picker("Richtung", selection: zahlung(i, \.richtung, sonst: entwurf.richtung)) {
                        Text("Zahlung").tag(entwurf.richtung)
                        Text("Erstattung").tag(gegenrichtung)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Toggle("Geprüft", isOn: zahlung(i, \.geprueft, sonst: false))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help("Geprüft")
                    Button("Zahlung entfernen", systemImage: "minus.circle") { zahlungEntfernen(i) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }

            Button("Zahlung hinzufügen", systemImage: "plus") {
                entwurf.zahlungen.append(
                    Zahlung(datum: .heute(), betrag: .null, richtung: entwurf.richtung, geprueft: true)
                )
            }

            if entwurf.zahlungsstand != .bezahlt {
                Button("Vollständig bezahlt heute") {
                    entwurf.zahlungen.append(
                        Zahlung(
                            datum: .heute(),
                            betrag: entwurf.brutto - entwurf.gezahlt,
                            richtung: entwurf.richtung,
                            geprueft: true
                        )
                    )
                }
            }
        }
    }

    private func zahlungEntfernen(_ i: Int) {
        guard entwurf.zahlungen.indices.contains(i) else { return }
        entwurf.zahlungen.remove(at: i)
    }

    private var gegenrichtung: Richtung {
        entwurf.richtung == .einnahme ? .ausgabe : .einnahme
    }

    // MARK: - Notizen

    private var notizen: some View {
        Section("Notizen") {
            TextField("Notizen", text: text(\.notizen), axis: .vertical)
                .labelsHidden()
                .focused($fokus, equals: .notizen)
                .lineLimit(3 ... 8)
        }
    }

    // MARK: - Bestätigen

    @ViewBuilder private var bestaetigung: some View {
        if entwurf.geprueftAm == nil {
            VStack(spacing: 0) {
                Divider()
                Button("Bestätigen") {
                    sichern()
                    modell.bestaetigen(entwurf)
                }
                .buttonStyle(.borderedProminent)
                .padding(12)
            }
            .background(.bar)
        }
    }

    // MARK: - Bindungen

    /// A binding into one position of the draft. It answers with a fallback
    /// once the row is gone, so removing a row cannot read past the end of the
    /// list while the form is still showing it.
    private func position<Wert>(_ i: Int, _ pfad: WritableKeyPath<Position, Wert>, sonst: Wert) -> Binding<Wert> {
        Binding(
            get: { entwurf.positionen.indices.contains(i) ? entwurf.positionen[i][keyPath: pfad] : sonst },
            set: { neu in
                guard entwurf.positionen.indices.contains(i) else { return }
                entwurf.positionen[i][keyPath: pfad] = neu
            }
        )
    }

    /// The same for one payment.
    private func zahlung<Wert>(_ i: Int, _ pfad: WritableKeyPath<Zahlung, Wert>, sonst: Wert) -> Binding<Wert> {
        Binding(
            get: { entwurf.zahlungen.indices.contains(i) ? entwurf.zahlungen[i][keyPath: pfad] : sonst },
            set: { neu in
                guard entwurf.zahlungen.indices.contains(i) else { return }
                entwurf.zahlungen[i][keyPath: pfad] = neu
            }
        )
    }

    /// An optional text column is an empty field in the form and nil in the row.
    private func text(_ pfad: WritableKeyPath<Buchung, String?>) -> Binding<String> {
        Binding(
            get: { entwurf[keyPath: pfad] ?? "" },
            set: { entwurf[keyPath: pfad] = $0.isEmpty ? nil : $0 }
        )
    }
}

extension Steuerbehandlung {
    var name: String {
        switch self {
        case .inland: "Inland"
        case .reverseCharge: "Reverse Charge"
        case .kleinunternehmer: "Kleinunternehmer"
        case .steuerfrei: "Steuerfrei"
        case .nichtSteuerbar: "Nicht steuerbar"
        case .unklar: "Unklar"
        }
    }
}
