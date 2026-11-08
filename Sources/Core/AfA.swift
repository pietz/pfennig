import Foundation

/// The Abschreibung of an abnutzbares bewegliches Wirtschaftsgut, §7 Abs. 1
/// EStG: linear over the Nutzungsdauer from the `afa_tabelle`, in the year of
/// the purchase only for the months from the purchase month on, and the last
/// year takes what is left. A Nutzungsdauer of one year writes the whole cost
/// off in the year of the purchase, BMF vom 22.02.2022.
///
/// The Anschaffungsdatum is the Belegdatum; the payment plays no role here,
/// §4 Abs. 3 Satz 3 EStG.
public enum AfA {
    /// The Anschaffungskosten: the net of the booking without its
    /// Privatanteil, the gross for a Kleinunternehmer, who deducts no
    /// Vorsteuer.
    public static func anschaffungskosten(_ buchung: Buchung, brutto: Bool) -> Cent {
        EUeR.ohnePrivatanteil(
            buchung.netto + (brutto ? buchung.steuer : .null),
            prozent: buchung.privatanteilProzent
        )
    }

    /// The AfA of the calendar year, zero before the year of the purchase and
    /// after the last year.
    public static func betrag(_ buchung: Buchung, jahr: Int, brutto: Bool) -> Cent {
        kumuliert(buchung, jahr: jahr, brutto: brutto) - kumuliert(buchung, jahr: jahr - 1, brutto: brutto)
    }

    /// What the Anlagegut is still worth at the end of the year.
    public static func restbuchwert(_ buchung: Buchung, endeJahr: Int, brutto: Bool) -> Cent {
        anschaffungskosten(buchung, brutto: brutto) - kumuliert(buchung, jahr: endeJahr, brutto: brutto)
    }

    /// The AfA from the year of the purchase to the end of the year.
    /// Everything else is a difference of this, so the rounded yearly amount
    /// cannot miss the sum: the Abschreibung ends with the month in which the
    /// Nutzungsdauer runs out, counted from the purchase month, and the last
    /// year of use takes the rest.
    private static func kumuliert(_ buchung: Buchung, jahr: Int, brutto: Bool) -> Cent {
        guard let jahre = buchung.nutzungsdauerJahre, jahr >= buchung.datum.jahr else { return .null }
        let kosten = anschaffungskosten(buchung, brutto: brutto)
        let letztesJahr = buchung.datum.jahr + (buchung.datum.monat - 1 + jahre * 12 - 1) / 12
        guard jahre > 1, jahr < letztesJahr else { return kosten }
        let jahresbetrag = geteilt(Decimal(kosten.value), durch: Decimal(jahre))
        let anschaffungsjahr = geteilt(Decimal(jahresbetrag.value * Int64(13 - buchung.datum.monat)), durch: 12)
        return min(anschaffungsjahr + Cent(Int64(jahr - buchung.datum.jahr) * jahresbetrag.value), kosten)
    }

    /// An amount out of a division, rounded to the cent.
    private static func geteilt(_ zaehler: Decimal, durch nenner: Decimal) -> Cent {
        var raw = zaehler / nenner
        var gerundet = Decimal()
        NSDecimalRound(&gerundet, &raw, 0, .plain)
        return Cent(NSDecimalNumber(decimal: gerundet).int64Value)
    }
}
