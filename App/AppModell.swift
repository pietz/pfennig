import Kern
import SwiftUI

/// The one model of the app: the repository, the bookings it delivers and what
/// the user has selected, filtered, searched and sorted.
@MainActor @Observable
final class AppModell {
    let repository: Repository

    var buchungen: [Buchung] = []
    /// `Buchung.ID` is the optional row id, so the selection carries one
    /// optional more than it looks like.
    var auswahl: Buchung.ID?
    var filter: Buchungsfilter = .alle
    var suche = ""
    var sortierung = [KeyPathComparator(\Buchung.datum, order: .reverse)]
    var inspektorSichtbar = true
    /// Set by the plus button so the inspector puts the cursor in the title.
    var fokusTitel = false
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
        guard let id = auswahl else { return nil }
        return buchungen.first { $0.id == id }
    }

    @discardableResult
    func speichern(_ buchung: Buchung) -> Buchung? {
        do {
            return try repository.speichern(buchung, akteur: .nutzer)
        } catch {
            fehler = "\(error)"
            return nil
        }
    }

    /// A new expense of today with one empty position, selected and ready to
    /// type. The toolbar must not hide it, so a running search or an income
    /// filter steps aside.
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
        fokusTitel = true
    }

    func bestaetigen(_ buchung: Buchung) {
        guard let id = buchung.id else { return }
        do {
            try repository.bestaetigen(id: id)
        } catch {
            fehler = "\(error)"
        }
    }

    func loeschen(_ buchung: Buchung) {
        guard let id = buchung.id else { return }
        do {
            try repository.loeschen(id: id)
            if ausgewaehlt?.id == id {
                auswahl = nil
            }
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
