@testable import Core
import Testing

@Test func sondervorauszahlungMindertDezemberUndXmlCentgenau() {
    let rechnung = buchung(
        richtung: .einnahme,
        datum: datum(2026, 12, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 12, 15, 119_000)]
    )
    let profile = Profil(
        rhythmus: .monatlich, dauerfristverlaengerung: true,
        sondervorauszahlungen: [2026: Cent(10025)]
    )
    let ustva = UStVA.calculate(
        [rechnung], zeitraum: Zeitraum(jahr: 2026, einteilung: .monat(12)), profile: profile
    )
    #expect(ustva.nummern == [81, 39])
    #expect(ustva.betrag(39) == 10025)
    #expect(ustva.zahllast == Cent(8975))
    let xml = UStVAXml.xml(ustva)
    #expect(xml.contains("<Kz39>100.25</Kz39>"))
    #expect(xml.contains("<Kz83>89.75</Kz83>"))
}

@Test func sondervorauszahlungKannOhneUmsaetzeEinenUeberschussErgeben() {
    let profile = Profil(
        rhythmus: .monatlich, dauerfristverlaengerung: true,
        sondervorauszahlungen: [2026: Cent(10025)]
    )
    let ustva = UStVA.calculate(
        [], zeitraum: Zeitraum(jahr: 2026, einteilung: .monat(12)), profile: profile
    )
    #expect(ustva.nummern == [39])
    #expect(ustva.zahllast == Cent(-10025))
    #expect(UStVAXml.xml(ustva).contains("<Kz83>-100.25</Kz83>"))
}

@Test func sondervorauszahlungBleibtAufDenDezemberDesJeweiligenJahresBegrenzt() {
    let profile = Profil(
        rhythmus: .monatlich, dauerfristverlaengerung: true,
        sondervorauszahlungen: [2025: Cent(50000), 2026: Cent(10025)]
    )
    let andereZeitraeume = (1 ... 11).map { Zeitraum(jahr: 2026, einteilung: .monat($0)) } + [
        Zeitraum(jahr: 2026, einteilung: .quartal(4)),
        Zeitraum(jahr: 2026, einteilung: .jahr),
        Zeitraum(jahr: 2027, einteilung: .monat(12))
    ]
    for zeitraum in andereZeitraeume {
        let ustva = UStVA.calculate([], zeitraum: zeitraum, profile: profile)
        #expect(ustva.zeilen.isEmpty)
        #expect(ustva.zahllast == .null)
        #expect(UStVAXml.xml(ustva).contains("<Kz39>") == false)
    }
    #expect(UStVA.calculate(
        [], zeitraum: Zeitraum(jahr: 2025, einteilung: .monat(12)), profile: profile
    ).betrag(39) == 50000)
    #expect(UStVA.calculate(
        [], zeitraum: Zeitraum(jahr: 2026, einteilung: .monat(12)), profile: profile
    ).betrag(39) == 10025)
}

@Test func sondervorauszahlungBrauchtMonatlicheDauerfristverlaengerungUndEinenBetrag() {
    let profiles = [
        Profil(rhythmus: .monatlich, sondervorauszahlungen: [2026: Cent(10025)]),
        Profil(dauerfristverlaengerung: true, sondervorauszahlungen: [2026: Cent(10025)]),
        Profil(
            kleinunternehmer: true, rhythmus: .monatlich, dauerfristverlaengerung: true,
            sondervorauszahlungen: [2026: Cent(10025)]
        ),
        Profil(rhythmus: .monatlich, dauerfristverlaengerung: true),
        Profil(rhythmus: .monatlich, dauerfristverlaengerung: true, sondervorauszahlungen: [2026: .null])
    ]
    for profile in profiles {
        let ustva = UStVA.calculate(
            [], zeitraum: Zeitraum(jahr: 2026, einteilung: .monat(12)), profile: profile
        )
        #expect(ustva.zeilen.isEmpty)
        #expect(ustva.zahllast == .null)
    }
}

@Test func sondervorauszahlungImProfilErsetztKeineZahlungsbuchungFuerDieEUeR() {
    let profile = Profil(
        rhythmus: .monatlich, dauerfristverlaengerung: true,
        sondervorauszahlungen: [2026: Cent(10025)]
    )
    #expect(EUeR.calculate([], jahr: 2026, profile: profile).zeilen.isEmpty)
    let vorauszahlung = buchung(
        richtung: .ausgabe, art: .steuerzahlung, datum: datum(2026, 2, 10),
        kategorie: "ust_zahlung", positionen: [position(10025, 0)],
        behandlung: .nichtSteuerbar, zahlungen: [zahlung(2026, 2, 10, 10025)]
    )
    let euer = EUeR.calculate([vorauszahlung], jahr: 2026, profile: profile)
    #expect(euer.zeilen.map(\.zeile) == [59])
    #expect(euer.ausgaben == Cent(10025))
}
