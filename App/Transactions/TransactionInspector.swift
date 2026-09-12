import AppKit
import Database
import DocumentStore
import Domain
import PDFKit
import SwiftUI

/// The inspector of one transaction (spec 6.4): document, fields, allocations,
/// tax, payments, issues and history, each field with its provenance (8.3).
struct TransactionInspector: View {
    @Environment(AppModel.self) private var model

    let detail: TransactionDetail?
    @State private var addingPayment = false

    var body: some View {
        if let detail {
            Form {
                documentSection(detail)
                fieldsSection(detail)
                allocationsSection(detail)
                taxSection(detail)
                paymentsSection(detail)
                issuesSection(detail)
                historySection(detail)
            }
            .formStyle(.grouped)
            .sheet(isPresented: $addingPayment) {
                PaymentEditor(detail: detail)
            }
        } else {
            ContentUnavailableView(
                "Keine Buchung ausgewählt",
                systemImage: "sidebar.trailing",
                description: Text("Wählen Sie eine Zeile, um Details zu sehen.")
            )
        }
    }

    // MARK: - Beleg

    private func documentSection(_ detail: TransactionDetail) -> some View {
        Section("Beleg") {
            if let entry = detail.documents.first, let archive = model.archive {
                DocumentThumbnail(url: archive.url(forRelativePath: entry.document.relativePath))
                LabeledContent("Datei") {
                    Text(entry.document.originalFilename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [archive.url(forRelativePath: entry.document.relativePath)]
                    )
                }
            } else {
                Label("Kein Beleg", systemImage: "doc.badge.plus")
                    .foregroundStyle(.secondary)
            }
            Button("Beleg anhängen", action: { attachDocument(to: detail) })
        }
    }

    private func attachDocument(to detail: TransactionDetail) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentStore.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Anhängen"
        panel.message = "Beleg zu dieser Buchung auswählen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.attachDocument(at: url, to: detail)
    }

    // MARK: - Felder

    private func fieldsSection(_ detail: TransactionDetail) -> some View {
        Section("Felder") {
            row(detail, "Gegenpartei", detail.counterparty?.displayName ?? "–", field: "counterpartyId")
            row(detail, "Art", detail.transaction.direction.text, field: "direction")
            if let title = detail.transaction.title {
                row(detail, "Titel", title, field: "title")
            }
            row(detail, "Rechnungsnummer", detail.transaction.invoiceNumber ?? "–", field: "invoiceNumber")
            row(detail, "Rechnungsdatum", Format.date(detail.transaction.invoiceDate), field: "invoiceDate")
            if let start = detail.transaction.servicePeriodStart, let end = detail.transaction.servicePeriodEnd {
                row(
                    detail,
                    "Leistungszeitraum",
                    "\(Format.date(start)) – \(Format.date(end))",
                    field: "servicePeriodStart"
                )
            } else {
                row(detail, "Leistungsdatum", Format.date(detail.transaction.serviceDate), field: "serviceDate")
            }
            row(
                detail,
                "Netto",
                Format.money(detail.transaction.bookedNetMinor, currency: currency(detail)),
                field: "netAmount"
            )
            row(
                detail,
                "Steuer",
                Format.money(detail.transaction.bookedTaxMinor, currency: currency(detail)),
                field: "taxAmount"
            )
            row(
                detail,
                "Brutto",
                Format.money(detail.transaction.bookedGrossMinor, currency: currency(detail)),
                field: "grossAmount"
            )
            if let notes = detail.transaction.notes {
                row(detail, "Notiz", notes, field: "notes")
            }
        }
    }

    // MARK: - Aufteilung

    private func allocationsSection(_ detail: TransactionDetail) -> some View {
        Section("Aufteilung") {
            ForEach(detail.allocations) { allocation in
                LabeledContent(model.categoryName(allocation.categoryId)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.money(allocation.amountMinor, currency: CurrencyCode(allocation.currency)))
                            .monospacedDigit()
                        if allocation.assetFlag {
                            Label("Anlagegut prüfen", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Steuer

    private func taxSection(_ detail: TransactionDetail) -> some View {
        Section("Steuer") {
            ForEach(detail.components) { component in
                LabeledContent("\(component.rate ?? "–") %") {
                    Text(
                        "\(Format.money(component.netMinor, currency: CurrencyCode(component.currency))) + "
                            + Format.money(component.taxMinor, currency: CurrencyCode(component.currency))
                    )
                    .monospacedDigit()
                }
            }
            if let assessment = detail.assessment {
                LabeledContent("Behandlung") {
                    HStack(spacing: 6) {
                        Text(assessment.treatment.label)
                        ProvenanceBadge(
                            provenance: detail.provenance(of: "treatment", entity: FieldProvenance.Entity.taxAssessment)
                        )
                    }
                }
                LabeledContent("Status", value: assessment.status.text)
                if let base = assessment.taxableBaseMinor {
                    LabeledContent("Bemessungsgrundlage") {
                        Text(Format.money(base, currency: CurrencyCode(assessment.currency)))
                    }
                }
                if let selfAssessed = assessment.selfAssessedVatMinor {
                    LabeledContent("Selbst berechnete USt.") {
                        Text(Format.money(selfAssessed, currency: CurrencyCode(assessment.currency)))
                    }
                }
                if let deductible = assessment.deductibleInputVatMinor {
                    LabeledContent("Abziehbare Vorsteuer") {
                        Text(Format.money(deductible, currency: CurrencyCode(assessment.currency)))
                    }
                }
                taxPoint(detail, "EÜR-Datum", detail.eurDate, origin: "Zahlung, § 11 EStG", field: nil)
                taxPoint(detail, "Vorsteuer", assessment.inputVatDate, origin: "§ 15 UStG", field: "inputVatDate")
                taxPoint(detail, "Umsatzsteuer", assessment.outputVatDate, origin: "§ 13 UStG", field: "outputVatDate")
                if let reasoning = assessment.reasoning {
                    Text(reasoning).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func taxPoint(
        _ detail: TransactionDetail,
        _ label: LocalizedStringKey,
        _ date: LocalDate?,
        origin: String,
        field: String?
    ) -> some View {
        if let date {
            LabeledContent(label) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Format.date(date)).monospacedDigit()
                        if let field {
                            ProvenanceBadge(
                                provenance: detail.provenance(of: field, entity: FieldProvenance.Entity.taxAssessment)
                            )
                        }
                    }
                    Text(origin).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Zahlungen

    private func paymentsSection(_ detail: TransactionDetail) -> some View {
        Section("Zahlungen") {
            if detail.payments.isEmpty {
                Label("Keine Zahlung erfasst", systemImage: "circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(detail.payments) { entry in
                LabeledContent(Format.date(entry.payment.paymentDate)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.allocated.formatted(locale: Format.german)).monospacedDigit()
                        Text(paymentSubtitle(entry)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Zahlung hinzufügen") { addingPayment = true }
        }
    }

    private func paymentSubtitle(_ entry: TransactionDetail.PaymentEntry) -> String {
        [entry.accountName, entry.payment.paymentMethod?.text, entry.payment.reference]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    // MARK: - Hinweise

    private func issuesSection(_ detail: TransactionDetail) -> some View {
        Section("Hinweise") {
            if detail.openIssues.isEmpty {
                Label("Keine Hinweise", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            ForEach(detail.openIssues) { issue in
                // Soft issues can be ignored; hard ones must be fixed (spec 44).
                if issue.severity == .error {
                    IssueRow(severity: issue.severity, message: issue.message)
                } else {
                    IssueRow(severity: issue.severity, message: issue.message) {
                        try? model.repository?.ignoreIssue(issue.id)
                    }
                }
            }
        }
    }

    // MARK: - Verlauf

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

    // MARK: - Helpers

    private func currency(_ detail: TransactionDetail) -> CurrencyCode {
        CurrencyCode(detail.transaction.bookedCurrency)
    }

    private func row(
        _ detail: TransactionDetail,
        _ label: LocalizedStringKey,
        _ value: String,
        field: String
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                ProvenanceBadge(provenance: detail.provenance(of: field))
            }
        }
    }
}

/// Belegvorschau: first PDF page or the image itself (spec 6.4).
struct DocumentThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "doc").foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .task(id: url) { image = Self.load(url) }
    }

    private static func load(_ url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }
}
