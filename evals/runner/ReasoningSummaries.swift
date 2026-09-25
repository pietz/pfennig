import Agent
import Foundation

/// Asks OpenAI for reasoning summaries, so a trace shows why the agent
/// decided. The app sends the same requests without them; the reasoning
/// itself does not change.
enum ReasoningSummaries {
    static func transport(over network: @escaping Transport) -> Transport {
        { request in
            guard request.httpMethod == "POST", let body = request.httpBody,
                  var json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  var reasoning = json["reasoning"] as? [String: Any]
            else { return try await network(request) }
            reasoning["summary"] = "detailed"
            json["reasoning"] = reasoning
            var request = request
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            return try await network(request)
        }
    }
}
