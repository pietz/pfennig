/// The direction filter of the toolbar.
public enum Buchungsfilter: String, CaseIterable, Hashable, Sendable, Identifiable {
    case alle
    case einnahmen
    case ausgaben

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .alle: "Alle"
        case .einnahmen: "Einnahmen"
        case .ausgaben: "Ausgaben"
        }
    }
}

/// What the footer under the table shows for the rows it can see.
public struct Summen: Hashable, Sendable {
    public var einnahmen: Cent
    public var ausgaben: Cent

    public var saldo: Cent {
        einnahmen - ausgaben
    }
}

/// What the table shows and what it adds up. Both are plain functions over the
/// bookings the repository delivered, so the window keeps no state of its own.
public enum Uebersicht {
    /// Bookings marked `ignoriert` never appear. The filter picks a direction,
    /// the search text matches title, counterparty, notes and the gross amount.
    public static func sichtbar(_ buchungen: [Buchung], filter: Buchungsfilter, suche: String) -> [Buchung] {
        let begriff = suche.trimmingCharacters(in: .whitespaces).lowercased()
        return buchungen.filter { buchung in
            guard buchung.art != .ignoriert else { return false }
            let passt = switch filter {
            case .alle: true
            case .einnahmen: buchung.richtung == .einnahme
            case .ausgaben: buchung.richtung == .ausgabe
            }
            guard passt else { return false }
            guard begriff.isEmpty == false else { return true }
            let felder = [
                buchung.titel,
                buchung.gegenparteiName ?? "",
                buchung.notizen ?? "",
                buchung.brutto.formatiert
            ]
            return felder.contains { $0.lowercased().contains(begriff) }
        }
    }

    public static func summen(_ buchungen: [Buchung]) -> Summen {
        Summen(
            einnahmen: buchungen.filter { $0.richtung == .einnahme }.reduce(Cent.null) { $0 + $1.brutto },
            ausgaben: buchungen.filter { $0.richtung == .ausgabe }.reduce(Cent.null) { $0 + $1.brutto }
        )
    }
}
