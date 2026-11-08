import CoreGraphics
import Foundation
import FoundationModels
import Vision

@Generable struct FactLine {
    @Guide(description: "Originaltext des Betrags, ohne Umrechnung oder Berechnung.") var betrag: String?
    var beschreibung: String?
}

@Generable struct DocumentFacts {
    var datum: String?
    var belegnummer: String?
    @Guide(description: "Nur tatsächlich im Dokument stehende Beträge.", .maximumCount(8)) var zeilen: [FactLine]
}

func apiProbe(image: CGImage, instructions: String) async throws {
    let model = SystemLanguageModel.default
    let tools: [any Tool] = [OCRTool(name: "ocr", description: "Liest Text aus dem angehängten Bild.")]
    let session = LanguageModelSession(
        model: model,
        tools: tools,
        instructions: "The person's locale is de_DE. Antworte auf Deutsch. " + instructions
    )
    let prompt = Prompt { "Lies Bild beleg09 mit ocr."; Attachment(image).label("beleg09") }
    let required = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 600, toolCallingMode: .required)
    _ = try await session.respond(to: prompt, options: required)
    _ = try await session.respond(
        to: prompt,
        generating: DocumentFacts.self,
        options: GenerationOptions(samplingMode: .greedy, toolCallingMode: .disallowed),
        contextOptions: ContextOptions(includeSchemaInPrompt: true)
    )
    print(model.contextSize)
    try await print(model.tokenCount(for: Instructions(instructions)))
    try await print(model.tokenCount(for: tools))
    try await print(model.tokenCount(for: prompt))
    try await print(model.tokenCount(for: DocumentFacts.generationSchema))
    try await print(model.tokenCount(for: session.transcript))
    print(session.usage.input.totalTokenCount, session.usage.output.totalTokenCount)
    _ = GenerationOptions(samplingMode: .random(top: 20, seed: 123), temperature: 0.2)
}

@main struct Probe {
    static func main() async {
        let model = SystemLanguageModel.default
        print("on_device_availability=\(model.availability)")
        print("context_size=\(model.contextSize)")
        print("german=\(model.supportsLocale(Locale(identifier: "de_DE")))")
        let pcc = PrivateCloudComputeLanguageModel()
        print("pcc_availability=\(pcc.availability)")
        // Deliberately no PCC session, prompt or inference.
        print("ocr_tool_name=\(OCRTool().name)")
        print("fact_schema=\(DocumentFacts.generationSchema)")
    }
}
