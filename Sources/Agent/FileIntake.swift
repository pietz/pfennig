import Core
import CryptoKit
import Foundation
import PDFKit

/// How one file ended.
public enum FileIntakeResult: Sendable {
    case verbucht
    case bereitsVorhanden
    case fehler(file: URL, text: String)
}

/// The way of a file from the drop to the archive, one file at a time. The
/// queue that keeps them in order lives in the app; this is the work for one.
public struct FileIntake: Sendable {
    /// Two copies of the same file in one drop must not both start a run.
    /// Files are processed side by side, so the claim cannot live in the
    /// database check alone.
    actor Laufende {
        private var hashes: Set<String> = []

        func belegen(_ hash: String) -> Bool {
            hashes.insert(hash).inserted
        }

        func freigeben(_ hash: String) {
            hashes.remove(hash)
        }
    }

    let repository: Repository
    let tool: SQLTool
    let path: ArchivePaths
    let transport: Transport
    private let key: String?
    private let laufende = Laufende()

    public init(
        repository: Repository,
        path: ArchivePaths = .standard,
        transport: @escaping Transport = Responses.netz
    ) throws {
        try self.init(repository: repository, path: path, transport: transport, key: nil)
    }

    /// Internal key override for tests. Production intake reads the key from
    /// the Keychain when it starts a run.
    init(
        repository: Repository,
        path: ArchivePaths,
        transport: @escaping Transport,
        key: String?
    ) throws {
        self.repository = repository
        tool = try SQLTool(repository)
        self.path = path
        self.transport = transport
        self.key = key
    }

    /// The SHA-256 of a file, lowercase hex. It is the key of `files` and
    /// the name of the file in the archive.
    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func erlaubt(_ url: URL) -> Bool {
        FileInput.erlaubteEndungen.contains(url.pathExtension.lowercased())
    }

    /// What is still waiting in the inbox, oldest name first. The app works
    /// through it on start and after every drop.
    public func inbox() -> [URL] {
        let content = try? FileManager.default.contentsOfDirectory(
            at: path.inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return (content ?? []).filter(FileIntake.erlaubt).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Discard only owns the Inbox copy. A failure before copying may still
    /// point at the user's original, which must remain untouched.
    public func discard(_ url: URL) throws {
        guard isInInbox(url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Hashes the file, copies it into the inbox, runs the agent and archives
    /// it. On failure the file stays in the inbox with the error text.
    public func process(_ url: URL) async -> FileIntakeResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .fehler(file: url, text: error.localizedDescription)
        }
        let hash = FileIntake.hash(data)
        guard await laufende.belegen(hash) else { return .bereitsVorhanden }
        let result = await process(url, data: data, hash: hash)
        await laufende.freigeben(hash)
        return result
    }

    private func process(_ url: URL, data: Data, hash: String) async -> FileIntakeResult {
        // Where the file lies when something goes wrong: in the inbox from the
        // moment it got there, at its origin before that.
        var liegt = url
        do {
            if try repository.receiptIsUsed(hash) {
                if isInInbox(url) {
                    try? FileManager.default.removeItem(at: url)
                }
                return .bereitsVorhanden
            }

            let inbox = try inInbox(url, data: data, hash: hash)
            liegt = inbox
            guard let key = key ?? Keychain.read(), key.isEmpty == false else {
                throw AgentError.keinSchluessel
            }

            let eingabe = FileInput(
                name: inbox.lastPathComponent,
                endung: inbox.pathExtension.lowercased(),
                sha256: hash,
                data: data
            )
            let lauf = AgentRun(
                repository: repository, tool: tool, key: key, transport: transport
            )
            let result = try await lauf.start(eingabe)
            do {
                try archive(inbox, hash: hash, data: data, result: result)
            } catch {
                // A file that did not reach the archive must be able to run
                // again, so its bookings go the same way a broken run's do.
                throw RunAbort(angelegt: result.angelegt, grund: error)
            }
            return .verbucht
        } catch let abbruch as RunAbort {
            // Rows of the broken run go, so a second attempt cannot double them.
            for id in abbruch.angelegt {
                _ = try? repository.delete(id: id)
            }
            return .fehler(file: liegt, text: abbruch.localizedDescription)
        } catch {
            return .fehler(file: liegt, text: error.localizedDescription)
        }
    }

    /// The file lands in the inbox before the run, so a crash leaves it there
    /// and the next start picks it up again.
    private func inInbox(_ url: URL, data: Data, hash: String) throws -> URL {
        guard isInInbox(url) == false else { return url }
        try path.anlegen()
        var ziel = path.inbox.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: ziel.path) {
            // Another file of that name is still waiting; it keeps its place.
            let name = url.deletingPathExtension().lastPathComponent
            ziel = path.inbox.appending(path: "\(name)-\(hash.prefix(8)).\(url.pathExtension)")
        }
        try data.write(to: ziel)
        return ziel
    }

    private func archive(_ inbox: URL, hash: String, data: Data, result: RunResult) throws {
        let endung = inbox.pathExtension.lowercased()
        let ziel = path.archiv.appending(path: "\(hash).\(endung)")
        // Copy first. A leftover archive copy is safe when a later database
        // write fails, and the Inbox remains the retryable source.
        if FileManager.default.fileExists(atPath: ziel.path) == false {
            try FileManager.default.copyItem(at: inbox, to: ziel)
        }
        try repository.saveFileAndAttachReceipt(Datei(
            sha256: hash,
            dateiname: inbox.lastPathComponent,
            endung: endung,
            groesse: Int64(data.count),
            art: .beleg,
            seiten: endung == "pdf" ? PDFDocument(data: data)?.pageCount : nil
        ), an: result.beruehrt)
        // The booking and file row are committed above. A cleanup failure must
        // not turn a successful import back into a failed run.
        try? FileManager.default.removeItem(at: inbox)
    }

    /// Symlinks are resolved on both sides: a directory listing answers with
    /// the resolved path, a dropped file with the one the Finder handed over.
    func isInInbox(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath()
            == path.inbox.resolvingSymlinksInPath()
    }
}
