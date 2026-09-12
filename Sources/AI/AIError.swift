import Foundation

/// Every failure the document-intelligence layer can produce, with a German
/// message for the review UI (spec 33: keep the document, mark the item
/// failed with a code, allow retry).
public enum AIError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case badRequest(String?)
    case server(status: Int, message: String?)
    case network(String)
    case invalidResponse(String)
    case refused(String)
    case incomplete(reason: String)
    case unsupportedDocument(String)

    /// Stable machine code for `import_items.error_code` (spec 17.17).
    public var code: String {
        switch self {
        case .missingAPIKey: "AI_NO_API_KEY"
        case .unauthorized: "AI_UNAUTHORIZED"
        case .forbidden: "AI_FORBIDDEN"
        case .rateLimited: "AI_RATE_LIMITED"
        case .badRequest: "AI_BAD_REQUEST"
        case .server: "AI_SERVER"
        case .network: "AI_NETWORK"
        case .invalidResponse: "AI_INVALID_RESPONSE"
        case .refused: "AI_REFUSED"
        case .incomplete: "AI_INCOMPLETE"
        case .unsupportedDocument: "AI_UNSUPPORTED_DOCUMENT"
        }
    }

    /// Only transient failures are worth another attempt (spec 33).
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .network: true
        case let .server(status, _): status == 500 || status == 503
        default: false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Kein OpenAI-Schlüssel hinterlegt. Bitte in den Einstellungen eintragen."
        case .unauthorized:
            "Der OpenAI-Schlüssel wurde abgelehnt. Bitte in den Einstellungen prüfen."
        case .forbidden:
            "OpenAI hat die Anfrage abgelehnt (Region oder Projekt nicht freigegeben)."
        case .rateLimited:
            "OpenAI hat das Anfragelimit gemeldet. Bitte später erneut versuchen."
        case let .badRequest(message):
            "Die Anfrage an OpenAI war ungültig\(message.map { ": \($0)" } ?? "")."
        case let .server(status, message):
            "OpenAI meldet einen Serverfehler (\(status))\(message.map { ": \($0)" } ?? "")."
        case let .network(message):
            "Keine Verbindung zu OpenAI: \(message)"
        case let .invalidResponse(message):
            "Die Antwort von OpenAI war nicht lesbar: \(message)"
        case let .refused(message):
            "Das Modell hat die Auswertung abgelehnt: \(message)"
        case let .incomplete(reason):
            "Die Auswertung wurde nicht abgeschlossen (\(reason))."
        case let .unsupportedDocument(message):
            message
        }
    }
}

/// Exponential backoff with jitter, max three attempts per item (spec 33).
public struct RetryPolicy: Sendable, Hashable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1, maxDelay: TimeInterval = 30) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// `attempt` is 1-based: the attempt that just failed.
    public func shouldRetry(_ error: AIError, attempt: Int) -> Bool {
        attempt < maxAttempts && error.isRetryable
    }

    /// `Retry-After` wins when the server sent one; otherwise
    /// `baseDelay * 2^(attempt-1)` scaled by `jitter` in 0...1.
    public func delay(forAttempt attempt: Int, retryAfter: TimeInterval?, jitter: Double) -> TimeInterval {
        if let retryAfter {
            return min(retryAfter, maxDelay)
        }
        let exponential = baseDelay * pow(2, Double(max(0, attempt - 1)))
        return min(exponential, maxDelay) * (0.5 + 0.5 * min(max(jitter, 0), 1))
    }
}
