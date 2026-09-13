import AppKit
import Database
import DocumentStore
import Domain
import ImportPipeline
import PDFKit
import SwiftUI

/// What the inspector currently edits.
enum InspectorSubject: Equatable {
    case none
    case transaction(TransactionDetail)
    case proposal(ProposalRecord)
    /// A new, unsaved transaction created with Cmd+N.
    case draft

    var key: String {
        switch self {
        case .none: "none"
        case let .transaction(detail): "t-\(detail.id)-\(detail.transaction.updatedAt)"
        case let .proposal(proposal): "p-\(proposal.id)-\(proposal.updatedAt)"
        case .draft: "draft"
        }
    }

    /// Stable identity used to distinguish a database refresh from selecting
    /// a different subject. Refreshes must not replace an in-progress draft.
    var identity: String {
        switch self {
        case .none: "none"
        case let .transaction(detail): "t-\(detail.id)"
        case let .proposal(proposal): "p-\(proposal.id)"
        case .draft: "draft"
        }
    }
}

/// The inspector of one transaction or proposal (spec 6.4, 27). Editing
/// happens inline: every field is a control, provenance sits next to it
/// (spec 8.3), and the footer offers what the subject allows.
struct TransactionInspector: View {
    @Environment(AppModel.self) private var model

    let subject: InspectorSubject
    @Binding var newDraft: TransactionDraft?

    @State private var draft = TransactionDraft(businessProfileId: "")
    @State private var original = TransactionDraft(businessProfileId: "")
    @State private var addingPayment = false
    @State private var invalidMoneyFields: Set<String> = []
    @State private var loadedSubjectIdentity: String?
    @State private var loadedProposalUpdatedAt: String?
    @State private var operationError: String?

    private var derived: DerivedTransaction? {
        model.derive(draft)
    }

    private var hasChanges: Bool {
        draft != original
    }

    private var isProposal: Bool {
        if case .proposal = subject {
            return true
        }
        return false
    }

    var body: some View {
        Group {
            if case .none = subject {
                ContentUnavailableView(
                    "Keine Buchung ausgewählt",
                    systemImage: "sidebar.trailing",
                    description: Text("Wählen Sie eine Zeile, oder ziehen Sie einen Beleg in das Fenster.")
                )
            } else {
                VStack(spacing: 0) {
                    Form {
                        documentSection
                        fieldsSection
                        amountsSection
                        allocationsSection
                        taxSection
                        if case let .transaction(detail) = subject {
                            paymentsSection(detail)
                        }
                        issuesSection
                        if case let .transaction(detail) = subject {
                            historySection(detail)
                        }
                    }
                    .formStyle(.grouped)
                    footer
                }
            }
        }
        .sheet(isPresented: $addingPayment) {
            if case .transaction = subject {
                PaymentEditor(draft: $draft) { savedDraft in
                    draft = savedDraft
                    original = savedDraft
                    operationError = nil
                }
            }
        }
        .onChange(of: subject.key, initial: true) { _, _ in
            if loadedSubjectIdentity != subject.identity || !hasChanges {
                load()
            }
        }
        .onChange(of: draft) { _, value in
            operationError = nil
            if case .draft = subject {
                newDraft = value
            }
        }
    }

    // MARK: - Beleg

    @ViewBuilder
    private var documentSection: some View {
        if let path = documentPath, let archive = model.archive {
            Section("Beleg") {
                DocumentPreview(url: archive.url(forRelativePath: path))
                if let name = documentName {
                    LabeledContent("Datei") {
                        Text(name).lineLimit(1).truncationMode(.middle)
                    }
                }
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([archive.url(forRelativePath: path)])
                }
            }
        } else if case .transaction = subject {
            Section("Beleg") {
                Label("Kein Beleg", systemImage: "doc.badge.plus").foregroundStyle(.secondary)
                Button("Beleg anhängen") { attachDocument() }
                    .disabled(!moneyFieldsAreValid)
            }
        }
    }

    private func attachDocument() {
        guard moneyFieldsAreValid else {
            operationError = "Bitte korrigieren Sie die ungültigen Beträge, bevor Sie einen Beleg anhängen."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentStore.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Anhängen"
        panel.message = "Beleg zu dieser Buchung auswählen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let updatedDraft = model.attachDocument(at: url, to: draft) else {
            operationError = "Beleg konnte nicht gespeichert werden. Ihre Änderungen bleiben erhalten."
            return
        }
        draft = updatedDraft
        original = updatedDraft
        operationError = nil
    }

    private func paymentsSection(_ detail: TransactionDetail) -> some View {
        Section("Zahlungen") {
            if detail.payments.isEmpty {
                Label("Keine Zahlung erfasst", systemImage: "circle").foregroundStyle(.secondary)
            }
            ForEach(detail.payments) { entry in
                LabeledContent(Format.date(entry.payment.paymentDate)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.allocated.formatted(locale: Format.german)).monospacedDigit()
                        Text(
                            [entry.accountName, entry.payment.paymentMethod?.text, entry.payment.reference]
                                .compactMap(\.self)
                                .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Zahlung hinzufügen") {
                operationError = nil
                addingPayment = true
            }
            .disabled(!moneyFieldsAreValid)
        }
    }

    private var documentPath: String? {
        switch subject {
        case let .transaction(detail): detail.documents.first?.document.relativePath
        case let .proposal(proposal): proposal.summary?.documentRelativePath
        default: nil
        }
    }

    private var documentName: String? {
        switch subject {
        case let .transaction(detail): detail.documents.first?.document.originalFilename
        case let .proposal(proposal): proposal.summary?.originalFilename
        default: nil
        }
    }

    // MARK: - Felder

    private var fieldsSection: some View {
        Section("Felder") {
            field("counterpartyId") {
                TextField("Firma", text: $draft.counterpartyName, prompt: Text("Firma oder Person"))
            }
            TextField("Land", text: $draft.counterpartyCountryCode.orEmpty, prompt: Text("DE"))
            TextField("USt-IdNr.", text: $draft.counterpartyVatId.orEmpty, prompt: Text("optional"))
            field("direction") {
                Picker("Richtung", selection: $draft.direction) {
                    Text("Ausgabe").tag(Direction.expense)
                    Text("Einnahme").tag(Direction.income)
                }
            }
            field("transactionType") {
                Picker("Art", selection: $draft.transactionType) {
                    ForEach(TransactionType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            TextField("Titel", text: $draft.title.orEmpty, prompt: Text("Kurzbeschreibung"))
            field("invoiceNumber") {
                TextField("Rechnungsnummer", text: $draft.invoiceNumber.orEmpty, prompt: Text("optional"))
            }
            field("invoiceDate") {
                OptionalDateField(label: "Rechnungsdatum", date: $draft.invoiceDate)
            }
            OptionalDateField(label: "Leistungsdatum", date: $draft.serviceDate)
            OptionalDateField(label: "Leistung von", date: $draft.servicePeriodStart)
            OptionalDateField(label: "Leistung bis", date: $draft.servicePeriodEnd)
            TextField("Notiz", text: $draft.notes.orEmpty, prompt: Text("optional"), axis: .vertical)
                .lineLimit(1 ... 4)
        }
    }

    private var amountsSection: some View {
        Section("Beträge") {
            Picker("Währung", selection: $draft.currency) {
                ForEach(["EUR", "USD", "GBP", "CHF"], id: \.self) { Text($0).tag(CurrencyCode($0)) }
            }
            field("netAmount") {
                MoneyField(
                    label: "Netto",
                    minor: $draft.netMinor,
                    currency: draft.currency,
                    onValidityChange: { setMoneyFieldValidity("netAmount", isValid: $0) }
                )
            }
            field("taxAmount") {
                MoneyField(
                    label: "Steuer",
                    minor: $draft.taxMinor,
                    currency: draft.currency,
                    onValidityChange: { setMoneyFieldValidity("taxAmount", isValid: $0) }
                )
            }
            field("grossAmount") {
                MoneyField(
                    label: "Brutto",
                    minor: $draft.grossMinor,
                    currency: draft.currency,
                    onValidityChange: { setMoneyFieldValidity("grossAmount", isValid: $0) }
                )
            }
            ForEach(draft.components) { component in
                LabeledContent("\(component.rate ?? "–") %") {
                    Text(
                        Format.money(component.netMinor, currency: draft.currency) + " + "
                            + Format.money(component.taxMinor, currency: draft.currency)
                    )
                    .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var allocationsSection: some View {
        Section("Aufteilung") {
            ForEach($draft.allocations) { $allocation in
                HStack(spacing: 8) {
                    Picker("", selection: $allocation.categoryId) {
                        ForEach(categoryOptions) { Text($0.nameDe).tag($0.id) }
                    }
                    .labelsHidden()
                    MoneyField(
                        label: "Betrag",
                        minor: Binding(
                            get: { allocation.amountMinor },
                            set: { allocation.amountMinor = $0 ?? 0 }
                        ),
                        currency: draft.currency,
                        onValidityChange: {
                            setMoneyFieldValidity("allocation.\(allocation.id)", isValid: $0)
                        }
                    )
                    ProvenanceBadge(provenance: isProposal ? .agent : nil)
                }
            }
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
            if let assessment = derived?.draft.assessment {
                LabeledContent("Entschieden als") {
                    HStack(spacing: 6) {
                        Text(assessment.treatment.label)
                        ProvenanceBadge(provenance: treatmentProvenance)
                    }
                }
                if let reasoning = assessment.reasoning ?? derived?.reasoning {
                    Text(reasoning).font(.callout).foregroundStyle(.secondary)
                }
                if let selfAssessed = assessment.selfAssessedVatMinor {
                    LabeledContent("Selbst berechnete USt.") {
                        Text(Format.money(selfAssessed, currency: draft.currency))
                    }
                }
                if let deductible = assessment.deductibleInputVatMinor {
                    LabeledContent("Abziehbare Vorsteuer") {
                        Text(Format.money(deductible, currency: draft.currency))
                    }
                }
                if let inputVATDate = assessment.inputVatDate {
                    LabeledContent("Vorsteuer-Zeitpunkt") { Text(Format.date(inputVATDate)) }
                }
                if let outputVATDate = assessment.outputVatDate {
                    LabeledContent("Umsatzsteuer-Zeitpunkt") { Text(Format.date(outputVATDate)) }
                }
            }
        }
    }

    private var issuesSection: some View {
        Section("Hinweise") {
            let issues = derived?.issues ?? []
            if let operationError {
                IssueRow(severity: .error, message: operationError)
            }
            if !moneyFieldsAreValid {
                IssueRow(
                    severity: .error,
                    message: "Bitte korrigieren Sie ungültige Beträge, bevor Sie speichern oder weitere Daten anhängen."
                )
            }
            if issues.isEmpty, operationError == nil, moneyFieldsAreValid {
                Label("Keine Hinweise", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            ForEach(issues.indices, id: \.self) { index in
                IssueRow(severity: issues[index].severity, message: issues[index].message)
            }
        }
    }

    private func historySection(_ detail: TransactionDetail) -> some View {
        Section {
            DisclosureGroup("Verlauf") {
                ForEach(detail.auditEvents) { event in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(event.action.text) · \(event.actor.text)")
                        Text(Format.timestamp(event.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if isProposal || hasChanges {
            Divider()
            HStack {
                if isProposal, hasChanges {
                    Label("Bearbeitet", systemImage: "pencil")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isProposal ? "Ablehnen" : "Verwerfen", role: isProposal ? .destructive : .cancel) {
                    if case let .proposal(proposal) = subject {
                        model.rejectProposal(proposal.id)
                    } else if case .draft = subject {
                        newDraft = nil
                    } else {
                        draft = original
                    }
                }
                Button(isProposal ? "Bestätigen" : "Sichern") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var canSave: Bool {
        moneyFieldsAreValid
            && !draft.counterpartyName.trimmingCharacters(in: .whitespaces).isEmpty
            && derived?.canSave == true
    }

    private func save() {
        switch subject {
        case let .proposal(proposal):
            model.acceptProposal(
                proposal.id,
                draft: hasChanges ? draft : nil,
                expectedUpdatedAt: loadedProposalUpdatedAt
            )
        case .draft:
            if model.save(draft) != nil {
                original = draft
                newDraft = nil
            }
        default:
            if model.save(draft) != nil {
                original = draft
            }
        }
    }

    // MARK: - Helpers

    private func load() {
        switch subject {
        case let .transaction(detail):
            draft = detail.draft
        case let .proposal(proposal):
            draft = proposal.draft ?? TransactionDraft(businessProfileId: model.profile?.id ?? "")
        case .draft:
            draft = newDraft ?? model.newDraft()
        case .none:
            draft = TransactionDraft(businessProfileId: model.profile?.id ?? "")
        }
        original = draft
        loadedSubjectIdentity = subject.identity
        loadedProposalUpdatedAt = if case let .proposal(proposal) = subject {
            proposal.updatedAt
        } else {
            nil
        }
        invalidMoneyFields.removeAll()
        operationError = nil
    }

    private var moneyFieldsAreValid: Bool {
        invalidMoneyFields.isEmpty
    }

    private func setMoneyFieldValidity(_ name: String, isValid: Bool) {
        if isValid {
            invalidMoneyFields.remove(name)
        } else {
            invalidMoneyFields.insert(name)
        }
    }

    private var categoryOptions: [Database.Category] {
        model.categories.filter { category in
            switch draft.direction {
            case .income: category.kind == .income || category.kind == .neutral
            case .expense, .unknown: category.kind != .income
            }
        }
    }

    private var treatmentProvenance: Provenance? {
        switch subject {
        case let .transaction(detail):
            detail.provenance(of: "treatment", entity: FieldProvenance.Entity.taxAssessment)?.provenance
        case .proposal:
            draft.treatmentOverride == nil ? .calculated : .manual
        default:
            nil
        }
    }

    /// A row with its provenance capsule; edited fields become `Manuell`
    /// as soon as they differ from what the subject arrived with (spec 8.3).
    private func field(_ name: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            content()
            ProvenanceBadge(provenance: provenance(name), help: evidence(name))
        }
    }

    private func provenance(_ name: String) -> Provenance? {
        if changed(name) {
            return .manual
        }
        switch subject {
        case let .transaction(detail):
            return detail.provenance(of: name)?.provenance
        case let .proposal(proposal):
            return proposal.summary?.provenance(of: name)?.provenance
        default:
            return nil
        }
    }

    private func evidence(_ name: String) -> String? {
        guard case let .proposal(proposal) = subject else { return nil }
        return proposal.summary?.provenance(of: name)?.evidenceText
    }

    private func changed(_ name: String) -> Bool {
        CommitService.changedFields(from: original, to: draft).contains(name)
    }
}

/// Belegvorschau: the archived file itself, rendered (spec 6.4).
struct DocumentPreview: View {
    let url: URL

    var body: some View {
        Group {
            if url.pathExtension.lowercased() == "pdf" {
                PDFPreview(url: url)
            } else if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "doc").foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
    }
}

private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
