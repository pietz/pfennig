import Agent
import Foundation

/// Replays exchange-rate answers from `fx-rates.json` beside the truth file,
/// so a rerun converts with the same rates. The agent's only GET requests are
/// rate lookups; one not stored yet is fetched once and added. OpenAI
/// requests pass through.
actor RateCache {
    private let file: URL
    private var answers: [String: String]

    init(file: URL) throws {
        self.file = file
        answers = try FileManager.default.fileExists(atPath: file.path)
            ? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
            : [:]
    }

    nonisolated func transport(over network: @escaping Transport) -> Transport {
        { request in
            guard request.httpMethod == "GET", let url = request.url else { return try await network(request) }
            if let stored = await self.answers[url.absoluteString],
               let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            {
                return (Data(stored.utf8), response)
            }
            let (data, response) = try await network(request)
            if response.statusCode == 200 {
                try await self.store(String(decoding: data, as: UTF8.self), for: url)
            }
            return (data, response)
        }
    }

    private func store(_ answer: String, for url: URL) throws {
        answers[url.absoluteString] = answer
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(answers).write(to: file, options: .atomic)
    }
}
