import Foundation
@testable import Kern
import Testing

@Test func derQuartalszahlerSchuldetImSeptemberDasDritteQuartal() {
    let zeitraum = Zeitraum.naechsteUStVA(
        rhythmus: .vierteljaehrlich, dauerfristverlaengerung: false, heute: datum(2026, 9, 14)
    )
    #expect(zeitraum == q3)
    #expect(zeitraum.frist().formatiert == "10.10.2026")
    #expect(zeitraum.frist(dauerfristverlaengerung: true).formatiert == "10.11.2026")
}

@Test func vorDerFristBleibtDasVorherigeQuartalOffen() {
    // Am 5. Juli ist die Frist für Q2 noch nicht verstrichen.
    let frueh = Zeitraum.naechsteUStVA(
        rhythmus: .vierteljaehrlich, dauerfristverlaengerung: false, heute: datum(2026, 7, 5)
    )
    #expect(frueh == Zeitraum(jahr: 2026, einteilung: .quartal(2)))
    // Mit Dauerfristverlängerung liefe die Frist für Q2 bis zum 10. August.
    let verlaengert = Zeitraum.naechsteUStVA(
        rhythmus: .vierteljaehrlich, dauerfristverlaengerung: true, heute: datum(2026, 8, 3)
    )
    #expect(verlaengert == Zeitraum(jahr: 2026, einteilung: .quartal(2)))
}

@Test func derMonatszahlerRuecktMitDemZehntenWeiter() {
    let vorher = Zeitraum.naechsteUStVA(rhythmus: .monatlich, dauerfristverlaengerung: false, heute: datum(2026, 9, 5))
    #expect(vorher == Zeitraum(jahr: 2026, einteilung: .monat(8)))
    let nachher = Zeitraum.naechsteUStVA(
        rhythmus: .monatlich,
        dauerfristverlaengerung: false,
        heute: datum(2026, 9, 14)
    )
    #expect(nachher == Zeitraum(jahr: 2026, einteilung: .monat(9)))
}

@Test func ueberDenJahreswechselHinweg() {
    let januar = Zeitraum.naechsteUStVA(rhythmus: .monatlich, dauerfristverlaengerung: false, heute: datum(2027, 1, 5))
    #expect(januar == Zeitraum(jahr: 2026, einteilung: .monat(12)))
    #expect(januar.frist().formatiert == "10.01.2027")
}

@Test func dieEuerZeigtBisZurFristAufDasVorjahr() {
    #expect(Zeitraum.naechsteEUeR(heute: datum(2026, 3, 1)) == Zeitraum(jahr: 2025, einteilung: .jahr))
    // Die Frist für 2025 läuft bis zum 31. Juli 2026, §149 Abs. 2 AO.
    #expect(Zeitraum.naechsteEUeR(heute: datum(2026, 7, 31)) == Zeitraum(jahr: 2025, einteilung: .jahr))
    #expect(Zeitraum.naechsteEUeR(heute: datum(2026, 8, 1)) == Zeitraum(jahr: 2026, einteilung: .jahr))
    #expect(Zeitraum.naechsteEUeR(heute: datum(2026, 9, 14)) == Zeitraum(jahr: 2026, einteilung: .jahr))
}

@Test func codeUndDateinameFolgenDerEinteilung() {
    #expect(q3.code == "43")
    #expect(q3.dateiname == "UStVA-2026-Q3.xml")
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(7)).code == "07")
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(7)).dateiname == "UStVA-2026-07.xml")
    #expect(Zeitraum(jahr: 2026, einteilung: .jahr).dateiname == "EUeR-2026.csv")
    #expect(Zeitraum(jahr: 2026, einteilung: .quartal(1)).bis.formatiert == "31.03.2026")
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(2)).bis.formatiert == "28.02.2026")
}

@Test func ungeprueftesImZeitraumWirdGezaehlt() {
    var offen = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 8, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 8, 2, 11900, .einnahme)]
    )
    offen.geprueftAm = nil
    var geprueft = offen
    geprueft.id = 2
    geprueft.geprueftAm = Date()
    var unsicher = geprueft
    unsicher.id = 3
    unsicher.zahlungen[0].geprueft = false
    #expect(q3.ungeprueft([offen, geprueft, unsicher]) == 2)
    #expect(q4.ungeprueft([offen, geprueft, unsicher]) == 0)
}

@Test func einExportierterZeitraumUeberlebtDenRundweg() throws {
    let repository = try Repository.imSpeicher()
    #expect(try repository.exportierteZeitraeume().isEmpty)

    try repository.exportVermerken(q3)
    try repository.exportVermerken(Zeitraum(jahr: 2025, einteilung: .jahr))
    try repository.exportVermerken(Zeitraum(jahr: 2026, einteilung: .monat(7)))
    let gelesen = try repository.exportierteZeitraeume()
    #expect(gelesen.count == 3)
    #expect(gelesen[q3] != nil)
    #expect(gelesen[Zeitraum(jahr: 2025, einteilung: .jahr)] != nil)
    #expect(gelesen[Zeitraum(jahr: 2026, einteilung: .monat(7))] != nil)
    #expect(gelesen[q4] == nil)

    // Ein zweiter Export desselben Zeitraums legt keine zweite Zeile an.
    try repository.exportVermerken(q3)
    #expect(try repository.exportierteZeitraeume().count == 3)
}
