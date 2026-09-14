import Agent
import Kern
import SwiftUI

/// The one model of the app: the repository, the bookings it delivers and what
/// the user has selected, filtered, searched and sorted.
@MainActor @Observable
final class AppModell {
    let repository: Repository
    let eingang: Eingang

    var buchungen: [Buchung] = []
    var auswahl: Int64?
    var filter: Buchungsfilter = .alle
    var suche = ""
    var sortierung = [KeyPathComparator(\Buchung.datum, order: .reverse)]
    var inspektorSichtbar = true
    var fehler: String?

    /// The files still to be processed, the two counters behind the progress
    /// in the toolbar and the ones that did not make it.
    private var warteschlange: [URL] = []
    private(set) var gesamt = 0
    private(set) var fertig = 0
    private(set) var gescheitert: [GescheiterteDatei] = []
    private var laeuft = false

    var zeigtFehler: Bool {
        get { fehler != nil }
        set {
            if newValue == false {
                fehler = nil
            }
        }
    }

    init() {
        do {
            try Archivpfad.anlegen()
            repository = try Repository(pfad: Archivpfad.datenbank)
            eingang = try Eingang(repository: repository)
        } catch {
            fatalError("Die Datenbank ließ sich nicht öffnen: \(error)")
        }
    }

    // MARK: - Eingang

    var laeuftEingang: Bool {
        gesamt > 0
    }

    /// The files the user dropped. Everything the agent cannot read is dropped
    /// silently; the window accepts only the allowed types in the first place.
    func dateienAnnehmen(_ urls: [URL]) {
        einreihen(urls.filter(Eingang.erlaubt))
    }

    /// A non-empty inbox is worked through when the app starts.
    func inboxAbarbeiten() {
        einreihen(Eingang.inbox().filter { datei in
            gescheitert.contains { $0.id == datei } == false
        })
    }

    func erneutVersuchen(_ datei: GescheiterteDatei) {
        gescheitert.removeAll { $0.id == datei.id }
        einreihen([datei.id])
    }

    func verwerfen(_ datei: GescheiterteDatei) {
        gescheitert.removeAll { $0.id == datei.id }
        try? FileManager.default.removeItem(at: datei.id)
    }

    private func einreihen(_ urls: [URL]) {
        guard urls.isEmpty == false else { return }
        warteschlange.append(contentsOf: urls)
        gesamt += urls.count
        abarbeiten()
    }

    /// One file after another, in one task; a second drop joins the queue the
    /// running task is already working through.
    private func abarbeiten() {
        guard gesamt > fertig, laeuft == false else { return }
        laeuft = true
        Task {
            while warteschlange.isEmpty == false {
                let url = warteschlange.removeFirst()
                let ergebnis = await eingang.verarbeiten(url)
                if case let .fehler(datei, text) = ergebnis {
                    gescheitert.removeAll { $0.id == datei }
                    gescheitert.append(GescheiterteDatei(id: datei, text: text))
                }
                fertig += 1
            }
            gesamt = 0
            fertig = 0
            laeuft = false
        }
    }

    /// Feeds the table for as long as the window lives.
    func beobachten() async {
        inboxAbarbeiten()
        do {
            for try await neue in repository.buchungenBeobachten() {
                buchungen = neue
            }
        } catch {
            fehler = "\(error)"
        }
    }

    var sichtbar: [Buchung] {
        Uebersicht.sichtbar(buchungen, filter: filter, suche: suche).sorted(using: sortierung)
    }

    var ausgewaehlt: Buchung? {
        guard let auswahl else { return nil }
        return buchungen.first { $0.id == auswahl }
    }

    /// The saved row goes into the list right away so the table shows the
    /// change in the same frame; the observation delivers the same content a
    /// moment later.
    @discardableResult
    func speichern(_ buchung: Buchung) -> Buchung? {
        do {
            let gespeichert = try repository.speichern(buchung, akteur: .nutzer)
            if let stelle = buchungen.firstIndex(where: { $0.id == gespeichert.id }) {
                buchungen[stelle] = gespeichert
            }
            return gespeichert
        } catch {
            fehler = "\(error)"
            return nil
        }
    }

    /// A new expense of today with one empty position, selected in the table.
    /// The toolbar must not hide it, so a running search or an income filter
    /// steps aside.
    func neueBuchung() {
        let buchung = Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: .heute(),
            titel: "",
            positionen: [Position(netto: .null, steuersatz: 19, steuer: .null)],
            steuerbehandlung: .inland,
            geprueftAm: Date()
        )
        guard let gespeichert = speichern(buchung) else { return }
        if filter == .einnahmen {
            filter = .alle
        }
        suche = ""
        auswahl = gespeichert.id
        inspektorSichtbar = true
    }

    func bestaetigen(_ buchung: Buchung) {
        guard let id = buchung.id else { return }
        do {
            try repository.bestaetigen(id: id)
        } catch {
            fehler = "\(error)"
        }
    }

    /// The row leaves the list before the inspector closes, so its pending
    /// edit cannot write the booking back.
    func loeschen(_ buchung: Buchung) {
        guard let id = buchung.id else { return }
        buchungen.removeAll { $0.id == id }
        auswahl = nil
        do {
            try repository.loeschen(id: id)
        } catch {
            fehler = "\(error)"
        }
    }

    func profil() -> Profil {
        do {
            return try repository.profil()
        } catch {
            fehler = "\(error)"
            return Profil()
        }
    }

    func profilSpeichern(_ profil: Profil) {
        do {
            try repository.profilSpeichern(profil)
        } catch {
            fehler = "\(error)"
        }
    }
}

/// A file that stayed in the inbox, with the text the run ended on.
struct GescheiterteDatei: Identifiable, Hashable {
    let id: URL
    let text: String

    var name: String {
        id.lastPathComponent
    }
}
