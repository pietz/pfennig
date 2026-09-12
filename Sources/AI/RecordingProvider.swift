import Foundation

/// Replays a recorded OpenAI response from `Fixtures/documents/<n>/response.json`
/// so the whole pipeline runs offline (spec 40.2). With `live` set and no
/// recording present, it calls the real client once and writes the response
/// for later replays.
public struct RecordingProvider: DocumentIntelligenceProvider {
    public let responseURL: URL
    public let live: (any DocumentIntelligenceProvider)?
    /// Records even when a recording already exists.
    public let overwrite: Bool

    public init(responseURL: URL, live: (any DocumentIntelligenceProvider)? = nil, overwrite: Bool = false) {
        self.responseURL = responseURL
        self.live = live
        self.overwrite = overwrite
    }

    public var hasRecording: Bool {
        FileManager.default.fileExists(atPath: responseURL.path(percentEncoded: false))
    }

    public func extract(document: PreparedDocument, context: ExtractionContext) async throws -> ExtractionOutcome {
        if let live, overwrite || !hasRecording {
            let outcome = try await live.extract(document: document, context: context)
            if let raw = outcome.rawResponseJSON {
                try? FileManager.default.createDirectory(
                    at: responseURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(raw.utf8).write(to: responseURL)
            }
            return outcome
        }
        return try replay()
    }

    /// Parses the recorded body with the same code path as a live response.
    public func replay() throws -> ExtractionOutcome {
        guard let data = try? Data(contentsOf: responseURL) else {
            throw AIError.invalidResponse("Keine Aufzeichnung unter \(responseURL.lastPathComponent).")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AIError.invalidResponse("Die Aufzeichnung war kein JSON-Objekt.")
        }
        let text = try OpenAIResponsesClient.outputText(of: json)
        guard let payload = text.data(using: .utf8) else {
            throw AIError.invalidResponse("Die Aufzeichnung war kein UTF-8.")
        }
        do {
            return ExtractionOutcome(
                extraction: try JSONDecoder().decode(DocumentExtraction.self, from: payload),
                model: json["model"] as? String ?? "recorded",
                usage: OpenAIResponsesClient.usage(of: json),
                rawResponseJSON: String(decoding: data, as: UTF8.self)
            )
        } catch {
            throw AIError.invalidResponse("Die Aufzeichnung passte nicht zum Schema: \(error)")
        }
    }
}
