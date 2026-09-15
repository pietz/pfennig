/// The direction filter of the toolbar.
public enum BookingFilter: String, CaseIterable, Hashable, Sendable, Identifiable {
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

/// The review filters shown in the bookings toolbar.
public enum ReviewFilter: String, CaseIterable, Hashable, Sendable, Identifiable {
    case alle
    case zuPruefen
    case ohneBeleg

    public var id: String {
        rawValue
    }

    public var menuTitle: String {
        switch self {
        case .alle: "Alle Status"
        case .zuPruefen: "Zu prüfen"
        case .ohneBeleg: "Ohne Beleg"
        }
    }

    public func includes(_ buchung: Buchung) -> Bool {
        switch self {
        case .alle: true
        // This deliberately uses the timestamp, so an unreviewed missing
        // receipt appears in both review queues.
        case .zuPruefen: buchung.geprueftAm == nil
        case .ohneBeleg: buchung.reviewStatus == .belegFehlt
        }
    }
}

/// What the footer under the table shows for the rows it can see.
public struct Totals: Hashable, Sendable {
    public var einnahmen: Cent
    public var ausgaben: Cent

    public var saldo: Cent {
        einnahmen - ausgaben
    }
}

/// What the table shows and what it adds up. Both are plain functions over the
/// bookings the repository delivered, so the window keeps no state of its own.
public enum Overview {
    /// Bookings marked `ignoriert` never appear. The filter picks a direction,
    /// the search text matches title, counterparty, notes and the gross amount.
    public static func visible(
        _ buchungen: [Buchung],
        filter: BookingFilter,
        reviewFilter: ReviewFilter = .alle,
        search: String
    ) -> [Buchung] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        return buchungen.filter { buchung in
            guard buchung.art != .ignoriert else { return false }
            guard reviewFilter.includes(buchung) else { return false }
            let matches = switch filter {
            case .alle: true
            case .einnahmen: buchung.richtung == .einnahme
            case .ausgaben: buchung.richtung == .ausgabe
            }
            guard matches else { return false }
            guard term.isEmpty == false else { return true }
            let fields = [
                buchung.titel,
                buchung.gegenparteiName ?? "",
                buchung.notizen ?? "",
                buchung.brutto.formatted
            ]
            return fields.contains { $0.lowercased().contains(term) }
        }
    }

    public static func totals(_ buchungen: [Buchung]) -> Totals {
        Totals(
            einnahmen: buchungen.filter { $0.richtung == .einnahme }.reduce(Cent.null) { $0 + $1.brutto },
            ausgaben: buchungen.filter { $0.richtung == .ausgabe }.reduce(Cent.null) { $0 + $1.brutto }
        )
    }
}
