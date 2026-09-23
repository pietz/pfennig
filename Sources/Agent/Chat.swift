import Core
import Foundation

/// The chat: the same agent as the import, continuing a stored conversation.
public struct Chat: Sendable {
    let intake: FileIntake

    public init(intake: FileIntake) {
        self.intake = intake
    }

    /// The longest title a new conversation takes from its first message.
    static let titleLength = 60

    /// Sends one message with its files and answers with the stored
    /// conversation. A new conversation is created with the first message and
    /// goes again if that first round fails; a failed round leaves an existing
    /// conversation as it was. Bookings the agent wrote stay either way.
    public func send(_ text: String, files urls: [URL], to gespraech: Gespraech?) async throws -> Gespraech {
        let repository = intake.repository
        guard let key = intake.key ?? Keychain.read(), key.isEmpty == false else {
            throw AgentError.missingKey
        }
        let files = try urls.map(intake.attach)
        let current = try gespraech ?? repository.saveConversation(Gespraech(titel: Chat.title(text, files: files)))
        let run = AgentRun(
            repository: repository, tool: intake.tool, key: key, transport: intake.transport, path: intake.path
        )
        do {
            let updated = try await run.chat(current, text: text, files: files)
            return try repository.saveConversation(updated)
        } catch {
            if gespraech == nil, let id = current.id {
                try? repository.deleteConversation(id: id)
            }
            throw error
        }
    }

    static func title(_ text: String, files: [FileInput]) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = line.isEmpty ? (files.first?.name ?? "Gespräch") : line
        return title.count > titleLength ? title.prefix(titleLength - 1) + "…" : title
    }
}
