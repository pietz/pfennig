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
/// happens inline: every field is a control, and the footer offers what the
/// subject allows.
struct TransactionInspector: View {
    @Environment(AppModel.self) private var model

    let subject: InspectorSubject
    @Binding var newDraft: TransactionDraft?
    @Binding var hasUnsavedChanges: Bool

    @State private var draft = TransactionDraft(businessProfileId: "")
    @State private var original = TransactionDraft(businessProfileId: "")
    @State private var addingPayment = false
    @State private var invalidMoneyFields: Set<String> = []
    @State private var loadedSubjectIdentity: String?
    @State private var loadedProposalUpdatedAt: String?
    @State private var operationError: String?
    @State private var metadataExpanded = false
    @State private var allocationsExpanded = false
    @State private var taxExpanded = false
    @State private var paymentsExpanded = true
    @State private var issuesExpanded = false
    @State private var historyExpanded = false

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
                        primaryFieldsSection
                        amountsSection
                        metadataDisclosure
                        allocationsDisclosure
                        taxDisclosure
                        if case let .transaction(detail) = subject {
                            paymentsDisclosure(detail)
                        }
                        issuesDisclosure
                        if case let .transaction(detail) = subject {
                            historyDisclosure(detail)
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
        .onChange(of: hasVisibleIssues, initial: true) { _, value in
            issuesExpanded = value
        }
        .onChange(of: hasChanges, initial: true) { _, value in
            hasUnsavedChanges = value
        }
        .onDisappear {
            hasUnsavedChanges = false
        }
    }

    // MARK: - Beleg

    @ViewBuilder
    private var documentSection: some View {
        if let path = documentPath, let archive = model.archive {
            Section("Beleg") {
                DocumentPreview(url: archive.url(forRelativePath: path))
                HStack(spacing: 8) {
                    Label {
                        Text(documentName ?? "Beleg")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        NSWorkspace.shared.open(archive.url(forRelativePath: path))
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Beleg öffnen")
                    .accessibilityLabel("Beleg öffnen")
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([archive.url(forRelativePath: path)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Im Finder zeigen")
                    .accessibilityLabel("Im Finder zeigen")
                }
            }
        } else if case .transaction = subject {
            Section("Beleg") {
                HStack(spacing: 8) {
                    Label("Kein Beleg", systemImage: "doc.badge.plus")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(action: attachDocument) {
                        Image(systemName: "paperclip")
                    }
                    .buttonStyle(.borderless)
                    .help("Beleg anhängen")
                    .accessibilityLabel("Beleg anhängen")
                    .disabled(!moneyFieldsAreValid)
                }
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

    // MARK: - Primäre Felder

    private var primaryFieldsSection: some View {
        Section("Grunddaten") {
            field(label: "Firma") {
                TextField("Firma", text: $draft.counterpartyName, prompt: Text("Firma oder Person"))
            }
            field(label: "Richtung") {
                Picker("Richtung", selection: $draft.direction) {
                    Text("Ausgabe").tag(Direction.expense)
                    Text("Einnahme").tag(Direction.income)
                }
            }
            field(label: "Art") {
                Picker("Art", selection: $draft.transactionType) {
                    ForEach(TransactionType.userSelectable, id: \.self) { Text($0.label).tag($0) }
                }
            }
            field(label: "Titel") {
                TextField("Titel", text: $draft.title.orEmpty, prompt: Text("Kurzbeschreibung"))
            }
            field(label: "Rechnungsnummer") {
                TextField("Rechnungsnummer", text: $draft.invoiceNumber.orEmpty, prompt: Text("optional"))
            }
            field(label: "Rechnungsdatum") {
                OptionalDateField(label: "Rechnungsdatum", date: $draft.invoiceDate, showsLabel: false)
            }
        }
    }

    private var amountsSection: some View {
        Section("Beträge") {
            field(label: "Währung") {
                Picker("Währung", selection: $draft.currency) {
                    ForEach(["EUR", "USD", "GBP", "CHF"], id: \.self) { Text($0).tag(CurrencyCode($0)) }
                }
            }
            field(label: "Netto") {
                MoneyField(
                    label: "Netto",
                    minor: $draft.netMinor,
                    currency: draft.currency,
                    onValidityChange: { setMoneyFieldValidity("netAmount", isValid: $0) }
                )
            }
            field(label: "Steuer") {
                HStack(spacing: 8) {
                    MoneyField(
                        label: "Steuer",
                        minor: $draft.taxMinor,
                        currency: draft.currency,
                        onValidityChange: { setMoneyFieldValidity("taxAmount", isValid: $0) }
                    )
                    Text(draft.effectiveTaxRateText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                        .accessibilityLabel(Text("Steuersatz"))
                }
            }
            field(label: "Brutto") {
                MoneyField(
                    label: "Brutto",
                    minor: $draft.grossMinor,
                    currency: draft.currency,
                    onValidityChange: { setMoneyFieldValidity("grossAmount", isValid: $0) }
                )
            }
        }
    }

    private var metadataDisclosure: some View {
        Section("Weitere Angaben", isExpanded: $metadataExpanded) {
            field(label: "Land") {
                TextField("Land", text: $draft.counterpartyCountryCode.orEmpty, prompt: Text("DE"))
            }
            field(label: "USt-IdNr.") {
                TextField("USt-IdNr.", text: $draft.counterpartyVatId.orEmpty, prompt: Text("optional"))
            }
            field(label: "Leistung von") {
                OptionalDateField(label: "Leistung von", date: $draft.servicePeriodStart, showsLabel: false)
            }
            field(label: "bis") {
                OptionalDateField(label: "Leistung bis", date: $draft.servicePeriodEnd, showsLabel: false)
            }
            field(label: "Leistungsart") {
                Picker("Leistungsart", selection: $draft.supplyType) {
                    ForEach([SupplyType.unknown, .service, .goods], id: \.self) { Text($0.label).tag($0) }
                }
            }
            field(label: "Anzahlung") {
                Toggle("Anzahlung", isOn: $draft.isAdvancePayment)
            }
            field(label: "Notiz") {
                TextField("Notiz", text: $draft.notes.orEmpty, prompt: Text("optional"), axis: .vertical)
                    .lineLimit(1 ... 4)
            }
        }
    }

    // MARK: - Aufteilung

    private var allocationsDisclosure: some View {
        Section(isExpanded: $allocationsExpanded) {
            if draft.allocations.isEmpty {
                Label("Keine Aufteilung erfasst", systemImage: "square.split.2x1")
                    .foregroundStyle(.secondary)
            }
            ForEach($draft.allocations) { $allocation in
                let rowNumber = allocationRowNumber(for: allocation.id)
                VStack(alignment: .leading, spacing: 8) {
                    field(label: "Kategorie") {
                        Picker("Kategorie", selection: $allocation.categoryId) {
                            ForEach(categoryOptions) { Text($0.nameDe).tag($0.id) }
                        }
                        .accessibilityLabel(Text("Aufteilung \(rowNumber), Kategorie"))
                    }
                    field(label: "Betrag") {
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
                        .accessibilityLabel(Text("Aufteilung \(rowNumber), Betrag"))
                    }
                    field(label: "Beschreibung") {
                        TextField("Beschreibung", text: $allocation.description.orEmpty, prompt: Text("optional"))
                            .accessibilityLabel(Text("Aufteilung \(rowNumber), Beschreibung"))
                    }
                    field(label: "Privatanteil") {
                        TextField(
                            "Privatanteil",
                            text: $allocation.privateSharePercent.orEmpty,
                            prompt: Text("optional")
                        )
                        .accessibilityLabel(Text("Aufteilung \(rowNumber), Privatanteil in Prozent"))
                    }
                    if allocation.assetFlag {
                        Label("Anlagegut prüfen", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(Text("Aufteilung \(rowNumber): Anlagegut prüfen"))
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text("Aufteilung")
                Spacer()
                Text("\(draft.allocations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Steuer

    /// Only the treatment is a decision; everything under it is the live
    /// result of the current values, the same derivation the reports use.
    private var taxDisclosure: some View {
        Section("Steuer", isExpanded: $taxExpanded) {
            field(label: "Behandlung") {
                Picker("Behandlung", selection: $draft.treatmentOverride) {
                    Text("Automatisch").tag(TaxTreatment?.none)
                    Divider()
                    ForEach(TaxTreatment.allCases, id: \.self) {
                        Text($0.label).tag(TaxTreatment?.some($0))
                    }
                }
            }
            taxSummary
        }
    }

    @ViewBuilder
    private var taxSummary: some View {
        if let derived, let assessment = derived.draft.assessment {
            LabeledContent("Entschieden als") { Text(assessment.treatment.label) }
            LabeledContent("Steuersatz") { Text(draft.effectiveTaxRateText).monospacedDigit() }
            LabeledContent("Umsatzsteuer") {
                Text(Format.money(draft.taxMinor ?? 0, currency: draft.currency)).monospacedDigit()
            }
            if let selfAssessed = assessment.selfAssessedVatMinor {
                LabeledContent("Selbst berechnet (§ 13b)") {
                    Text(Format.money(selfAssessed, currency: draft.currency)).monospacedDigit()
                }
            }
            if draft.direction == .expense {
                LabeledContent("Vorsteuer abziehbar") {
                    Text(deductibleInputVatText(derived.deductibleInputVatMinor)).monospacedDigit()
                }
            }
            if let reasoning = derived.reasoning {
                Text(reasoning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isSmallBusiness(assessment.treatment) {
                Text("Kleinunternehmer nach § 19 UStG: keine Umsatzsteuer, kein Vorsteuerabzug.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func deductibleInputVatText(_ minor: Int64?) -> String {
        guard let minor, minor > 0 else { return "Nein" }
        return "Ja · \(Format.money(minor, currency: draft.currency))"
    }

    private func isSmallBusiness(_ treatment: TaxTreatment) -> Bool {
        treatment == .smallBusiness || model.profile?.vatStatus == .smallBusiness
    }

    // MARK: - Zahlungen

    private func paymentsDisclosure(_ detail: TransactionDetail) -> some View {
        Section(isExpanded: $paymentsExpanded) {
            if detail.payments.isEmpty {
                Label("Keine Zahlung erfasst", systemImage: "circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(detail.payments) { entry in
                let isRefund = entry.payment.direction != draft.direction.settlingPaymentDirection
                LabeledContent(Format.date(entry.payment.paymentDate)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.money(
                            isRefund ? -entry.allocation.allocatedMinor : entry.allocation.allocatedMinor,
                            currency: CurrencyCode(entry.allocation.currency)
                        ))
                        .monospacedDigit()
                        if let caption = paymentCaption(entry.payment, isRefund: isRefund) {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            if draft.openAmountMinor != 0 {
                Button(action: recordFullPayment) {
                    Label(fullPaymentLabel, systemImage: "checkmark.circle")
                }
                .disabled(!moneyFieldsAreValid)
                .help("Bucht den offenen Restbetrag mit dem heutigen Datum")
            }
            Button {
                operationError = nil
                addingPayment = true
            } label: {
                Label("Zahlung hinzufügen", systemImage: "plus")
            }
            .disabled(!moneyFieldsAreValid)
        } header: {
            HStack {
                Text("Zahlungen")
                Spacer()
                if detail.payments.isEmpty {
                    Text("Keine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(detail.payments.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// A credit note is not "paid" but settled the other way round.
    private var fullPaymentLabel: LocalizedStringKey {
        (draft.grossMinor ?? 0) < 0 ? "Vollständig erstattet" : "Vollständig bezahlt"
    }

    /// Where a payment came from, and whether it went back. Manual payments
    /// carry neither method nor reference; the statement import fills both.
    private func paymentCaption(_ payment: Payment, isRefund: Bool) -> String? {
        let refundLabel = draft.direction == .income ? "Rückzahlung" : "Erstattung"
        let parts = [isRefund ? refundLabel : nil, payment.paymentMethod?.text, payment.reference]
            .compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One click for the ordinary case: the open remainder, paid today. On a
    /// credit note the money moves the other way, so the payment does too.
    private func recordFullPayment() {
        let open = draft.openAmountMinor
        guard moneyFieldsAreValid, open != 0, let direction = draft.settlingPaymentDirection else { return }
        var updatedDraft = draft
        updatedDraft.payments.append(
            PaymentDraft(
                direction: direction,
                paymentDate: .today(),
                amountMinor: abs(open),
                currency: draft.currency
            )
        )
        guard model.save(updatedDraft) != nil else {
            operationError = "Zahlung konnte nicht gespeichert werden. Ihre Änderungen bleiben erhalten."
            return
        }
        draft = updatedDraft
        original = updatedDraft
        operationError = nil
    }

    // MARK: - Hinweise und Verlauf

    private var issuesDisclosure: some View {
        Section(isExpanded: $issuesExpanded) {
            issuesContent
        } header: {
            HStack {
                Text("Hinweise")
                Spacer()
                if !hasVisibleIssues {
                    Text("Keine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var issuesContent: some View {
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
            Label("Keine Hinweise", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
        ForEach(issues.indices, id: \.self) { index in
            IssueRow(severity: issues[index].severity, message: issues[index].message)
        }
    }

    private var hasVisibleIssues: Bool {
        operationError != nil || !moneyFieldsAreValid || !(derived?.issues.isEmpty ?? true)
    }

    private func historyDisclosure(_ detail: TransactionDetail) -> some View {
        Section(isExpanded: $historyExpanded) {
            if detail.auditEvents.isEmpty {
                Text("Noch kein Verlauf")
                    .foregroundStyle(.secondary)
            }
            ForEach(detail.auditEvents) { event in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(event.action.text) · \(event.actor.text)")
                    Text(Format.timestamp(event.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Verlauf")
                Spacer()
                Text("\(detail.auditEvents.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
        issuesExpanded = hasVisibleIssues
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

    private func allocationRowNumber(for id: String) -> Int {
        draft.allocations.firstIndex { $0.id == id }.map { $0 + 1 } ?? 1
    }

    private var categoryOptions: [Database.Category] {
        model.categories.filter { category in
            switch draft.direction {
            case .income: category.kind == .income || category.kind == .neutral
            case .expense, .unknown: category.kind != .income
            }
        }
    }

    private func field(
        label: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        LabeledContent(label) {
            content()
                .labelsHidden()
        }
    }
}

/// Belegvorschau: a small first-page thumbnail rather than a live PDF view.
struct DocumentPreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .overlay(Rectangle().strokeBorder(.separator, lineWidth: 1))
        .task(id: url) { image = Self.load(url) }
    }

    private static func load(_ url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 480, height: 640), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }
}
