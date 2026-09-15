import Agent
import Core
import SwiftUI

/// The one model of the app: the repository, the bookings it delivers and what
/// the user has selected, filtered, searched and sorted.
@MainActor @Observable
final class AppModel {
    let repository: Repository
    let path = ArchivePaths.standard
    let intake: FileIntake

    var buchungen: [Buchung] = []
    var selection: Int64?
    var filter: BookingFilter = .alle
    var reviewFilter: ReviewFilter = .alle
    var search = ""
    var sortOrder = [KeyPathComparator(\Buchung.datum, order: .reverse)]
    var inspectorVisible = true
    var exportVisible = false
    var fehler: String?

    /// The periods the user has already exported, with the day they left the
    /// app. Read once and after every export; the export sheet and the
    /// inspector both ask it.
    private(set) var exportedPeriods: [Zeitraum: Date] = [:]

    /// The files still to be processed, what the toolbar shows about them and
    /// the notes the strip over the table carries.
    private var queue: [URL] = []
    private var inProgress: Set<URL> = []
    private(set) var fortschritt = Progress()
    private(set) var messages: [IntakeMessage] = []
    /// The inbox is read on the first look at the window, not on every one.
    private var inboxRead = false

    var showsError: Bool {
        get { fehler != nil }
        set {
            if newValue == false {
                fehler = nil
            }
        }
    }

    /// How many files the agent works on at the same time.
    static let gleichzeitig = 10

    init() {
        do {
            try path.anlegen()
            repository = try Repository(path: path.datenbank)
            intake = try FileIntake(repository: repository, path: path)
        } catch {
            fatalError("Die Datenbank ließ sich nicht öffnen: \(error)")
        }
    }

    // MARK: - FileIntake

    /// The files the user dropped. Everything the agent cannot read is dropped
    /// silently; the window accepts only the allowed types in the first place.
    func acceptFiles(_ urls: [URL]) {
        enqueue(urls.filter(FileIntake.erlaubt))
    }

    /// A non-empty inbox is worked through when the app starts, once.
    func processInbox() {
        guard inboxRead == false else { return }
        inboxRead = true
        enqueue(intake.inbox())
    }

    func retry(_ meldung: IntakeMessage) {
        messages.removeAll { $0.id == meldung.id }
        enqueue([meldung.id])
    }

    func discard(_ meldung: IntakeMessage) {
        messages.removeAll { $0.id == meldung.id }
        if meldung.art == .fehler {
            try? intake.discard(meldung.id)
        }
    }

    /// A file already queued or in the machine does not go in a second time.
    private func enqueue(_ urls: [URL]) {
        let neue = urls.filter { inProgress.contains($0) == false && queue.contains($0) == false }
        guard neue.isEmpty == false else { return }
        queue.append(contentsOf: neue)
        fortschritt.gesamt += neue.count
        process()
    }

    /// Files run side by side, at most `gleichzeitig` of them. A drop that
    /// arrives while they run joins the queue the task is already emptying.
    /// Every statement of every run still goes through the one database queue,
    /// so the rows stay consistent.
    private func process() {
        guard fortschritt.laeuft == false else { return }
        fortschritt.laeuft = true
        let intake = intake
        Task {
            await withTaskGroup(of: (URL, FileIntakeResult).self) { gruppe in
                var offen = 0
                while true {
                    while offen < AppModel.gleichzeitig, queue.isEmpty == false {
                        let url = queue.removeFirst()
                        inProgress.insert(url)
                        gruppe.addTask { await (url, intake.process(url)) }
                        offen += 1
                    }
                    guard let (url, result) = await gruppe.next() else { break }
                    offen -= 1
                    inProgress.remove(url)
                    record(result, fuer: url)
                    fortschritt.erledigt += 1
                }
            }
            fortschritt = Progress()
        }
    }

    private func record(_ result: FileIntakeResult, fuer url: URL) {
        let meldung: IntakeMessage? = switch result {
        case .verbucht:
            nil
        case .bereitsVorhanden:
            IntakeMessage(id: url, art: .hinweis, text: "Bereits vorhanden, der Beleg hängt schon an einer Buchung.")
        case let .fehler(file, text):
            IntakeMessage(id: file, art: .fehler, text: text)
        }
        guard let meldung else { return }
        messages.removeAll { $0.id == meldung.id }
        messages.append(meldung)
    }

    /// Feeds the table for as long as the window lives.
    func observe() async {
        processInbox()
        loadExported()
        do {
            for try await neue in repository.observeBookings() {
                buchungen = neue
            }
        } catch {
            fehler = "\(error)"
        }
    }

    var visible: [Buchung] {
        Overview.visible(buchungen, filter: filter, reviewFilter: reviewFilter, search: search).sorted(using: sortOrder)
    }

    var ausgewaehlt: Buchung? {
        guard let selection else { return nil }
        return buchungen.first { $0.id == selection }
    }

    /// The saved row goes into the list right away so the table shows the
    /// change in the same frame; the observation delivers the same content a
    /// moment later.
    @discardableResult
    func save(_ buchung: Buchung) -> Buchung? {
        do {
            let saved = try repository.save(buchung, akteur: .nutzer)
            if let stelle = buchungen.firstIndex(where: { $0.id == saved.id }) {
                buchungen[stelle] = saved
            }
            return saved
        } catch {
            fehler = "\(error)"
            return nil
        }
    }

    /// A new expense of today with one empty position, selected in the table.
    /// The toolbar must not hide it, so a running search or an income filter
    /// steps aside.
    func createBooking() {
        let buchung = Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: .today(),
            titel: "",
            positionen: [Position(netto: .null, steuersatz: 19, steuer: .null)],
            steuerbehandlung: .inland,
            geprueftAm: Date()
        )
        guard let saved = save(buchung) else { return }
        if filter == .einnahmen {
            filter = .alle
        }
        search = ""
        selection = saved.id
        inspectorVisible = true
    }

    /// The click on the symbol in the Bezahlt column. An open booking is
    /// settled with one payment of the rest, a settled one loses its payments.
    /// Part payments and refunds stay a matter for the inspector.
    func togglePayment(_ buchung: Buchung) {
        var neu = buchung
        if buchung.zahlungsstand == .bezahlt {
            neu.zahlungen = []
        } else {
            let offen = buchung.brutto - buchung.gezahlt
            guard offen > .null else { return }
            neu.zahlungen.append(
                Zahlung(datum: .today(), betrag: offen, richtung: buchung.richtung, geprueft: true)
            )
        }
        save(neu)
    }

    func confirm(_ buchung: Buchung) {
        guard let id = buchung.id else { return }
        do {
            try repository.confirm(id: id)
        } catch {
            fehler = "\(error)"
        }
    }

    /// The row leaves the list before the inspector closes, so its pending
    /// edit cannot write the booking back.
    func delete(_ buchung: Buchung) {
        guard let id = buchung.id else { return }
        buchungen.removeAll { $0.id == id }
        selection = nil
        do {
            // The last booking of a receipt takes the file with it.
            try path.remove(repository.delete(id: id))
        } catch {
            fehler = "\(error)"
        }
    }

    /// Takes one receipt off a booking, and its original out of the archive
    /// when no other booking carries it.
    func removeReceipt(_ sha256: String, von id: Int64) {
        do {
            try path.remove(repository.removeReceipt(sha256, von: id))
        } catch {
            fehler = "\(error)"
        }
    }

    // MARK: - Export

    private func loadExported() {
        do {
            exportedPeriods = try repository.exportedPeriods()
        } catch {
            fehler = "\(error)"
        }
    }

    /// Notes that the values of the period left the app.
    func markExported(_ zeitraum: Zeitraum) {
        do {
            try repository.markExported(zeitraum)
            loadExported()
        } catch {
            fehler = "\(error)"
        }
    }

    /// True when the booking was changed after the values of one of its
    /// periods left the app. Only then does the inspector have something to
    /// say; a booking that has not moved since the export is fine.
    func changedAfterExport(_ buchung: Buchung) -> Bool {
        exportedPeriods.contains { zeitraum, exportiertAm in
            zeitraum.beruehrt(buchung) && buchung.geaendertAm > exportiertAm
        }
    }

    func profile() -> Profil {
        do {
            return try repository.profile()
        } catch {
            fehler = "\(error)"
            return Profil()
        }
    }

    func aiSettings() -> KiEinstellungen {
        do {
            return try repository.aiSettings()
        } catch {
            fehler = "\(error)"
            return KiEinstellungen()
        }
    }

    func saveAISettings(_ einstellungen: KiEinstellungen) {
        do {
            try repository.saveAISettings(einstellungen)
        } catch {
            fehler = "\(error)"
        }
    }

    func saveProfile(_ profile: Profil) {
        do {
            try repository.saveProfile(profile)
        } catch {
            fehler = "\(error)"
        }
    }
}

/// What the toolbar shows while the inbox is worked through.
struct Progress: Equatable {
    var gesamt = 0
    var erledigt = 0
    var laeuft = false

    var visible: Bool {
        gesamt > 0
    }

    var text: String {
        "\(erledigt) von \(gesamt) fertig"
    }
}

/// A note over the table: a file that stayed in the inbox with the text the
/// run ended on, or a short word that a file was already there.
struct IntakeMessage: Identifiable, Hashable {
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
