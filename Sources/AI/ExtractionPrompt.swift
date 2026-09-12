import Domain
import Foundation

/// Loads `Prompts/extraction.md` and renders the context of spec 42 into it.
/// Prompts are versioned resources; changing one means re-running the fixture
/// suite (spec 41).
public enum ExtractionPrompt {
    public static func render(_ context: ExtractionContext) -> String {
        template
            .replacingOccurrences(of: "{{BUSINESS}}", with: business(context.business))
            .replacingOccurrences(of: "{{CATEGORIES}}", with: categories(context.categories))
            .replacingOccurrences(of: "{{TREATMENTS}}", with: treatments(context.treatments))
    }

    static let template: String = {
        guard let url = Bundle.module.url(forResource: "extraction", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Prompts/extraction.md is missing from the AI bundle")
            return ""
        }
        return text
    }()

    private static func business(_ business: ExtractionContext.Business) -> String {
        var lines = ["- Name: \(business.name)"]
        if let legal = business.legalName, !legal.isEmpty {
            lines.append("- Registered name: \(legal)")
        }
        lines.append("- Country: \(business.countryCode)")
        lines.append("- VAT ID: \(business.vatId ?? "none")")
        lines.append(
            "- VAT status: \(business.vatStatus == .taxable ? "VAT-registered" : "small business (§19 UStG)")"
        )
        lines.append(
            "- Accounting: \(business.accountingMethod == .cash ? "cash basis (§20 UStG)" : "accrual basis")"
        )
        return lines.joined(separator: "\n")
    }

    private static func categories(_ options: [ExtractionContext.CategoryOption]) -> String {
        options.map { "- `\($0.id)` — \($0.nameDE)" }.joined(separator: "\n")
    }

    private static func treatments(_ treatments: [TaxTreatment]) -> String {
        treatments.map { "- `\($0.rawValue)` — \(description(of: $0))" }.joined(separator: "\n")
    }

    private static func description(of treatment: TaxTreatment) -> String {
        switch treatment {
        case .domesticVAT: "German VAT shown and charged (§13 UStG)"
        case .reverseCharge: "recipient owes the VAT (§13b UStG, or §3a for outgoing EU B2B services)"
        case .intraCommunityAcquisition: "goods acquired from another EU member state (§1a UStG)"
        case .intraCommunitySupply: "goods supplied to another EU member state (§4 Nr. 1b UStG)"
        case .export: "supply to a third country (§4 Nr. 1a UStG)"
        case .importVAT: "import VAT paid at the border (§21 UStG)"
        case .nonTaxable: "outside the scope of German VAT"
        case .exempt: "exempt supply (§4 UStG)"
        case .smallBusiness: "no VAT under the small-business rule (§19 UStG)"
        case .unknown: "cannot be determined from the document"
        }
    }
}
