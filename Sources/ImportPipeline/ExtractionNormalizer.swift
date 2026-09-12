import AI
import Database
import Domain
import Foundation
import Tax

/// A model extraction turned into the app's own value types (spec 10.2,
/// step "Swift: normalization"). Nothing here talks to the model or the
/// database; it is pure and therefore directly testable.
public struct NormalizedExtraction: Sendable {
    public var draft: TransactionDraft
    public var provenance: [ProvenanceEntry]
    public var hint: ModelTreatmentHint?
    public var reverseChargeNote: Bool
}

public enum ExtractionNormalizer {
    /// Categories whose purchases are goods, not services - the distinction
    /// that separates an intra-Community acquisition from a reverse charge.
    static let goodsCategoryIDs: Set<String> = AssetDetection.hardwareCategoryIDs
        .union(["office_supplies", "hardware_small", "postage_shipping", "revenue_goods"])

    /// Schema paths of spec 13 mapped to the field names the repository uses
    /// for provenance and audit.
    static let fieldPaths: [String: String] = [
        "invoice.invoiceNumber": "invoiceNumber",
        "invoice.invoiceDate": "invoiceDate",
        "invoice.serviceDate": "serviceDate",
        "invoice.servicePeriodStart": "servicePeriodStart",
        "invoice.servicePeriodEnd": "servicePeriodEnd",
        "invoice.currency": "currency",
        "invoice.netAmount": "netAmount",
        "invoice.taxAmount": "taxAmount",
        "invoice.grossAmount": "grossAmount",
        "counterparty.name": "counterpartyId",
        "documentType": "transactionType",
        "direction": "direction",
    ]

    public static func normalize(
        _ extraction: DocumentExtraction,
        document: DocumentDraft?,
        profile: BusinessProfile,
        categoryIDs: Set<String>
    ) throws -> NormalizedExtraction {
        let currency = CurrencyCode((extraction.invoice.currency ?? "EUR").trimmed)
        guard currency.isWellFormed else {
            throw AIError.invalidResponse("Unbekannter Währungscode '\(extraction.invoice.currency ?? "")'.")
        }

        var net = try minor(extraction.invoice.netAmount, currency)
        var tax = try minor(extraction.invoice.taxAmount, currency)
        var gross = try minor(extraction.invoice.grossAmount, currency)
        // Complete the third value the document did not print (spec 13).
        switch (net, tax, gross) {
        case let (n?, t?, nil): gross = n + t
        case let (n?, nil, g?): tax = g - n
        case let (nil, t?, g?): net = g - t
        case (nil, nil, let g?): net = g; tax = 0
        default: break
        }

        let components = try extraction.taxComponents.map { component in
            TaxComponentDraft(
                kind: component.kind,
                rate: component.rate?.trimmed.nilIfEmpty,
                netMinor: try minor(component.netAmount, currency) ?? 0,
                taxMinor: try minor(component.taxAmount, currency) ?? 0
            )
        }

        let allocationBase = (net ?? gross ?? 0) == 0 ? (gross ?? 0) : (net ?? 0)
        let allocations = allocations(
            for: extraction.lineItems,
            total: allocationBase,
            currency: currency,
            categoryIDs: categoryIDs
        )

        let hintedCategories = Set(allocations.map(\.categoryId))
        let supplyType: SupplyType = hintedCategories.contains(where: goodsCategoryIDs.contains) ? .goods : .service

        var draft = TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: normalizedName(extraction.counterparty.name) ?? "Unbekannte Gegenpartei",
            counterpartyCountryCode: extraction.counterparty.countryCode?.trimmed.uppercased().nilIfEmpty,
            counterpartyVatId: extraction.counterparty.vatId?.trimmed.nilIfEmpty,
            direction: extraction.direction,
            transactionType: transactionType(for: extraction.documentType),
            title: title(of: extraction),
            invoiceNumber: extraction.invoice.invoiceNumber?.trimmed.nilIfEmpty,
            invoiceDate: LocalDate(extraction.invoice.invoiceDate ?? ""),
            serviceDate: LocalDate(extraction.invoice.serviceDate ?? ""),
            servicePeriodStart: LocalDate(extraction.invoice.servicePeriodStart ?? ""),
            servicePeriodEnd: LocalDate(extraction.invoice.servicePeriodEnd ?? ""),
            currency: currency,
            netMinor: net,
            taxMinor: tax,
            grossMinor: gross,
            supplyType: supplyType,
            components: components,
            allocations: allocations,
            documents: document.map { [$0] } ?? [],
            reviewStatus: .needsReview
        )
        draft.completeAmounts()

        return NormalizedExtraction(
            draft: draft,
            provenance: provenance(for: extraction, draft: draft),
            hint: ModelTreatmentHint(
                treatment: extraction.taxTreatmentHint.treatment,
                confidence: extraction.taxTreatmentHint.confidence ?? 0
            ),
            reverseChargeNote: extraction.taxComponents.contains { $0.kind == .reverseChargeNote }
        )
    }

    // MARK: - Pieces

    static func minor(_ value: String?, _ currency: CurrencyCode) throws -> Int64? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        do {
            return try Money.fromDecimalString(value, currency: currency).minorUnits
        } catch {
            throw AIError.invalidResponse("Der Betrag '\(value)' war nicht lesbar.")
        }
    }

    /// Trims and collapses whitespace; the repository normalizes further for
    /// counterparty identity (spec 17.3).
    static func normalizedName(_ name: String?) -> String? {
        guard let name else { return nil }
        let parts = name.split(whereSeparator: \.isWhitespace)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func transactionType(for documentType: DocumentType) -> TransactionType {
        switch documentType {
        case .invoice: .invoice
        case .receipt: .receipt
        case .creditNote: .creditNote
        case .statement, .contract, .other, .unknown: .other
        }
    }

    static func title(of extraction: DocumentExtraction) -> String? {
        extraction.lineItems.compactMap { $0.description?.trimmed.nilIfEmpty }.first
    }

    /// One allocation per hinted category, scaled so the sum matches the
    /// booked base exactly (spec 14.1 `ALLOCATION_SUM_MISMATCH`).
    static func allocations(
        for lineItems: [DocumentExtraction.LineItem],
        total: Int64,
        currency: CurrencyCode,
        categoryIDs: Set<String>
    ) -> [AllocationDraft] {
        var order: [String] = []
        var amounts: [String: Int64] = [:]
        for item in lineItems {
            let category = item.categoryHint.flatMap { categoryIDs.contains($0) ? $0 : nil } ?? "uncategorized"
            let amount = (try? minor(item.netAmount, currency)) ?? nil
            if amounts[category] == nil {
                order.append(category)
                amounts[category] = 0
            }
            amounts[category]? += amount ?? 0
        }
        guard !order.isEmpty else {
            return [AllocationDraft(categoryId: "uncategorized", amountMinor: total)]
        }
        var drafts = order.map { AllocationDraft(categoryId: $0, amountMinor: amounts[$0] ?? 0) }
        let difference = total - drafts.reduce(0) { $0 + $1.amountMinor }
        if difference != 0, let index = drafts.indices.max(by: { abs(drafts[$0].amountMinor) < abs(drafts[$1].amountMinor) }) {
            drafts[index].amountMinor += difference
        }
        return drafts
    }

    /// Fields read off the document get `document` provenance with the
    /// model's evidence; inferred fields get `agent` (spec 8.3).
    static func provenance(for extraction: DocumentExtraction, draft: TransactionDraft) -> [ProvenanceEntry] {
        let confidence = extraction.taxTreatmentHint.confidence.map { "\($0)" }
        var entries: [ProvenanceEntry] = []
        for (path, field) in fieldPaths.sorted(by: { $0.key < $1.key }) {
            let evidence = extraction.evidence(for: path)
            entries.append(
                ProvenanceEntry(
                    fieldName: field,
                    provenance: field == "direction" || field == "transactionType" ? .agent : .document,
                    evidencePage: evidence?.page,
                    evidenceSnippet: evidence?.snippet
                )
            )
        }
        entries.append(ProvenanceEntry(fieldName: "title", provenance: .agent))
        entries.append(
            ProvenanceEntry(
                entityType: "taxAssessment",
                fieldName: "treatment",
                provenance: .calculated,
                confidence: confidence
            )
        )
        return entries
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
