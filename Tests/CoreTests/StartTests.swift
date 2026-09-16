@testable import Core
import Foundation
import Testing

private let heute = LocalDate(jahr: 2026, monat: 9, tag: 16)
/// Far enough back that the real clock cannot make it current again.
private let langeVorbei = LocalDate(jahr: 2020, monat: 1, tag: 1)

private func eintrag(
    id: Int64,
    richtung: Richtung = .ausgabe,
    art: Art = .sonstiges,
    datum belegdatum: LocalDate = heute,
    faelligkeit: LocalDate? = nil,
    geprueft: Bool = true,
    netto: Int64 = 10000,
    zahlungen: [Zahlung] = []
) -> Buchung {
    var eintrag = buchung(
        id: id,
        richtung: richtung,
        art: art,
        datum: belegdatum,
        positionen: [position(netto, 19)],
        zahlungen: zahlungen
    )
    eintrag.faelligkeit = faelligkeit
    eintrag.geprueftAm = geprueft ? Date() : nil
    return eintrag
}

private func anzahl(_ aufgaben: [Start.Aufgabe], _ art: Start.Aufgabenart) -> Int {
    aufgaben.first { $0.art == art }?.anzahl ?? -1
}

@Suite("Startseite")
struct StartTests {
    @Test("Jede Aufgabe zählt genau das, was ihr Filter zeigt")
    func aufgabenZaehlenWieIhrFilter() {
        let buchungen = [
            eintrag(id: 1, art: .rechnung, geprueft: false),
            eintrag(id: 2, geprueft: false),
            eintrag(id: 3, art: .rechnung),
            eintrag(id: 4, faelligkeit: langeVorbei)
        ]
        let aufgaben = Start.aufgaben(buchungen)
        for aufgabe in aufgaben {
            #expect(aufgabe.anzahl == buchungen.filter(aufgabe.art.filter.includes).count)
        }
        // 1 und 3 haben keinen Beleg, 1 und 2 sind ungeprüft, 4 ist überfällig.
        #expect(anzahl(aufgaben, .belege) == 2)
        #expect(anzahl(aufgaben, .pruefen) == 2)
        #expect(anzahl(aufgaben, .ueberfaellig) == 1)
    }

    @Test("Ignorierte Buchungen zählen in keiner Aufgabe")
    func ignorierteZaehlenNicht() {
        let aufgaben = Start.aufgaben([eintrag(id: 1, art: .ignoriert, geprueft: false, zahlungen: [])])
        #expect(aufgaben.map(\.anzahl) == [0, 0, 0])
    }

    @Test("Alle drei Aufgaben bleiben stehen, auch ohne Buchungen")
    func alleAufgabenBleibenStehen() {
        let aufgaben = Start.aufgaben([])
        #expect(aufgaben.map(\.art) == Start.Aufgabenart.allCases)
        #expect(aufgaben.map(\.anzahl) == [0, 0, 0])
    }

    @Test("Eine bezahlte Rechnung ist nicht überfällig")
    func bezahltIstNichtUeberfaellig() {
        let bezahlt = eintrag(
            id: 1,
            faelligkeit: langeVorbei,
            netto: 10000,
            zahlungen: [zahlung(2020, 1, 1, 11900)]
        )
        #expect(bezahlt.istUeberfaellig == false)
        #expect(anzahl(Start.aufgaben([bezahlt]), .ueberfaellig) == 0)
    }

    @Test("Fristen listen jeden offenen Zeitraum, früheste zuerst")
    func fristenNachDatum() throws {
        // Die älteste Buchung setzt die Untergrenze der Liste, dazwischen zählen nur belegte Zeiträume.
        let buchungen = [eintrag(id: 1, datum: LocalDate(jahr: 2025, monat: 2, tag: 3))]
        let fristen = Start.fristen(buchungen, exportiert: [:], profil: regel, today: heute)
        #expect(fristen.map(\.faellig) == fristen.map(\.faellig).sorted())
        // Q1 2025 trägt die Buchung, Q3 2026 ist die nächste; Q1 2026 ist leer und fehlt.
        #expect(fristen.contains { $0.titel == "UStVA Q1 2025" })
        #expect(fristen.contains { $0.titel == "UStVA Q3 2026" })
        #expect(fristen.contains { $0.titel == "UStVA Q1 2026" } == false)
        // Die EÜR 2025 war am 31. Juli 2026 fällig und ist offen.
        let euer = try #require(fristen.first { $0.titel == "EÜR 2025" })
        #expect(euer.faellig == LocalDate(jahr: 2026, monat: 7, tag: 31))
        #expect(euer.tage < 0)
    }

    @Test("Ohne Buchungen sind nur die nächste UStVA und die nächste EÜR geschuldet")
    func leereDatenbankHatNichtsUeberfaelliges() {
        let fristen = Start.fristen([], exportiert: [:], profil: regel, today: heute)
        #expect(fristen.map(\.titel) == ["UStVA Q3 2026", "EÜR 2026"])
        #expect(fristen.allSatisfy { $0.tage >= 0 })
    }

    @Test("Leere Zeiträume vor der ersten Buchung erscheinen nicht")
    func leereZeitraeumeFehlen() {
        // Ein Beleg vom November 2025: Q1 bis Q3 2025 bleiben draußen, Q4 2025 und die EÜR 2025 kommen.
        let buchungen = [eintrag(id: 1, datum: LocalDate(jahr: 2025, monat: 11, tag: 5))]
        let fristen = Start.fristen(buchungen, exportiert: [:], profil: regel, today: heute)
        #expect(fristen.map(\.titel) == ["UStVA Q4 2025", "EÜR 2025", "UStVA Q3 2026", "EÜR 2026"])
    }

    @Test("Der monatliche Rhythmus läuft über den Jahreswechsel")
    func monatlicherRhythmus() {
        var profil = regel
        profil.rhythmus = .monatlich
        let buchungen = [
            eintrag(id: 1, datum: LocalDate(jahr: 2025, monat: 12, tag: 20)),
            eintrag(id: 2, datum: LocalDate(jahr: 2026, monat: 8, tag: 2))
        ]
        let fristen = Start.fristen(buchungen, exportiert: [:], profil: profil, today: heute)
        let ustva = fristen.filter { $0.zeitraum.art == .ustva }.map(\.titel)
        // September 2026 ist die nächste, die August-Frist war am 10. September.
        #expect(ustva == ["UStVA Dezember 2025", "UStVA August 2026", "UStVA September 2026"])
    }

    @Test("Ein exportierter Zeitraum verschwindet aus den Fristen")
    func exportierteFristenFallenWeg() {
        let buchungen = [eintrag(id: 1, datum: LocalDate(jahr: 2026, monat: 2, tag: 3))]
        let q1 = Zeitraum(jahr: 2026, einteilung: .quartal(1))
        let fristen = Start.fristen(buchungen, exportiert: [q1: Date()], profil: regel, today: heute)
        #expect(fristen.contains { $0.zeitraum == q1 } == false)
    }

    @Test("Die Dauerfristverlängerung schiebt nur die UStVA, nicht die EÜR")
    func dauerfristverlaengerungNurUStVA() throws {
        var profil = regel
        profil.dauerfristverlaengerung = true
        let fristen = Start.fristen([], exportiert: [:], profil: profil, today: heute)
        // Q3 2026 ist ohne Verlängerung am 10. Oktober fällig, mit ihr im November.
        let ustva = try #require(fristen.first { $0.zeitraum.art == .ustva })
        #expect(ustva.faellig == LocalDate(jahr: 2026, monat: 11, tag: 10))
        let euer = try #require(fristen.first { $0.zeitraum.art == .euer })
        #expect(euer.faellig.monat == 7 && euer.faellig.tag == 31)
    }

    @Test("Jahreswerte zählen Zahlungen des Jahres, nicht Belegdaten")
    func jahreswerteNachZahlung() {
        let buchungen = [
            // Rechnung aus 2025, bezahlt in 2026: zählt in 2026.
            eintrag(
                id: 1,
                richtung: .einnahme,
                datum: LocalDate(jahr: 2025, monat: 12, tag: 20),
                netto: 100_000,
                zahlungen: [zahlung(2026, 1, 15, 119_000)]
            ),
            // Ausgabe mit Teilzahlung und Erstattung im selben Jahr.
            eintrag(
                id: 2,
                netto: 50000,
                zahlungen: [zahlung(2026, 3, 1, 59500), zahlung(2026, 4, 1, -9500)]
            ),
            // Zahlung eines anderen Jahres zählt nicht.
            eintrag(id: 3, netto: 10000, zahlungen: [zahlung(2025, 5, 1, 11900)]),
            // Ignorierte Buchungen bleiben draußen.
            eintrag(id: 4, art: .ignoriert, netto: 10000, zahlungen: [zahlung(2026, 6, 1, 11900)])
        ]
        let werte = Start.jahreswerte(buchungen, jahr: 2026)
        #expect(werte.einnahmen == Cent(119_000))
        #expect(werte.ausgaben == Cent(50000))
        #expect(werte.saldo == Cent(69000))
    }

    @Test("Die Jahresauswahl kennt jedes Jahr mit Zahlungen und das laufende")
    func jahreDerAuswahl() {
        let buchungen = [
            eintrag(id: 1, zahlungen: [zahlung(2024, 5, 1, 11900), zahlung(2026, 5, 1, 11900)]),
            eintrag(id: 2, zahlungen: [zahlung(2022, 1, 1, 11900)]),
            eintrag(id: 3, art: .ignoriert, zahlungen: [zahlung(2019, 1, 1, 11900)])
        ]
        #expect(Start.jahre(buchungen, today: heute) == [2026, 2024, 2022])
        #expect(Start.jahre([], today: heute) == [2026])
    }

    @Test("Eine Buchung über null Euro gilt als bezahlt")
    func nullBetragIstBezahlt() {
        #expect(eintrag(id: 1, netto: 0).zahlungsstand == .bezahlt)
    }

    @Test("Tage zwischen zwei Tagen zählen vorwärts und rückwärts")
    func tageZwischenDatum() {
        #expect(heute.tage(bis: LocalDate(jahr: 2026, monat: 9, tag: 16)) == 0)
        #expect(heute.tage(bis: LocalDate(jahr: 2026, monat: 10, tag: 16)) == 30)
        #expect(heute.tage(bis: LocalDate(jahr: 2026, monat: 9, tag: 6)) == -10)
    }
}
