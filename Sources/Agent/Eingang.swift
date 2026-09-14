import CryptoKit
import Foundation
import Kern
import PDFKit

/// How one file ended.
public enum Eingangsergebnis: Sendable {
    case verbucht(ids: [Int64], zusammenfassung: String)
    case bereitsVorhanden
    case fehler(datei: URL, text: String)
}

/// The way of a file from the drop to the archive, one file at a time. The
/// queue that keeps them in order lives in the app; this is the work for one.
public struct Eingang: Sendable {
    let repository: Repository
    let werkzeug: Werkzeug
    let transport: Transport

    public init(repository: Repository, transport: @escaping Transport = Responses.netz) throws {
        self.repository = repository
        werkzeug = try Werkzeug(repository)
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
    public static func inbox() -> [URL] {
        let inhalt = try? FileManager.default.contentsOfDirectory(
            at: Archivpfad.inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return (inhalt ?? []).filter(erlaubt).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Hashes the file, copies it into the inbox, runs the agent and archives
    /// it. On failure the file stays in the inbox with the error text.
    public func verarbeiten(_ url: URL) async -> Eingangsergebnis {
        // Where the file lies when something goes wrong: in the inbox from the
        // moment it got there, at its origin before that.
        var liegt = url
        do {
            let daten = try Data(contentsOf: url)
            let hash = Eingang.hash(daten)
            if try repository.hashVorhanden(hash) {
                if Eingang.liegtInInbox(url) {
                    try? FileManager.default.removeItem(at: url)
                }
                return .bereitsVorhanden
            }

            let inbox = try inInbox(url, daten: daten)
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
            let ergebnis: Laufergebnis
            do {
                ergebnis = try await lauf.starten(eingabe)
            } catch let abbruch as Laufabbruch {
                // Rows of the broken run go, so a second attempt cannot double them.
                for id in abbruch.angelegt {
                    try? repository.loeschen(id: id)
                }
                throw abbruch
            }
            try archivieren(inbox, hash: hash, daten: daten, ergebnis: ergebnis)
            return .verbucht(ids: ergebnis.beruehrt, zusammenfassung: ergebnis.zusammenfassung)
        } catch {
            return .fehler(datei: liegt, text: error.localizedDescription)
        }
    }

    /// The file lands in the inbox before the run, so a crash leaves it there
    /// and the next start picks it up again.
    private func inInbox(_ url: URL, daten: Data) throws -> URL {
        guard Eingang.liegtInInbox(url) == false else { return url }
        try Archivpfad.anlegen()
        let ziel = Archivpfad.inbox.appending(path: url.lastPathComponent)
        try daten.write(to: ziel)
        return ziel
    }

    static func liegtInInbox(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == Archivpfad.inbox.standardizedFileURL
    }

    private func archivieren(_ inbox: URL, hash: String, daten: Data, ergebnis: Laufergebnis) throws {
        let endung = inbox.pathExtension.lowercased()
        let ziel = Archivpfad.archiv.appending(path: "\(hash).\(endung)")
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
}
