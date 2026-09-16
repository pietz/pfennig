import Core
import Foundation

/// The file as it goes to the model: PDF and images as base64 data URLs, CSV
/// as plain text. Nothing is prepared or converted, the file goes as it is.
public struct FileInput: Sendable {
    public var name: String
    public var fileExtension: String
    public var sha256: String
    public var data: Data

    public init(name: String, fileExtension: String, sha256: String, data: Data) {
        self.name = name
        self.fileExtension = fileExtension
        self.sha256 = sha256
        self.data = data
    }

    /// No HEIC: the API does not take it, and Pfennig converts nothing.
    static let allowedExtensions = ["pdf", "png", "jpg", "jpeg", "csv"]

    var mediaType: String {
        switch fileExtension.lowercased() {
        case "pdf": "application/pdf"
        case "png": "image/png"
        case "csv": "text/csv"
        default: "image/jpeg"
        }
    }

    /// One content item of the user message.
    var content: [String: Any] {
        let dataURL = "data:\(mediaType);base64,\(data.base64EncodedString())"
        switch fileExtension.lowercased() {
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
    public var touched: [Int64] = []
    public var created: [Int64] = []
    public var summary = ""
}

/// A run that gave up, with the bookings it had already written. Swift removes
/// them before the file is tried again, so nothing doubles.
public struct RunAbort: Error, LocalizedError {
    public var created: [Int64]
    public var reason: any Error

    public var errorDescription: String? {
        reason.localizedDescription
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
        transport: @escaping Transport = Responses.network
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
        let instructions = try AgentInstructions.build(repository)
        let ai = try repository.aiSettings()
        let request = try repository.startRequest(dateiSha256: file.sha256, modell: ai.model.rawValue)
        var trace = Trace()
        var result = RunResult()
        do {
            try await loop(file, ai: ai, instructions: instructions, result: &result, trace: &trace)
            guard result.touched.isEmpty == false else {
                throw AgentError.noBooking
            }
            // The log is metadata. A failure to write it must not turn a
            // finished run into an abort that removes the committed bookings.
            try? repository.finishRequest(
                id: request, status: .erfolg, eingabeTokens: trace.inputTokens,
                ausgabeTokens: trace.outputTokens, konversation: trace.asJSON()
            )
            return result
        } catch {
            trace.steps.append(["fehler": error.localizedDescription])
            try? repository.finishRequest(
                id: request, status: .fehler, eingabeTokens: trace.inputTokens,
                ausgabeTokens: trace.outputTokens, konversation: trace.asJSON()
            )
            throw RunAbort(created: result.created, reason: error)
        }
    }

    private func loop(
        _ file: FileInput,
        ai: AISettings,
        instructions: String,
        result: inout RunResult,
        trace: inout Trace
    ) async throws {
        let client = Responses(key: key, transport: transport)
        var calls = 0
        var previousResponse: String?
        var input: [[String: Any]] = [
            ["role": "system", "content": instructions],
            ["role": "user", "content": [
                file.content,
                ["type": "input_text", "text": "Datei hinzugefügt: \(file.name)"]
            ]]
        ]

        while true {
            var body: [String: Any] = [
                "model": ai.model.rawValue,
                "reasoning": ["effort": ai.effort.rawValue],
                "tools": [AgentRun.sqlToolDescription, AgentRun.conversionToolDescription],
                "input": input
            ]
            if ai.fast {
                // OpenAI's priority processing, about twice the price.
                body["service_tier"] = "priority"
            }
            if let previousResponse {
                body["previous_response_id"] = previousResponse
            }
            let response = try await client.send(body)
            trace.count(response)
            previousResponse = response["id"] as? String
            try AgentRun.validateStatus(response)

            let callsThisRound = AgentRun.toolCalls(response)
            guard callsThisRound.isEmpty == false else {
                result.summary = AgentRun.text(response)
                trace.steps.append(["agent": result.summary])
                return
            }
            calls += callsThisRound.count
            guard calls <= AgentRun.maxToolCalls else {
                throw AgentError.tooManyToolCalls
            }

            input = []
            for call in callsThisRound {
                let text: String
                switch call.name {
                case "sql":
                    let sql = AgentRun.sql(call.arguments)
                    let toolResult = tool.execute(sql)
                    result.touched = Array(Set(result.touched).union(toolResult.touched)).sorted()
                    result.created = Array(Set(result.created).union(toolResult.created)).sorted()
                    text = toolResult.text
                case "umrechnen":
                    text = await CurrencyConverter.execute(call.arguments, transport: transport)
                default:
                    text = "Fehler: Unbekanntes Werkzeug \(call.name). Verwende sql oder umrechnen."
                }
                let step = [
                    "werkzeug": call.name,
                    "argumente": call.arguments,
                    "ergebnis": text
                ]
                trace.steps.append(step)
                input.append([
                    "type": "function_call_output",
                    "call_id": call.callId,
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
        outputItems(response).compactMap { item in
            guard item["type"] as? String == "function_call",
                  let callId = item["call_id"] as? String
            else { return nil }
            return ToolCall(
                name: item["name"] as? String ?? "",
                callId: callId,
                arguments: item["arguments"] as? String ?? "{}"
            )
        }
    }

    static func text(_ response: [String: Any]) -> String {
        for item in outputItems(response) where item["type"] as? String == "message" {
            for piece in (item["content"] as? [[String: Any]]) ?? [] {
                if let text = piece["text"] as? String, piece["type"] as? String == "output_text" {
                    return text
                }
            }
        }
        return ""
    }

    static func validateStatus(_ response: [String: Any]) throws {
        let status = response["status"] as? String ?? "completed"
        guard status != "completed" else { return }
        let reason = (response["incomplete_details"] as? [String: Any])?["reason"] as? String
        throw AgentError.response("Der Lauf endete mit Status \(status)\(reason.map { ", Grund \($0)" } ?? ".")")
    }

    /// The model hands the arguments over as a JSON string.
    static func sql(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sql = object["sql"] as? String
        else { return "" }
        return sql
    }

    private static func outputItems(_ response: [String: Any]) -> [[String: Any]] {
        response["output"] as? [[String: Any]] ?? []
    }
}

/// What goes into `anfragen.konversation`: the text and the tool exchange,
/// never the bytes of the file.
struct Trace {
    var steps: [[String: String]] = []
    var inputTokens = 0
    var outputTokens = 0

    mutating func count(_ response: [String: Any]) {
        guard let usage = response["usage"] as? [String: Any] else { return }
        inputTokens += usage["input_tokens"] as? Int ?? 0
        outputTokens += usage["output_tokens"] as? Int ?? 0
    }

    func asJSON() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: steps, options: [.withoutEscapingSlashes])
        else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
