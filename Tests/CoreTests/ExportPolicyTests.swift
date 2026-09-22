@testable import Core
import Foundation
import Testing

@Test(arguments: [Art.rechnung, .nurZahlung])
func ungepruefteBuchungenBleibenInBeidenExporten(art: Art) {
    for richtung in [Richtung.einnahme, .ausgabe] {
        var eintrag = buchung(
            richtung: richtung, art: art, datum: datum(2026, 7, 1),
            kategorie: richtung == .einnahme ? "umsatz_dienstleistung" : "buerobedarf",
            positionen: [position(10000, 19)], zahlungen: [zahlung(2026, 7, 2, 11900)]
        )
        let ustva = UStVA.calculate([eintrag], zeitraum: q3, profile: regel)
        let euer = EUeR.calculate([eintrag], jahr: 2026, profile: regel)
        #expect(eintrag.geprueftAm == nil)
        #expect(q3.ungeprueft([eintrag]) == 1)
        #expect(q3.fehlendeSteuerbehandlungen([eintrag]) == 0)
        #expect(ustva.betrag(richtung == .einnahme ? 81 : 66) == (richtung == .einnahme ? 10000 : 1900))
        #expect(euer.ergebnis == Cent(richtung == .einnahme ? 11900 : -11900))
        eintrag.geprueftAm = Date()
        #expect(UStVA.calculate([eintrag], zeitraum: q3, profile: regel) == ustva)
        #expect(EUeR.calculate([eintrag], jahr: 2026, profile: regel) == euer)
    }
}

@Test(arguments: [Art.rechnung, .nurZahlung])
func unklareSteuerBleibtSichtbarAuchNachBestaetigung(art: Art) {
    var eintrag = buchung(
        richtung: .ausgabe, art: art, datum: datum(2026, 7, 1), kategorie: "buerobedarf",
        positionen: [position(10000, 0)], behandlung: nil,
        zahlungen: [zahlung(2026, 7, 2, 10000)]
    )
    let jahr = Zeitraum(jahr: 2026, einteilung: .jahr)
    for geprueftAm: Date? in [nil, Date()] {
        eintrag.geprueftAm = geprueftAm
        #expect(q3.fehlendeSteuerbehandlungen([eintrag]) == 1)
        #expect(jahr.fehlendeSteuerbehandlungen([eintrag]) == 1)
        #expect(UStVA.calculate([eintrag], zeitraum: q3, profile: regel).zeilen.isEmpty)
        #expect(EUeR.calculate([eintrag], jahr: 2026, profile: regel).ausgaben == Cent(10000))
    }
}

@Test func fehlendeSteuerbehandlungenZaehlenNurImBetroffenenZeitraumUndNieIgnorierte() {
    var eintrag = buchung(
        richtung: .ausgabe, datum: datum(2026, 7, 1), kategorie: "buerobedarf",
        positionen: [position(10000, 0)], behandlung: nil,
        zahlungen: [zahlung(2026, 10, 2, 10000), zahlung(2026, 10, 3, -1000)]
    )
    #expect(q3.fehlendeSteuerbehandlungen([eintrag]) == 1)
    #expect(q4.fehlendeSteuerbehandlungen([eintrag]) == 1)
    #expect(Zeitraum(jahr: 2026, einteilung: .jahr).fehlendeSteuerbehandlungen([eintrag]) == 1)
    #expect(Zeitraum(jahr: 2025, einteilung: .jahr).fehlendeSteuerbehandlungen([eintrag]) == 0)
    eintrag.art = .ignoriert
    #expect(q3.fehlendeSteuerbehandlungen([eintrag]) == 0)
}

@Test func unklareSteuerbehandlungEinerAnlageBleibtInSpaeterenAfaJahrenSichtbar() {
    let anlage = buchung(
        richtung: .ausgabe, datum: datum(2025, 7, 1), kategorie: "hardware", nutzungsdauer: 3,
        positionen: [position(300_000, 0)], behandlung: nil
    )
    #expect(Zeitraum(jahr: 2026, einteilung: .jahr).fehlendeSteuerbehandlungen([anlage]) == 1)
    #expect(q3.fehlendeSteuerbehandlungen([anlage]) == 0)
    #expect(Zeitraum(jahr: 2029, einteilung: .jahr).fehlendeSteuerbehandlungen([anlage]) == 0)
}
