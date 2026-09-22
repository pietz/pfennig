@testable import Core
import Foundation
import GRDB
import Testing

private func completeDraft() -> Buchung {
    Buchung(
        richtung: .ausgabe, art: .beleg, datum: datum(2026, 9, 1),
        titel: "Software", kategorie: "software", gegenparteiLand: "US",
        positionen: [positionOhneSteuer(1000, 19)], steuerbehandlung: .reverseCharge,
        belege: [1]
    )
}

@Test func fehlendeSteuerBleibtAlsEntwurfUndBlockiertBestaetigung() throws {
    let repository = try Repository.inMemory()
    let tool = try SQLTool(repository)
    // Omission and explicit NULL both mean no selection, without a sentinel.
    for taxColumn in ["", ", steuerbehandlung"] {
        let result = tool.execute("""
        INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen\(taxColumn))
        VALUES ('ausgabe', 'beleg', '2026-09-01', 'Dienstleistung', 'software',
            '[{"netto":1000,"steuersatz":0,"steuer":0}]'\(taxColumn.isEmpty ? "" : ", NULL"))
        """)
        let id = try #require(result.created.first)
        let saved = try #require(try repository.allBookings().first { $0.id == id })
        #expect(saved.steuerbehandlung == nil)
        #expect(saved.geprueftAm == nil)
        #expect(ValidationRules.issues(saved, profile: Profil()).map(\.field) == [.taxTreatment])
        #expect(throws: CoreError.self) { try repository.confirm(id: id) }
    }
    #expect(try repository.agentCreatedBookingIDs().count == 2)
}

@Test func alteBestaetigungVerdecktFehlendeSteuerNicht() throws {
    let repository = try Repository.inMemory()
    var draft = completeDraft()
    draft.steuerbehandlung = nil
    let saved = try repository.save(draft, akteur: .agent)
    let id = try #require(saved.id)
    let timestamp = Date(timeIntervalSince1970: 123)
    // Simulate an already stored, incomplete row with an old confirmation.
    try repository.database.write { db in
        try db.execute(sql: "UPDATE buchungen SET geprueft_am = ? WHERE id = ?", arguments: [timestamp, id])
    }
    var historical = try #require(try repository.allBookings().first)
    #expect(historical.needsReview(profile: Profil()))
    #expect(historical.reviewStatus(profile: Profil()) == .zuPruefen)
    #expect(ReviewFilter.zuPruefen.includes(historical))
    #expect(Start.aufgaben([historical]).first { $0.art == .pruefen }?.anzahl == 1)
    #expect(Overview.visible([historical], filter: .alle, reviewFilter: .zuPruefen, search: "").map(\.id) == [id])
    #expect(throws: CoreError.self) { try repository.confirm(id: id) }
    #expect(try repository.allBookings().first?.geprueftAm == timestamp)

    historical.steuerbehandlung = .reverseCharge
    let corrected = try repository.save(historical, akteur: .nutzer)
    #expect(corrected.geprueftAm == nil)
    try repository.confirm(id: id)
    let complete = try #require(try repository.allBookings().first)
    #expect(complete.reviewStatus(profile: Profil()) == .geprueft)
    #expect(Start.aufgaben([complete]).first { $0.art == .pruefen }?.anzahl == 0)
}

@Test func unvollstaendigeNutzeraenderungBrauchtErneuteBestaetigung() throws {
    let repository = try Repository.inMemory()
    var saved = try repository.save(completeDraft(), akteur: .nutzer)
    let id = try #require(saved.id)
    try repository.confirm(id: id)
    saved = try #require(try repository.allBookings().first)
    saved.steuerbehandlung = nil
    saved = try repository.save(saved, akteur: .nutzer)
    #expect(saved.geprueftAm == nil)
    saved.steuerbehandlung = .reverseCharge
    saved = try repository.save(saved, akteur: .nutzer)
    #expect(saved.geprueftAm == nil)
    try repository.confirm(id: id)
    #expect(try repository.allBookings().first?.geprueftAm != nil)
}

@Test func herkunftBleibtNachManuellerKorrekturUndNeustartErhalten() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("test.sqlite")
    let repository = try Repository(path: path)
    var agent = try repository.save(completeDraft(), akteur: .agent)
    var manual = try repository.save(completeDraft(), akteur: .nutzer)
    agent.kategorie = nil
    manual.kategorie = nil
    _ = try repository.save(agent, akteur: .nutzer)
    _ = try repository.save(manual, akteur: .agent)
    let restarted = try Repository(path: path)
    #expect(try restarted.agentCreatedBookingIDs() == Set([#require(agent.id)]))
    try repository.delete(id: #require(agent.id))
    #expect(try repository.agentCreatedBookingIDs().isEmpty)
}

@Test func erforderlicheAngabenHabenFeldbezogeneHinweise() {
    var draft = completeDraft()
    draft.titel = " \n"
    draft.kategorie = nil
    draft.steuerbehandlung = nil
    draft.positionen = []
    let findings = ValidationRules.issues(draft, profile: Profil())
    #expect(Set(findings.map(\.field)) == [.title, .category, .taxTreatment, .positions])
    #expect(findings.contains { !$0.isMissing } == false)
    #expect(ValidationRules.validate(draft, profile: Profil()).isEmpty)

    draft = completeDraft()
    draft.gegenparteiLand = nil
    #expect(ValidationRules.issues(draft, profile: Profil()).map(\.field) == [.country])
    #expect(ValidationRules.validate(draft, profile: Profil()).isEmpty)
    draft.gegenparteiLand = "DE"
    #expect(ValidationRules.validate(draft, profile: Profil()).isEmpty == false)

    draft.richtung = .einnahme
    draft.kategorie = "umsatz_dienstleistung"
    draft.steuerbehandlung = .nichtSteuerbar
    draft.gegenparteiLand = nil
    #expect(ValidationRules.issues(draft, profile: Profil()).map(\.field) == [.country])
    draft.gegenparteiLand = "DE"
    #expect(ValidationRules.issues(draft, profile: Profil()).isEmpty)

    draft = completeDraft()
    draft.waehrung = "USD"
    #expect(ValidationRules.issues(draft, profile: Profil()).map(\.field) == [.originalAmount])
    draft.originalbetrag = Decimal(string: "10.123")
    #expect(ValidationRules.issues(draft, profile: Profil()).isEmpty)
    draft.waehrung = nil
    #expect(ValidationRules.issues(draft, profile: Profil()).map(\.field) == [.currency])
}

@Test func optionaleAngabenSindKeinePflichtfelder() {
    var draft = completeDraft()
    draft.steuerbehandlung = .steuerfrei
    draft.gegenparteiLand = nil
    draft.gegenparteiName = nil
    draft.belege = []
    #expect(ValidationRules.issues(draft, profile: Profil()).isEmpty)
    // Missing attachments retain their separate task, without inventing tax requirements.
    #expect(draft.missingReceipt)
}

@Test func profilabhaengigePruefungIstInAllenAnsichtenGleich() {
    var draft = completeDraft()
    draft.richtung = .einnahme
    draft.kategorie = "umsatz_dienstleistung"
    draft.steuerbehandlung = .inland
    draft.positionen = [position(1000, 19)]
    draft.geprueftAm = Date()
    let profile = Profil(kleinunternehmer: true)
    #expect(draft.needsReview(profile: Profil()) == false)
    #expect(draft.needsReview(profile: profile))
    #expect(ValidationRules.issues(draft, profile: profile).map(\.field) == [.taxTreatment])
    #expect(draft.reviewStatus(profile: profile) == .zuPruefen)
    #expect(ReviewFilter.zuPruefen.includes(draft, profile: profile))
    #expect(Start.aufgaben([draft], profile: profile).first { $0.art == .pruefen }?.anzahl == 1)
}
