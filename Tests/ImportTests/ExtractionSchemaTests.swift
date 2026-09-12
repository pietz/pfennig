import AI
import Domain
import Foundation
import Testing

/// Structured Outputs under `strict: true` accept no optional keys and no
/// open objects (spec 10.6, docs/openai-responses-api.md §2).
@Suite("Extraktionsschema")
struct ExtractionSchemaTests {
    private func schema() -> [String: Any] {
        ExtractionSchema.schema(categoryIDs: ["software_subscriptions", "uncategorized"])
    }

    /// Walks every nested object and reports the ones that break a rule.
    private func violations(_ node: Any, path: String = "$") -> [String] {
        guard let object = node as? [String: Any] else { return [] }
        var problems: [String] = []
        let types = (object["type"] as? [String]) ?? (object["type"] as? String).map { [$0] } ?? []
        if types.contains("object") {
            guard let properties = object["properties"] as? [String: Any] else {
                return ["\(path): object without properties"]
            }
            if object["additionalProperties"] as? Bool != false {
                problems.append("\(path): additionalProperties is not false")
            }
            let required = Set((object["required"] as? [String]) ?? [])
            if required != Set(properties.keys) {
                problems.append("\(path): required \(required.sorted()) != properties \(properties.keys.sorted())")
            }
            for (key, value) in properties {
                problems += violations(value, path: "\(path).\(key)")
            }
        }
        if types.contains("array"), let items = object["items"] {
            problems += violations(items, path: "\(path)[]")
        }
        return problems
    }

    @Test("Jedes Objekt ist geschlossen und verlangt alle Felder")
    func strict() throws {
        #expect(violations(schema()).isEmpty)
    }

    @Test("Das Schema ist gültiges JSON")
    func serializable() throws {
        let data = try JSONSerialization.data(withJSONObject: schema())
        #expect(data.count > 0)
    }

    @Test("Die Kategorien kommen aus der übergebenen Liste")
    func categoryEnum() throws {
        let lineItems = schema()["properties"] as? [String: Any]
        let items = (lineItems?["lineItems"] as? [String: Any])?["items"] as? [String: Any]
        let hint = (items?["properties"] as? [String: Any])?["categoryHint"] as? [String: Any]
        let members = hint?["enum"] as? [Any] ?? []
        #expect(members.count == 3) // two ids plus null
        #expect(members.contains { $0 as? String == "software_subscriptions" })
        #expect(members.contains { $0 is NSNull })
    }

    @Test("Alle Domain-Enums sind vollständig abgebildet")
    func enums() throws {
        let properties = schema()["properties"] as? [String: Any]
        let documentType = properties?["documentType"] as? [String: Any]
        #expect(documentType?["enum"] as? [String] == DocumentType.allCases.map(\.rawValue))
        let hint = (properties?["taxTreatmentHint"] as? [String: Any])?["properties"] as? [String: Any]
        let treatment = hint?["treatment"] as? [String: Any]
        #expect(treatment?["enum"] as? [String] == TaxTreatment.allCases.map(\.rawValue))
    }

    @Test("Der Prompt trägt Betrieb, Kategorien und Behandlungen")
    func prompt() throws {
        let rendered = ExtractionPrompt.render(
            ExtractionContext(
                business: .init(name: "Mara Beispiel", vatId: "DE999999999"),
                categories: [.init(id: "software_subscriptions", nameDE: "Software-Abonnements")]
            )
        )
        #expect(rendered.contains("Mara Beispiel"))
        #expect(rendered.contains("DE999999999"))
        #expect(rendered.contains("`software_subscriptions` — Software-Abonnements"))
        #expect(rendered.contains("`reverseCharge`"))
        #expect(!rendered.contains("{{"))
    }
}
