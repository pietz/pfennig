import Foundation

/// What the schema cannot express. The CHECK constraints guarantee form and
/// types, these rules guarantee content. Every rule is one small function that
/// answers with a German sentence when the booking does not hold; a new rule
/// is a new function in `alle` or, if it only catches a misread document, in
/// `leseregeln`.
public enum ValidationRules {
    /// A rate is met when net times rate and the written tax differ by at most
    /// one cent, which is the rounding the document itself may have used.
    public static let toleranz = Cent(1)

    /// A document dated a few days ahead is a normal invoice; anything beyond
    /// that is a misread year or day.
    public static let vorlaufTage = 3

    public typealias Regel = @Sendable (Buchung, Profil) -> String?

    /// What makes a booking invalid, no matter who wrote it.
    public static let alle: [Regel] = [
        mindestensEinePosition,
        kategorieIstBekannt,
        reverseChargeNurBeiAuslaendischerGegenpartei,
        kleinunternehmerNurBeiEigenenEinnahmen,
        inlandNurMit19Oder7,
        reverseChargeOhneSteuer,
        reverseChargeAusgabeBrauchtSatz,
        zahlungenSindPlausibel,
        nutzungsdauerNurBeiAusgaben
    ]

    /// What catches the agent misreading a document. A booking that breaks one
    /// of these may still be true: an invoice rounds its lines differently than
    /// the total, or it really is dated ahead. The user who confirms has the
    /// document in front of them, so only the agent's writes run these.
    public static let leseregeln: [Regel] = [
        steuerPasstZumSatz,
        datumLiegtNichtWeitInDerZukunft
    ]

    /// All complaints about one booking, empty when it passes.
    public static func validate(_ buchung: Buchung, profile: Profil) -> [String] {
        alle.compactMap { $0(buchung, profile) }
    }

    // MARK: - Die Regeln

    static let mindestensEinePosition: Regel = { buchung, _ in
        buchung.positionen.isEmpty ? "Die Buchung braucht mindestens eine Position." : nil
    }

    /// The positions of a reverse charge booking carry the rate the recipient
    /// owes and no tax at all, so there is nothing here to compare.
    static let steuerPasstZumSatz: Regel = { buchung, _ in
        guard buchung.steuerbehandlung != .reverseCharge else { return nil }
        for (nummer, position) in buchung.positionen.enumerated() {
            let erwartet = Position.steuer(netto: position.netto, steuersatz: position.steuersatz)
            let abweichung = Cent(abs((position.steuer - erwartet).value))
            guard abweichung > toleranz else { continue }
            return """
            Position \(nummer + 1): steuer \(position.steuer.value) passt nicht zu netto \
            \(position.netto.value) bei \(position.steuersatz) Prozent. Lies die Beträge im Beleg noch \
            einmal und lege für jeden Steuersatz und jede Rechnungszeile eine eigene Position an.
            """
        }
        return nil
    }

    static let kategorieIstBekannt: Regel = { buchung, _ in
        guard let kategorie = buchung.kategorie, kategorie.isEmpty == false else {
            return "kategorie fehlt; sie muss ein Schlüssel aus der Kategorienliste sein."
        }
        guard let bekannt = Kategorie.alle.first(where: { $0.schluessel == kategorie }) else {
            return "kategorie \"\(kategorie)\" steht nicht in der Kategorienliste."
        }
        guard bekannt.richtung == buchung.richtung else {
            return "Kategorie passt nicht zur Richtung."
        }
        return nil
    }

    static let datumLiegtNichtWeitInDerZukunft: Regel = { buchung, _ in
        let grenze = LocalDate(Date().addingTimeInterval(Double(vorlaufTage) * 86400))
        guard buchung.datum > grenze else { return nil }
        return "datum \(buchung.datum) liegt zu weit in der Zukunft."
    }

    static let reverseChargeNurBeiAuslaendischerGegenpartei: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .reverseCharge else { return nil }
        let land = buchung.gegenparteiLand?.uppercased() ?? ""
        guard land.isEmpty || land == "DE" else { return nil }
        return "steuerbehandlung reverse_charge setzt eine ausländische Gegenpartei mit gegenpartei_land voraus."
    }

    static let kleinunternehmerNurBeiEigenenEinnahmen: Regel = { buchung, profile in
        guard buchung.steuerbehandlung == .kleinunternehmer else { return nil }
        guard buchung.richtung == .einnahme else {
            return "steuerbehandlung kleinunternehmer gilt nur für eigene Einnahmen."
        }
        guard profile.kleinunternehmer else {
            return "steuerbehandlung kleinunternehmer passt nicht, das Profil ist regelbesteuert."
        }
        return nil
    }

    /// A rate of 0 is no domestic turnover in either direction; it belongs on
    /// another treatment. The 19 or 7 binds income alone: the 2026 form has
    /// lines for those two rates, so any other rate would fall out of the UStVA
    /// without a word. An incoming invoice may carry the rate the supplier
    /// charges, among them the flat rate of §24 UStG, and Kz 66 takes the
    /// written tax as it stands.
    static let inlandNurMit19Oder7: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .inland else { return nil }
        if buchung.positionen.contains(where: { $0.steuersatz == 0 }) {
            return "steuerbehandlung inland mit Steuersatz 0 gehört auf steuerfrei oder nicht_steuerbar."
        }
        guard buchung.richtung == .einnahme,
              let fremd = buchung.positionen.first(where: { [19, 7].contains($0.steuersatz) == false })
        else { return nil }
        return "steuerbehandlung inland gilt nur für 19 oder 7 Prozent, nicht für \(fremd.steuersatz)."
    }

    /// A §13b invoice carries no German VAT; the app computes the owed tax and
    /// the matching Vorsteuer itself. Tax in a position would count twice.
    static let reverseChargeOhneSteuer: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .reverseCharge else { return nil }
        guard buchung.positionen.contains(where: { $0.steuer != .null }) else { return nil }
        return "Bei reverse_charge steht in jeder Position steuer 0; die geschuldete Steuer rechnet Pfennig selbst."
    }

    /// On a §13b purchase the rate is the one the recipient owes, and Pfennig
    /// computes Kz 47 or 85 from it, so it has to be a German rate. On an own
    /// service abroad the recipient owes their own country's tax, which the
    /// form never asks for, so there the rate stays free.
    static let reverseChargeAusgabeBrauchtSatz: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .reverseCharge, buchung.richtung == .ausgabe else { return nil }
        guard let fremd = buchung.positionen.first(where: { [19, 7].contains($0.steuersatz) == false })
        else { return nil }
        return """
        Bei reverse_charge trägt jede Position den Steuersatz, den du als Leistungsempfänger schuldest: \
        19 oder 7, nicht \(fremd.steuersatz).
        """
    }

    /// Eine Nutzungsdauer macht die Buchung zum Anlagegut; eine Einnahme kann
    /// keines sein und null Jahre gibt es nicht.
    static let nutzungsdauerNurBeiAusgaben: Regel = { buchung, _ in
        guard let jahre = buchung.nutzungsdauerJahre else { return nil }
        guard buchung.richtung == .ausgabe else {
            return "nutzungsdauer_jahre gibt es nur bei Ausgaben."
        }
        return jahre > 0 ? nil : "nutzungsdauer_jahre muss größer als null sein."
    }

    static let zahlungenSindPlausibel: Regel = { buchung, _ in
        for zahlung in buchung.zahlungen where zahlung.betrag == .null {
            return "Eine Zahlung hat den Betrag 0; Zahlungen brauchen einen Betrag ungleich null."
        }
        return nil
    }
}
