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
        "invoice.servicePeriodStart": "servicePeriodStart",
        "invoice.servicePeriodEnd": "servicePeriodEnd",
        "invoice.currency": "currency",
        "invoice.netAmount": "netAmount",
        "invoice.taxAmount": "taxAmount",
        "invoice.grossAmount": "grossAmount",
        "counterparty.name": "counterpartyId",
        "documentType": "transactionType",
        "direction": "direction"
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

        // A Gutschrift prints ordinary positive amounts under a heading that
        // says they go the other way. The booking is a negative transaction in
        // the direction of the document it corrects, so every amount is
        // mirrored here - once, at the boundary - and a model that already
        // returned negative numbers changes nothing.
        let isCreditNote = extraction.documentType == .creditNote
        net = Self.mirrored(net, isCreditNote)
        tax = Self.mirrored(tax, isCreditNote)
        gross = Self.mirrored(gross, isCreditNote)

        let components = try extraction.taxComponents.map { component in
            try TaxComponentDraft(
                kind: component.kind,
                rate: component.rate?.trimmed.nilIfEmpty,
                netMinor: Self.mirrored(minor(component.netAmount, currency) ?? 0, isCreditNote),
                taxMinor: Self.mirrored(minor(component.taxAmount, currency) ?? 0, isCreditNote)
            )
        }

        let homeCountry = profile.countryCode.trimmed.uppercased()
        let isDomestic = (extraction.counterparty.countryCode?.trimmed.uppercased() ?? homeCountry) == homeCountry
        let isSmallBusinessExpense = extraction.direction == .expense
            && (
                profile.vatStatus == .smallBusiness
                    || (
                        isDomestic
                            && extraction.taxTreatmentHint.treatment == .smallBusiness
                            && (tax ?? 0) == 0
                    )
            )
        let allocationBase = isSmallBusinessExpense
            ? (gross ?? net ?? 0)
            : ((net ?? gross ?? 0) == 0 ? (gross ?? 0) : (net ?? 0))
        let allocations = allocations(
            for: extraction.lineItems,
            total: allocationBase,
            currency: currency,
            categoryIDs: categoryIDs,
            isCreditNote: isCreditNote
        )

        var unparseableDateFields: [String] = []
        func date(_ raw: String?, fieldName: String) -> LocalDate? {
            guard let raw, !raw.isEmpty else { return nil }
            guard let date = LocalDate(raw) else {
                unparseableDateFields.append(fieldName)
                return nil
            }
            return date
        }
        let invoiceDate = date(extraction.invoice.invoiceDate, fieldName: "invoiceDate")
        let servicePeriodStart = date(extraction.invoice.servicePeriodStart, fieldName: "servicePeriodStart")
        let servicePeriodEnd = date(extraction.invoice.servicePeriodEnd, fieldName: "servicePeriodEnd")

        let hintedCategories = Set(allocations.map(\.categoryId))
        let supplyType: SupplyType = hintedCategories.contains(where: goodsCategoryIDs.contains) ? .goods : .service

        var draft = TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: normalizedName(extraction.counterparty.name) ?? "Unbekannte Firma",
            counterpartyCountryCode: extraction.counterparty.countryCode?.trimmed.uppercased().nilIfEmpty,
            counterpartyVatId: extraction.counterparty.vatId?.trimmed.nilIfEmpty,
            direction: extraction.direction,
            transactionType: transactionType(for: extraction.documentType),
            title: title(of: extraction),
            invoiceNumber: extraction.invoice.invoiceNumber?.trimmed.nilIfEmpty,
            invoiceDate: invoiceDate,
            servicePeriodStart: servicePeriodStart,
            servicePeriodEnd: servicePeriodEnd,
            unparseableDateFields: unparseableDateFields.isEmpty ? nil : unparseableDateFields,
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
            provenance: provenance(),
            hint: ModelTreatmentHint(treatment: extraction.taxTreatmentHint.treatment),
            reverseChargeNote: extraction.taxComponents.contains { $0.kind == .reverseChargeNote }
        )
    }

    // MARK: - Pieces

    /// Negative magnitude for a credit note, the value untouched otherwise.
    static func mirrored(_ value: Int64, _ isCreditNote: Bool) -> Int64 {
        isCreditNote ? -abs(value) : value
    }

    static func mirrored(_ value: Int64?, _ isCreditNote: Bool) -> Int64? {
        value.map { mirrored($0, isCreditNote) }
    }

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

    /// Hard limit for a ledger title. The prompt asks for about 40
    /// characters; this is the safety net for the times the model ignores it.
    static let titleLimit = 60

    /// The model's own short phrase, or the first line item on a recording
    /// made before `title` existed. Either way the ledger gets a single,
    /// whitespace-collapsed line of at most `titleLimit` characters.
    static func title(of extraction: DocumentExtraction) -> String? {
        let raw = extraction.title?.nilIfBlank
            ?? extraction.lineItems.compactMap { $0.description?.nilIfBlank }.first
        return shortened(raw)
    }

    /// Trims, collapses internal whitespace and cuts an over-long title at a
    /// word boundary, replacing the remainder with an ellipsis. A single word
    /// longer than the limit is cut mid-word rather than left in full.
    static func shortened(_ title: String?) -> String? {
        guard let collapsed = normalizedName(title) else { return nil }
        guard collapsed.count > titleLimit else { return collapsed }
        let head = collapsed.prefix(titleLimit - 1)
        let word = head.lastIndex(where: \.isWhitespace).map { head[head.startIndex ..< $0] } ?? head[...]
        let cut = word.count >= titleLimit / 2 ? word : head
        return String(cut).trimmingCharacters(in: Self.titleTail) + "…"
    }

    /// Trailing characters that would dangle in front of the ellipsis.
    static let titleTail = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ",;:.-–—/·•"))

    /// One allocation per hinted category, scaled so the sum matches the
    /// booked base exactly (spec 14.1 `ALLOCATION_SUM_MISMATCH`).
    static func allocations(
        for lineItems: [DocumentExtraction.LineItem],
        total: Int64,
        currency: CurrencyCode,
        categoryIDs: Set<String>,
        isCreditNote: Bool = false
    ) -> [AllocationDraft] {
        var order: [String] = []
        var amounts: [String: Int64] = [:]
        for item in lineItems {
            let category = item.categoryHint.flatMap { categoryIDs.contains($0) ? $0 : nil } ?? "uncategorized"
            let amount = mirrored((try? minor(item.netAmount, currency)) ?? nil, isCreditNote)
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
        if difference != 0,
           let index = drafts.indices.max(by: { abs(drafts[$0].amountMinor) < abs(drafts[$1].amountMinor) })
        {
            drafts[index].amountMinor += difference
        }
        return drafts
    }

    /// Fields read off the document get `document` provenance; inferred fields
    /// get `agent` (spec 8.3).
    static func provenance() -> [ProvenanceEntry] {
        var entries: [ProvenanceEntry] = []
        for (_, field) in fieldPaths.sorted(by: { $0.key < $1.key }) {
            entries.append(
                ProvenanceEntry(
                    fieldName: field,
                    provenance: field == "direction" || field == "transactionType" ? .agent : .document
                )
            )
        }
        entries.append(ProvenanceEntry(fieldName: "title", provenance: .agent))
        entries.append(
            ProvenanceEntry(
                entityType: "taxAssessment",
                fieldName: "treatment",
                provenance: .calculated
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

    var nilIfBlank: String? {
        trimmed.nilIfEmpty
    }
}
