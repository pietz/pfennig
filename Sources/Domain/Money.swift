import Foundation

public enum MoneyError: Error, Equatable, Sendable {
    case malformedCurrencyCode(String)
    case malformedDecimalString(String)
    case notRepresentableInMinorUnits(String)
    case currencyMismatch(CurrencyCode, CurrencyCode)
}

/// An exact monetary amount: signed minor units plus an explicit currency.
/// All bookkeeping arithmetic goes through this type; never `Double`.
public struct Money: Codable, Hashable, Sendable {
    public let minorUnits: Int64
    public let currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    /// Exact major-unit value, derived from the currency exponent.
    public var decimal: Decimal {
        Decimal(minorUnits) / currency.minorUnitsPerMajor
    }

    /// Canonical, locale-independent decimal string, e.g. `"-1234.56"`.
    public var decimalString: String {
        let exponent = currency.exponent
        let negative = minorUnits < 0
        var digits = String(minorUnits.magnitude)
        guard exponent > 0 else { return (negative ? "-" : "") + digits }
        if digits.count <= exponent {
            digits = String(repeating: "0", count: exponent - digits.count + 1) + digits
        }
        let split = digits.index(digits.endIndex, offsetBy: -exponent)
        return (negative ? "-" : "") + digits[..<split] + "." + digits[split...]
    }

    // MARK: - Parsing

    /// Parses German (`"1.234,56"`), English (`"1,234.56"`) and plain
    /// (`"71.39"`, `"71"`) decimal strings. Rounds half-up to the currency
    /// exponent. Never guesses a currency.
    public static func fromDecimalString(_ string: String, currency: CurrencyCode) throws -> Money {
        guard currency.isWellFormed else { throw MoneyError.malformedCurrencyCode(currency.rawValue) }
        let decimal = try parseDecimal(string, fractionDigits: currency.exponent)
        return try Money(rounding: decimal, currency: currency)
    }

    /// Rounds an arbitrary decimal half-up to the currency exponent.
    public init(rounding decimal: Decimal, currency: CurrencyCode) throws {
        guard currency.isWellFormed else { throw MoneyError.malformedCurrencyCode(currency.rawValue) }
        let scaled = decimal * currency.minorUnitsPerMajor
        let rounded = Money.roundHalfUp(scaled)
        guard let units = Int64(exactly: NSDecimalNumber(decimal: rounded).int64Value),
              Decimal(units) == rounded
        else {
            throw MoneyError.notRepresentableInMinorUnits("\(decimal)")
        }
        self.init(minorUnits: units, currency: currency)
    }

    /// Half-up rounding to an integer: 0.5 -> 1, -0.5 -> -1 (away from zero).
    public static func roundHalfUp(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }

    /// Rounds a decimal half-up to a given number of fraction digits.
    public static func roundHalfUp(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Locale-independent decimal parsing that accepts both separator
    /// conventions. `fractionDigits` resolves the ambiguity of a lone
    /// separator with three trailing digits ("1.234").
    public static func parseDecimal(_ string: String, fractionDigits: Int = 2) throws -> Decimal {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for noise in ["\u{00A0}", "\u{202F}", "'", " "] {
            text = text.replacingOccurrences(of: noise, with: "")
        }

        var negative = false
        if text.hasPrefix("-") {
            negative = true
            text.removeFirst()
        } else if text.hasPrefix("+") {
            text.removeFirst()
        } else if text.hasSuffix("-") { // trailing sign, seen on some statements
            negative = true
            text.removeLast()
        }

        guard text.contains(where: { $0.isASCII && $0.isNumber }),
              text.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." || $0 == "," })
        else {
            throw MoneyError.malformedDecimalString(string)
        }

        var integerPart = text
        var fractionPart = ""
        if let separator = decimalSeparator(in: text, fractionDigits: fractionDigits),
           let index = text.lastIndex(of: separator)
        {
            integerPart = String(text[..<index])
            fractionPart = String(text[text.index(after: index)...])
        }
        guard fractionPart.allSatisfy(\.isNumber) else {
            throw MoneyError.malformedDecimalString(string)
        }

        // Remaining separators in the integer part must form valid groups.
        let groups = integerPart.split(whereSeparator: { $0 == "." || $0 == "," })
        if integerPart.contains(where: { $0 == "." || $0 == "," }) {
            guard groups.count > 1, (1 ... 3).contains(groups[0].count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 })
            else {
                throw MoneyError.malformedDecimalString(string)
            }
        }
        let digits = groups.joined()
        let canonical = (digits.isEmpty ? "0" : digits) + (fractionPart.isEmpty ? "" : "." + fractionPart)
        guard let value = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MoneyError.malformedDecimalString(string)
        }
        return negative ? -value : value
    }

    /// Decides which of `.` / `,` acts as the decimal separator, or nil when
    /// the string is an integer with grouping separators only.
    private static func decimalSeparator(in text: String, fractionDigits: Int) -> Character? {
        let lastDot = text.lastIndex(of: ".")
        let lastComma = text.lastIndex(of: ",")
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            return dot > comma ? "." : ","
        case let (dot?, nil):
            return isGrouping(text, lastIndex: dot, fractionDigits: fractionDigits) ? nil : "."
        case let (nil, comma?):
            return isGrouping(text, lastIndex: comma, fractionDigits: fractionDigits) ? nil : ","
        case (nil, nil):
            return nil
        }
    }

    private static func isGrouping(_ text: String, lastIndex: String.Index, fractionDigits: Int) -> Bool {
        let separator = text[lastIndex]
        if text.filter({ $0 == separator }).count > 1 {
            return true
        } // "1.234.567"
        let head = String(text[text.startIndex ..< lastIndex])
        let tail = String(text[text.index(after: lastIndex)...])
        if tail.count == fractionDigits {
            return false
        } // "1.234" in a 3-decimal currency
        // "1,234" / "1.234": thousands. "0.123" / "12.3456": decimals.
        return tail.count == 3 && (1 ... 3).contains(head.count) && head.first != "0"
    }

    // MARK: - Arithmetic

    public static func + (lhs: Money, rhs: Money) throws -> Money {
        try lhs.requireSameCurrency(rhs)
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) throws -> Money {
        try lhs.requireSameCurrency(rhs)
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }

    public static prefix func - (value: Money) -> Money {
        Money(minorUnits: -value.minorUnits, currency: value.currency)
    }

    public var absolute: Money {
        Money(minorUnits: abs(minorUnits), currency: currency)
    }

    public var isZero: Bool {
        minorUnits == 0
    }

    private func requireSameCurrency(_ other: Money) throws {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(currency, other.currency)
        }
    }

    // MARK: - VAT helpers

    /// VAT on this amount treated as a net base, e.g. `rate: 19`.
    /// Rounded half-up to the currency exponent (§ UStAE 16.x practice).
    public func vat(ratePercent rate: Decimal) throws -> Money {
        try Money(rounding: decimal * rate / 100, currency: currency)
    }

    /// This amount plus VAT at `rate`.
    public func addingVAT(ratePercent rate: Decimal) throws -> Money {
        try self + vat(ratePercent: rate)
    }

    /// Net base contained in this amount treated as gross.
    public func netFromGross(ratePercent rate: Decimal) throws -> Money {
        try Money(rounding: decimal * 100 / (100 + rate), currency: currency)
    }

    /// VAT contained in this amount treated as gross (gross - net, so that
    /// net + vat == gross holds exactly).
    public func vatFromGross(ratePercent rate: Decimal) throws -> Money {
        try self - netFromGross(ratePercent: rate)
    }

    // MARK: - Formatting

    /// Locale-aware display string, e.g. "71,39 €" in German.
    public func formatted(locale: Locale = .current) -> String {
        decimal.formatted(
            .currency(code: currency.rawValue)
                .precision(.fractionLength(currency.exponent))
                .locale(locale)
        )
    }
}

extension Money: Comparable {
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "Cannot compare \(lhs.currency) with \(rhs.currency)")
        return lhs.minorUnits < rhs.minorUnits
    }
}

extension Money: CustomStringConvertible {
    public var description: String {
        "\(decimalString) \(currency)"
    }
}
