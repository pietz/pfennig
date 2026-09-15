@testable import Core
import Testing

@Test func eineVolleZahlungTrifftDiePositionenGenau() {
    let positionen = [position(10000, 19), position(10000, 7)]
    let anteile = Aufteilung.aufteilen(positionen: positionen, betraege: [Cent(22600)])
    #expect(anteile[0].map(\.netto.value) == [10000, 10000])
    #expect(anteile[0].map(\.steuer.value) == [1900, 700])
}

@Test func teilzahlungenVerteilenMitRestAufDenGroesstenRest() {
    // 1.000 Cent netto, 190 Cent Steuer: eine Zahlung von 100 Cent lässt einen
    // Cent übrig, der an den größten Rest geht.
    let positionen = [position(1000, 19)]
    let anteile = Aufteilung.aufteilen(positionen: positionen, betraege: [Cent(100), Cent(1090)])
    #expect(anteile[0].map(\.netto.value) == [84])
    #expect(anteile[0].map(\.steuer.value) == [16])
    // Die zweite Zahlung macht die Rechnung genau voll.
    #expect(anteile[1].map(\.netto.value) == [916])
    #expect(anteile[1].map(\.steuer.value) == [174])
}

@Test func teilzahlungenEinesMischbelegsSummierenSichAufDenBeleg() {
    let positionen = [position(3333, 19), position(777, 7)]
    let betraege = [Cent(1000), Cent(1000), Cent(2797)]
    let anteile = Aufteilung.aufteilen(positionen: positionen, betraege: betraege)
    let netto = anteile.flatMap(\.self).reduce(Int64(0)) { $0 + $1.netto.value }
    let steuer = anteile.flatMap(\.self).reduce(Int64(0)) { $0 + $1.steuer.value }
    #expect(netto == 3333 + 777)
    #expect(steuer == 633 + 54)
}

@Test func eineErstattungDrehtDenAnteilUm() {
    let positionen = [position(10000, 19)]
    let anteile = Aufteilung.aufteilen(positionen: positionen, betraege: [Cent(11900), Cent(-11900)])
    #expect(anteile[0].map(\.netto.value) == [10000])
    #expect(anteile[1].map(\.netto.value) == [-10000])
    #expect(anteile[1].map(\.steuer.value) == [-1900])
}

@Test func eineGutschriftTeiltWieDieRechnung() {
    let positionen = [position(-10000, 19)]
    let anteile = Aufteilung.aufteilen(positionen: positionen, betraege: [Cent(-5950)])
    #expect(anteile[0].map(\.netto.value) == [-5000])
    #expect(anteile[0].map(\.steuer.value) == [-950])
}
