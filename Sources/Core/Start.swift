import Foundation

/// What the start page shows: the work still to do, the deadlines still
/// running, and the running year in three numbers. Plain functions over the
/// bookings, so the page keeps no state of its own.
public enum Start {
    // MARK: - Aufgaben

    /// The three kinds of work the page groups bookings into.
    public enum Aufgabenart: String, CaseIterable, Sendable, Identifiable {
        case pruefen
        case belege
        case ueberfaellig

        public var id: String {
            rawValue
        }

        public var titel: String {
            switch self {
            case .pruefen: "Prüfen"
            case .belege: "Belege nachtragen"
            case .ueberfaellig: "Überfällig"
            }
        }

        public var erklaerung: String {
            switch self {
            case .pruefen: "Vom Agenten angelegt oder geändert"
            case .belege: "Rechnung oder Beleg ohne Dokument"
            case .ueberfaellig: "Zahlungsziel überschritten"
            }
        }

        /// The ledger filter behind the row. The count uses the same filter, so
        /// the number and the list the click opens can never disagree. Prüfen
        /// and Belege therefore overlap, exactly as the filters do.
        public var filter: ReviewFilter {
            switch self {
            case .pruefen: .zuPruefen
            case .belege: .ohneBeleg
            case .ueberfaellig: .ueberfaellig
            }
        }
    }

    public struct Aufgabe: Identifiable, Hashable, Sendable {
        public let art: Aufgabenart
        public let anzahl: Int

        public var id: String {
            art.id
        }

        public var erledigt: Bool {
            anzahl == 0
        }
    }

    /// All three kinds, always and in the same order. A kind without bookings
    /// keeps its row and reads as done. Ignored bookings never count, as in the
    /// table.
    public static func aufgaben(_ buchungen: [Buchung]) -> [Aufgabe] {
        let sichtbar = buchungen.filter { $0.art != .ignoriert }
        return Aufgabenart.allCases.map { art in
            Aufgabe(art: art, anzahl: sichtbar.filter(art.filter.includes).count)
        }
    }

    // MARK: - Fristen

    public struct Frist: Identifiable, Hashable, Sendable {
        public let zeitraum: Zeitraum
        public let faellig: LocalDate
        /// Days from today to the deadline, negative once it has passed.
        public let tage: Int

        public var id: String {
            "\(zeitraum.art.rawValue)-\(zeitraum.jahr)-\(zeitraum.idx)"
        }

        /// Short enough for one line: `UStVA Q3 2026`, `EÜR 2025`.
        public var titel: String {
            switch zeitraum.art {
            case .ustva: "UStVA \(zeitraum.name)"
            case .euer: "EÜR \(zeitraum.name)"
            }
        }
    }

    /// Every period the user still owes: the UStVA periods and the EÜR years
    /// from the oldest booking up to the one due next, minus the ones already
    /// exported, earliest deadline first.
    /// The periods still owed, earliest deadline first. The next UStVA and
    /// the next EÜR are always owed; an earlier period only when a booking
    /// falls into it. So an empty ledger shows nothing as overdue, and a first
    /// receipt from November does not drag the empty quarters before it onto
    /// the page.
    public static func fristen(
        _ buchungen: [Buchung],
        exportiert: [Zeitraum: Date],
        profil: Profil,
        today: LocalDate = .today()
    ) -> [Frist] {
        let sichtbar = buchungen.filter { $0.art != .ignoriert }
        let aeltestes = sichtbar.flatMap { [$0.datum] + $0.zahlungen.map(\.datum) }.min()

        func offene(ab naechster: Zeitraum) -> [Zeitraum] {
            func brauchtUStVA(_ zeitraum: Zeitraum) -> Bool {
                guard profil.kleinunternehmer, zeitraum.art == .ustva else { return true }
                let unterstuetzt = sichtbar.filter { buchung in
                    ValidationRules.reverseChargeNurBeiAuslaendischerGegenpartei(buchung, profil) == nil
                        && ValidationRules.reverseChargeOhneSteuer(buchung, profil) == nil
                        && ValidationRules.reverseChargeAusgabeBrauchtSatz(buchung, profil) == nil
                }
                return UStVA.calculate(unterstuetzt, zeitraum: zeitraum, profile: profil).zeilen.contains {
                    [47, 85].contains($0.kennzahl.nummer)
                }
            }

            var zeitraeume = brauchtUStVA(naechster) ? [naechster] : []
            guard let aeltestes else { return zeitraeume }
            var zeitraum = naechster.vorheriger
            while zeitraum.bis >= aeltestes {
                if brauchtUStVA(zeitraum), sichtbar.contains(where: zeitraum.beruehrt) {
                    zeitraeume.append(zeitraum)
                }
                zeitraum = zeitraum.vorheriger
            }
            return zeitraeume
        }

        let ustva = Zeitraum.naechsteUStVA(
            rhythmus: profil.rhythmus,
            dauerfristverlaengerung: profil.dauerfristverlaengerung,
            today: today
        )
        return (offene(ab: ustva) + offene(ab: Zeitraum.naechsteEUeR(today: today)))
            .filter { exportiert[$0] == nil }
            .map { zeitraum in
                // The Dauerfristverlängerung only moves a UStVA deadline; the
                // EÜR ignores the flag by itself.
                let faellig = zeitraum.frist(dauerfristverlaengerung: profil.dauerfristverlaengerung)
                return Frist(zeitraum: zeitraum, faellig: faellig, tage: today.tage(bis: faellig))
            }
            .sorted { $0.faellig < $1.faellig }
    }

    /// The years the start page can show, newest first: every year money moved
    /// in, and the running one even when nothing has happened in it yet.
    public static func jahre(_ buchungen: [Buchung], today: LocalDate = .today()) -> [Int] {
        var jahre = Set(
            buchungen
                .filter { $0.art != .ignoriert }
                .flatMap { $0.zahlungen.map(\.datum.jahr) }
        )
        jahre.insert(today.jahr)
        return jahre.sorted(by: >)
    }

    /// Income, expenses and balance of one year, counted the way the tax is:
    /// by the day the money moved, not by the document date. A refund carries a
    /// negative amount and lowers its side.
    public static func jahreswerte(_ buchungen: [Buchung], jahr: Int) -> Totals {
        var einnahmen = Cent.null
        var ausgaben = Cent.null
        for buchung in buchungen where buchung.art != .ignoriert {
            let summe = buchung.zahlungen
                .filter { $0.datum.jahr == jahr }
                .reduce(Cent.null) { $0 + $1.betrag }
            if buchung.richtung == .einnahme {
                einnahmen = einnahmen + summe
            } else {
                ausgaben = ausgaben + summe
            }
        }
        return Totals(einnahmen: einnahmen, ausgaben: ausgaben)
    }
}
