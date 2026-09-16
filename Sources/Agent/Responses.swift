import Core
import Foundation

/// Everything that can go wrong between the app and OpenAI, in German,
/// because the text ends up in the inbox next to the file.
public enum AgentError: Error, LocalizedError {
    case missingKey
    case network(String)
    case api(status: Int, text: String)
    case response(String)
    case noBooking
    case tooManyToolCalls
    case textTooLarge

    public var errorDescription: String? {
        switch self {
        case .textTooLarge:
            "Die Textdatei ist größer als \(FileInput.maxTextBytes / 1_000_000) MB und geht nicht an den Agenten."
        case .missingKey:
            "Kein API-Schlüssel hinterlegt. Der Schlüssel steht in den Einstellungen unter KI-Zugang."
        case let .network(text):
            "Die Verbindung zu OpenAI kam nicht zustande: \(text)"
        case let .api(status, text):
            "OpenAI hat mit \(status) geantwortet: \(text)"
        case let .response(text):
            "Die Antwort war unbrauchbar: \(text)"
        case .noBooking:
            "Der Agent hat keine Buchung angelegt oder geändert."
        case .tooManyToolCalls:
            "Der Agent hat nach \(AgentRun.maxToolCalls) sql-Aufrufen kein Ergebnis geliefert."
        }
    }
}

/// The one injection point of this target. Tests hand in a closure that
/// answers from a script; the app hands in nothing and gets `URLSession`.
public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

/// `POST /v1/responses` and nothing else: one request, one JSON object back,
/// a single retry on the transient status codes.
public struct Responses: Sendable {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    let key: String
    let transport: Transport
    /// The wait before a failed connection is tried once more.
    var networkRetryDelay: Duration = .seconds(3)

    /// The transport the app uses. Tests never touch it.
    public static let network: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.network("Keine HTTP-Antwort.")
        }
        return (data, http)
    }

    /// The smallest request that proves key and connection: no tools, no file,
    /// a handful of tokens. It throws what the settings window shows.
    public static func testConnection(transport: @escaping Transport = network) async throws {
        guard let key = Keychain.read(), key.isEmpty == false else {
            throw AgentError.missingKey
        }
        _ = try await Responses(key: key, transport: transport).send([
            // The cheapest model at the lowest effort; this asks the key, not the choice.
            "model": Model.luna.rawValue,
            "reasoning": ["effort": ReasoningEffort.none.rawValue],
            "max_output_tokens": 16,
            "input": "Antworte nur mit OK."
        ])
    }

    /// One failed attempt, with the wait OpenAI asked for.
    private struct Rejection: Error {
        var status: Int
        var text: String
        var retryAfter: Double?

        /// Rate limits and server errors pass; a bad key or a bad request does not.
        var isTransient: Bool {
            status == 429 || status >= 500
        }
    }

    /// Sends the body and answers with the parsed response object. A rate limit
    /// or a server error is tried once more, after `Retry-After` when it is
    /// there. So is a failed connection: macOS drops a burst of large uploads
    /// over HTTP/3 with "Message too long" and falls back to HTTP/2 for the
    /// host afterwards, so the same request tends to go through a moment later.
    func send(_ body: [String: Any]) async throws -> [String: Any] {
        do {
            return try await sendOnce(body)
        } catch let rejection as Rejection where rejection.isTransient {
            try await Task.sleep(for: .seconds(rejection.retryAfter ?? 2))
            return try await sendAgain(body)
        } catch let rejection as Rejection {
            throw AgentError.api(status: rejection.status, text: rejection.text)
        } catch AgentError.network(_) {
            try await Task.sleep(for: networkRetryDelay)
            return try await sendAgain(body)
        }
    }

    private func sendAgain(_ body: [String: Any]) async throws -> [String: Any] {
        do {
            return try await sendOnce(body)
        } catch let second as Rejection {
            throw AgentError.api(status: second.status, text: second.text)
        }
    }

    private func sendOnce(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: Responses.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport(request)
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.network(error.localizedDescription)
        }
        guard http.statusCode == 200 else {
            throw Rejection(
                status: http.statusCode,
                text: Responses.errorMessage(data) ?? String(decoding: data.prefix(400), as: UTF8.self),
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            )
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.response("Die Antwort war kein JSON-Objekt.")
        }
        return object
    }

    static func errorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}
