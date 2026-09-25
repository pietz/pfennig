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
    let chat: Chat

    var buchungen: [Buchung] = []
    private(set) var agentCreatedBookingIDs: Set<Int64> = []
    private(set) var currentProfile = Profil()
    var selection: Set<Int64> = []
    var filter: BookingFilter = .alle
    var reviewFilter: ReviewFilter = .alle
    var search = ""
    var sortOrder = [KeyPathComparator(\Buchung.datum, order: .reverse)]
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

    /// The open conversation, nil for a new one, and the message on its way.
    private(set) var conversation: Gespraech? {
        didSet { chatMessages = conversation.map { Conversation.messages($0.verlauf) } ?? [] }
    }

    private(set) var chatMessages: [ChatMessage] = []
    private(set) var conversations: [Gespraech] = []
    private(set) var pendingMessage: String?
    /// The message being written, kept here so it survives a change of page
    /// and comes back after a failed round.
    var draft = ""
    var draftFiles: [URL] = []

    var canSend: Bool {
        pendingMessage == nil
            && (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || draftFiles.isEmpty == false)
    }

    /// A running agent, from the inbox or the chat, may still hang a receipt on
    /// a booking; deleting waits until it is done.
    var deleteLocked: Bool {
        progress.running || pendingMessage != nil
    }

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
    /// The most files one drop may add to the queue.
    static let maxDrop = 50

    init() {
        do {
            try path.create()
            repository = try Repository(path: path.databaseFile)
            intake = try FileIntake(repository: repository, path: path)
            chat = Chat(intake: intake)
            currentProfile = try repository.profile()
        } catch {
            fatalError("Die Datenbank ließ sich nicht öffnen: \(error)")
        }
    }

    // MARK: - FileIntake

    /// The files the user dropped, folders included down to their last
    /// allowed file. Everything the agent cannot read is dropped silently.
    /// A drop takes at most `maxDrop` files, each one a paid run; the rest
    /// stays where it is and the strip says so.
    func acceptFiles(_ urls: [URL]) {
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                FileIntake.files(in: urls)
            }.value
            enqueue(Array(files.prefix(AppModel.maxDrop)))
            guard files.count > AppModel.maxDrop, let first = urls.first else { return }
            // Named after where the drop came from: the folder itself, or the
            // folder of the first file. Never a file, so a finished run cannot
            // clear the note.
            let origin = files.contains(first) ? first.deletingLastPathComponent() : first
            let message = IntakeMessage(
                id: origin, kind: .info,
                text: "Nur die ersten \(AppModel.maxDrop) von \(files.count) Dateien wurden übernommen; die übrigen blieben liegen."
            )
            messages.removeAll { $0.id == message.id }
            messages.append(message)
        }
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
            IntakeMessage(id: url, kind: .info, text: "Bereits vorhanden, die Datei wurde schon verarbeitet.")
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
                agentCreatedBookingIDs = try repository.agentCreatedBookingIDs()
                buchungen = incoming
            }
        } catch {
            errorMessage = "\(error)"
        }
    }

    var visible: [Buchung] {
        Overview.visible(buchungen, filter: filter, reviewFilter: reviewFilter, search: search, profile: currentProfile)
            .sorted(using: sortOrder)
    }

    var selected: Buchung? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return buchungen.first { $0.id == id }
    }

    var selectedBookings: [Buchung] {
        buchungen.filter { buchung in
            buchung.id.map(selection.contains) ?? false
        }
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

    /// A new, incomplete expense of today, selected in the table.
    /// The toolbar must not hide it, so a running search or an income filter
    /// steps aside.
    func createBooking() {
        let buchung = Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: .today(),
            titel: "",
            positionen: []
        )
        guard let saved = save(buchung) else { return }
        if filter == .einnahmen {
            filter = .alle
        }
        reviewFilter = .alle
        search = ""
        selection = Set(saved.id.map { [$0] } ?? [])
        if let id = saved.id {
            blankDrafts[id] = saved
        }
    }

    /// Bookings from the plus button as they were created. One left without
    /// any input is dropped again instead of lingering as an empty draft.
    private var blankDrafts: [Int64: Buchung] = [:]

    /// The inspector calls this when it leaves a booking, after its last save.
    /// A blank draft carries no receipt, so a running import cannot need it.
    func discardIfBlank(_ buchung: Buchung) {
        guard let id = buchung.id, var blank = blankDrafts.removeValue(forKey: id) else { return }
        // The row's timestamps come back from the database; only content counts.
        blank.erstelltAm = buchung.erstelltAm
        blank.geaendertAm = buchung.geaendertAm
        guard blank == buchung else { return }
        buchungen.removeAll { $0.id == id }
        selection.remove(id)
        do {
            try repository.delete(id: id)
        } catch {
            errorMessage = "\(error)"
        }
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
            errorMessage = error.localizedDescription
        }
    }

    /// The row leaves the list before the inspector closes, so its pending
    /// edit cannot write the booking back. Receipts no surviving booking carries
    /// go with it, row and original, so the document can be dropped again.
    func delete(_ bookings: [Buchung]) {
        guard deleteLocked == false else { return }
        let ids = Set(bookings.compactMap(\.id))
        guard ids.isEmpty == false else { return }
        let previousBookings = buchungen
        let previousSelection = selection
        buchungen.removeAll { $0.id.map(ids.contains) ?? false }
        selection.subtract(ids)
        do {
            for file in try repository.deleteWithReceipts(ids: ids) {
                try? FileManager.default.removeItem(at: path.original(file))
            }
        } catch {
            buchungen = previousBookings
            selection = previousSelection
            errorMessage = "\(error)"
        }
    }

    /// Takes one receipt off a booking. The file stays in the archive.
    func removeReceipt(_ fileID: Int64, from id: Int64) {
        do {
            try repository.removeReceipt(fileID, from: id)
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: - Chat

    /// Sends the draft. It leaves the field at once and comes back when the
    /// round fails, so the user can send it again.
    func send() async {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = draftFiles
        draft = ""
        draftFiles = []
        pendingMessage = text.isEmpty ? files.map(\.lastPathComponent).joined(separator: "\n") : text
        defer { pendingMessage = nil }
        do {
            conversation = try await chat.send(text, files: files, to: conversation)
            loadConversations()
        } catch {
            draft = text
            draftFiles = files
            errorMessage = error.localizedDescription
        }
    }

    /// Files for the next message; whatever the agent cannot read falls away.
    func attach(_ urls: [URL]) {
        draftFiles += FileIntake.files(in: urls).filter { draftFiles.contains($0) == false }
    }

    func newConversation() {
        conversation = nil
        draft = ""
        draftFiles = []
    }

    func open(_ gespraech: Gespraech) {
        conversation = gespraech
    }

    func deleteConversation(_ gespraech: Gespraech) {
        guard let id = gespraech.id else { return }
        do {
            try repository.deleteConversation(id: id)
            if conversation?.id == id {
                conversation = nil
            }
            loadConversations()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func loadConversations() {
        do {
            conversations = try repository.conversations()
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

    /// Records a file export or a manual marker that the period was handled elsewhere.
    func markExported(_ zeitraum: Zeitraum) {
        do {
            try repository.markExported(zeitraum)
            loadExported()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// True when the booking changed after one of its periods was exported
    /// or manually marked handled. The inspector warns for either event.
    func changedAfterExport(_ buchung: Buchung) -> Bool {
        exportedPeriods.contains { zeitraum, exportiertAm in
            zeitraum.beruehrt(buchung) && buchung.geaendertAm > exportiertAm
        }
    }

    func profile() -> Profil {
        currentProfile
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
            currentProfile = profile
        } catch {
            errorMessage = "\(error)"
        }
    }
}

/// Whether the toolbar shows its spinner while the inbox is worked through.
struct Progress: Equatable {
    var running = false

    var visible: Bool {
        running
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
