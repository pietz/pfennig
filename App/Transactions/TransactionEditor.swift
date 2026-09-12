import Database
import Domain
import ImportPipeline
import SwiftUI

/// Create or edit a transaction by hand (spec 39 M3, 44). The same sheet
/// serves "Neue Buchung" and "Bearbeiten"; everything it shows is derived
/// from the draft it edits.
struct TransactionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TransactionDraft
    @State private var servicePeriod: ServicePeriodKind
    @State private var lastEditedAmount: AmountField?

    private enum ServicePeriodKind: String, CaseIterable, Identifiable {
        case none, date, period
        var id: String {
            rawValue
        }

        var label: LocalizedStringKey {
            switch self {
            case .none: "Ohne"
            case .date: "Datum"
            case .period: "Zeitraum"
            }
        }
    }

    private enum AmountField { case net, tax, gross }

    init(draft: TransactionDraft) {
        _draft = State(initialValue: draft)
        _servicePeriod = State(
            initialValue: draft.servicePeriodStart != nil ? .period : (draft.serviceDate != nil ? .date : .none)
        )
    }

    private var isNew: Bool {
        draft.id == nil
    }

    private var derived: DerivedTransaction? {
        model.derive(draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Neue Buchung" : "Buchung bearbeiten").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            Form {
                counterpartySection
                datesSection
                amountsSection
                componentsSection
                allocationsSection
                taxSection
                notesSection
                issuesSection
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 660, height: 720)
    }

    // MARK: - Sections

    private var counterpartySection: some View {
        Section {
            TextField("Gegenpartei", text: $draft.counterpartyName, prompt: Text("Firma oder Person"))
            TextField("Land", text: $draft.counterpartyCountryCode.orEmpty, prompt: Text("DE"))
            TextField("USt-IdNr.", text: $draft.counterpartyVatId.orEmpty, prompt: Text("optional"))
            Picker("Richtung", selection: $draft.direction) {
                Text("Ausgabe").tag(Direction.expense)
                Text("Einnahme").tag(Direction.income)
            }
            .pickerStyle(.segmented)
            Picker("Art", selection: $draft.transactionType) {
                ForEach(TransactionType.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            TextField("Titel", text: $draft.title.orEmpty, prompt: Text("Kurzbeschreibung"))
            TextField("Rechnungsnummer", text: $draft.invoiceNumber.orEmpty, prompt: Text("optional"))
        }
    }

    private var datesSection: some View {
        Section {
            OptionalDateField(label: "Rechnungsdatum", date: $draft.invoiceDate)
            Picker("Leistung", selection: $servicePeriod) {
                ForEach(ServicePeriodKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: servicePeriod) { _, kind in
                switch kind {
                case .none:
                    draft.serviceDate = nil
                    draft.servicePeriodStart = nil
                    draft.servicePeriodEnd = nil
                case .date:
                    draft.serviceDate = draft.serviceDate ?? draft.servicePeriodEnd ?? draft.invoiceDate ?? .today()
                    draft.servicePeriodStart = nil
                    draft.servicePeriodEnd = nil
                case .period:
                    draft.servicePeriodStart = draft.servicePeriodStart ?? draft.serviceDate ?? .today()
                    draft.servicePeriodEnd = draft.servicePeriodEnd ?? draft.servicePeriodStart
                    draft.serviceDate = nil
                }
            }
            switch servicePeriod {
            case .none:
                EmptyView()
            case .date:
                OptionalDateField(label: "Leistungsdatum", date: $draft.serviceDate)
            case .period:
                OptionalDateField(label: "Leistung von", date: $draft.servicePeriodStart)
                OptionalDateField(label: "Leistung bis", date: $draft.servicePeriodEnd)
            }
            Toggle("Anzahlung", isOn: $draft.isAdvancePayment)
        }
    }

    private var amountsSection: some View {
        Section("Beträge") {
            Picker("Währung", selection: $draft.currency) {
                ForEach(["EUR", "USD", "GBP", "CHF"], id: \.self) { Text($0).tag(CurrencyCode($0)) }
            }
            MoneyField(label: "Netto", minor: $draft.netMinor, currency: draft.currency) {
                completeAmounts(after: .net)
            }
            MoneyField(label: "Steuer", minor: $draft.taxMinor, currency: draft.currency) {
                completeAmounts(after: .tax)
            }
            MoneyField(label: "Brutto", minor: $draft.grossMinor, currency: draft.currency) {
                completeAmounts(after: .gross)
            }
        }
    }

    private var componentsSection: some View {
        Section {
            ForEach($draft.components) { $component in
                HStack(spacing: 8) {
                    Picker("", selection: $component.rate) {
                        Text("19 %").tag(String?.some("19"))
                        Text("7 %").tag(String?.some("7"))
                        Text("0 %").tag(String?.some("0"))
                    }
                    .labelsHidden()
                    .frame(width: 80)
                    .onChange(of: component.rate) { _, rate in
                        component.kind = TaxComponentDraft.kind(forRate: rate)
                    }
                    Picker("", selection: $component.kind) {
                        ForEach(TaxComponentKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    MoneyField(label: "Netto", minor: optional($component.netMinor), currency: draft.currency)
                    MoneyField(label: "Steuer", minor: optional($component.taxMinor), currency: draft.currency)
                    Button {
                        draft.components.removeAll { $0.id == component.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Steuerkomponente hinzufügen") {
                draft.components.append(TaxComponentDraft(rate: "19"))
            }
        } header: {
            Text("Steuerkomponenten")
        } footer: {
            Text("Was der Beleg je Steuersatz ausweist – z. B. 7 % Übernachtung und 19 % Frühstück.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var allocationsSection: some View {
        Section {
            ForEach($draft.allocations) { $allocation in
                HStack(spacing: 8) {
                    Picker("", selection: $allocation.categoryId) {
                        ForEach(categoryOptions) { Text($0.nameDe).tag($0.id) }
                    }
                    .labelsHidden()
                    MoneyField(label: "Betrag", minor: optional($allocation.amountMinor), currency: draft.currency)
                    Button {
                        draft.allocations.removeAll { $0.id == allocation.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(draft.allocations.count == 1)
                }
            }
            Button("Aufteilung hinzufügen") {
                draft.allocations.append(AllocationDraft(amountMinor: remainingAllocation))
            }
        } header: {
            Text("Aufteilung")
        }
    }

    private var taxSection: some View {
        Section("Steuer") {
            Picker("Behandlung", selection: $draft.treatmentOverride) {
                Text("Automatisch").tag(TaxTreatment?.none)
                Divider()
                ForEach(TaxTreatment.allCases.filter { $0 != .smallBusiness }, id: \.self) {
                    Text($0.label).tag(TaxTreatment?.some($0))
                }
            }
            if let derived, let assessment = derived.draft.assessment {
                if derived.isTreatmentAutomatic {
                    LabeledContent("Entschieden als") {
                        Text(assessment.treatment.label)
                    }
                }
                if let reasoning = assessment.reasoning ?? derived.reasoning {
                    Text(reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let selfAssessed = assessment.selfAssessedVatMinor {
                    LabeledContent("Selbst berechnete USt.") {
                        Text(Format.money(selfAssessed, currency: draft.currency))
                    }
                }
                if let inputVATDate = assessment.inputVatDate {
                    LabeledContent("Vorsteuer-Zeitpunkt") {
                        Text(Format.date(inputVATDate))
                    }
                }
                if let outputVATDate = assessment.outputVatDate {
                    LabeledContent("Umsatzsteuer-Zeitpunkt") {
                        Text(Format.date(outputVATDate))
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notizen") {
            TextField("Notiz", text: $draft.notes.orEmpty, prompt: Text("optional"), axis: .vertical)
                .lineLimit(2 ... 5)
                .labelsHidden()
        }
    }

    private var issuesSection: some View {
        Section("Hinweise") {
            if let derived, !derived.issues.isEmpty {
                ForEach(derived.issues.indices, id: \.self) { index in
                    IssueRow(severity: derived.issues[index].severity, message: derived.issues[index].message)
                }
            } else {
                Label("Keine Hinweise", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Behaviour

    private var canSave: Bool {
        !draft.counterpartyName.trimmingCharacters(in: .whitespaces).isEmpty && derived?.canSave == true
    }

    private var categoryOptions: [Database.Category] {
        model.categories.filter { category in
            switch draft.direction {
            case .income: category.kind == .income || category.kind == .neutral
            case .expense, .unknown: category.kind != .income
            }
        }
    }

    private var remainingAllocation: Int64 {
        let target = draft.netMinor ?? draft.grossMinor ?? 0
        return target - draft.allocations.reduce(0) { $0 + $1.amountMinor }
    }

    /// Fills the value the user did not type and keeps the single default
    /// component and allocation in step with the amounts.
    private func completeAmounts(after field: AmountField) {
        lastEditedAmount = field
        switch field {
        case .net:
            if let net = draft.netMinor, let tax = draft.taxMinor {
                draft.grossMinor = net + tax
            } else if let net = draft.netMinor, let gross = draft.grossMinor {
                draft.taxMinor = gross - net
            }
        case .tax:
            if let net = draft.netMinor, let tax = draft.taxMinor {
                draft.grossMinor = net + tax
            }
        case .gross:
            if let gross = draft.grossMinor, let net = draft.netMinor {
                draft.taxMinor = gross - net
            } else if let gross = draft.grossMinor, let tax = draft.taxMinor {
                draft.netMinor = gross - tax
            }
        }
        draft.completeAmounts()
        syncDefaultRows()
    }

    /// A single component/allocation is a default that follows the amounts;
    /// as soon as the user splits either list, it is left alone.
    private func syncDefaultRows() {
        let net = draft.netMinor ?? 0
        let tax = draft.taxMinor ?? 0
        if draft.components.count <= 1 {
            let rate = Self.rate(net: net, tax: tax)
            var component = draft.components.first ?? TaxComponentDraft()
            component.rate = rate
            component.kind = TaxComponentDraft.kind(forRate: rate)
            component.netMinor = net
            component.taxMinor = tax
            draft.components = [component]
        }
        if draft.allocations.count <= 1 {
            var allocation = draft.allocations.first ?? AllocationDraft()
            allocation.amountMinor = draft.netMinor ?? draft.grossMinor ?? 0
            draft.allocations = [allocation]
        }
    }

    /// The rate implied by a net/tax pair, rounded to whole percent.
    private static func rate(net: Int64, tax: Int64) -> String? {
        guard net != 0, tax != 0 else { return "0" }
        let percent = (Decimal(tax) * 100 / Decimal(net)).rounded()
        return "\(percent)"
    }

    private func save() {
        guard model.save(draft) != nil else { return }
        dismiss()
    }

    /// Bridges a non-optional amount to `MoneyField`'s optional binding.
    private func optional(_ binding: Binding<Int64>) -> Binding<Int64?> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0 ?? 0 })
    }
}

private extension Decimal {
    func rounded() -> Int {
        NSDecimalNumber(decimal: Money.roundHalfUp(self)).intValue
    }
}
