import Foundation

/// The stored form of an agent exchange: the Responses items as they went
/// out and came back, with every file standing as a reference to its row in
/// `dateien` instead of its bytes. `gespraeche.verlauf` and
/// `anfragen.konversation` both hold it.
public enum Conversation {
    static func reference(_ id: Int64) -> [String: Any] {
        ["type": "datei", "id": id]
    }

    static func items(_ json: String) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] ?? []
    }

    static func json(_ items: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.withoutEscapingSlashes])
        else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func fileIDs(_ items: [[String: Any]]) -> [Int64] {
        items.flatMap(userContent).compactMap(fileID)
    }

    /// The items as they go to the model: each reference replaced by the file
    /// itself, or by a note when the file is no longer there.
    static func expand(_ items: [[String: Any]], files: [Int64: FileInput]) -> [[String: Any]] {
        items.map { item in
            guard item["role"] as? String == "user" else { return item }
            var expanded = item
            expanded["content"] = userContent(item).map { piece in
                guard let id = fileID(piece) else { return piece }
                return files[id]?.content
                    ?? ["type": "input_text", "text": "Datei \(id) ist nicht mehr vorhanden."]
            }
            return expanded
        }
    }

    /// What the chat shows: the user's messages and the agent's answers, not
    /// the tool calls in between.
    public static func messages(_ verlauf: String) -> [ChatMessage] {
        items(verlauf).enumerated().compactMap { index, item in
            if item["role"] as? String == "user" {
                let text = userContent(item).compactMap { $0["text"] as? String }.joined(separator: "\n")
                return ChatMessage(id: index, fromUser: true, text: text)
            }
            guard item["type"] as? String == "message" else { return nil }
            let pieces = item["content"] as? [[String: Any]] ?? []
            let text = pieces.filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
            return ChatMessage(id: index, fromUser: false, text: text)
        }
    }

    private static func userContent(_ item: [String: Any]) -> [[String: Any]] {
        guard item["role"] as? String == "user" else { return [] }
        return item["content"] as? [[String: Any]] ?? []
    }

    private static func fileID(_ piece: [String: Any]) -> Int64? {
        guard piece["type"] as? String == "datei" else { return nil }
        return (piece["id"] as? NSNumber)?.int64Value
    }
}

/// One bubble of the chat.
public struct ChatMessage: Identifiable, Hashable, Sendable {
    public var id: Int
    public var fromUser: Bool
    public var text: String
}
