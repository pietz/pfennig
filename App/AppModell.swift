import Agent
import Kern
import SwiftUI

/// The one model of the app: the repository, the bookings it delivers and what
/// the user has selected, filtered, searched and sorted.
@MainActor @Observable
final class AppModell {
    let repository: Repository
    let pfad = Archivpfad.standard
    let eingang: Eingang

    var buchungen: [Buchung] = []
    var auswahl: Int64?
    var filter: Buchungsfilter = .alle
    var suche = ""
    var sortierung = [KeyPathComparator(\Buchung.datum, order: .reverse)]
    var inspektorSichtbar = true
    var fehler: String?

    /// The files still to be processed, what the toolbar shows about them and
    /// the notes the strip over the table carries.
    private var warteschlange: [URL] = []
    private var inArbeit: URL?
    private(set) var fortschritt = Fortschritt()
    private(set) var meldungen: [Eingangsmeldung] = []
    /// The inbox is read on the first look at the window, not on every one.
    private var inboxGelesen = false

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
            try pfad.anlegen()
            repository = try Repository(pfad: pfad.datenbank)
            eingang = try Eingang(repository: repository, pfad: pfad)
        } catch {
            fatalError("Die Datenbank ließ sich nicht öffnen: \(error)")
        }
    }

    // MARK: - Eingang

    /// The files the user dropped. Everything the agent cannot read is dropped
    /// silently; the window accepts only the allowed types in the first place.
    func dateienAnnehmen(_ urls: [URL]) {
        einreihen(urls.filter(Eingang.erlaubt))
    }

    /// A non-empty inbox is worked through when the app starts, once.
    func inboxAbarbeiten() {
        guard inboxGelesen == false else { return }
        inboxGelesen = true
        einreihen(eingang.inbox())
    }

    func erneutVersuchen(_ meldung: Eingangsmeldung) {
        meldungen.removeAll { $0.id == meldung.id }
        einreihen([meldung.id])
    }

    func verwerfen(_ meldung: Eingangsmeldung) {
        meldungen.removeAll { $0.id == meldung.id }
        if meldung.art == .fehler {
            try? FileManager.default.removeItem(at: meldung.id)
        }
    }

    /// A file already queued or in the machine does not go in a second time.
    private func einreihen(_ urls: [URL]) {
        let neue = urls.filter { $0 != inArbeit && warteschlange.contains($0) == false }
        guard neue.isEmpty == false else { return }
        warteschlange.append(contentsOf: neue)
        fortschritt.gesamt += neue.count
        abarbeiten()
    }

    /// One file after another in a single task. A drop that arrives while it
    /// runs joins the queue the task is already working through.
    private func abarbeiten() {
        guard fortschritt.laeuft == false else { return }
        fortschritt.laeuft = true
        Task {
            while warteschlange.isEmpty == false {
                let url = warteschlange.removeFirst()
                inArbeit = url
                let ergebnis = await eingang.verarbeiten(url)
                inArbeit = nil
                vermerken(ergebnis, fuer: url)
                fortschritt.erledigt += 1
            }
            fortschritt = Fortschritt()
        }
    }

    private func vermerken(_ ergebnis: Eingangsergebnis, fuer url: URL) {
        let meldung: Eingangsmeldung? = switch ergebnis {
        case .verbucht:
            nil
        case .bereitsVorhanden:
            Eingangsmeldung(id: url, art: .hinweis, text: "Bereits vorhanden, der Beleg hängt schon an einer Buchung.")
        case let .fehler(datei, text):
            Eingangsmeldung(id: datei, art: .fehler, text: text)
        }
        guard let meldung else { return }
        meldungen.removeAll { $0.id == meldung.id }
        meldungen.append(meldung)
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
            // The last booking of a receipt takes the file with it.
            try pfad.entfernen(repository.loeschen(id: id))
        } catch {
            fehler = "\(error)"
        }
    }

    /// Takes one receipt off a booking, and its original out of the archive
    /// when no other booking carries it.
    func belegEntfernen(_ sha256: String, von id: Int64) {
        do {
            try pfad.entfernen(repository.belegEntfernen(sha256, von: id))
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

/// What the toolbar shows while the inbox is worked through.
struct Fortschritt: Equatable {
    var gesamt = 0
    var erledigt = 0
    var laeuft = false

    var sichtbar: Bool {
        gesamt > 0
    }

    /// The file being worked on right now, not the ones already done.
    var text: String {
        "\(min(erledigt + 1, gesamt)) von \(gesamt)"
    }
}

/// A note over the table: a file that stayed in the inbox with the text the
/// run ended on, or a short word that a file was already there.
struct Eingangsmeldung: Identifiable, Hashable {
    enum Art: Hashable {
        case fehler
        case hinweis
    }

    let id: URL
    let art: Art
    let text: String

    var name: String {
        id.lastPathComponent
    }
}
