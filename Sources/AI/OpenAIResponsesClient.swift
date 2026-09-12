import Foundation

/// Direct calls to `POST /v1/responses` with strict Structured Outputs
/// (spec 10.1). No SDK, no tool loop, one document per request.
public struct OpenAIResponsesClient: DocumentIntelligenceProvider {
    public static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    /// Reasoning plus visible output share this budget; OpenAI recommends
    /// reserving at least 25k for reasoning models.
    public static let defaultMaxOutputTokens = 32000

    let apiKey: String
    let model: OpenAIModel
    let effort: ReasoningEffort
    let maxOutputTokens: Int
    let retry: RetryPolicy
    let session: URLSession

    public init(
        apiKey: String,
        model: OpenAIModel = .default,
        effort: ReasoningEffort = .default,
        maxOutputTokens: Int = defaultMaxOutputTokens,
        retry: RetryPolicy = RetryPolicy(),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
        self.maxOutputTokens = maxOutputTokens
        self.retry = retry
        self.session = session
    }

    public func extract(document: PreparedDocument, context: ExtractionContext) async throws -> ExtractionOutcome {
        let body = requestBody(document: document, context: context)
        let payload = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let response = try await send(payload)
        let text = try Self.outputText(of: response.json)
        guard let data = text.data(using: .utf8) else {
            throw AIError.invalidResponse("Die Ausgabe war kein UTF-8.")
        }
        do {
            return ExtractionOutcome(
                extraction: try JSONDecoder().decode(DocumentExtraction.self, from: data),
                model: model.rawValue,
                usage: Self.usage(of: response.json),
                rawResponseJSON: String(decoding: response.data, as: UTF8.self),
                requestMetadataJSON: requestMetadata(document: document, context: context)
            )
        } catch {
            throw AIError.invalidResponse("Die Ausgabe passte nicht zum Schema: \(error.localizedDescription)")
        }
    }

    // MARK: - Request

    func requestBody(document: PreparedDocument, context: ExtractionContext) -> [String: Any] {
        var content: [[String: Any]] = []
        switch document.kind {
        case .pdf:
            content.append([
                "type": "input_file",
                "filename": document.filename,
                "file_data": document.dataURL,
            ])
        case .image:
            content.append([
                "type": "input_image",
                "image_url": document.dataURL,
                "detail": "high",
            ])
        }
        content.append([
            "type": "input_text",
            "text": "Extract the bookkeeping facts of this document as schema-valid JSON.",
        ])
        return [
            "model": model.rawValue,
            "reasoning": ["effort": effort.rawValue],
            "max_output_tokens": maxOutputTokens,
            "text": ["format": ExtractionSchema.textFormat(categoryIDs: context.categoryIDs)],
            "input": [
                ["role": "system", "content": ExtractionPrompt.render(context)],
                ["role": "user", "content": content],
            ],
        ]
    }

    /// Never the document content and never the key (spec 17.18, 32).
    func requestMetadata(document: PreparedDocument, context: ExtractionContext) -> String? {
        let metadata: [String: Any] = [
            "model": model.rawValue,
            "reasoningEffort": effort.rawValue,
            "maxOutputTokens": maxOutputTokens,
            "promptVersion": AIConfiguration.promptVersion,
            "schemaVersion": AIConfiguration.schemaVersion,
            "documentKind": document.kind.rawValue,
            "mimeType": document.mimeType,
            "byteSize": document.data.count,
            "pageCount": document.pageCount ?? 0,
            "categoryCount": context.categories.count,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Transport

    struct RawResponse {
        var data: Data
        var json: [String: Any]
    }

    /// Sends the request, retrying only 429/500/503 with exponential backoff
    /// plus jitter, at most `retry.maxAttempts` times (spec 33).
    func send(_ payload: Data) async throws -> RawResponse {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await perform(payload)
            } catch let error as AIError {
                guard retry.shouldRetry(error, attempt: attempt) else { throw error }
                var retryAfter: TimeInterval?
                if case let .rateLimited(seconds) = error {
                    retryAfter = seconds
                }
                let delay = retry.delay(
                    forAttempt: attempt,
                    retryAfter: retryAfter,
                    jitter: Double.random(in: 0 ... 1)
                )
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func perform(_ payload: Data) async throws -> RawResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 300

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Keine HTTP-Antwort.")
        }
        guard http.statusCode == 200 else {
            throw Self.error(status: http.statusCode, headers: http.allHeaderFields, body: data)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AIError.invalidResponse("Die Antwort war kein JSON-Objekt.")
        }
        return RawResponse(data: data, json: json)
    }

    // MARK: - Mapping

    /// Maps an HTTP failure to a typed error (spec 33, docs/openai-responses-api.md §6).
    public static func error(status: Int, headers: [AnyHashable: Any], body: Data) -> AIError {
        let message = self.message(in: body)
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429:
            // Billing-state 429s are not transient; only true rate limits retry.
            if let message, message.lowercased().contains("quota")
                || message.lowercased().contains("billing")
                || message.lowercased().contains("credit")
                || message.lowercased().contains("limit reached")
            {
                return .badRequest(message)
            }
            let retryAfter = (headers["Retry-After"] as? String)
                ?? (headers["retry-after"] as? String)
            return .rateLimited(retryAfter: retryAfter.flatMap(TimeInterval.init))
        case 400 ... 499: return .badRequest(message)
        default: return .server(status: status, message: message)
        }
    }

    static func message(in body: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let error = json["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }

    /// Scans the `output` array for the message item's `output_text`, and
    /// fails loudly on refusals and incomplete responses (§5 of the notes).
    public static func outputText(of json: [String: Any]) throws -> String {
        if let status = json["status"] as? String, status != "completed" {
            if status == "incomplete" {
                let reason = (json["incomplete_details"] as? [String: Any])?["reason"] as? String
                throw AIError.incomplete(reason: reason ?? status)
            }
            throw AIError.incomplete(reason: status)
        }
        guard let output = json["output"] as? [[String: Any]] else {
            throw AIError.invalidResponse("Die Antwort enthielt kein output-Array.")
        }
        for item in output where item["type"] as? String == "message" {
            for part in (item["content"] as? [[String: Any]]) ?? [] {
                if part["type"] as? String == "refusal", let refusal = part["refusal"] as? String {
                    throw AIError.refused(refusal)
                }
                if part["type"] as? String == "output_text", let text = part["text"] as? String {
                    return text
                }
            }
        }
        throw AIError.invalidResponse("Die Antwort enthielt keine Textausgabe.")
    }

    public static func usage(of json: [String: Any]) -> TokenUsage? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let details = usage["output_tokens_details"] as? [String: Any]
        return TokenUsage(
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            reasoningTokens: details?["reasoning_tokens"] as? Int ?? 0
        )
    }
}
