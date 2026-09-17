@testable import Core
import Foundation
import Testing

private func mehrjaehrigesAnlagegut() -> Buchung {
    buchung(
        id: 100,
        richtung: .ausgabe,
        art: .sonstiges,
        datum: datum(2024, 3, 15),
        nutzungsdauer: 2,
        positionen: [position(300_000, 19)],
        zahlungen: [zahlung(2024, 3, 20, 357_000)]
    )
}

@Test func derQuartalszahlerSchuldetImSeptemberDasDritteQuartal() {
    let zeitraum = Zeitraum.naechsteUStVA(
        rhythmus: .vierteljaehrlich, dauerfristverlaengerung: false, today: datum(2026, 9, 14)
    )
    #expect(zeitraum == q3)
    // Der 10. Oktober 2026 ist ein Samstag, §108 Abs. 3 AO schiebt auf Montag.
    #expect(zeitraum.frist().formatted == "12.10.2026")
    #expect(zeitraum.frist(dauerfristverlaengerung: true).formatted == "10.11.2026")
}

@Test func vorDerFristBleibtDasVorherigeQuartalOffen() {
    // Am 5. Juli ist die Frist für Q2 noch nicht verstrichen.
    let frueh = Zeitraum.naechsteUStVA(
        rhythmus: .vierteljaehrlich, dauerfristverlaengerung: false, today: datum(2026, 7, 5)
    )
    #expect(frueh == Zeitraum(jahr: 2026, einteilung: .quartal(2)))
    // Mit Dauerfristverlängerung liefe die Frist für Q2 bis zum 10. August.
    let verlaengert = Zeitraum.naechsteUStVA(
        rhythmus: .vierteljaehrlich, dauerfristverlaengerung: true, today: datum(2026, 8, 3)
    )
    #expect(verlaengert == Zeitraum(jahr: 2026, einteilung: .quartal(2)))
}

@Test func derMonatszahlerRuecktMitDemZehntenWeiter() {
    let vorher = Zeitraum.naechsteUStVA(rhythmus: .monatlich, dauerfristverlaengerung: false, today: datum(2026, 9, 5))
    #expect(vorher == Zeitraum(jahr: 2026, einteilung: .monat(8)))
    let nachher = Zeitraum.naechsteUStVA(
        rhythmus: .monatlich,
        dauerfristverlaengerung: false,
        today: datum(2026, 9, 14)
    )
    #expect(nachher == Zeitraum(jahr: 2026, einteilung: .monat(9)))
}

@Test func ueberDenJahreswechselHinweg() {
    let januar = Zeitraum.naechsteUStVA(rhythmus: .monatlich, dauerfristverlaengerung: false, today: datum(2027, 1, 5))
    #expect(januar == Zeitraum(jahr: 2026, einteilung: .monat(12)))
    // Der 10. Januar 2027 ist ein Sonntag.
    #expect(januar.frist().formatted == "11.01.2027")
}

@Test func dieEuerZeigtBisZurFristAufDasVorjahr() {
    #expect(Zeitraum.naechsteEUeR(today: datum(2026, 3, 1)) == Zeitraum(jahr: 2025, einteilung: .jahr))
    // Die Frist für 2025 läuft bis zum 31. Juli 2026, §149 Abs. 2 AO.
    #expect(Zeitraum.naechsteEUeR(today: datum(2026, 7, 31)) == Zeitraum(jahr: 2025, einteilung: .jahr))
    #expect(Zeitraum.naechsteEUeR(today: datum(2026, 8, 1)) == Zeitraum(jahr: 2026, einteilung: .jahr))
    #expect(Zeitraum.naechsteEUeR(today: datum(2026, 9, 14)) == Zeitraum(jahr: 2026, einteilung: .jahr))
}

@Test func codeUndDateinameFolgenDerEinteilung() {
    #expect(q3.code == "43")
    #expect(q3.dateiname == "UStVA-2026-Q3.xml")
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(7)).code == "07")
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(7)).dateiname == "UStVA-2026-07.xml")
    #expect(Zeitraum(jahr: 2026, einteilung: .jahr).dateiname == "EUeR-2026.csv")
    #expect(Zeitraum(jahr: 2026, einteilung: .quartal(1)).bis.formatted == "31.03.2026")
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(2)).bis.formatted == "28.02.2026")
}

@Test func ungeprueftesImZeitraumWirdGezaehlt() {
    var offen = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 8, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 8, 2, 11900)]
    )
    offen.geprueftAm = nil
    var geprueft = offen
    geprueft.id = 2
    geprueft.geprueftAm = Date()
    #expect(q3.ungeprueft([offen, geprueft]) == 1)
    #expect(q4.ungeprueft([offen, geprueft]) == 0)
}

@Test func euerBeruehrtSpaetereUndLetzteAfaJahreAberKeineUStVA() {
    let anlagegut = mehrjaehrigesAnlagegut()
    let euer2025 = Zeitraum(jahr: 2025, einteilung: .jahr)
    let euer2026 = Zeitraum(jahr: 2026, einteilung: .jahr)
    let euer2027 = Zeitraum(jahr: 2027, einteilung: .jahr)
    let ustva2025 = Zeitraum(jahr: 2025, einteilung: .quartal(1))

    #expect(euer2025.beruehrt(anlagegut))
    // 2026 is the final partial depreciation year for a March acquisition.
    #expect(euer2026.beruehrt(anlagegut))
    #expect(euer2027.beruehrt(anlagegut) == false)
    #expect(ustva2025.beruehrt(anlagegut) == false)
}

@Test func datumUndZahlungBeruehrenWeiterhinEuerUndUStVA() {
    let rechnung = buchung(
        id: 101,
        richtung: .einnahme,
        datum: datum(2025, 12, 31),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 1, 15, 11900)]
    )
    #expect(Zeitraum(jahr: 2025, einteilung: .monat(12)).beruehrt(rechnung))
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(1)).beruehrt(rechnung))
    #expect(Zeitraum(jahr: 2025, einteilung: .jahr).beruehrt(rechnung))
    #expect(Zeitraum(jahr: 2026, einteilung: .jahr).beruehrt(rechnung))
    #expect(Zeitraum(jahr: 2027, einteilung: .jahr).beruehrt(rechnung) == false)
}

@Test func eineEinjaehrigeAnlageBleibtAufIhrAnschaffungsjahrBegrenzt() {
    let anlagegut = buchung(
        id: 102,
        richtung: .ausgabe,
        art: .sonstiges,
        datum: datum(2026, 11, 2),
        nutzungsdauer: 1,
        positionen: [position(250_000, 19)]
    )
    #expect(Zeitraum(jahr: 2025, einteilung: .jahr).beruehrt(anlagegut) == false)
    #expect(Zeitraum(jahr: 2026, einteilung: .jahr).beruehrt(anlagegut))
    #expect(Zeitraum(jahr: 2027, einteilung: .jahr).beruehrt(anlagegut) == false)
}

@Test func ungepruefteSpaetereAfaZaehltNurInDerEuer() {
    let anlagegut = mehrjaehrigesAnlagegut()
    #expect(Zeitraum(jahr: 2025, einteilung: .jahr).ungeprueft([anlagegut]) == 1)
    #expect(Zeitraum(jahr: 2025, einteilung: .quartal(1)).ungeprueft([anlagegut]) == 0)
}

@Test func einExportierterZeitraumUeberlebtDenRundweg() throws {
    let repository = try Repository.inMemory()
    #expect(try repository.exportedPeriods().isEmpty)

    try repository.markExported(q3)
    try repository.markExported(Zeitraum(jahr: 2025, einteilung: .jahr))
    try repository.markExported(Zeitraum(jahr: 2026, einteilung: .monat(7)))
    let gelesen = try repository.exportedPeriods()
    #expect(gelesen.count == 3)
    #expect(gelesen[q3] != nil)
    #expect(gelesen[Zeitraum(jahr: 2025, einteilung: .jahr)] != nil)
    #expect(gelesen[Zeitraum(jahr: 2026, einteilung: .monat(7))] != nil)
    #expect(gelesen[q4] == nil)

    // Ein zweiter Export desselben Zeitraums legt keine zweite Zeile an.
    try repository.markExported(q3)
    #expect(try repository.exportedPeriods().count == 3)
}

@Test func fristenWeichenWochenendeUndBundesweitenFeiertagenAus() {
    // Pfingstmontag 2030 fällt auf den 10. Juni.
    #expect(Werktag.ostersonntag(2030).formatted == "21.04.2030")
    let mai2030 = Zeitraum(jahr: 2030, einteilung: .monat(5))
    #expect(mai2030.frist().formatted == "11.06.2030")
    // Christi Himmelfahrt 2029 fällt auf den 10. Mai.
    #expect(Zeitraum(jahr: 2029, einteilung: .monat(4)).frist().formatted == "11.05.2029")
    // Der 31. Juli 2027 ist ein Samstag.
    #expect(Zeitraum(jahr: 2026, einteilung: .jahr).frist().formatted == "02.08.2027")
    // Ein Werktag bleibt, wie er ist.
    #expect(Zeitraum(jahr: 2026, einteilung: .monat(8)).frist().formatted == "10.09.2026")
}
