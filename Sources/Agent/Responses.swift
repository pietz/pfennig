import Foundation

/// Everything that can go wrong between the app and OpenAI, in German,
/// because the text ends up in the inbox next to the file.
public enum Agentenfehler: Error, LocalizedError {
    case keinSchluessel
    case netzwerk(String)
    case api(status: Int, text: String)
    case antwort(String)
    case zuVieleWerkzeugaufrufe

    public var errorDescription: String? {
        switch self {
        case .keinSchluessel:
            "Kein API-Schlüssel hinterlegt. Der Schlüssel steht in den Einstellungen unter KI-Zugang."
        case let .netzwerk(text):
            "Die Verbindung zu OpenAI kam nicht zustande: \(text)"
        case let .api(status, text):
            "OpenAI hat mit \(status) geantwortet: \(text)"
        case let .antwort(text):
            "Die Antwort war unbrauchbar: \(text)"
        case .zuVieleWerkzeugaufrufe:
            "Der Agent hat nach \(Agentenlauf.hoechstzahlWerkzeugaufrufe) sql-Aufrufen kein Ergebnis geliefert."
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

    let schluessel: String
    let transport: Transport

    /// The transport the app uses. Tests never touch it.
    public static let netz: Transport = { anfrage in
        let (daten, antwort) = try await URLSession.shared.data(for: anfrage)
        guard let http = antwort as? HTTPURLResponse else {
            throw Agentenfehler.netzwerk("Keine HTTP-Antwort.")
        }
        return (daten, http)
    }

    /// The smallest request that proves key and connection: no tools, no file,
    /// a handful of tokens. It throws what the settings window shows.
    public static func verbindungPruefen(transport: @escaping Transport = netz) async throws {
        guard let schluessel = Schluesselbund.lesen(), schluessel.isEmpty == false else {
            throw Agentenfehler.keinSchluessel
        }
        _ = try await Responses(schluessel: schluessel, transport: transport).senden([
            "model": Agentenlauf.modell,
            "reasoning": ["effort": "none"],
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
    func senden(_ koerper: [String: Any]) async throws -> [String: Any] {
        do {
            return try await einmalSenden(koerper)
        } catch let absage as Absage where absage.voruebergehend {
            try await Task.sleep(for: .seconds(absage.wartezeit ?? 2))
            do {
                return try await einmalSenden(koerper)
            } catch let zweite as Absage {
                throw Agentenfehler.api(status: zweite.status, text: zweite.text)
            }
        } catch let absage as Absage {
            throw Agentenfehler.api(status: absage.status, text: absage.text)
        }
    }

    private func einmalSenden(_ koerper: [String: Any]) async throws -> [String: Any] {
        var anfrage = URLRequest(url: Responses.adresse)
        anfrage.httpMethod = "POST"
        anfrage.setValue("Bearer \(schluessel)", forHTTPHeaderField: "Authorization")
        anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
        anfrage.httpBody = try JSONSerialization.data(withJSONObject: koerper)
        anfrage.timeoutInterval = 300

        let daten: Data
        let http: HTTPURLResponse
        do {
            (daten, http) = try await transport(anfrage)
        } catch let fehler as Agentenfehler {
            throw fehler
        } catch {
            throw Agentenfehler.netzwerk(error.localizedDescription)
        }
        guard http.statusCode == 200 else {
            throw Absage(
                status: http.statusCode,
                text: Responses.meldung(daten) ?? String(decoding: daten.prefix(400), as: UTF8.self),
                wartezeit: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            )
        }
        guard let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any] else {
            throw Agentenfehler.antwort("Die Antwort war kein JSON-Objekt.")
        }
        return objekt
    }

    static func meldung(_ daten: Data) -> String? {
        guard let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let fehler = objekt["error"] as? [String: Any]
        else { return nil }
        return fehler["message"] as? String
    }
}
