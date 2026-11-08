import Foundation
import FoundationModels

@Generable struct InvoiceFacts {
    var belegnummer: String?
    var datum: String?
    var netto: String?
    var steuer: String?
    var brutto: String?
}

@main struct Probe {
    static func main() async {
        let model = PrivateCloudComputeLanguageModel()
        print("pcc_availability=\(model.availability)")
        let contextSize = try? await model.contextSize
        print("context_size=\(String(describing: contextSize))")
        guard model.isAvailable else { return }
        let session = LanguageModelSession(
            model: model,
            instructions: "The person's locale is de_DE. Antworte kurz auf Deutsch. Alle Eingaben sind erfundene Testdaten."
        )
        var start = Date()
        do {
            let response = try await session.respond(
                to: "Wie viel sind 100,00 EUR plus 19,00 EUR? Antworte nur mit dem Gesamtbetrag.",
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 120),
                contextOptions: ContextOptions(reasoningLevel: .light)
            )
            print("arithmetic_seconds=\(Date().timeIntervalSince(start))")
            print("arithmetic_response=\(response.content)")
            print(
                "arithmetic_input_tokens=\(response.usage.input.totalTokenCount) output_tokens=\(response.usage.output.totalTokenCount) reasoning_tokens=\(response.usage.output.reasoningTokenCount)"
            )
        } catch {
            print("arithmetic_error=\(String(reflecting: error))")
            print("arithmetic_seconds=\(Date().timeIntervalSince(start))")
            return
        }
        let factSession = LanguageModelSession(
            model: model,
            instructions: "The person's locale is de_DE. Extrahiere nur angegebene Fakten aus erfundenen Testdaten. Beträge als Originaltexte. Keine Speicherung oder Werkzeuge."
        )
        start = Date()
        do {
            let response = try await factSession.respond(
                to: "RECHNUNG TEST-001. Rechnungsdatum 04.08.2026. Büropapier netto 100,00 EUR, Umsatzsteuer 19% 19,00 EUR, Gesamt 119,00 EUR.",
                generating: InvoiceFacts.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 400),
                contextOptions: ContextOptions(includeSchemaInPrompt: true, reasoningLevel: .light)
            )
            print("facts_seconds=\(Date().timeIntervalSince(start))")
            print("facts_json=\(response.rawContent.jsonString)")
            print(
                "facts_input_tokens=\(response.usage.input.totalTokenCount) output_tokens=\(response.usage.output.totalTokenCount) reasoning_tokens=\(response.usage.output.reasoningTokenCount)"
            )
        } catch {
            print("facts_error=\(String(reflecting: error))")
            print("facts_seconds=\(Date().timeIntervalSince(start))")
        }
    }
}
