import Foundation

/// ISO-4217 currency code with the exponent (number of minor-unit digits)
/// that governs storage and rounding of ``Money``.
public struct CurrencyCode: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }

    /// True for three uppercase ASCII letters.
    public var isWellFormed: Bool {
        rawValue.count == 3 && rawValue.allSatisfy { $0.isASCII && $0.isUppercase && $0.isLetter }
    }

    /// Digits after the decimal separator. Unknown currencies default to 2.
    public var exponent: Int {
        Self.exponents[rawValue] ?? 2
    }

    /// 10^exponent, as the divisor between major and minor units.
    public var minorUnitsPerMajor: Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: 1)
    }

    public static let eur = CurrencyCode("EUR")
    public static let usd = CurrencyCode("USD")
    public static let gbp = CurrencyCode("GBP")
    public static let chf = CurrencyCode("CHF")
    public static let jpy = CurrencyCode("JPY")

    /// Only currencies whose exponent differs from 2, plus the common ones we
    /// want to state explicitly. Everything else falls back to 2.
    static let exponents: [String: Int] = [
        "EUR": 2, "USD": 2, "GBP": 2, "CHF": 2, "SEK": 2, "NOK": 2, "DKK": 2,
        "PLN": 2, "CZK": 2, "CAD": 2, "AUD": 2, "NZD": 2, "SGD": 2, "HKD": 2,
        "BGN": 2, "RON": 2, "HUF": 2, "TRY": 2, "ZAR": 2, "INR": 2, "BRL": 2,
        "MXN": 2, "ILS": 2, "CNY": 2, "AED": 2,
        "JPY": 0, "KRW": 0, "ISK": 0, "CLP": 0, "VND": 0, "XAF": 0, "XOF": 0,
        "BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3
    ]
}
