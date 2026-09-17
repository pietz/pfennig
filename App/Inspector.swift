import AppKit
import Combine
import Core
import SwiftUI

/// The inspector of the selected booking. It edits a draft and writes it back
/// through the repository as soon as the user commits a field; there is no
/// save and no discard.
struct Inspector: View {
    let model: AppModel
    let buchung: Buchung

    @State private var draft: Buchung
    /// The last state that went to the database. It separates a real edit from
    /// the timestamps the repository sets with every write.
    @State private var savedBaseline: Buchung
    /// True once the user asked for the foreign currency line on a booking
    /// that does not carry one yet.
    @State private var foreignCurrency = false
    @State private var originalAmountText: String
    @State private var dueDateText: String
    /// A plain text field writes into the draft with every keystroke. The
    /// draft goes to the database when the field is submitted or loses focus,
    /// so the table shows the change right away.
    @FocusState private var focus: Field?

    private enum Field {
        case titel
        case belegnummer
        case faelligkeit
        case gegenpartei
        case land
        case ustid
        case waehrung
        case originalbetrag
        case notizen
    }

    init(model: AppModel, buchung: Buchung) {
        self.model = model
        self.buchung = buchung
        _draft = State(initialValue: buchung)
        _savedBaseline = State(initialValue: buchung)
        _originalAmountText = State(initialValue: buchung.originalbetrag?.deutschFormatiert ?? "")
        _dueDateText = State(initialValue: buchung.faelligkeit?.formatted ?? "")
    }

    var body: some View {
        Form {
            // An edit after the values of the period went to the tax office.
            if model.changedAfterExport(buchung) {
                Label("Nach dem Export des Zeitraums geändert", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if buchung.belege.isEmpty == false {
                ReceiptSection(model: model, buchung: buchung)
            }
            grunddaten
            betraege
            steuer
            zahlungen
            notizen
        }
        .formStyle(.grouped)
        .onSubmit(save)
        .onChange(of: focus) { save() }
        .onChange(of: buchung) { _, updated in
            // The database is authoritative, even if local typing is unsaved.
            // Keep the draft and baseline in lockstep so this refresh cannot save itself.
            draft = updated
            savedBaseline = updated
            originalAmountText = updated.originalbetrag?.deutschFormatiert ?? ""
            dueDateText = updated.faelligkeit?.formatted ?? ""
        }
        .onDisappear(perform: save)
        // Quitting must not swallow a field the user typed but never committed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            save()
        }
        // Controls other than the free text fields commit the moment they change.
        .onChange(of: draft.richtung) { save() }
        .onChange(of: draft.art) { save() }
        .onChange(of: draft.datum) { save() }
        .onChange(of: draft.kategorie) { save() }
        .onChange(of: draft.privatanteilProzent) { save() }
        .onChange(of: draft.nutzungsdauerJahre) { save() }
        .onChange(of: draft.positionen) { save() }
        .onChange(of: draft.steuerbehandlung) { save() }
        .onChange(of: draft.zahlungen) { save() }
        .safeAreaInset(edge: .bottom) { confirmBar }
    }

    private func save() {
        applyOriginalAmount()
        applyDueDate()
        guard draft != savedBaseline else { return }
        guard model.buchungen.contains(where: { $0.id == draft.id }) else { return }
        guard let saved = model.save(draft) else { return }
        draft = saved
        savedBaseline = saved
    }

    // MARK: - Grunddaten

    private var grunddaten: some View {
        Section("Grunddaten") {
            Picker("Richtung", selection: directionBinding) {
                Text("Einnahme").tag(Richtung.einnahme)
                Text("Ausgabe").tag(Richtung.ausgabe)
            }
            .pickerStyle(.segmented)

            Picker("Art", selection: $draft.art) {
                ForEach(Art.allCases, id: \.self) { Text($0.name).tag($0) }
            }

            TextField("Datum", value: $draft.datum, format: .deutsch)
            TextField("Titel", text: $draft.titel)
                .focused($focus, equals: .titel)
            TextField("Belegnummer", text: text(\.belegnummer))
                .focused($focus, equals: .belegnummer)
            HStack {
                TextField("Fälligkeit", text: $dueDateText)
                    .focused($focus, equals: .faelligkeit)
                if draft.istUeberfaellig {
                    Label("Überfällig", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            TextField("Gegenpartei", text: text(\.gegenparteiName))
                .focused($focus, equals: .gegenpartei)
            TextField("Land", text: text(\.gegenparteiLand))
                .focused($focus, equals: .land)
            TextField("USt-IdNr.", text: text(\.gegenparteiUstid))
                .focused($focus, equals: .ustid)

            Picker("Kategorie", selection: $draft.kategorie) {
                Text("Keine").tag(String?.none)
                ForEach(Kategorie.fuer(draft.richtung)) { Text($0.name).tag(String?.some($0.schluessel)) }
                // A key that is not in the list still needs an entry, otherwise
                // choosing anything else would drop it silently.
                if let fremde = foreignCategory {
                    Text(Kategorie.name(fremde)).tag(String?.some(fremde))
                }
            }

            TextField("Privatanteil in Prozent", value: $draft.privatanteilProzent, format: .number)
            if draft.richtung == .ausgabe {
                TextField("Nutzungsdauer in Jahren", value: $draft.nutzungsdauerJahre, format: .number)
            }
        }
    }

    /// Changing the direction drops a category of the other side; an unknown
    /// key stays where it is.
    private var directionBinding: Binding<Richtung> {
        Binding(
            get: { draft.richtung },
            set: { updated in
                draft.richtung = updated
                if let known = Kategorie.alle.first(where: { $0.schluessel == draft.kategorie }),
                   known.richtung != updated
                {
                    draft.kategorie = nil
                }
            }
        )
    }

    private var foreignCategory: String? {
        guard let key = draft.kategorie else { return nil }
        return Kategorie.fuer(draft.richtung).contains { $0.schluessel == key } ? nil : key
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

            ForEach(Array(draft.positionen.indices), id: \.self) { i in
                HStack {
                    TextField("Netto", value: netBinding(i), format: .euro)
                        .labelsHidden()
                    HStack(spacing: 2) {
                        TextField("Satz", value: rateBinding(i), format: .number)
                            .labelsHidden()
                        Text("%").foregroundStyle(.secondary)
                    }
                    .frame(width: 70)
                    TextField("Steuer", value: position(i, \.steuer, fallback: .null), format: .euro)
                        .labelsHidden()
                    Button("Position entfernen", systemImage: "minus.circle") { removePosition(i) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(draft.positionen.count == 1)
                }
            }

            Button("Position hinzufügen", systemImage: "plus") {
                draft.positionen.append(Position(netto: .null, steuersatz: 19, steuer: .null))
            }

            if draft.waehrung != nil || draft.originalbetrag != nil || foreignCurrency {
                LabeledContent("Original") {
                    HStack {
                        TextField("Betrag", text: $originalAmountText)
                            .labelsHidden()
                            .focused($focus, equals: .originalbetrag)
                        TextField("Währung", text: text(\.waehrung))
                            .labelsHidden()
                            .focused($focus, equals: .waehrung)
                            .frame(width: 60)
                    }
                }
            } else {
                Button("Fremdwährung…") { foreignCurrency = true }
            }

            LabeledContent("Brutto", value: draft.brutto.formatted)
        }
    }

    /// The tax follows the net amount and the rate, until the user overwrites it.
    private func netBinding(_ i: Int) -> Binding<Cent> {
        Binding(
            get: { position(i, \.netto, fallback: .null).wrappedValue },
            set: { updated in
                guard draft.positionen.indices.contains(i) else { return }
                draft.positionen[i].netto = updated
                draft.positionen[i].steuer = Position.steuer(netto: updated, steuersatz: draft.positionen[i].steuersatz)
            }
        )
    }

    /// A percentage, any rate the document shows, foreign ones included.
    private func rateBinding(_ i: Int) -> Binding<Decimal> {
        Binding(
            get: { position(i, \.steuersatz, fallback: 0).wrappedValue },
            set: { updated in
                guard draft.positionen.indices.contains(i) else { return }
                let satz = min(max(updated, 0), 100)
                draft.positionen[i].steuersatz = satz
                draft.positionen[i].steuer = Position.steuer(netto: draft.positionen[i].netto, steuersatz: satz)
            }
        )
    }

    private func removePosition(_ i: Int) {
        guard draft.positionen.indices.contains(i) else { return }
        draft.positionen.remove(at: i)
    }

    private func applyOriginalAmount() {
        let text = originalAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            draft.originalbetrag = nil
            return
        }
        guard let value = Decimal(text: text) else {
            originalAmountText = draft.originalbetrag?.deutschFormatiert ?? ""
            return
        }
        draft.originalbetrag = value
    }

    private func applyDueDate() {
        let text = dueDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            draft.faelligkeit = nil
            return
        }
        guard let value = LocalDate(deutsch: text) else {
            dueDateText = draft.faelligkeit?.formatted ?? ""
            return
        }
        draft.faelligkeit = value
    }

    // MARK: - Steuer

    private var steuer: some View {
        Section("Steuer") {
            Picker("Behandlung", selection: $draft.steuerbehandlung) {
                ForEach(Steuerbehandlung.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            LabeledContent("davon USt", value: draft.steuer.formatted)
        }
    }

    // MARK: - Zahlungen

    private var zahlungen: some View {
        Section("Zahlungen") {
            ForEach(Array(draft.zahlungen.indices), id: \.self) { i in
                HStack {
                    TextField("Datum", value: zahlung(i, \.datum, fallback: .today()), format: .deutsch)
                        .labelsHidden()
                        .frame(width: 90)
                    TextField("Betrag", value: zahlung(i, \.betrag, fallback: .null), format: .euro)
                        .labelsHidden()
                    Text(draft.zahlungen[i].betrag < .null ? "Erstattung" : "Zahlung")
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Button("Zahlung entfernen", systemImage: "minus.circle") { removePayment(i) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }

            Button("Zahlung hinzufügen", systemImage: "plus") {
                draft.zahlungen.append(Zahlung(datum: .today(), betrag: .null))
            }

            if draft.zahlungsstand != .bezahlt {
                Button("Vollständig bezahlt heute") {
                    draft.zahlungen.append(
                        Zahlung(
                            datum: .today(),
                            betrag: draft.brutto - draft.gezahlt
                        )
                    )
                }
            }
        }
    }

    private func removePayment(_ i: Int) {
        guard draft.zahlungen.indices.contains(i) else { return }
        draft.zahlungen.remove(at: i)
    }

    // MARK: - Notizen

    private var notizen: some View {
        Section("Notizen") {
            TextField("Notizen", text: text(\.notizen), axis: .vertical)
                .labelsHidden()
                .focused($focus, equals: .notizen)
                .lineLimit(3 ... 8)
        }
    }

    // MARK: - Bestätigen

    @ViewBuilder private var confirmBar: some View {
        if draft.geprueftAm == nil {
            VStack(spacing: 0) {
                Divider()
                Button {
                    save()
                    model.confirm(draft)
                } label: {
                    Text("Bestätigen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(12)
            }
            .background(.bar)
        }
    }

    // MARK: - Bindings

    /// A binding into one position of the draft. It answers with a fallback
    /// once the row is gone, so removing a row cannot read past the end of the
    /// list while the form is still showing it.
    private func position<Value>(
        _ i: Int,
        _ path: WritableKeyPath<Position, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { draft.positionen.indices.contains(i) ? draft.positionen[i][keyPath: path] : fallback },
            set: { updated in
                guard draft.positionen.indices.contains(i) else { return }
                draft.positionen[i][keyPath: path] = updated
            }
        )
    }

    /// The same for one payment.
    private func zahlung<Value>(_ i: Int, _ path: WritableKeyPath<Zahlung, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { draft.zahlungen.indices.contains(i) ? draft.zahlungen[i][keyPath: path] : fallback },
            set: { updated in
                guard draft.zahlungen.indices.contains(i) else { return }
                draft.zahlungen[i][keyPath: path] = updated
            }
        )
    }

    /// An optional text column is an empty field in the form and nil in the row.
    private func text(_ path: WritableKeyPath<Buchung, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: path] ?? "" },
            set: { draft[keyPath: path] = $0.isEmpty ? nil : $0 }
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
