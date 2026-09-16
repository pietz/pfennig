import GRDB
import GRDBSQLite

/// The first of the three limits from spec section 4: what the agent's sql
/// tool may compile at all. SQLite asks this function once per action while it
/// compiles a statement, so a denied action fails the statement before a single
/// row is read or written.
///
/// GRDB keeps its own authorizer on every connection it opens and needs it for
/// change observation, so this one is never installed on the app's connection.
/// It sits on a second, empty in-memory connection that carries the same
/// schema and does nothing but compile the agent's statement. Authorization is
/// a pure function of statement and schema, so a statement that compiles there
/// is exactly a statement that is allowed here.
public enum SQLAuthorizer {
    /// SELECT is allowed on everything the agent may see.
    static let readable: Set<String> = ["buchungen"]
    /// INSERT and UPDATE only ever touch the bookings.
    static let writable: Set<String> = ["buchungen"]

    /// Whether SQLite asked at all while it compiled. `VACUUM` is the one
    /// statement that asks nothing, so without this note it would walk past a
    /// table that only ever answers questions. A compile without a single
    /// question is not a statement this table has seen, and is refused.
    ///
    /// Only ever touched inside the serialized queue of the check connection.
    final class Probe: @unchecked Sendable {
        var asked = false
    }

    /// The decision for one action code and its first argument, usually the
    /// table name. Everything the table below does not name is denied: DELETE,
    /// DROP, ALTER, CREATE, PRAGMA, ATTACH, transactions of the agent's own
    /// and every access outside `buchungen`, including `sqlite_master`.
    static func allows(action: CInt, name: String?) -> Bool {
        switch action {
        case SQLITE_SELECT, SQLITE_FUNCTION: true
        case SQLITE_READ: readable.contains(name ?? "")
        case SQLITE_INSERT, SQLITE_UPDATE: writable.contains(name ?? "")
        default: false
        }
    }

    /// Installs the decision on a connection. Only ever called on the private
    /// connection the sql tool compiles on.
    static func install(_ connection: OpaquePointer?, _ trace: Probe) {
        sqlite3_set_authorizer(
            connection,
            { pointer, action, text1, _, _, _ in
                if let pointer {
                    Unmanaged<Probe>.fromOpaque(pointer).takeUnretainedValue().asked = true
                }
                let name = text1.map { String(cString: $0) }
                return SQLAuthorizer.allows(action: action, name: name) ? SQLITE_OK : SQLITE_DENY
            },
            Unmanaged.passUnretained(trace).toOpaque()
        )
    }
}
