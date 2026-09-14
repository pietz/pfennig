import Domain
import Foundation

/// The strict JSON schema of `DocumentExtraction` (spec 13, 10.6).
///
/// Structured Outputs under `strict: true` allow no optional keys: every
/// property is listed in `required`, every object sets
/// `additionalProperties: false`, and "absent" is expressed by widening the
/// type to include `null`.
public enum ExtractionSchema {
    public static let name = "document_extraction"

    /// Builds the schema; the category enum is injected from the seeded
    /// category list so the model can only return canonical ids (spec 13).
    public static func schema(categoryIDs: [String]) -> [String: Any] {
        object([
            "documentType": enumeration(DocumentType.allCases.map(\.rawValue)),
            "direction": enumeration(Direction.allCases.map(\.rawValue)),
            "counterparty": object([
                "name": nullable("string"),
                "countryCode": nullable("string"),
                "vatId": nullable("string"),
                "street": nullable("string"),
                "postalCode": nullable("string"),
                "city": nullable("string")
            ]),
            "invoice": object([
                "invoiceNumber": nullable("string"),
                "invoiceDate": nullable("string"),
                "serviceDate": nullable("string"),
                "servicePeriodStart": nullable("string"),
                "servicePeriodEnd": nullable("string"),
                "currency": nullable("string"),
                "netAmount": nullable("string"),
                "taxAmount": nullable("string"),
                "grossAmount": nullable("string"),
                "statedEurEquivalent": nullable("string")
            ]),
            "taxComponents": array(object([
                "rate": nullable("string"),
                "netAmount": nullable("string"),
                "taxAmount": nullable("string"),
                "kind": enumeration(TaxComponentKind.allCases.map(\.rawValue))
            ])),
            "taxTreatmentHint": object([
                "treatment": enumeration(TaxTreatment.allCases.map(\.rawValue))
            ]),
            "lineItems": array(object([
                "description": nullable("string"),
                "netAmount": nullable("string"),
                "categoryHint": nullableEnumeration(categoryIDs),
                "assetCandidate": ["type": "boolean"]
            ])),
            "paymentInfo": object([
                "paymentMethodHint": nullableEnumeration(PaymentMethod.allCases.map(\.rawValue)),
                "paidIndicator": nullableEnumeration(DocumentExtraction.PaidIndicator.allCases.map(\.rawValue)),
                "paymentDate": nullable("string"),
                "iban": nullable("string"),
                "reference": nullable("string")
            ]),
            "missingFields": array(["type": "string"]),
            "warnings": array(["type": "string"])
        ])
    }

    /// The `text.format` value of the request body.
    public static func textFormat(categoryIDs: [String]) -> [String: Any] {
        [
            "type": "json_schema",
            "name": name,
            "strict": true,
            "schema": schema(categoryIDs: categoryIDs)
        ]
    }

    // MARK: - Builders

    /// An object with every property required and no extra keys.
    public static func object(_ properties: [String: Any]) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": properties.keys.sorted(),
            "additionalProperties": false
        ]
    }

    static func array(_ items: [String: Any]) -> [String: Any] {
        ["type": "array", "items": items]
    }

    static func nullable(_ type: String) -> [String: Any] {
        ["type": [type, "null"]]
    }

    static func enumeration(_ values: [String]) -> [String: Any] {
        ["type": "string", "enum": values]
    }

    static func nullableEnumeration(_ values: [String]) -> [String: Any] {
        var members: [Any] = values
        members.append(NSNull())
        return ["type": ["string", "null"], "enum": members]
    }
}
