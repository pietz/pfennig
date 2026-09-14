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
    /// Positions whose rate the user types freely instead of picking it.
    @State private var freieSaetze: Set<Int> = []
    @FocusState private var titelFokus: Bool

    init(modell: AppModell, buchung: Buchung) {
        self.modell = modell
        self.buchung = buchung
        _entwurf = State(initialValue: buchung)
        _gesichert = State(initialValue: buchung)
    }

    var body: some View {
        Form {
            grunddaten
            betraege
            steuer
            zahlungen
            notizen
        }
        .formStyle(.grouped)
        .onSubmit(sichern)
        .onChange(of: buchung) { _, neu in
            // Follow the database unless the user has an unsaved edit in flight.
            if entwurf == gesichert {
                entwurf = neu
            }
            gesichert = neu
        }
        .onDisappear(perform: sichern)
        .onAppear {
            guard modell.fokusTitel else { return }
            modell.fokusTitel = false
            // The field exists only after this pass, so ask for focus in the next one.
            Task { titelFokus = true }
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
                ForEach(Art.allCases, id: \.self) { Text(beschriftung($0)).tag($0) }
            }

            TextField("Datum", value: $entwurf.datum, format: .deutsch)
            TextField("Titel", text: $entwurf.titel).focused($titelFokus)
            TextField("Gegenpartei", text: text(\.gegenparteiName))
            TextField("Land", text: text(\.gegenparteiLand))
            TextField("USt-IdNr.", text: text(\.gegenparteiUstid))

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
                Text("Satz").frame(width: 90, alignment: .leading)
                Text("Steuer").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 16)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(entwurf.positionen.indices), id: \.self) { i in
                HStack {
                    TextField("Netto", value: nettoBindung(i), format: .euro)
                        .labelsHidden()
                    satzfeld(i)
                    TextField("Steuer", value: $entwurf.positionen[i].steuer, format: .euro)
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

            if entwurf.waehrung != nil {
                LabeledContent("Original") {
                    HStack {
                        TextField("Betrag", value: originalbetragBindung, format: .number.precision(.fractionLength(2)))
                            .labelsHidden()
                        TextField("Währung", text: text(\.waehrung))
                            .labelsHidden()
                            .frame(width: 60)
                    }
                }
            }

            LabeledContent("Brutto", value: entwurf.brutto.formatiert)
        }
    }

    @ViewBuilder private func satzfeld(_ i: Int) -> some View {
        if freieSaetze.contains(i) || feldSaetze.contains(entwurf.positionen[i].steuersatz) == false {
            TextField("Satz", value: satzBindung(i), format: .number)
                .labelsHidden()
                .frame(width: 90)
        } else {
            Picker("Satz", selection: satzAuswahl(i)) {
                Text("0 %").tag(Decimal?.some(0))
                Text("7 %").tag(Decimal?.some(7))
                Text("19 %").tag(Decimal?.some(19))
                Text("anderer").tag(Decimal?.none)
            }
            .labelsHidden()
            .frame(width: 90)
        }
    }

    private let feldSaetze: [Decimal] = [0, 7, 19]

    /// The tax follows the net amount and the rate, until the user overwrites it.
    private func nettoBindung(_ i: Int) -> Binding<Cent> {
        Binding(
            get: { entwurf.positionen[i].netto },
            set: { neu in
                entwurf.positionen[i].netto = neu
                entwurf.positionen[i].steuer = Position.steuer(netto: neu, steuersatz: entwurf.positionen[i].steuersatz)
            }
        )
    }

    private func satzBindung(_ i: Int) -> Binding<Decimal> {
        Binding(
            get: { entwurf.positionen[i].steuersatz },
            set: { neu in
                entwurf.positionen[i].steuersatz = neu
                entwurf.positionen[i].steuer = Position.steuer(netto: entwurf.positionen[i].netto, steuersatz: neu)
                if feldSaetze.contains(neu) {
                    freieSaetze.remove(i)
                }
            }
        )
    }

    private func satzAuswahl(_ i: Int) -> Binding<Decimal?> {
        Binding(
            get: { entwurf.positionen[i].steuersatz },
            set: { neu in
                guard let neu else {
                    freieSaetze.insert(i)
                    return
                }
                satzBindung(i).wrappedValue = neu
            }
        )
    }

    private func positionEntfernen(_ i: Int) {
        entwurf.positionen.remove(at: i)
        freieSaetze = []
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
                ForEach(Steuerbehandlung.allCases, id: \.self) { Text(beschriftung($0)).tag($0) }
            }
            LabeledContent("davon USt", value: entwurf.steuer.formatiert)
        }
    }

    // MARK: - Zahlungen

    private var zahlungen: some View {
        Section("Zahlungen") {
            ForEach(Array(entwurf.zahlungen.indices), id: \.self) { i in
                HStack {
                    TextField("Datum", value: $entwurf.zahlungen[i].datum, format: .deutsch)
                        .labelsHidden()
                        .frame(width: 90)
                    TextField("Betrag", value: $entwurf.zahlungen[i].betrag, format: .euro)
                        .labelsHidden()
                    Picker("Richtung", selection: $entwurf.zahlungen[i].richtung) {
                        Text("Zahlung").tag(entwurf.richtung)
                        Text("Erstattung").tag(gegenrichtung)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Toggle("Geprüft", isOn: $entwurf.zahlungen[i].geprueft)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help("Geprüft")
                    Button("Zahlung entfernen", systemImage: "minus.circle") { entwurf.zahlungen.remove(at: i) }
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

    private var gegenrichtung: Richtung {
        entwurf.richtung == .einnahme ? .ausgabe : .einnahme
    }

    // MARK: - Notizen

    private var notizen: some View {
        Section("Notizen") {
            TextField("Notizen", text: text(\.notizen), axis: .vertical)
                .labelsHidden()
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

    // MARK: - Kleinkram

    /// An optional text column is an empty field in the form and nil in the row.
    private func text(_ pfad: WritableKeyPath<Buchung, String?>) -> Binding<String> {
        Binding(
            get: { entwurf[keyPath: pfad] ?? "" },
            set: { entwurf[keyPath: pfad] = $0.isEmpty ? nil : $0 }
        )
    }

    private func beschriftung(_ art: Art) -> String {
        switch art {
        case .rechnung: "Rechnung"
        case .beleg: "Beleg"
        case .gutschrift: "Gutschrift"
        case .steuerzahlung: "Steuerzahlung"
        case .nurZahlung: "Nur Zahlung"
        case .ignoriert: "Ignoriert"
        case .sonstiges: "Sonstiges"
        }
    }

    private func beschriftung(_ behandlung: Steuerbehandlung) -> String {
        switch behandlung {
        case .inland: "Inland"
        case .reverseCharge: "Reverse Charge"
        case .kleinunternehmer: "Kleinunternehmer"
        case .steuerfrei: "Steuerfrei"
        case .nichtSteuerbar: "Nicht steuerbar"
        case .unklar: "Unklar"
        }
    }
}
