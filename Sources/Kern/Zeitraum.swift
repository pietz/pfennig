import Foundation
import GRDB

/// What a period was exported for. The raw values are what `zeitraeume.art`
/// stores.
public enum Zeitraumart: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case ustva
    case euer
}

/// One reporting period: a month or a quarter for the UStVA, a year for the
/// EÜR. The whole export hangs on this type; it also knows the filing deadline
/// and therefore which period is the one the user owes next.
public struct Zeitraum: Hashable, Sendable {
    public enum Einteilung: Hashable, Sendable {
        case monat(Int)
        case quartal(Int)
        case jahr
    }

    public var jahr: Int
    public var einteilung: Einteilung

    public init(jahr: Int, einteilung: Einteilung) {
        self.jahr = jahr
        self.einteilung = einteilung
    }

    public var art: Zeitraumart {
        einteilung == .jahr ? .euer : .ustva
    }

    /// The ELSTER `Zeitraum` code and the `idx` column in one: `1`-`12` for a
    /// month, `41`-`44` for a quarter, `0` for the EÜR year.
    ///
    /// Unverified: the quarter codes come from the open-source project
    /// geierlein and the common ELSTER convention, not from an elster.de page
    /// (docs/research-ustva-xml.md, "Verifiziert vs. unsicher").
    public var idx: Int {
        switch einteilung {
        case let .monat(monat): monat
        case let .quartal(quartal): 40 + quartal
        case .jahr: 0
        }
    }

    /// The plain number inside the year: the month, the quarter, or zero for
    /// the EÜR year. What the picker in the export sheet holds.
    public var nummer: Int {
        switch einteilung {
        case let .monat(monat): monat
        case let .quartal(quartal): quartal
        case .jahr: 0
        }
    }

    /// The code as the XML writes it: `01`, `07`, `43`.
    public var code: String {
        String(format: "%02d", idx)
    }

    /// Reads a row of `zeitraeume` back.
    public init(jahr: Int, art: Zeitraumart, idx: Int) {
        self.jahr = jahr
        einteilung = switch art {
        case .euer: .jahr
        case .ustva: idx > 40 ? .quartal(idx - 40) : .monat(idx)
        }
    }

    // MARK: - Grenzen

    private var ersterMonat: Int {
        switch einteilung {
        case let .monat(monat): monat
        case let .quartal(quartal): (quartal - 1) * 3 + 1
        case .jahr: 1
        }
    }

    private var letzterMonat: Int {
        switch einteilung {
        case let .monat(monat): monat
        case let .quartal(quartal): quartal * 3
        case .jahr: 12
        }
    }

    public var von: Datum {
        Datum(jahr: jahr, monat: ersterMonat, tag: 1)
    }

    public var bis: Datum {
        Datum(jahr: jahr, monat: letzterMonat, tag: Datum.tageImMonat(jahr: jahr, monat: letzterMonat))
    }

    public func enthaelt(_ datum: Datum) -> Bool {
        von <= datum && datum <= bis
    }

    /// The deadline: the tenth day after the period, §18 Abs. 1 UStG, one
    /// month later with a Dauerfristverlängerung, §§46-48 UStDV. The EÜR year
    /// is due on the 31st of July of the following year, §149 Abs. 2 AO.
    public func frist(dauerfristverlaengerung: Bool = false) -> Datum {
        guard art == .ustva else { return Datum(jahr: jahr + 1, monat: 7, tag: 31) }
        var jahr = jahr
        var monat = letzterMonat + 1 + (dauerfristverlaengerung ? 1 : 0)
        while monat > 12 {
            monat -= 12
            jahr += 1
        }
        return Datum(jahr: jahr, monat: monat, tag: 10)
    }

    public var vorheriger: Zeitraum {
        switch einteilung {
        case let .monat(monat):
            monat > 1 ? Zeitraum(jahr: jahr, einteilung: .monat(monat - 1))
                : Zeitraum(jahr: jahr - 1, einteilung: .monat(12))
        case let .quartal(quartal):
            quartal > 1 ? Zeitraum(jahr: jahr, einteilung: .quartal(quartal - 1))
                : Zeitraum(jahr: jahr - 1, einteilung: .quartal(4))
        case .jahr:
            Zeitraum(jahr: jahr - 1, einteilung: .jahr)
        }
    }

    // MARK: - Vorauswahl

    /// The period the user owes next: the earliest one whose deadline has not
    /// passed. On the 14th of September 2026 that is Q3 2026 for a quarterly
    /// rhythm, and September 2026 for a monthly one, whose August deadline was
    /// four days ago.
    public static func naechsteUStVA(
        rhythmus: Rhythmus,
        dauerfristverlaengerung: Bool,
        heute: Datum = .heute()
    ) -> Zeitraum {
        let laufend = Zeitraum(
            jahr: heute.jahr,
            einteilung: rhythmus == .monatlich ? .monat(heute.monat) : .quartal((heute.monat - 1) / 3 + 1)
        )
        var kandidat = laufend
        while kandidat.vorheriger.frist(dauerfristverlaengerung: dauerfristverlaengerung) >= heute {
            kandidat = kandidat.vorheriger
        }
        return kandidat
    }

    /// The year the EÜR sheet opens on, by the same rule: the year before
    /// while its deadline of the 31st of July has not passed, the running year
    /// afterwards.
    public static func naechsteEUeR(heute: Datum = .heute()) -> Zeitraum {
        let laufend = Zeitraum(jahr: heute.jahr, einteilung: .jahr)
        return laufend.vorheriger.frist() >= heute ? laufend.vorheriger : laufend
    }

    // MARK: - Namen

    private static let monatsnamen = [
        "Januar", "Februar", "März", "April", "Mai", "Juni",
        "Juli", "August", "September", "Oktober", "November", "Dezember"
    ]

    /// `Q3 2026`, `Juli 2026`, `2026`.
    public var name: String {
        switch einteilung {
        case let .monat(monat): "\(Zeitraum.monatsnamen[monat - 1]) \(jahr)"
        case let .quartal(quartal): "Q\(quartal) \(jahr)"
        case .jahr: "\(jahr)"
        }
    }

    public static func monatsname(_ monat: Int) -> String {
        monatsnamen[monat - 1]
    }

    /// What the save panel suggests: `UStVA-2026-Q3.xml`, `EUeR-2026.csv`.
    public var dateiname: String {
        switch einteilung {
        case let .monat(monat): String(format: "UStVA-%d-%02d.xml", jahr, monat)
        case let .quartal(quartal): "UStVA-\(jahr)-Q\(quartal).xml"
        case .jahr: "EUeR-\(jahr).csv"
        }
    }

    // MARK: - Buchungen im Zeitraum

    /// True when a date of the booking can place it in this period: its own
    /// date, which carries §13b and is the floor of the Vorsteuer, or one of
    /// its payment dates.
    public func beruehrt(_ buchung: Buchung) -> Bool {
        enthaelt(buchung.datum) || buchung.zahlungen.contains { enthaelt($0.datum) }
    }

    /// How many bookings of the period the user has not confirmed yet, an
    /// unchecked payment counted as unchecked too.
    public func ungeprueft(_ buchungen: [Buchung]) -> Int {
        buchungen.filter { buchung in
            guard buchung.art != .ignoriert, beruehrt(buchung) else { return false }
            return buchung.geprueftAm == nil || buchung.zahlungen.contains { $0.geprueft == false }
        }
        .count
    }
}
