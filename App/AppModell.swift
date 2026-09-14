import Kern
import SwiftUI

/// The one model of the app: the repository, the bookings it delivers and what
/// the user has selected, filtered, searched and sorted.
@MainActor @Observable
final class AppModell {
    let repository: Repository

    var buchungen: [Buchung] = []
    var auswahl: Int64?
    var filter: Buchungsfilter = .alle
    var suche = ""
    var sortierung = [KeyPathComparator(\Buchung.datum, order: .reverse)]
    var inspektorSichtbar = true
    var fehler: String?

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
        } catch {
            fatalError("Die Datenbank ließ sich nicht öffnen: \(error)")
        }
    }

    /// Feeds the table for as long as the window lives.
    func beobachten() async {
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
