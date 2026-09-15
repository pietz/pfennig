import Core
import Foundation

/// The file as it goes to the model: PDF and images as base64 data URLs, CSV
/// as plain text. Nothing is prepared or converted, the file goes as it is.
public struct FileInput: Sendable {
    public var name: String
    public var endung: String
    public var sha256: String
    public var data: Data

    public init(name: String, endung: String, sha256: String, data: Data) {
        self.name = name
        self.endung = endung
        self.sha256 = sha256
        self.data = data
    }

    /// No HEIC: the API does not take it, and Pfennig converts nothing.
    static let erlaubteEndungen = ["pdf", "png", "jpg", "jpeg", "csv"]

    var mediaType: String {
        switch endung.lowercased() {
        case "pdf": "application/pdf"
        case "png": "image/png"
        case "csv": "text/csv"
        default: "image/jpeg"
        }
    }

    /// One content item of the user message.
    var content: [String: Any] {
        let dataURL = "data:\(mediaType);base64,\(data.base64EncodedString())"
        switch endung.lowercased() {
        case "pdf":
            return ["type": "input_file", "filename": name, "file_data": dataURL]
        case "csv":
            return ["type": "input_text", "text": String(decoding: data, as: UTF8.self)]
        default:
            return ["type": "input_image", "image_url": dataURL, "detail": "high"]
        }
    }
}

/// What one run left behind.
public struct RunResult: Sendable {
    public var beruehrt: [Int64] = []
    public var angelegt: [Int64] = []
    public var summary = ""
}

/// A run that gave up, with the bookings it had already written. Swift removes
/// them before the file is tried again, so nothing doubles.
public struct RunAbort: Error, LocalizedError {
    public var angelegt: [Int64]
    public var grund: any Error

    public var errorDescription: String? {
        grund.localizedDescription
    }
}

/// One file, one run: the tool loop over the Responses API. The model is fixed
/// in the code, there is no choice in the settings.
public struct AgentRun: Sendable {
    public static let maxToolCalls = 25

    let repository: Repository
    let tool: SQLTool
    /// Read once per run from the Keychain, never kept anywhere else.
    let key: String
    let transport: Transport

    public init(
        repository: Repository,
        tool: SQLTool,
        key: String,
        transport: @escaping Transport = Responses.netz
    ) {
        self.repository = repository
        self.tool = tool
        self.key = key
        self.transport = transport
    }

    /// The SQL tool the agent gets, in the shape the Responses API expects.
    static var sqlToolDescription: [String: Any] {
        [
            "type": "function",
            "name": "sql",
            "description": """
            Führt genau eine SQL-Anweisung auf der Buchhaltungsdatenbank aus. \(SQLTool.allowed) Ein \
            SELECT antwortet mit den Zeilen als JSON, ein Schreibvorgang mit den berührten Buchungs-IDs \
            oder mit dem Text der verletzten Prüfregel.
            """,
            "parameters": [
                "type": "object",
                "properties": ["sql": ["type": "string", "description": "Eine einzelne SQL-Anweisung."]],
                "required": ["sql"],
                "additionalProperties": false
            ],
            "strict": true
        ]
    }

    /// The sole additional tool: it receives original major-unit amounts and
    /// returns their EUR cents plus the reference-rate provenance.
    static var conversionToolDescription: [String: Any] {
        [
            "type": "function",
            "name": "umrechnen",
            "description": "Holt einmal den historischen Frankfurter-Referenzkurs für eine Währung und ein Datum und rechnet alle gelieferten Originalbeträge in EUR-Cent um. Die API bekommt nur Währung und Datum; die Beträge werden lokal mit Decimal gerechnet.",
            "parameters": [
                "type": "object",
                "properties": [
                    "waehrung": [
                        "type": "string",
                        "description": "Dreistelliger ISO-Währungscode, zum Beispiel USD oder JPY."
                    ],
                    "datum": ["type": "string", "description": "Kursdatum als JJJJ-MM-TT."],
                    "betraege": [
                        "type": "array",
                        "description": "Originalbeträge in exakten Haupteinheiten als Dezimaltexte, ohne Währungssymbol.",
                        "items": ["type": "string"]
                    ]
                ],
                "required": ["waehrung", "datum", "betraege"],
                "additionalProperties": false
            ],
            "strict": true
        ]
    }

    /// Runs the loop and records it in `anfragen`, whatever the outcome.
    public func start(_ file: FileInput) async throws -> RunResult {
        let anleitung = try AgentInstructions.build(repository)
        let ki = try repository.aiSettings()
        let request = try repository.startRequest(dateiSha256: file.sha256, modell: ki.modell.rawValue)
        var protokoll = Trace()
        var result = RunResult()
        do {
            try await schleife(file, ki: ki, anleitung: anleitung, result: &result, protokoll: &protokoll)
            guard result.beruehrt.isEmpty == false else {
                throw AgentError.keineBuchung
            }
            try repository.finishRequest(
                id: request, status: .erfolg, eingabeTokens: protokoll.eingabeTokens,
                ausgabeTokens: protokoll.ausgabeTokens, konversation: protokoll.asJSON()
            )
            return result
        } catch {
            protokoll.steps.append(["fehler": error.localizedDescription])
            try? repository.finishRequest(
                id: request, status: .fehler, eingabeTokens: protokoll.eingabeTokens,
                ausgabeTokens: protokoll.ausgabeTokens, konversation: protokoll.asJSON()
            )
            throw RunAbort(angelegt: result.angelegt, grund: error)
        }
    }

    private func schleife(
        _ file: FileInput,
        ki: KiEinstellungen,
        anleitung: String,
        result: inout RunResult,
        protokoll: inout Trace
    ) async throws {
        let client = Responses(key: key, transport: transport)
        var calls = 0
        var previousResponse: String?
        var eingabe: [[String: Any]] = [
            ["role": "system", "content": anleitung],
            ["role": "user", "content": [
                file.content,
                ["type": "input_text", "text": "Verbuche dieses Dokument."]
            ]]
        ]

        while true {
            var body: [String: Any] = [
                "model": ki.modell.rawValue,
                "reasoning": ["effort": ki.aufwand.rawValue],
                "tools": [AgentRun.sqlToolDescription, AgentRun.conversionToolDescription],
                "input": eingabe
            ]
            if ki.schnell {
                // OpenAI's priority processing, about twice the price.
                body["service_tier"] = "priority"
            }
            if let previousResponse {
                body["previous_response_id"] = previousResponse
            }
            let response = try await client.send(body)
            protokoll.zaehle(response)
            previousResponse = response["id"] as? String
            try AgentRun.validateStatus(response)

            let callsThisRound = AgentRun.toolCalls(response)
            guard callsThisRound.isEmpty == false else {
                result.summary = AgentRun.text(response)
                protokoll.steps.append(["agent": result.summary])
                return
            }
            calls += callsThisRound.count
            guard calls <= AgentRun.maxToolCalls else {
                throw AgentError.zuVieleWerkzeugaufrufe
            }

            eingabe = []
            for aufruf in callsThisRound {
                let text: String
                switch aufruf.name {
                case "sql":
                    let sql = AgentRun.sql(aufruf.arguments)
                    let toolResult = tool.execute(sql)
                    result.beruehrt = Array(Set(result.beruehrt).union(toolResult.beruehrt)).sorted()
                    result.angelegt = Array(Set(result.angelegt).union(toolResult.angelegt)).sorted()
                    text = toolResult.text
                case "umrechnen":
                    text = await CurrencyConverter.execute(aufruf.arguments, transport: transport)
                default:
                    text = "Fehler: Unbekanntes Werkzeug \(aufruf.name). Verwende sql oder umrechnen."
                }
                let schritt = [
                    "werkzeug": aufruf.name,
                    "argumente": aufruf.arguments,
                    "ergebnis": text
                ]
                protokoll.steps.append(schritt)
                eingabe.append([
                    "type": "function_call_output",
                    "call_id": aufruf.callId,
                    "output": text
                ])
            }
        }
    }

    // MARK: - Antwort read

    struct ToolCall {
        var name: String
        var callId: String
        var arguments: String
    }

    /// `output` is an array of items, not a single message: a run answers with
    /// reasoning items, `function_call` items and at most one `message`.
    static func toolCalls(_ response: [String: Any]) -> [ToolCall] {
        ausgabe(response).compactMap { teil in
            guard teil["type"] as? String == "function_call",
                  let callId = teil["call_id"] as? String
            else { return nil }
            return ToolCall(
                name: teil["name"] as? String ?? "",
                callId: callId,
                arguments: teil["arguments"] as? String ?? "{}"
            )
        }
    }

    static func text(_ response: [String: Any]) -> String {
        for teil in ausgabe(response) where teil["type"] as? String == "message" {
            for stueck in (teil["content"] as? [[String: Any]]) ?? [] {
                if let text = stueck["text"] as? String, stueck["type"] as? String == "output_text" {
                    return text
                }
            }
        }
        return ""
    }

    static func validateStatus(_ response: [String: Any]) throws {
        let status = response["status"] as? String ?? "completed"
        guard status != "completed" else { return }
        let grund = (response["incomplete_details"] as? [String: Any])?["reason"] as? String
        throw AgentError.response("Der Lauf endete mit Status \(status)\(grund.map { ", Grund \($0)" } ?? ".")")
    }

    /// The model hands the arguments over as a JSON string.
    static func sql(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sql = object["sql"] as? String
        else { return "" }
        return sql
    }

    private static func ausgabe(_ response: [String: Any]) -> [[String: Any]] {
        response["output"] as? [[String: Any]] ?? []
    }
}

/// What goes into `anfragen.konversation`: the text and the tool exchange,
/// never the bytes of the file.
struct Trace {
    var steps: [[String: String]] = []
    var eingabeTokens = 0
    var ausgabeTokens = 0

    mutating func zaehle(_ response: [String: Any]) {
        guard let verbrauch = response["usage"] as? [String: Any] else { return }
        eingabeTokens += verbrauch["input_tokens"] as? Int ?? 0
        ausgabeTokens += verbrauch["output_tokens"] as? Int ?? 0
    }

    func asJSON() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: steps, options: [.withoutEscapingSlashes])
        else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
