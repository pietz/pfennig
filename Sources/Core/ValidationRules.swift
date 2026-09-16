import Foundation

/// What the schema cannot express. The CHECK constraints guarantee form and
/// types, these rules guarantee content. Every rule is one small function that
/// answers with a German sentence when the booking does not hold; a new rule
/// is a new function in `alle`.
public enum ValidationRules {
    /// A rate is met when net times rate and the written tax differ by at most
    /// one cent, which is the rounding the document itself may have used.
    public static let toleranz = Cent(1)

    /// A document dated a few days ahead is a normal invoice; anything beyond
    /// that is a misread year or day.
    public static let vorlaufTage = 3

    public typealias Regel = @Sendable (Buchung, Profil) -> String?

    public static let alle: [Regel] = [
        mindestensEinePosition,
        steuerPasstZumSatz,
        kategorieIstBekannt,
        datumLiegtNichtWeitInDerZukunft,
        reverseChargeNurBeiAuslaendischerGegenpartei,
        kleinunternehmerNurBeiEigenenEinnahmen,
        inlandOhneSteuerBrauchtEigeneBehandlung,
        zahlungenSindPlausibel
    ]

    /// All complaints about one booking, empty when it passes.
    public static func validate(_ buchung: Buchung, profile: Profil) -> [String] {
        alle.compactMap { $0(buchung, profile) }
    }

    // MARK: - Die Regeln

    static let mindestensEinePosition: Regel = { buchung, _ in
        buchung.positionen.isEmpty ? "Die Buchung braucht mindestens eine Position." : nil
    }

    static let steuerPasstZumSatz: Regel = { buchung, _ in
        for (nummer, position) in buchung.positionen.enumerated() {
            let erwartet = Position.steuer(netto: position.netto, steuersatz: position.steuersatz)
            let abweichung = Cent(abs((position.steuer - erwartet).value))
            guard abweichung > toleranz else { continue }
            return """
            Position \(nummer + 1): steuer \(position.steuer.value) passt nicht zu netto \
            \(position.netto.value) bei \(position.steuersatz) Prozent, erwartet \(erwartet.value) Cent.
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

    static let inlandOhneSteuerBrauchtEigeneBehandlung: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .inland, buchung.positionen.isEmpty == false else { return nil }
        guard buchung.positionen.allSatisfy({ $0.steuersatz == 0 }) else { return nil }
        return "steuerbehandlung inland mit Steuersatz 0 gehört auf steuerfrei oder nicht_steuerbar."
    }

    static let zahlungenSindPlausibel: Regel = { buchung, _ in
        for zahlung in buchung.zahlungen where zahlung.betrag == .null {
            return "Eine Zahlung hat den Betrag 0; Zahlungen brauchen einen Betrag ungleich null."
        }
        return nil
    }
}
