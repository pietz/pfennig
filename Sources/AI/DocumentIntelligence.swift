import Domain
import Foundation

/// A document ready to be sent to the model: PDF bytes or an image the API
/// accepts (spec 10.4). `DocumentPreparer` is the only producer.
public struct PreparedDocument: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case pdf, image
    }

    public var kind: Kind
    public var data: Data
    public var filename: String
    public var mimeType: String
    /// PDF page count; `nil` for images.
    public var pageCount: Int?

    public init(kind: Kind, data: Data, filename: String, mimeType: String, pageCount: Int? = nil) {
        self.kind = kind
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
        self.pageCount = pageCount
    }

    /// `data:<mime>;base64,…`, the form both `input_file` and `input_image` take.
    public var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

/// Everything Swift puts in front of the model (spec 42). No transaction data.
public struct ExtractionContext: Sendable, Hashable {
    public struct Business: Sendable, Hashable {
        public var name: String
        public var legalName: String?
        public var countryCode: String
        public var vatId: String?
        public var vatStatus: VATStatus
        public var accountingMethod: VATAccountingMethod

        public init(
            name: String,
            legalName: String? = nil,
            countryCode: String = "DE",
            vatId: String? = nil,
            vatStatus: VATStatus = .taxable,
            accountingMethod: VATAccountingMethod = .cash
        ) {
            self.name = name
            self.legalName = legalName
            self.countryCode = countryCode
            self.vatId = vatId
            self.vatStatus = vatStatus
            self.accountingMethod = accountingMethod
        }
    }

    /// One canonical category id with its German one-liner (spec 42).
    public struct CategoryOption: Sendable, Hashable {
        public var id: String
        public var nameDE: String

        public init(id: String, nameDE: String) {
            self.id = id
            self.nameDE = nameDE
        }
    }

    public var business: Business
    public var categories: [CategoryOption]
    /// Treatments the app supports, including the document-evidenced
    /// `smallBusiness` hint (§19 UStG).
    public var treatments: [TaxTreatment]

    public init(
        business: Business,
        categories: [CategoryOption],
        treatments: [TaxTreatment] = TaxTreatment.allCases
    ) {
        self.business = business
        self.categories = categories
        self.treatments = treatments
    }

    public var categoryIDs: [String] {
        categories.map(\.id)
    }
}

/// Billing-relevant counters of one model run (spec 17.18).
public struct TokenUsage: Codable, Sendable, Hashable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, reasoningTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }
}

/// The result of one extraction call plus what `model_runs` needs to store.
public struct ExtractionOutcome: Sendable {
    public var extraction: DocumentExtraction
    public var model: String
    public var usage: TokenUsage?
    /// The verbatim response body, retained for replay tests (spec 31).
    public var rawResponseJSON: String?
    /// Request metadata without document content and without the key (spec 17.18).
    public var requestMetadataJSON: String?

    public init(
        extraction: DocumentExtraction,
        model: String,
        usage: TokenUsage? = nil,
        rawResponseJSON: String? = nil,
        requestMetadataJSON: String? = nil
    ) {
        self.extraction = extraction
        self.model = model
        self.usage = usage
        self.rawResponseJSON = rawResponseJSON
        self.requestMetadataJSON = requestMetadataJSON
    }
}

/// The single AI entry point of V1 (spec 10.1). `disambiguate` and
/// `inferStatementColumnMapping` arrive with milestone M6 together with the
/// statement and payment types they need.
public protocol DocumentIntelligenceProvider: Sendable {
    func extract(document: PreparedDocument, context: ExtractionContext) async throws -> ExtractionOutcome
}
