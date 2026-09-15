import CryptoKit
import Foundation
import Kern
import PDFKit

/// How one file ended.
public enum Eingangsergebnis: Sendable {
    case verbucht
    case bereitsVorhanden
    case fehler(datei: URL, text: String)
}

/// The way of a file from the drop to the archive, one file at a time. The
/// queue that keeps them in order lives in the app; this is the work for one.
public struct Eingang: Sendable {
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
    let werkzeug: Werkzeug
    let pfad: Archivpfad
    let transport: Transport
    private let laufende = Laufende()

    public init(
        repository: Repository,
        pfad: Archivpfad = .standard,
        transport: @escaping Transport = Responses.netz
    ) throws {
        self.repository = repository
        werkzeug = try Werkzeug(repository)
        self.pfad = pfad
        self.transport = transport
    }

    /// The SHA-256 of a file, lowercase hex. It is the key of `dateien` and
    /// the name of the file in the archive.
    public static func hash(_ daten: Data) -> String {
        SHA256.hash(data: daten).map { String(format: "%02x", $0) }.joined()
    }

    public static func erlaubt(_ url: URL) -> Bool {
        Dateieingabe.erlaubteEndungen.contains(url.pathExtension.lowercased())
    }

    /// What is still waiting in the inbox, oldest name first. The app works
    /// through it on start and after every drop.
    public func inbox() -> [URL] {
        let inhalt = try? FileManager.default.contentsOfDirectory(
            at: pfad.inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return (inhalt ?? []).filter(Eingang.erlaubt).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Discard only owns the Inbox copy. A failure before copying may still
    /// point at the user's original, which must remain untouched.
    public func verwerfen(_ url: URL) throws {
        guard liegtInInbox(url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Hashes the file, copies it into the inbox, runs the agent and archives
    /// it. On failure the file stays in the inbox with the error text.
    public func verarbeiten(_ url: URL) async -> Eingangsergebnis {
        let daten: Data
        do {
            daten = try Data(contentsOf: url)
        } catch {
            return .fehler(datei: url, text: error.localizedDescription)
        }
        let hash = Eingang.hash(daten)
        guard await laufende.belegen(hash) else { return .bereitsVorhanden }
        let ergebnis = await verarbeiten(url, daten: daten, hash: hash)
        await laufende.freigeben(hash)
        return ergebnis
    }

    private func verarbeiten(_ url: URL, daten: Data, hash: String) async -> Eingangsergebnis {
        // Where the file lies when something goes wrong: in the inbox from the
        // moment it got there, at its origin before that.
        var liegt = url
        do {
            if try repository.belegVerwendet(hash) {
                if liegtInInbox(url) {
                    try? FileManager.default.removeItem(at: url)
                }
                return .bereitsVorhanden
            }

            let inbox = try inInbox(url, daten: daten, hash: hash)
            liegt = inbox
            guard let schluessel = Schluesselbund.lesen(), schluessel.isEmpty == false else {
                throw Agentenfehler.keinSchluessel
            }

            let eingabe = Dateieingabe(
                name: inbox.lastPathComponent,
                endung: inbox.pathExtension.lowercased(),
                sha256: hash,
                daten: daten
            )
            let lauf = Agentenlauf(
                repository: repository, werkzeug: werkzeug, schluessel: schluessel, transport: transport
            )
            let ergebnis = try await lauf.starten(eingabe)
            do {
                try archivieren(inbox, hash: hash, daten: daten, ergebnis: ergebnis)
            } catch {
                // A file that did not reach the archive must be able to run
                // again, so its bookings go the same way a broken run's do.
                throw Laufabbruch(angelegt: ergebnis.angelegt, grund: error)
            }
            return .verbucht
        } catch let abbruch as Laufabbruch {
            // Rows of the broken run go, so a second attempt cannot double them.
            for id in abbruch.angelegt {
                try? repository.loeschen(id: id)
            }
            return .fehler(datei: liegt, text: abbruch.localizedDescription)
        } catch {
            return .fehler(datei: liegt, text: error.localizedDescription)
        }
    }

    /// The file lands in the inbox before the run, so a crash leaves it there
    /// and the next start picks it up again.
    private func inInbox(_ url: URL, daten: Data, hash: String) throws -> URL {
        guard liegtInInbox(url) == false else { return url }
        try pfad.anlegen()
        var ziel = pfad.inbox.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: ziel.path) {
            // Another file of that name is still waiting; it keeps its place.
            let name = url.deletingPathExtension().lastPathComponent
            ziel = pfad.inbox.appending(path: "\(name)-\(hash.prefix(8)).\(url.pathExtension)")
        }
        try daten.write(to: ziel)
        return ziel
    }

    private func archivieren(_ inbox: URL, hash: String, daten: Data, ergebnis: Laufergebnis) throws {
        let endung = inbox.pathExtension.lowercased()
        let ziel = pfad.archiv.appending(path: "\(hash).\(endung)")
        // The original may already be there: its booking was deleted and the
        // same file came back. One copy is enough.
        if FileManager.default.fileExists(atPath: ziel.path) {
            try FileManager.default.removeItem(at: inbox)
        } else {
            try FileManager.default.moveItem(at: inbox, to: ziel)
        }
        try repository.dateiSpeichern(Datei(
            sha256: hash,
            dateiname: inbox.lastPathComponent,
            endung: endung,
            groesse: Int64(daten.count),
            art: .beleg,
            seiten: endung == "pdf" ? PDFDocument(data: daten)?.pageCount : nil
        ))
        try repository.belegAnhaengen(hash, an: ergebnis.beruehrt)
    }

    /// Symlinks are resolved on both sides: a directory listing answers with
    /// the resolved path, a dropped file with the one the Finder handed over.
    func liegtInInbox(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath()
            == pfad.inbox.resolvingSymlinksInPath()
    }
}
