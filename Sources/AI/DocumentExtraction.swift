import Domain
import Foundation

/// The strict Structured Output of the extraction call (spec 13). Amounts are
/// decimal strings in the document's own currency, dates are `YYYY-MM-DD`,
/// and everything the document does not state is `null`.
public struct DocumentExtraction: Codable, Sendable, Hashable {
    public struct Counterparty: Codable, Sendable, Hashable {
        public var name: String?
        public var countryCode: String?
        public var vatId: String?
        public var street: String?
        public var postalCode: String?
        public var city: String?
    }

    public struct Invoice: Codable, Sendable, Hashable {
        public var invoiceNumber: String?
        public var invoiceDate: String?
        public var serviceDate: String?
        public var servicePeriodStart: String?
        public var servicePeriodEnd: String?
        public var currency: String?
        public var netAmount: String?
        public var taxAmount: String?
        public var grossAmount: String?
        /// EUR value printed on a foreign-currency document (§16 Abs. 6 UStG).
        public var statedEurEquivalent: String?
    }

    public struct TaxComponent: Codable, Sendable, Hashable {
        public var rate: String?
        public var netAmount: String?
        public var taxAmount: String?
        public var kind: TaxComponentKind
    }

    /// The model's non-binding treatment suggestion; Swift decides the
    /// binding treatment (spec 13).
    public struct TreatmentHint: Codable, Sendable, Hashable {
        public var treatment: TaxTreatment
    }

    public struct LineItem: Codable, Sendable, Hashable {
        public var description: String?
        public var netAmount: String?
        /// A canonical category id from the supplied list, or `null`.
        public var categoryHint: String?
        public var assetCandidate: Bool
    }

    public enum PaidIndicator: String, Codable, Sendable, Hashable, CaseIterable {
        case paid, unpaid, partiallyPaid, unknown
    }

    public struct PaymentInfo: Codable, Sendable, Hashable {
        public var paymentMethodHint: PaymentMethod?
        public var paidIndicator: PaidIndicator?
        public var paymentDate: String?
        public var iban: String?
        public var reference: String?
    }

    public var documentType: DocumentType
    public var direction: Direction
    public var counterparty: Counterparty
    public var invoice: Invoice
    public var taxComponents: [TaxComponent]
    public var taxTreatmentHint: TreatmentHint
    public var lineItems: [LineItem]
    public var paymentInfo: PaymentInfo
    public var missingFields: [String]
    public var warnings: [String]

    /// `missingFields` and `warnings` default to empty so the ground-truth
    /// `expected.json` fixtures, which may omit them, decode unchanged.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentType = try container.decode(DocumentType.self, forKey: .documentType)
        direction = try container.decode(Direction.self, forKey: .direction)
        counterparty = try container.decode(Counterparty.self, forKey: .counterparty)
        invoice = try container.decode(Invoice.self, forKey: .invoice)
        taxComponents = try container.decode([TaxComponent].self, forKey: .taxComponents)
        taxTreatmentHint = try container.decode(TreatmentHint.self, forKey: .taxTreatmentHint)
        lineItems = try container.decode([LineItem].self, forKey: .lineItems)
        paymentInfo = try container.decode(PaymentInfo.self, forKey: .paymentInfo)
        missingFields = try container.decodeIfPresent([String].self, forKey: .missingFields) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
