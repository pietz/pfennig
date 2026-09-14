import Domain
import Foundation

/// Normalization of header cells. Everything that compares a column name —
/// the catalog, the heuristic, the fingerprint — goes through this, so
/// quoting, casing, a stray byte-order mark and doubled spaces never decide
/// whether a format is recognized.
public enum HeaderNormalization {
    /// German umlauts are transliterated the way the banks themselves spell
    /// them out (`Empfänger` and `Empfaenger` must compare equal), before any
    /// remaining diacritics are folded away.
    public static func normalize(_ cell: String) -> String {
        var text = cell.replacingOccurrences(of: "\u{FEFF}", with: "")
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.lowercased()
        for (umlaut, replacement) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            text = text.replacingOccurrences(of: umlaut, with: replacement)
        }
        text = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let parts = text.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// Normalized cells with every character that is not a letter or digit
    /// removed, for matching `Betrag (€)` against `betrag eur` and friends.
    public static func compact(_ cell: String) -> String {
        normalize(cell).filter { $0.isLetter || $0.isNumber }
    }
}

/// Stable hash of a header row, so a mapping (from the catalog, the model, or
/// the user) can be cached per header shape.
public enum HeaderFingerprint {
    public static func make(_ columns: [String]) -> String {
        let normalized = columns.map(HeaderNormalization.normalize).joined(separator: "\u{1F}")
        return SHA256Hex.of(normalized)
    }
}

/// Numbers, dates and IBANs as they appear in statement exports.
public enum StatementValueParser {
    // MARK: - Amounts

    public enum AmountError: Error, Equatable, Sendable {
        case empty
        case malformed(String)
    }

    /// Parses a statement amount into minor units.
    ///
    /// Accepts German (`1.234,56`), English (`1,234.56`) and plain (`-1234.56`)
    /// notation, a leading or trailing sign, a currency symbol or code, and
    /// accountants' parentheses for negatives.
    public static func amountMinor(_ raw: String, currency: CurrencyCode) throws(AmountError) -> Int64 {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AmountError.empty }

        var negative = false
        if text.hasPrefix("("), text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }
        text = stripCurrencyMarks(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AmountError.empty }

        do {
            let decimal = try Money.parseDecimal(text, fractionDigits: currency.exponent)
            let money = try Money(rounding: negative ? -decimal : decimal, currency: currency)
            return money.minorUnits
        } catch {
            throw AmountError.malformed(raw)
        }
    }

    /// Removes currency symbols and ISO codes but keeps digits, separators
    /// and the sign, so `Money` sees only the number.
    static func stripCurrencyMarks(from text: String) -> String {
        var result = text
        for symbol in ["€", "$", "£", "¥", "CHF", "chf", "EUR", "eur", "USD", "usd", "GBP", "gbp"] {
            result = result.replacingOccurrences(of: symbol, with: "")
        }
        for space in ["\u{00A0}", "\u{202F}", "\u{2007}"] {
            result = result.replacingOccurrences(of: space, with: "")
        }
        return result
    }

    // MARK: - Dates

    public enum DateError: Error, Equatable, Sendable {
        case empty
        case malformed(String)
    }

    /// Parses a date in the layout the mapping declares. `.auto` sniffs the
    /// value: ISO first, then the German dotted forms, then slashes — where
    /// `dd/MM` and `MM/dd` are only distinguishable when one part exceeds 12,
    /// so `.auto` prefers the German reading and a real format declares it.
    public static func date(_ raw: String, format: StatementDateFormat) throws(DateError) -> LocalDate {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DateError.empty }
        // A trailing time part (Stripe's "2026-08-05 10:14:22") is not a date.
        let head = String(text.prefix { $0 != " " && $0 != "T" })

        let parsed: LocalDate? = switch format {
        case .iso: iso(head)
        case .dayMonthYear: dotted(head, shortYear: false)
        case .dayMonthShortYear: dotted(head, shortYear: true)
        case .dayMonthYearSlash: slashed(head, dayFirst: true)
        case .monthDayYearSlash: slashed(head, dayFirst: false)
        case .auto: iso(head) ?? dotted(head, shortYear: nil) ?? slashed(head, dayFirst: true)
        }
        guard let parsed else { throw DateError.malformed(raw) }
        return parsed
    }

    static func iso(_ text: String) -> LocalDate? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4 else { return nil }
        return make(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]))
    }

    /// `shortYear == nil` accepts both `dd.MM.yyyy` and `dd.MM.yy`.
    static func dotted(_ text: String, shortYear: Bool?) -> LocalDate? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        if let shortYear, shortYear != (parts[2].count == 2) {
            return nil
        }
        return make(year: expandYear(parts[2]), month: Int(parts[1]), day: Int(parts[0]))
    }

    static func slashed(_ text: String, dayFirst: Bool) -> LocalDate? {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let first = Int(parts[0])
        let second = Int(parts[1])
        return make(
            year: expandYear(parts[2]),
            month: dayFirst ? second : first,
            day: dayFirst ? first : second
        )
    }

    /// Two-digit years in a statement are always this century: bookkeeping
    /// exports do not reach back to 1926.
    static func expandYear(_ digits: Substring) -> Int? {
        guard let value = Int(digits) else { return nil }
        if digits.count == 2 {
            return 2000 + value
        }
        return digits.count == 4 ? value : nil
    }

    static func make(year: Int?, month: Int?, day: Int?) -> LocalDate? {
        guard let year, let month, let day else { return nil }
        let candidate = LocalDate(year: year, month: month, day: day)
        return candidate.isValid ? candidate : nil
    }

    // MARK: - IBAN

    /// True for a string shaped like an IBAN. Not a checksum validation: the
    /// point is to recognize an account identifier in a preamble cell.
    public static func looksLikeIBAN(_ raw: String) -> Bool {
        let text = normalizedIBAN(raw)
        guard (15 ... 34).contains(text.count) else { return false }
        let characters = Array(text)
        guard characters[0].isLetter, characters[1].isLetter,
              characters[2].isNumber, characters[3].isNumber
        else { return false }
        return characters.allSatisfy { ($0.isLetter && $0.isASCII && $0.isUppercase) || $0.isNumber }
    }

    /// Uppercase, without spaces — the form account keys are compared in.
    public static func normalizedIBAN(_ raw: String) -> String {
        raw.uppercased().filter { !$0.isWhitespace }
    }

    // MARK: - Labelled free text

    /// Splits a text that packs several labelled segments into one field,
    /// comdirect style: `Auftraggeber: X Buchungstext: Y Karte Nr. 1234`.
    /// Returns the segment behind each label found, keyed by the label.
    public static func labelledSegments(_ text: String, vocabulary: [String]) -> [String: String] {
        guard !vocabulary.isEmpty else { return [:] }
        var hits: [(range: Range<String.Index>, label: String)] = []
        for label in vocabulary {
            var searchFrom = text.startIndex
            while let range = text.range(of: label, options: [.caseInsensitive], range: searchFrom ..< text.endIndex) {
                hits.append((range, label))
                searchFrom = range.upperBound
            }
        }
        guard !hits.isEmpty else { return [:] }
        hits.sort { $0.range.lowerBound < $1.range.lowerBound }

        var segments: [String: String] = [:]
        for (index, hit) in hits.enumerated() {
            let end = index + 1 < hits.count ? hits[index + 1].range.lowerBound : text.endIndex
            let value = text[hit.range.upperBound ..< end]
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\t\n\r"))
            if segments[hit.label] == nil, !value.isEmpty {
                segments[hit.label] = value
            }
        }
        return segments
    }
}
