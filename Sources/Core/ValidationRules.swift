import Foundation

/// The existing rules identify the control that can resolve each finding.
public struct ValidationIssue: Hashable, Sendable {
    public enum Field: Hashable, Sendable {
        case title, category, taxTreatment, country, privateShare, usefulLife
        case positions, rate(Int), tax(Int), payment(Int), currency, originalAmount
    }

    public let field: Field
    public let message: String
    /// Missing input can be saved as a draft, but never confirmed.
    public let isMissing: Bool

    init(_ field: Field, _ message: String, isMissing: Bool = false) {
        self.field = field
        self.message = message
        self.isMissing = isMissing
    }
}

/// What the schema cannot express. The CHECK constraints guarantee form and
/// types, these rules identify missing or invalid content at its field. A new rule
/// is a new function in `alle` or, if it only catches a misread document, in
/// `leseregeln`.
public enum ValidationRules {
    /// A rate is met when net times rate and the written tax differ by at most
    /// one cent, which is the rounding the document itself may have used.
    public static let toleranz = Cent(1)

    /// A document dated a few days ahead needs no rereading; beyond that,
    /// the agent should check for a misread year or day.
    public static let vorlaufTage = 3

    public typealias Regel = @Sendable (Buchung, Profil) -> ValidationIssue?

    /// What a complete, confirmable booking requires, regardless of its author.
    public static let alle: [Regel] = [
        titelIstVorhanden,
        steuerbehandlungIstVorhanden,
        mindestensEinePosition,
        kategorieIstBekannt,
        privatanteilIstGueltig,
        reverseChargeNurBeiAuslaendischerGegenpartei,
        innergemeinschaftlicherErwerbNurBeiEUAusgaben,
        nichtSteuerbareEinnahmeBrauchtLand,
        kleinunternehmerNurBeiEigenenEinnahmen,
        kleinunternehmerKeineInlandseinnahmen,
        inlandNurMit19Oder7,
        empfaengersteuerOhneRechnungssteuer,
        empfaengersteuerAusgabeBrauchtSatz,
        zahlungenSindPlausibel,
        nutzungsdauerNurBeiAusgaben,
        originalbetragHatWaehrung,
        waehrungHatOriginalbetrag
    ]

    /// What catches the agent misreading a document. A booking that breaks one
    /// of these may still be true: an invoice rounds its lines differently than
    /// the total, or it really is dated ahead. The user who confirms has the
    /// document in front of them, so only the agent's writes run these.
    public static let leseregeln: [@Sendable (Buchung, Profil) -> String?] = [
        steuerPasstZumSatz,
        datumLiegtNichtWeitInDerZukunft
    ]

    /// Draft writes reject invalid values, but allow missing required input.
    public static func validate(_ buchung: Buchung, profile: Profil) -> [String] {
        issues(buchung, profile: profile).filter { !$0.isMissing }.map(\.message)
    }

    /// Confirmation, review queues and field feedback use exactly these findings.
    public static func issues(_ buchung: Buchung, profile: Profil) -> [ValidationIssue] {
        alle.compactMap { $0(buchung, profile) }
    }

    // MARK: - Die Regeln

    static let mindestensEinePosition: Regel = { buchung, _ in
        buchung.positionen.isEmpty
            ? ValidationIssue(.positions, "Mindestens eine Position mit den Belegbeträgen hinzufügen.", isMissing: true)
            : nil
    }

    static let titelIstVorhanden: Regel = { buchung, _ in
        buchung.titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ValidationIssue(.title, "Titel ergänzen.", isMissing: true) : nil
    }

    static let steuerbehandlungIstVorhanden: Regel = { buchung, _ in
        buchung.steuerbehandlung == nil
            ? ValidationIssue(
                .taxTreatment,
                "Steuerbehandlung auswählen, um die Buchung zu bestätigen.",
                isMissing: true
            ) : nil
    }

    static let originalbetragHatWaehrung: Regel = { buchung, _ in
        guard buchung.originalbetrag != nil,
              buchung.waehrung?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return nil }
        return ValidationIssue(.currency, "Währung des Originalbetrags ergänzen.", isMissing: true)
    }

    static let waehrungHatOriginalbetrag: Regel = { buchung, _ in
        guard buchung.waehrung?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              buchung.originalbetrag == nil else { return nil }
        return ValidationIssue(.originalAmount, "Originalbetrag in der angegebenen Währung ergänzen.", isMissing: true)
    }

    /// Recipient-tax positions carry the applicable rate, not invoice VAT.
    static let steuerPasstZumSatz: @Sendable (Buchung, Profil) -> String? = { buchung, _ in
        guard buchung.steuerbehandlung?.empfaengerSchuldetSteuer != true else { return nil }
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
            return ValidationIssue(.category, "Kategorie auswählen.", isMissing: true)
        }
        guard let bekannt = Kategorie.alle.first(where: { $0.schluessel == kategorie }) else {
            return ValidationIssue(.category, "kategorie \"\(kategorie)\" steht nicht in der Kategorienliste.")
        }
        guard bekannt.richtung == buchung.richtung else {
            return ValidationIssue(.category, "Kategorie passt nicht zur Richtung.")
        }
        return nil
    }

    static let privatanteilIstGueltig: Regel = { buchung, _ in
        guard (0 ... 100).contains(buchung.privatanteilProzent) else {
            return ValidationIssue(.privateShare, "privatanteil_prozent muss zwischen 0 und 100 liegen.")
        }
        return nil
    }

    static let datumLiegtNichtWeitInDerZukunft: @Sendable (Buchung, Profil) -> String? = { buchung, _ in
        let grenze = LocalDate(Date().addingTimeInterval(Double(vorlaufTage) * 86400))
        guard buchung.datum > grenze else { return nil }
        return "datum \(buchung.datum) liegt zu weit in der Zukunft."
    }

    static let reverseChargeNurBeiAuslaendischerGegenpartei: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .reverseCharge else { return nil }
        let land = buchung.gegenparteiLand?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard land.isEmpty || land == "DE" else { return nil }
        return ValidationIssue(
            .country,
            "Reverse Charge braucht das Land der ausländischen Gegenpartei.",
            isMissing: land.isEmpty
        )
    }

    static let innergemeinschaftlicherErwerbNurBeiEUAusgaben: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .innergemeinschaftlicherErwerb else { return nil }
        guard buchung.richtung == .ausgabe,
              let land = buchung.gegenparteiLand, land.isEmpty == false,
              Kennzahl.istEUStaat(land)
        else {
            let missing = buchung.richtung == .ausgabe
                && buchung.gegenparteiLand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            return ValidationIssue(
                buchung.richtung == .ausgabe ? .country : .taxTreatment,
                "Innergemeinschaftlicher Erwerb gilt nur für Ausgaben mit Gegenpartei in einem anderen EU-Staat.",
                isMissing: missing
            )
        }
        return nil
    }

    static let kleinunternehmerNurBeiEigenenEinnahmen: Regel = { buchung, profile in
        guard buchung.steuerbehandlung == .kleinunternehmer else { return nil }
        guard buchung.richtung == .einnahme else {
            return ValidationIssue(.taxTreatment, "steuerbehandlung kleinunternehmer gilt nur für eigene Einnahmen.")
        }
        guard profile.kleinunternehmer else {
            return ValidationIssue(
                .taxTreatment,
                "steuerbehandlung kleinunternehmer passt nicht, das Profil ist regelbesteuert."
            )
        }
        return nil
    }

    /// Kz 45 depends on whether the counterparty is abroad. Missing country
    /// must not silently mean domestic when confirming non-taxable income.
    static let nichtSteuerbareEinnahmeBrauchtLand: Regel = { buchung, _ in
        guard buchung.richtung == .einnahme, buchung.steuerbehandlung == .nichtSteuerbar,
              buchung.gegenparteiLand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        else { return nil }
        return ValidationIssue(
            .country,
            "Land der Gegenpartei ergänzen, damit die UStVA-Zuordnung feststeht.",
            isMissing: true
        )
    }

    /// Taxable domestic income would populate UStVA fields that a
    /// Kleinunternehmer must not report.
    static let kleinunternehmerKeineInlandseinnahmen: Regel = { buchung, profile in
        guard profile.kleinunternehmer,
              buchung.richtung == .einnahme,
              buchung.steuerbehandlung == .inland else { return nil }
        return ValidationIssue(
            .taxTreatment,
            "steuerbehandlung inland ist bei Einnahmen eines Kleinunternehmers nicht zulässig."
        )
    }

    /// Pfennig supports domestic income at 19 or 7 percent only. A purchase
    /// may carry other rates, including the average rates of §24 UStG, and
    /// untaxed parts such as a tip at 0; Kz 66 takes the written invoice tax.
    /// A purchase without any tax uses another treatment.
    static let inlandNurMit19Oder7: Regel = { buchung, _ in
        guard buchung.steuerbehandlung == .inland else { return nil }
        if buchung.richtung == .ausgabe, buchung.positionen.isEmpty == false,
           buchung.positionen.allSatisfy({ $0.steuersatz == 0 })
        {
            return ValidationIssue(
                .rate(0),
                "Inland braucht einen positiven Steuersatz; andernfalls die Steuerbehandlung berichtigen."
            )
        }
        guard buchung.richtung == .einnahme,
              let index = buchung.positionen.firstIndex(where: { [19, 7].contains($0.steuersatz) == false })
        else { return nil }
        return ValidationIssue(
            .rate(index),
            "steuerbehandlung inland gilt nur für 19 oder 7 Prozent, nicht für \(buchung.positionen[index].steuersatz)."
        )
    }

    static let empfaengersteuerOhneRechnungssteuer: Regel = { buchung, _ in
        guard let treatment = buchung.steuerbehandlung, treatment.empfaengerSchuldetSteuer else { return nil }
        guard let index = buchung.positionen.firstIndex(where: { $0.steuer != .null }) else { return nil }
        return ValidationIssue(
            .tax(index),
            "Bei \(treatment.rawValue) steht in jeder Position steuer 0; die geschuldete Steuer rechnet Pfennig selbst."
        )
    }

    /// Own services abroad retain the foreign recipient's rate; only purchases
    /// require a supported German rate.
    static let empfaengersteuerAusgabeBrauchtSatz: Regel = { buchung, _ in
        guard let treatment = buchung.steuerbehandlung, treatment.empfaengerSchuldetSteuer,
              buchung.richtung == .ausgabe else { return nil }
        guard let index = buchung.positionen.firstIndex(where: { [19, 7].contains($0.steuersatz) == false })
        else { return nil }
        return ValidationIssue(.rate(index), """
        Bei \(treatment.rawValue) trägt jede Position den Steuersatz, den du als Leistungsempfänger schuldest: \
        19 oder 7, nicht \(buchung.positionen[index].steuersatz).
        """)
    }

    /// Eine Nutzungsdauer macht die Buchung zum Anlagegut; eine Einnahme kann
    /// keines sein und null Jahre gibt es nicht.
    static let nutzungsdauerNurBeiAusgaben: Regel = { buchung, _ in
        guard let jahre = buchung.nutzungsdauerJahre else { return nil }
        guard buchung.richtung == .ausgabe else {
            return ValidationIssue(.usefulLife, "nutzungsdauer_jahre gibt es nur bei Ausgaben.")
        }
        return jahre > 0 ? nil : ValidationIssue(.usefulLife, "nutzungsdauer_jahre muss größer als null sein.")
    }

    static let zahlungenSindPlausibel: Regel = { buchung, _ in
        for (index, zahlung) in buchung.zahlungen.enumerated() where zahlung.betrag == .null {
            return ValidationIssue(
                .payment(index),
                "Eine Zahlung hat den Betrag 0; Zahlungen brauchen einen Betrag ungleich null."
            )
        }
        return nil
    }
}
