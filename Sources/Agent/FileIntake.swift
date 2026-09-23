import Core
import CryptoKit
import Foundation
import PDFKit

/// How one file ended.
public enum FileIntakeResult: Sendable {
    case booked
    case alreadyPresent
    case failed(file: URL, text: String)
}

/// The way of a file from the drop to the archive, one file at a time. The
/// queue that keeps them in order lives in the app; this is the work for one.
public struct FileIntake: Sendable {
    /// Two copies of the same file in one drop must not both start a run.
    /// Files are processed side by side, so the claim cannot live in the
    /// database check alone.
    actor InFlight {
        private var hashes: Set<String> = []

        func claim(_ hash: String) -> Bool {
            hashes.insert(hash).inserted
        }

        func release(_ hash: String) {
            hashes.remove(hash)
        }
    }

    let repository: Repository
    let tool: SQLTool
    let path: ArchivePaths
    let transport: Transport
    let key: String?
    private let inFlight = InFlight()

    public init(
        repository: Repository,
        path: ArchivePaths = .standard,
        transport: @escaping Transport = Responses.network
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

    public static func isAllowed(_ url: URL) -> Bool {
        FileInput.isAllowed(extension: url.pathExtension)
    }

    /// The files behind a drop: allowed files as they are, folders opened
    /// down to every allowed file inside them. Hidden files and folders are
    /// skipped, packages such as a Numbers document count as files, and a
    /// file reached twice (a folder and its subfolder in one drop) goes in
    /// once. Anything else falls away.
    public static func files(in urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.flatMap { url -> [URL] in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isFolder = values?.isDirectory == true && values?.isPackage != true
            guard isFolder else { return isAllowed(url) ? [url] : [] }
            let content = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return (content?.allObjects as? [URL] ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false }
                .filter(isAllowed)
                .sorted { $0.path < $1.path }
        }
        .filter { seen.insert($0).inserted }
    }

    /// What is still waiting in the inbox, oldest name first. The app works
    /// through it on start and after every drop.
    public func inbox() -> [URL] {
        let content = try? FileManager.default.contentsOfDirectory(
            at: path.inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return (content ?? []).filter(FileIntake.isAllowed).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Discard only owns the Inbox copy. A failure before copying may still
    /// point at the user's original, which must remain untouched.
    public func discard(_ url: URL) throws {
        guard isInInbox(url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Hashes the file, stores it in inbox, archive and `dateien`, then runs
    /// the agent. On failure the inbox copy stays with the error text; the
    /// stored file is reused by the retry.
    public func process(_ url: URL) async -> FileIntakeResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failed(file: url, text: error.localizedDescription)
        }
        let hash = FileIntake.hash(data)
        guard await inFlight.claim(hash) else { return .alreadyPresent }
        let result = await process(url, data: data, hash: hash)
        await inFlight.release(hash)
        return result
    }

    private func process(_ url: URL, data: Data, hash: String) async -> FileIntakeResult {
        // Where the file lies when something goes wrong: in the inbox from the
        // moment it got there, at its origin before that.
        var location = url
        do {
            // A known hash is done once a run for it has succeeded. A stored
            // file whose runs all failed is work again, from the inbox copy or
            // from a fresh drop.
            let known = try repository.fileID(sha256: hash)
            if let known, try repository.hasSuccessfulRun(dateiId: known) {
                // A leftover inbox copy of a done file would announce itself
                // on every start and has no discard; take it along. An
                // original from outside the inbox stays untouched.
                if isInInbox(url) {
                    try? FileManager.default.removeItem(at: url)
                }
                return .alreadyPresent
            }

            let inbox = try inInbox(url, data: data, hash: hash)
            location = inbox
            let fileExtension = inbox.pathExtension.lowercased()
            guard FileInput.textExtensions.contains(fileExtension) == false
                || data.count <= FileInput.maxTextBytes
            else {
                throw AgentError.textTooLarge
            }
            guard let key = key ?? Keychain.read(), key.isEmpty == false else {
                throw AgentError.missingKey
            }

            let id = try known ?? store(name: inbox.lastPathComponent, data: data, hash: hash)
            let input = FileInput(id: id, name: inbox.lastPathComponent, fileExtension: fileExtension, data: data)
            let run = AgentRun(
                repository: repository, tool: tool, key: key, transport: transport, path: path
            )
            _ = try await run.start(input)
            // The run is committed. A cleanup failure must not turn a
            // successful import back into a failed run.
            try? FileManager.default.removeItem(at: inbox)
            return .booked
        } catch let abort as RunAbort {
            // Rows of the broken run go, so a second attempt cannot double them.
            for id in abort.created {
                _ = try? repository.delete(id: id)
            }
            return .failed(file: location, text: abort.localizedDescription)
        } catch {
            return .failed(file: location, text: error.localizedDescription)
        }
    }

    /// The file lands in the inbox before the run, so a crash leaves it there
    /// and the next start picks it up again.
    private func inInbox(_ url: URL, data: Data, hash: String) throws -> URL {
        guard isInInbox(url) == false else { return url }
        try path.create()
        var destination = path.inbox.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            // Another file of that name is still waiting; it keeps its place.
            let name = url.deletingPathExtension().lastPathComponent
            destination = path.inbox.appending(path: "\(name)-\(hash.prefix(8)).\(url.pathExtension)")
        }
        try data.write(to: destination)
        return destination
    }

    /// A file attached in the chat: stored like a dropped one, or the stored
    /// row reused, but no import runs and nothing has to be booked.
    public func attach(_ url: URL) throws -> FileInput {
        let data = try Data(contentsOf: url)
        let fileExtension = url.pathExtension.lowercased()
        guard FileInput.textExtensions.contains(fileExtension) == false || data.count <= FileInput.maxTextBytes else {
            throw AgentError.textTooLarge
        }
        let hash = FileIntake.hash(data)
        try path.create()
        let id = try repository.fileID(sha256: hash) ?? store(name: url.lastPathComponent, data: data, hash: hash)
        return FileInput(id: id, name: url.lastPathComponent, fileExtension: fileExtension, data: data)
    }

    /// Archive copy first, row second: a leftover copy without a row is
    /// harmless and the next attempt finds it in place.
    private func store(name: String, data: Data, hash: String) throws -> Int64 {
        let endung = (name as NSString).pathExtension.lowercased()
        let destination = path.archive.appending(path: "\(hash).\(endung)")
        if FileManager.default.fileExists(atPath: destination.path) == false {
            try data.write(to: destination)
        }
        return try repository.saveFile(Datei(
            sha256: hash,
            dateiname: name,
            endung: endung,
            groesse: Int64(data.count),
            seiten: endung == "pdf" ? PDFDocument(data: data)?.pageCount : nil
        ))
    }

    /// Symlinks are resolved on both sides: a directory listing answers with
    /// the resolved path, a dropped file with the one the Finder handed over.
    func isInInbox(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath()
            == path.inbox.resolvingSymlinksInPath()
    }
}
