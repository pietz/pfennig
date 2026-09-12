import AI
import Foundation
import Testing

/// Error mapping, retry policy and document preparation - the parts of the
/// client that must behave without touching the network (spec 33, 10.4).
@Suite("OpenAI-Client")
struct ClientTests {
    private func body(_ message: String) -> Data {
        Data(#"{"error":{"message":"\#(message)"}}"#.utf8)
    }

    @Test("HTTP-Status wird auf typisierte Fehler abgebildet")
    func errorMapping() {
        #expect(OpenAIResponsesClient.error(status: 401, headers: [:], body: Data()) == .unauthorized)
        #expect(OpenAIResponsesClient.error(status: 403, headers: [:], body: Data()) == .forbidden)
        #expect(
            OpenAIResponsesClient.error(status: 429, headers: ["Retry-After": "12"], body: Data())
                == .rateLimited(retryAfter: 12)
        )
        #expect(OpenAIResponsesClient.error(status: 500, headers: [:], body: Data()) == .server(
            status: 500,
            message: nil
        ))
        if case .badRequest = OpenAIResponsesClient.error(status: 400, headers: [:], body: body("bad schema")) {
        } else {
            Issue.record("400 muss badRequest ergeben")
        }
    }

    @Test("Nur 429, 500 und 503 werden wiederholt, höchstens dreimal")
    func retryPolicy() {
        let policy = RetryPolicy()
        #expect(policy.shouldRetry(.rateLimited(retryAfter: nil), attempt: 1))
        #expect(policy.shouldRetry(.server(status: 503, message: nil), attempt: 2))
        #expect(!policy.shouldRetry(.server(status: 503, message: nil), attempt: 3))
        #expect(!policy.shouldRetry(.unauthorized, attempt: 1))
        #expect(!policy.shouldRetry(.server(status: 502, message: nil), attempt: 1))
        #expect(!policy.shouldRetry(.refused("nein"), attempt: 1))
    }

    @Test("Backoff wächst exponentiell, Retry-After hat Vorrang")
    func backoff() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 30)
        #expect(policy.delay(forAttempt: 1, retryAfter: nil, jitter: 1) == 1)
        #expect(policy.delay(forAttempt: 2, retryAfter: nil, jitter: 1) == 2)
        #expect(policy.delay(forAttempt: 3, retryAfter: nil, jitter: 1) == 4)
        #expect(policy.delay(forAttempt: 1, retryAfter: nil, jitter: 0) == 0.5)
        #expect(policy.delay(forAttempt: 3, retryAfter: 7, jitter: 1) == 7)
        #expect(policy.delay(forAttempt: 9, retryAfter: nil, jitter: 1) == 30)
    }

    @Test("Die Textausgabe wird aus dem output-Array gelesen")
    func outputText() throws {
        let json: [String: Any] = [
            "status": "completed",
            "output": [
                ["type": "reasoning", "summary": []],
                ["type": "message", "content": [["type": "output_text", "text": "{\"a\":1}"]]]
            ]
        ]
        #expect(try OpenAIResponsesClient.outputText(of: json) == "{\"a\":1}")
    }

    @Test("Ablehnung und Abbruch werden als Fehler gemeldet")
    func refusalAndIncomplete() {
        let refusal: [String: Any] = [
            "status": "completed",
            "output": [["type": "message", "content": [["type": "refusal", "refusal": "nein"]]]]
        ]
        #expect(throws: AIError.refused("nein")) { try OpenAIResponsesClient.outputText(of: refusal) }

        let incomplete: [String: Any] = [
            "status": "incomplete",
            "incomplete_details": ["reason": "max_output_tokens"]
        ]
        #expect(throws: AIError.incomplete(reason: "max_output_tokens")) {
            try OpenAIResponsesClient.outputText(of: incomplete)
        }
    }

    @Test("Token-Verbrauch wird gelesen")
    func usage() {
        let json: [String: Any] = [
            "usage": ["input_tokens": 10, "output_tokens": 20, "output_tokens_details": ["reasoning_tokens": 5]]
        ]
        #expect(OpenAIResponsesClient.usage(of: json) == TokenUsage(
            inputTokens: 10,
            outputTokens: 20,
            reasoningTokens: 5
        ))
    }

    @Test("Der Medientyp kommt aus dem Inhalt, nicht aus der Endung")
    func mimeSniffing() {
        #expect(DocumentPreparer.mimeType(data: Data("%PDF-1.4".utf8), filename: "beleg.jpg") == "application/pdf")
        #expect(DocumentPreparer.mimeType(data: Data([0xFF, 0xD8, 0xFF, 0xE0]), filename: "beleg.pdf") == "image/jpeg")
        #expect(DocumentPreparer.mimeType(data: Data([0x89, 0x50, 0x4E, 0x47]), filename: "x") == "image/png")
    }

    @Test("PDFs über dem Seitenlimit werden mit deutscher Meldung abgelehnt")
    func pageLimit() throws {
        let fixture = try #require(Support.fixtures().first)
        let prepared = try DocumentPreparer.prepare(fileAt: fixture.documentURL)
        #expect(prepared.kind == .pdf)
        #expect((prepared.pageCount ?? 0) >= 1)
        #expect(prepared.dataURL.hasPrefix("data:application/pdf;base64,"))

        do {
            _ = try DocumentPreparer.prepare(fileAt: fixture.documentURL, pageLimit: 0)
            Issue.record("Das Seitenlimit muss greifen")
        } catch let error as AIError {
            #expect(error.code == "AI_UNSUPPORTED_DOCUMENT")
            #expect(error.localizedDescription.contains("Seiten"))
        }
    }

    @Test("Unbekannte Formate werden abgelehnt")
    func unsupportedFormat() {
        #expect(throws: AIError.self) {
            try DocumentPreparer.prepare(data: Data("hallo".utf8), filename: "notiz.txt")
        }
    }
}
