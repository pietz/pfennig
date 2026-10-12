@testable import Agent
@testable import Core
import Foundation
import GRDB
import Testing

private actor MockResponses {
    var replies: [String]

    init(_ replies: [String]) {
        self.replies = replies
    }

    func answer(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        let reply = replies.isEmpty ? "{}" : replies.removeFirst()
        return (
            Data(reply.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    var transport: Transport {
        { [self] request in await answer(request) }
    }
}

private func archiveFolder() throws -> (ArchivePaths, URL) {
    let folder = FileManager.default.temporaryDirectory.appending(path: "pfennig-archive-preservation-\(UUID())")
    let paths = ArchivePaths(folder: folder)
    try paths.create()
    return (paths, folder)
}

private func archiveRows(_ repository: Repository) throws -> [String: [Row]] {
    let tables = ["buchungen", "dateien", "aktivitaeten", "anfragen", "gespraeche", "einstellungen", "zeitraeume"]
    return try repository.database.read { db in
        try Dictionary(uniqueKeysWithValues: tables.map { table in
            try (table, Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid"))
        })
    }
}

private func responseObject(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

private func sqlToolReply(_ sql: String) -> String {
    let arguments = responseObject(["sql": sql])
    return responseObject([
        "id": "retry-tool",
        "status": "completed",
        "output": [[
            "id": "function-1",
            "call_id": "call-1",
            "type": "function_call",
            "name": "sql",
            "arguments": arguments
        ]]
    ])
}

private let successfulReply = responseObject([
    "id": "retry-finished",
    "status": "completed",
    "output": [[
        "type": "message",
        "role": "assistant",
        "content": [["type": "output_text", "text": "Buchung gespeichert."]]
    ]]
])

@Test func currentArchiveReopensWithRecordsSettingsAndFilesIntact() throws {
    let (paths, folder) = try archiveFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let receiptBytes = Data("%PDF synthetic archive original".utf8)
    let inboxBytes = Data("%PDF retained inbox item".utf8)
    let hash = FileIntake.hash(receiptBytes)
    let period = Zeitraum(jahr: 2026, einteilung: .quartal(3))

    let fileID: Int64
    let reviewedID: Int64
    let draftID: Int64
    let requestID: Int64
    let conversationID: Int64
    let beforeRows: [String: [Row]]
    let beforeProfile: Profil
    let beforeAISettings: AISettings
    let beforeExportedPeriods: [Zeitraum: Date]
    do {
        let repository = try Repository(path: paths.databaseFile)
        var file = Datei(sha256: hash, dateiname: "receipt.pdf", endung: "pdf", groesse: Int64(receiptBytes.count))
        fileID = try repository.saveFile(file)
        file.id = fileID
        try receiptBytes.write(to: paths.original(file))
        try inboxBytes.write(to: paths.inbox.appending(path: "pending.pdf"))

        let date = LocalDate(jahr: 2026, monat: 9, tag: 1)
        let reviewed = try repository.save(Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: date,
            titel: "Hosting",
            kategorie: "software",
            positionen: [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
            steuerbehandlung: .inland,
            zahlungen: [Zahlung(datum: date, betrag: Cent(11900))],
            belege: [fileID]
        ), akteur: .nutzer)
        reviewedID = try #require(reviewed.id)
        try repository.confirm(id: reviewedID)

        let draft = try repository.save(Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: date,
            titel: "Domain renewal",
            kategorie: "software",
            positionen: [Position(netto: Cent(2000), steuersatz: 19, steuer: Cent(380))],
            steuerbehandlung: .inland,
            belege: [fileID]
        ), akteur: .agent)
        draftID = try #require(draft.id)

        try repository.saveProfile(Profil(
            name: "Synthetic Studio",
            adresse: "Synthetic Street 1",
            steuernummer: "000/000/00000",
            ustid: "DE000000000",
            rhythmus: .monatlich,
            dauerfristverlaengerung: true,
            sondervorauszahlungen: [2026: Cent(12000)]
        ))
        try repository.saveAISettings(AISettings(model: .luna, effort: .medium, fast: true))
        try repository.setSetting("synthetic.marker", value: "kept")
        try repository.markExported(period)

        let conversation = try repository.saveConversation(Gespraech(
            titel: "Preserved chat",
            verlauf: "[{\"type\":\"message\",\"text\":\"synthetic history\"}]"
        ))
        conversationID = try #require(conversation.id)
        requestID = try repository.startRequest(dateiId: fileID, modell: "synthetic-model")
        try repository.recordRequestTrace(
            id: requestID,
            eingabeTokens: 12,
            ausgabeTokens: 7,
            konversation: "synthetic request trace with all fields"
        )
        try repository.finishRequest(id: requestID, status: .erfolg)
        beforeRows = try archiveRows(repository)
        beforeProfile = try repository.profile()
        beforeAISettings = try repository.aiSettings()
        beforeExportedPeriods = try repository.exportedPeriods()
    }

    let reopened = try Repository(path: paths.databaseFile)
    let bookings = try reopened.allBookings()
    #expect(try archiveRows(reopened) == beforeRows)
    #expect(try reopened.profile() == beforeProfile)
    #expect(try reopened.aiSettings() == beforeAISettings)
    #expect(try reopened.exportedPeriods() == beforeExportedPeriods)
    #expect(Set(bookings.compactMap(\.id)) == Set([reviewedID, draftID]))
    let storedReviewed = try #require(bookings.first { $0.id == reviewedID })
    let storedDraft = try #require(bookings.first { $0.id == draftID })
    #expect(bookings.count == 2)
    #expect(storedReviewed.geprueftAm != nil)
    #expect(storedDraft.geprueftAm == nil)
    #expect(storedReviewed.belege == [fileID])
    #expect(try reopened.agentCreatedBookingIDs().contains(draftID))
    #expect(try reopened.fileID(sha256: hash) == fileID)
    #expect(try reopened.setting("synthetic.marker") == "kept")
    #expect(try reopened.conversations().compactMap(\.id) == [conversationID])
    let request = try #require(reopened.allRequests().first)
    #expect(request.id == requestID)
    #expect(request.dateiId == fileID)
    #expect(request.status == .erfolg)
    #expect(request.eingabeTokens == 12)
    #expect(request.ausgabeTokens == 7)
    #expect(request.konversation == "synthetic request trace with all fields")
    let storedFile = try #require(reopened.files(for: [fileID]).first)
    #expect(try Data(contentsOf: paths.original(storedFile)) == receiptBytes)
    #expect(try Data(contentsOf: paths.inbox.appending(path: "pending.pdf")) == inboxBytes)
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Backups").path) == false)
}

@Test func detachedReceiptRetriesAfterReopeningWithSameID() async throws {
    let (paths, folder) = try archiveFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let bytes = Data("%PDF detached synthetic receipt".utf8)
    let hash = FileIntake.hash(bytes)
    let date = LocalDate(jahr: 2026, monat: 9, tag: 1)

    let fileID: Int64
    let bookingID: Int64
    let firstRequestID: Int64
    let archiveOriginal: URL
    do {
        let repository = try Repository(path: paths.databaseFile)
        var file = Datei(sha256: hash, dateiname: "detached.pdf", endung: "pdf", groesse: Int64(bytes.count))
        fileID = try repository.saveFile(file)
        file.id = fileID
        archiveOriginal = paths.original(file)
        try bytes.write(to: archiveOriginal)
        let booking = try repository.save(Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: date,
            titel: "Hosting",
            kategorie: "software",
            positionen: [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
            steuerbehandlung: .inland,
            zahlungen: [Zahlung(datum: date, betrag: Cent(11900))],
            belege: [fileID]
        ), akteur: .nutzer)
        bookingID = try #require(booking.id)
        firstRequestID = try repository.startRequest(dateiId: fileID, modell: "synthetic-model")
        try repository.finishRequest(id: firstRequestID, status: .erfolg)
        try repository.removeReceipt(fileID, from: bookingID)
        #expect(try repository.isReceiptUsed(fileID) == false)
        try bytes.write(to: paths.inbox.appending(path: "detached.pdf"))
    }

    let reopened = try Repository(path: paths.databaseFile)
    #expect(try reopened.fileID(sha256: hash) == fileID)
    #expect(try reopened.hasSuccessfulRun(dateiId: fileID))
    #expect(try reopened.isReceiptUsed(fileID) == false)
    let script = MockResponses([
        sqlToolReply("UPDATE buchungen SET belege = '[\(fileID)]' WHERE id = \(bookingID)"),
        successfulReply
    ])
    let transport = await script.transport
    let intake = try FileIntake(repository: reopened, path: paths, transport: transport, key: "test")
    let inboxFile = try #require(intake.inbox().first)
    guard case .booked = await intake.process(inboxFile) else {
        Issue.record("The detached receipt should book after the archive is reopened.")
        return
    }

    let bookings = try reopened.allBookings()
    #expect(bookings.count == 1)
    #expect(bookings.first?.id == bookingID)
    #expect(bookings.first?.belege == [fileID])
    #expect(try reopened.fileID(sha256: hash) == fileID)
    #expect(try reopened.isReceiptUsed(fileID))
    #expect(try reopened.allRequests().map(\.dateiId) == [fileID, fileID])
    #expect(try reopened.allRequests().map(\.status) == [.erfolg, .erfolg])
    #expect(try Data(contentsOf: archiveOriginal) == bytes)
    #expect(intake.inbox().isEmpty)
    #expect(FileManager.default.fileExists(atPath: inboxFile.path) == false)
}
