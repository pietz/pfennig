import Foundation

/// The share of one payment that falls on one position of the booking.
public struct Anteil: Hashable, Sendable {
    public var steuersatz: Decimal
    public var netto: Cent
    public var steuer: Cent

    public init(steuersatz: Decimal, netto: Cent, steuer: Cent) {
        self.steuersatz = steuersatz
        self.netto = netto
        self.steuer = steuer
    }
}

/// Splits payments proportionally over the positions of a booking.
///
/// Under Ist-Versteuerung a partly paid invoice contributes to several
/// periods. Every payment has to carry its proportional share of every
/// position, and the shares of all payments of a fully paid booking have to
/// add up to the booking's own amounts to the cent, otherwise a receipt with
/// 7 % and 19 % paid in two instalments would report one cent too much
/// forever.
///
/// Rounding each payment on its own does not do that, so the split is
/// cumulative: for the running total of everything paid up to and including
/// the current payment, that total is apportioned over the flat list of
/// buckets `[netto₁, steuer₁, netto₂, steuer₂, …]` with the largest remainder
/// method, and the share of a payment is the apportionment of the new running
/// total minus the apportionment of the previous one. The differences
/// telescope, so the shares always add up, and the largest remainder method is
/// exact once the running total equals the sum of the buckets.
///
/// Refunds and credit notes carry a negative amount and mirror the whole
/// apportionment, so they split exactly like the payment they reverse.
public enum Aufteilung {
    /// One entry per payment, in the order given, each with one share per
    /// position. `betraege` are signed: positive in the direction of the
    /// booking, negative for a refund.
    public static func aufteilen(positionen: [Position], betraege: [Cent]) -> [[Anteil]] {
        let gewichte = positionen.flatMap { [$0.netto.wert, $0.steuer.wert] }
        var vorher = verteilen(gesamt: 0, gewichte: gewichte)
        var summe: Int64 = 0
        var ergebnis: [[Anteil]] = []
        for betrag in betraege {
            summe += betrag.wert
            let jetzt = verteilen(gesamt: summe, gewichte: gewichte)
            ergebnis.append(positionen.enumerated().map { stelle, position in
                Anteil(
                    steuersatz: position.steuersatz,
                    netto: Cent(jetzt[stelle * 2] - vorher[stelle * 2]),
                    steuer: Cent(jetzt[stelle * 2 + 1] - vorher[stelle * 2 + 1])
                )
            })
            vorher = jetzt
        }
        return ergebnis
    }

    /// Largest remainder apportionment of `gesamt` over `gewichte`. The result
    /// always adds up to `gesamt` and equals `gewichte` once the two sums are
    /// the same.
    static func verteilen(gesamt rohGesamt: Int64, gewichte rohGewichte: [Int64]) -> [Int64] {
        guard rohGewichte.isEmpty == false else { return [] }
        let rohSumme = rohGewichte.reduce(0, +)
        guard rohSumme != 0 else {
            // Nothing to be proportional to. The amount keeps its place on the
            // first bucket instead of being dropped.
            var entartet = [Int64](repeating: 0, count: rohGewichte.count)
            entartet[0] = rohGesamt
            return entartet
        }

        // Mirror a credit note so the denominator is always positive.
        let gespiegelt = rohSumme < 0
        let gesamt = gespiegelt ? -rohGesamt : rohGesamt
        let gewichte = gespiegelt ? rohGewichte.map { -$0 } : rohGewichte
        let nenner = gespiegelt ? -rohSumme : rohSumme

        var teile = [Int64](repeating: 0, count: gewichte.count)
        var reste = [Int64](repeating: 0, count: gewichte.count)
        for (stelle, gewicht) in gewichte.enumerated() {
            (teile[stelle], reste[stelle]) = geteilt(gesamt, gewicht, durch: nenner)
        }

        var rest = gesamt - teile.reduce(0, +)
        if rest != 0 {
            let schritt: Int64 = rest > 0 ? 1 : -1
            let reihenfolge = reste.indices.sorted { links, rechts in
                guard reste[links] == reste[rechts] else {
                    return schritt > 0 ? reste[links] > reste[rechts] : reste[links] < reste[rechts]
                }
                return links < rechts
            }
            var stelle = 0
            while rest != 0 {
                teile[reihenfolge[stelle % reihenfolge.count]] += schritt
                rest -= schritt
                stelle += 1
            }
        }

        return gespiegelt ? teile.map { -$0 } : teile
    }

    /// `gesamt * gewicht / nenner`, truncated towards zero, plus the exact
    /// remainder. The product goes through 128 bits, so large cent amounts
    /// cannot overflow. `nenner` is positive.
    private static func geteilt(_ gesamt: Int64, _ gewicht: Int64, durch nenner: Int64) -> (Int64, Int64) {
        guard gesamt != 0, gewicht != 0 else { return (0, 0) }
        let produkt = gesamt.magnitude.multipliedFullWidth(by: gewicht.magnitude)
        let (teil, rest) = UInt64(nenner).dividingFullWidth(produkt)
        let negativ = (gesamt < 0) != (gewicht < 0)
        return negativ ? (-Int64(teil), -Int64(rest)) : (Int64(teil), Int64(rest))
    }
}
