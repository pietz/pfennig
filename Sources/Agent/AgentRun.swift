import Core
import Foundation

/// The file as it goes to the model: PDF and images as base64 data URLs, text
/// formats as plain text. Nothing is prepared or converted, the file goes as
/// it is; there is no parser for any format.
public struct FileInput: Sendable {
    /// The row in `dateien`; the agent writes it into `belege`.
    public var id: Int64
    public var name: String
    public var fileExtension: String
    public var data: Data

    public init(id: Int64, name: String, fileExtension: String, data: Data) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.data = data
    }

    /// The binary formats the model reads natively, sent as an attachment.
    /// No HEIC: the API does not take it, and Pfennig converts nothing.
    static let binaryExtensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "webp"]
    /// The text formats, sent as plain text in the message.
    static let textExtensions: Set<String> = ["xml", "csv", "txt", "json", "html"]
    /// A text file larger than this does not go into the message.
    public static let maxTextBytes = 1_000_000

    public static func isAllowed(extension fileExtension: String) -> Bool {
        let lowered = fileExtension.lowercased()
        return binaryExtensions.contains(lowered) || textExtensions.contains(lowered)
    }

    /// A text file larger than `maxTextBytes` does not go to the agent.
    static func checkSize(_ fileExtension: String, _ data: Data) throws {
        guard textExtensions.contains(fileExtension) == false || data.count <= maxTextBytes else {
            throw AgentError.textTooLarge
        }
    }

    var isText: Bool {
        FileInput.textExtensions.contains(fileExtension.lowercased())
    }

    var mediaType: String {
        switch fileExtension.lowercased() {
        case "pdf": "application/pdf"
        case "png": "image/png"
        case "webp": "image/webp"
        default: "image/jpeg"
        }
    }

    /// One content item of the user message.
    var content: [String: Any] {
        if isText {
            return ["type": "input_text", "text": FileInput.text(data)]
        }
        let dataURL = "data:\(mediaType);base64,\(data.base64EncodedString())"
        switch fileExtension.lowercased() {
        case "pdf":
            return ["type": "input_file", "filename": name, "file_data": dataURL]
        default:
            return ["type": "input_image", "image_url": dataURL, "detail": "high"]
        }
    }

    /// UTF-8 when the bytes are UTF-8, otherwise Windows-1252: German bank
    /// exports still come that way, and a lossy decode would hand the agent
    /// „Geb�hren“ as the name of a booking. Five bytes are undefined in
    /// Windows-1252; Latin-1 reads every byte and differs only in those.
    static func text(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}

/// What one run left behind.
public struct RunResult: Sendable {
    public var touched: [Int64] = []
    public var created: [Int64] = []
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

/// The agent: one tool loop over the Responses API, started by the import of
/// a file or by a round of a conversation.
public struct AgentRun: Sendable {
    public static let maxToolCalls = 60

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

    /// A dropped file without further instruction: the import. It must change
    /// a booking, or the run counts as failed.
    public func start(_ file: FileInput) async throws -> RunResult {
        let message: [[String: Any]] = [
            Conversation.reference(file.id),
            ["type": "input_text", "text": "Datei \(file.id) hinzugefügt: \(file.name)"]
        ]
        return try await run(history: [], message: message, files: [file], dateiId: file.id).result
    }

    /// One round of a stored conversation: the user's text with the files
    /// attached to it. `earlier` holds the files the conversation already
    /// refers to; one missing there is named as gone. The round may end
    /// without touching a booking. Answers with the conversation grown by the
    /// round; the caller stores it.
    public func chat(
        _ gespraech: Gespraech,
        text: String,
        files: [FileInput],
        earlier: [FileInput]
    ) async throws -> Gespraech {
        guard let id = gespraech.id else { preconditionFailure("the conversation is stored before its first round") }
        let history = Conversation.items(gespraech.verlauf)
        var message: [[String: Any]] = files.flatMap { file -> [[String: Any]] in
            [
                Conversation.reference(file.id),
                ["type": "input_text", "text": "Datei \(file.id) angehängt: \(file.name)"]
            ]
        }
        if text.isEmpty == false {
            message.append(["type": "input_text", "text": text])
        }
        let items = try await run(history: history, message: message, files: files + earlier, gespraechId: id).items
        var updated = gespraech
        updated.verlauf = Conversation.json(history + items)
        return updated
    }

    /// The one tool loop of import and chat. It continues `history` with the
    /// user message until the agent answers and records the run in
    /// `anfragen`, whatever the outcome. Answers with the new items, file
    /// bytes replaced by their reference.
    private func run(
        history: [[String: Any]],
        message: [[String: Any]],
        files: [FileInput],
        dateiId: Int64? = nil,
        gespraechId: Int64? = nil
    ) async throws -> (result: RunResult, items: [[String: Any]]) {
        let instructions = try AgentInstructions.build(repository)
        let ai = try repository.aiSettings()
        let request = try repository.startRequest(dateiId: dateiId, gespraechId: gespraechId, modell: ai.model.rawValue)
        var items: [[String: Any]] = [["role": "user", "content": message]]
        var usage = Usage()
        var result = RunResult()
        defer {
            // Diagnostics may fail without changing the durable run outcome.
            try? repository.recordRequestTrace(
                id: request, eingabeTokens: usage.input,
                ausgabeTokens: usage.output, konversation: Conversation.json(items)
            )
        }
        do {
            let known = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            try await loop(
                history: history, items: &items, files: known, ai: ai, instructions: instructions,
                result: &result, usage: &usage
            )
            // Only the import has to book something; a conversation need not.
            guard dateiId == nil || result.touched.isEmpty == false else {
                throw AgentError.noBooking
            }
        } catch {
            // The reason goes into the log only, never into a conversation.
            items.append(["fehler": error.localizedDescription])
            try? repository.finishRequest(id: request, status: .fehler)
            throw RunAbort(created: result.created, reason: error)
        }
        // Completion is required before intake removes the inbox copy. Keep
        // this outside the abort handler: bookings are already committed and
        // must survive a failure to persist the completion status.
        try repository.finishRequest(id: request, status: .erfolg)
        return (result, items)
    }

    /// Stateless on OpenAI's side: every request carries the whole item list
    /// and nothing is stored there. The encrypted reasoning comes back with
    /// the output, so a conversation continues later from the local copy.
    private func loop(
        history: [[String: Any]],
        items: inout [[String: Any]],
        files: [Int64: FileInput],
        ai: AISettings,
        instructions: String,
        result: inout RunResult,
        usage: inout Usage
    ) async throws {
        let client = Responses(key: key, transport: transport)
        var calls = 0
        while true {
            var body: [String: Any] = [
                "model": ai.model.rawValue,
                "reasoning": ["effort": ai.effort.rawValue],
                "tools": [AgentRun.sqlToolDescription, AgentRun.conversionToolDescription],
                "store": false,
                "include": ["reasoning.encrypted_content"],
                "input": [["role": "system", "content": instructions]]
                    + Conversation.expand(history + items, files: files)
            ]
            if ai.fast {
                // OpenAI's priority processing, about twice the price.
                body["service_tier"] = "priority"
            }
            let response = try await client.send(body)
            usage.count(response)
            try AgentRun.validateStatus(response)
            items.append(contentsOf: AgentRun.outputItems(response))

            let callsThisRound = AgentRun.toolCalls(response)
            guard callsThisRound.isEmpty == false else { return }
            calls += callsThisRound.count
            guard calls <= AgentRun.maxToolCalls else {
                throw AgentError.tooManyToolCalls
            }

            for call in callsThisRound {
                let text: String
                switch call.name {
                case "sql":
                    let toolResult = tool.execute(AgentRun.sql(call.arguments))
                    result.touched = Array(Set(result.touched).union(toolResult.touched)).sorted()
                    result.created = Array(Set(result.created).union(toolResult.created)).sorted()
                    text = toolResult.text
                case "umrechnen":
                    text = await CurrencyConverter.execute(call.arguments, transport: transport)
                default:
                    text = "Fehler: Unbekanntes Werkzeug \(call.name). Verwende sql oder umrechnen."
                }
                items.append([
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

    static func outputItems(_ response: [String: Any]) -> [[String: Any]] {
        response["output"] as? [[String: Any]] ?? []
    }
}

/// The tokens of a run, summed over its requests.
struct Usage {
    var input = 0
    var output = 0

    mutating func count(_ response: [String: Any]) {
        guard let usage = response["usage"] as? [String: Any] else { return }
        input += usage["input_tokens"] as? Int ?? 0
        output += usage["output_tokens"] as? Int ?? 0
    }
}
