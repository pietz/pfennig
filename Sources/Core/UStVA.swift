import Foundation

/// The values of one Umsatzsteuer-Voranmeldung, computed from the bookings.
///
/// Ist-Versteuerung, as decided in `docs/specs/pfennig-neu.md`, section 5:
///
/// - **Umsatzsteuer auf Einnahmen** arises per payment, in the period of the
///   payment date. A partial payment carries its proportional share of the
///   positions; an unpaid invoice does not count at all.
/// - **Vorsteuer auf Ausgaben** counts in the period of max(Belegdatum,
///   Zahlungsdatum), per payment. That is conservative against §15 UStG, where
///   the invoice alone would already do, and needs no further field.
/// - **§13b** arises with the service, in practice with the Belegdatum, and in
///   full, at the rate of its positions; the payment date does not matter. A
///   Kleinunternehmer owes the tax without the matching Vorsteuer.
/// - **Kz 21**, an own service to a business in another member state, follows
///   the same clock: the whole net in the period of the Belegdatum and no
///   Anzahlungen (Anleitung USt 1 E 2026 zu Zeile 35, §18b Satz 3 UStG). The
///   Belegdatum stands in for the day of the service, which Pfennig does not
///   keep. Kz 45 stays with the payments.
/// - A **Kleinunternehmer** has no Kz 81/86/66 and does not report the §19
///   income in Kz 48 either: the Voranmeldung exists only because of §13b
///   (§18 Abs. 4a UStG) and reports only that.
/// - A **Gutschrift** carries negative positions and a **Erstattung** is a
///   payment in the opposite direction; both lower the period their money
///   moved in.
public struct UStVA: Hashable, Sendable {
    /// One filled line of the form. Lines that stay at zero are not part of
    /// the result.
    public struct Zeile: Hashable, Sendable, Identifiable {
        public let kennzahl: Kennzahl
        public let betrag: Cent

        public var id: Int {
            kennzahl.nummer
        }
    }

    public let zeitraum: Zeitraum
    public let steuernummer: String
    public let zeilen: [Zeile]
    /// Kz 83: positive is a Zahllast, negative an Erstattung.
    public let zahllast: Cent

    // MARK: - Berechnung

    public static func calculate(_ buchungen: [Buchung], zeitraum: Zeitraum, profile: Profil) -> UStVA {
        var werte: [Int: Cent] = [:]
        for buchung in buchungen where zaehlt(buchung) {
            switch buchung.richtung {
            case .einnahme: einnahme(buchung, zeitraum: zeitraum, profile: profile, in: &werte)
            case .ausgabe: ausgabe(buchung, zeitraum: zeitraum, profile: profile, in: &werte)
            }
        }

        // Only filled lines, in the order of the form.
        let rows = Kennzahl.alle.compactMap { kennzahl -> Zeile? in
            guard let betrag = werte[kennzahl.nummer], betrag != .null else { return nil }
            return Zeile(kennzahl: kennzahl, betrag: betrag)
        }
        return UStVA(
            zeitraum: zeitraum,
            steuernummer: profile.steuernummer,
            zeilen: rows,
            zahllast: zahllast(rows)
        )
    }

    /// A booking marked `ignoriert` is private or an internal transfer, a
    /// `steuerzahlung` is the settlement of this very tax, and a booking whose
    /// treatment is `unklar` has nothing the form could take. None of the
    /// three is an Umsatz.
    private static func zaehlt(_ buchung: Buchung) -> Bool {
        buchung.art != .ignoriert && buchung.art != .steuerzahlung && buchung.steuerbehandlung != .unklar
    }

    /// Income counts per payment in the period of its date, with the
    /// Bemessungsgrundlage of the share that payment carries. A service to a
    /// business in another member state is the exception: it counts in full in
    /// the period of its Belegdatum.
    private static func einnahme(
        _ buchung: Buchung,
        zeitraum: Zeitraum,
        profile: Profil,
        in werte: inout [Int: Cent]
    ) {
        if buchung.steuerbehandlung == .reverseCharge, Kennzahl.istEUStaat(buchung.gegenparteiLand) {
            guard zeitraum.enthaelt(buchung.datum) else { return }
            buchen(21, buchung.netto, in: &werte)
            return
        }

        let zahlungen = geordnet(buchung)
        let anteile = Aufteilung.aufteilen(positionen: buchung.positionen, betraege: zahlungen.map(\.betrag))
        for (stelle, zahlung) in zahlungen.enumerated() where zeitraum.enthaelt(zahlung.datum) {
            for anteil in anteile[stelle] {
                guard let nummer = Kennzahl.einnahme(
                    behandlung: buchung.steuerbehandlung, steuersatz: anteil.steuersatz,
                    land: buchung.gegenparteiLand
                ) else { continue }
                // The §19 income of a Kleinunternehmer stays out of the form.
                guard profile.kleinunternehmer == false || nummer != 48 else { continue }
                buchen(nummer, anteil.netto, in: &werte)
            }
        }
    }

    private static func ausgabe(
        _ buchung: Buchung,
        zeitraum: Zeitraum,
        profile: Profil,
        in werte: inout [Int: Cent]
    ) {
        switch buchung.steuerbehandlung {
        case .inland:
            // Vorsteuer at max(Belegdatum, Zahlungsdatum), per payment.
            guard profile.kleinunternehmer == false else { return }
            let zahlungen = geordnet(buchung)
            let anteile = Aufteilung.aufteilen(positionen: buchung.positionen, betraege: zahlungen.map(\.betrag))
            for (stelle, zahlung) in zahlungen.enumerated() {
                guard zeitraum.enthaelt(max(buchung.datum, zahlung.datum)) else { continue }
                let steuer = anteile[stelle].reduce(Cent.null) { $0 + $1.steuer }
                buchen(66, abziehbar(steuer, privatanteil: buchung.privatanteilProzent), in: &werte)
            }

        case .reverseCharge:
            // The service dates the entry, not the payment.
            guard zeitraum.enthaelt(buchung.datum) else { return }
            // Every position carries the rate the recipient owes, 19 or 7.
            let steuer = buchung.positionen.reduce(Cent.null) {
                $0 + Position.steuer(netto: $1.netto, steuersatz: $1.steuersatz)
            }
            let rows = Kennzahl.reverseCharge(land: buchung.gegenparteiLand)
            buchen(rows.bemessung, buchung.netto, in: &werte)
            buchen(rows.steuer, steuer, in: &werte)
            if profile.kleinunternehmer == false {
                // §15 Abs. 1 Satz 2's ten-percent rule is limited to goods.
                // This supported RC flow is for services, so Kz 67 keeps the
                // business share even when business use is below ten percent.
                buchen(
                    67,
                    EUeR.ohnePrivatanteil(steuer, prozent: buchung.privatanteilProzent),
                    in: &werte
                )
            }

        case .kleinunternehmer, .steuerfrei, .nichtSteuerbar, .unklar:
            // The supplier charged no deductible tax; there is nothing to report.
            return
        }
    }

    /// Payments in date order for the cumulative split. Swift does not promise
    /// a stable sort, so payments of the same day keep their place in the list
    /// through their index.
    private static func geordnet(_ buchung: Buchung) -> [Zahlung] {
        buchung.zahlungen.enumerated()
            .sorted { ($0.element.datum, $0.offset) < ($1.element.datum, $1.offset) }
            .map(\.element)
    }

    /// The deductible share of the input VAT: none below ten percent of
    /// business use, §15 Abs. 1 Satz 2 UStG, otherwise the business share.
    static func abziehbar(_ steuer: Cent, privatanteil: Int) -> Cent {
        privatanteil > 90 ? .null : EUeR.ohnePrivatanteil(steuer, prozent: privatanteil)
    }

    private static func buchen(_ nummer: Int, _ betrag: Cent, in werte: inout [Int: Cent]) {
        guard betrag != .null else { return }
        werte[nummer, default: .null] = werte[nummer, default: .null] + betrag
    }

    /// Kz 83, taken the way ELSTER takes it: a base without a tax column is
    /// cut to whole euros first and multiplied by its rate, so the Zahllast
    /// shown here is the one the portal computes from the same values.
    private static func zahllast(_ rows: [Zeile]) -> Cent {
        rows.reduce(Cent.null) { summe, zeile in
            let nummer = zeile.kennzahl.nummer
            if Kennzahl.abgeleiteteSaetze[nummer] != nil {
                return summe + Kennzahl.abgeleiteteSteuer(nummer: nummer, bemessung: zeile.betrag)
            }
            if Kennzahl.steuerKennzahlen.contains(nummer) {
                return summe + zeile.betrag
            }
            if Kennzahl.vorsteuerKennzahlen.contains(nummer) {
                return summe - zeile.betrag
            }
            return summe
        }
    }
}
