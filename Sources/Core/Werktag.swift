import Foundation

/// §108 Abs. 3 AO: a deadline that falls on a Saturday, Sunday or public
/// holiday ends on the next working day. The holidays are the nationwide
/// ones; the regional ones (Fronleichnam and the like) are left out on
/// purpose, so a deadline is shown at most one day early, never late.
public enum Werktag {
    /// The first working day on or after the date.
    public static func amOderNach(_ datum: LocalDate) -> LocalDate {
        var tag = datum
        while istWochenende(tag) || istFeiertag(tag) {
            tag = tag.plus(tage: 1)
        }
        return tag
    }

    static func istWochenende(_ datum: LocalDate) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: DateComponents(year: datum.jahr, month: datum.monat, day: datum.tag))
        else { return false }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// The nationwide public holidays: the fixed ones and the four that move
    /// with Easter.
    static func istFeiertag(_ datum: LocalDate) -> Bool {
        let fest = [(1, 1), (5, 1), (10, 3), (12, 25), (12, 26)]
        if fest.contains(where: { $0.0 == datum.monat && $0.1 == datum.tag }) {
            return true
        }
        let ostern = ostersonntag(datum.jahr)
        return [-2, 1, 39, 50].contains { ostern.plus(tage: $0) == datum }
    }

    /// Easter Sunday by the anonymous Gregorian algorithm.
    static func ostersonntag(_ jahr: Int) -> LocalDate {
        let a = jahr % 19
        let b = jahr / 100
        let c = jahr % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let monat = (h + l - 7 * m + 114) / 31
        let tag = (h + l - 7 * m + 114) % 31 + 1
        return LocalDate(jahr: jahr, monat: monat, tag: tag)
    }
}

extension LocalDate {
    /// The day a number of days later, or earlier for a negative count.
    func plus(tage: Int) -> LocalDate {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: DateComponents(year: jahr, month: monat, day: tag)),
              let moved = calendar.date(byAdding: .day, value: tage, to: date)
        else { return self }
        return LocalDate(moved)
    }
}
