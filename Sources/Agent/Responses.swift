import Core
import Foundation

/// Everything that can go wrong between the app and OpenAI, in German,
/// because the text ends up in the inbox next to the file.
public enum AgentError: Error, LocalizedError {
    case keinSchluessel
    case netzwerk(String)
    case api(status: Int, text: String)
    case response(String)
    case keineBuchung
    case zuVieleWerkzeugaufrufe

    public var errorDescription: String? {
        switch self {
        case .keinSchluessel:
            "Kein API-Schlüssel hinterlegt. Der Schlüssel steht in den Einstellungen unter KI-Zugang."
        case let .netzwerk(text):
            "Die Verbindung zu OpenAI kam nicht zustande: \(text)"
        case let .api(status, text):
            "OpenAI hat mit \(status) geantwortet: \(text)"
        case let .response(text):
            "Die Antwort war unbrauchbar: \(text)"
        case .keineBuchung:
            "Der Agent hat keine Buchung angelegt oder geändert."
        case .zuVieleWerkzeugaufrufe:
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
    static let adresse = URL(string: "https://api.openai.com/v1/responses")!

    let key: String
    let transport: Transport

    /// The transport the app uses. Tests never touch it.
    public static let netz: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.netzwerk("Keine HTTP-Antwort.")
        }
        return (data, http)
    }

    /// The smallest request that proves key and connection: no tools, no file,
    /// a handful of tokens. It throws what the settings window shows.
    public static func testConnection(transport: @escaping Transport = netz) async throws {
        guard let key = Keychain.read(), key.isEmpty == false else {
            throw AgentError.keinSchluessel
        }
        _ = try await Responses(key: key, transport: transport).send([
            // The cheapest model at the lowest effort; this asks the key, not the choice.
            "model": Modell.luna.rawValue,
            "reasoning": ["effort": Denkaufwand.keiner.rawValue],
            "max_output_tokens": 16,
            "input": "Antworte nur mit OK."
        ])
    }

    /// One failed attempt, with the wait OpenAI asked for.
    private struct Absage: Error {
        var status: Int
        var text: String
        var wartezeit: Double?

        /// Rate limits and server errors pass; a bad key or a bad request does not.
        var voruebergehend: Bool {
            status == 429 || status >= 500
        }
    }

    /// Sends the body and answers with the parsed response object. A rate limit
    /// or a server error is tried once more, after `Retry-After` when it is there.
    func send(_ body: [String: Any]) async throws -> [String: Any] {
        do {
            return try await sendOnce(body)
        } catch let absage as Absage where absage.voruebergehend {
            try await Task.sleep(for: .seconds(absage.wartezeit ?? 2))
            do {
                return try await sendOnce(body)
            } catch let zweite as Absage {
                throw AgentError.api(status: zweite.status, text: zweite.text)
            }
        } catch let absage as Absage {
            throw AgentError.api(status: absage.status, text: absage.text)
        }
    }

    private func sendOnce(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: Responses.adresse)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport(request)
        } catch let fehler as AgentError {
            throw fehler
        } catch {
            throw AgentError.netzwerk(error.localizedDescription)
        }
        guard http.statusCode == 200 else {
            throw Absage(
                status: http.statusCode,
                text: Responses.meldung(data) ?? String(decoding: data.prefix(400), as: UTF8.self),
                wartezeit: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            )
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.response("Die Antwort war kein JSON-Objekt.")
        }
        return object
    }

    static func meldung(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fehler = object["error"] as? [String: Any]
        else { return nil }
        return fehler["message"] as? String
    }
}
