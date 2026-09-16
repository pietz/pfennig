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
    var inspectorVisible = false
    var exportVisible = false
    /// Set by the start page so the export sheet opens on that period.
    var exportPeriod: Zeitraum?
    var errorMessage: String?

    /// The periods the user has already exported, with the day they left the
    /// app. Read once and after every export; the export sheet and the
    /// inspector both ask it.
    private(set) var exportedPeriods: [Zeitraum: Date] = [:]

    /// The files still to be processed, what the toolbar shows about them and
    /// the notes the strip over the table carries.
    private var queue: [URL] = []
    private var inProgress: Set<URL> = []
    private(set) var progress = Progress()
    private(set) var messages: [IntakeMessage] = []
    /// The inbox is read on the first look at the window, not on every one.
    private var inboxRead = false

    var showsError: Bool {
        get { errorMessage != nil }
        set {
            if newValue == false {
                errorMessage = nil
            }
        }
    }

    /// How many files the agent works on at the same time.
    static let maxConcurrent = 10

    init() {
        do {
            try path.create()
            repository = try Repository(path: path.databaseFile)
            intake = try FileIntake(repository: repository, path: path)
        } catch {
            fatalError("Die Datenbank ließ sich nicht öffnen: \(error)")
        }
    }

    // MARK: - FileIntake

    /// The files the user dropped. Everything the agent cannot read is dropped
    /// silently; the window accepts only the allowed types in the first place.
    func acceptFiles(_ urls: [URL]) {
        enqueue(urls.filter(FileIntake.isAllowed))
    }

    /// A non-empty inbox is worked through when the app starts, once.
    func processInbox() {
        guard inboxRead == false else { return }
        inboxRead = true
        enqueue(intake.inbox())
    }

    func retry(_ message: IntakeMessage) {
        messages.removeAll { $0.id == message.id }
        enqueue([message.id])
    }

    func discard(_ message: IntakeMessage) {
        messages.removeAll { $0.id == message.id }
        if message.kind == .failure {
            try? intake.discard(message.id)
        }
    }

    /// A file already queued or in the machine does not go in a second time.
    private func enqueue(_ urls: [URL]) {
        let incoming = urls.filter { inProgress.contains($0) == false && queue.contains($0) == false }
        guard incoming.isEmpty == false else { return }
        queue.append(contentsOf: incoming)
        progress.total += incoming.count
        process()
    }

    /// Files run side by side, at most `maxConcurrent` of them. A drop that
    /// arrives while they run joins the queue the task is already emptying.
    /// Every statement of every run still goes through the one database queue,
    /// so the rows stay consistent.
    private func process() {
        guard progress.running == false else { return }
        progress.running = true
        let intake = intake
        Task {
            // A drop that lands while the group drains its last file joins
            // the queue after the loop has decided to stop, so look again.
            repeat {
                await withTaskGroup(of: (URL, FileIntakeResult).self) { group in
                    var offen = 0
                    while true {
                        while offen < AppModel.maxConcurrent, queue.isEmpty == false {
                            let url = queue.removeFirst()
                            inProgress.insert(url)
                            group.addTask { await (url, intake.process(url)) }
                            offen += 1
                        }
                        guard let (url, result) = await group.next() else { break }
                        offen -= 1
                        inProgress.remove(url)
                        record(result, fuer: url)
                        progress.done += 1
                    }
                }
            } while queue.isEmpty == false
            progress = Progress()
        }
    }

    private func record(_ result: FileIntakeResult, fuer url: URL) {
        let message: IntakeMessage? = switch result {
        case .booked:
            nil
        case .alreadyPresent:
            IntakeMessage(id: url, kind: .info, text: "Bereits vorhanden, der Beleg hängt schon an einer Buchung.")
        case let .failed(file, text):
            IntakeMessage(id: file, kind: .failure, text: text)
        }
        guard let message else { return }
        messages.removeAll { $0.id == message.id }
        messages.append(message)
    }

    /// Feeds the table for as long as the window lives.
    func observe() async {
        processInbox()
        loadExported()
        do {
            for try await incoming in repository.observeBookings() {
                buchungen = incoming
            }
        } catch {
            errorMessage = "\(error)"
        }
    }

    var visible: [Buchung] {
        Overview.visible(buchungen, filter: filter, reviewFilter: reviewFilter, search: search).sorted(using: sortOrder)
    }

    var selected: Buchung? {
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
            if let index = buchungen.firstIndex(where: { $0.id == saved.id }) {
                buchungen[index] = saved
            }
            return saved
        } catch {
            errorMessage = "\(error)"
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
        reviewFilter = .alle
        search = ""
        selection = saved.id
        inspectorVisible = true
    }

    /// The click on the symbol in the Bezahlt column. An open booking is
    /// settled with one payment of the rest, a settled one loses its payments.
    /// Part payments and refunds stay a matter for the inspector.
    func togglePayment(_ buchung: Buchung) {
        var updated = buchung
        if buchung.zahlungsstand == .bezahlt {
            updated.zahlungen = []
        } else {
            let offen = buchung.brutto - buchung.gezahlt
            guard offen != .null else { return }
            updated.zahlungen.append(Zahlung(datum: .today(), betrag: offen))
        }
        save(updated)
    }

    func confirm(_ buchung: Buchung) {
        guard let id = buchung.id else { return }
        do {
            try repository.confirm(id: id)
        } catch {
            errorMessage = "\(error)"
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
            errorMessage = "\(error)"
        }
    }

    /// Takes one receipt off a booking, and its original out of the archive
    /// when no other booking carries it.
    func removeReceipt(_ sha256: String, from id: Int64) {
        do {
            try path.remove(repository.removeReceipt(sha256, from: id))
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: - Export

    private func loadExported() {
        do {
            exportedPeriods = try repository.exportedPeriods()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Notes that the values of the period left the app.
    func markExported(_ zeitraum: Zeitraum) {
        do {
            try repository.markExported(zeitraum)
            loadExported()
        } catch {
            errorMessage = "\(error)"
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
            errorMessage = "\(error)"
            return Profil()
        }
    }

    func aiSettings() -> AISettings {
        do {
            return try repository.aiSettings()
        } catch {
            errorMessage = "\(error)"
            return AISettings()
        }
    }

    func saveAISettings(_ settings: AISettings) {
        do {
            try repository.saveAISettings(settings)
        } catch {
            errorMessage = "\(error)"
        }
    }

    func saveProfile(_ profile: Profil) {
        do {
            try repository.saveProfile(profile)
        } catch {
            errorMessage = "\(error)"
        }
    }
}

/// What the toolbar shows while the inbox is worked through.
struct Progress: Equatable {
    var total = 0
    var done = 0
    var running = false

    var visible: Bool {
        total > 0
    }

    var text: String {
        "\(done) von \(total) fertig"
    }
}

/// A note over the table: a file that stayed in the inbox with the text the
/// run ended on, or a short word that a file was already there.
struct IntakeMessage: Identifiable, Hashable {
    enum Kind: Hashable {
        case failure
        case info
    }

    let id: URL
    let kind: Kind
    let text: String

    var name: String {
        id.lastPathComponent
    }
}
