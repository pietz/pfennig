import Foundation
import GRDB

/// Key/value access to the `settings` table (spec 17.23). Values are stored
/// as JSON; never the API key, which lives only in the Keychain.
public extension AppDatabase {
    func setting<Value: Codable>(_ type: Value.Type = Value.self, forKey key: String) throws -> Value? {
        let json = try reader.read { db in
            try String.fetchOne(db, sql: "SELECT value_json FROM settings WHERE key = ?", arguments: [key])
        }
        guard let json else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }

    func setSetting(_ value: some Codable, forKey key: String) throws {
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO settings (key, value_json, updated_at) VALUES (:key, :value, :updatedAt)
                ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at
                """,
                arguments: ["key": key, "value": json, "updatedAt": Timestamp.string()]
            )
        }
    }
}
