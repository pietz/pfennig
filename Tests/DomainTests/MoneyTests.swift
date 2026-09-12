@testable import Domain
import Foundation
import Testing

@Suite("Money")
struct MoneyTests {
    @Test("Plain decimal strings")
    func plainStrings() throws {
        #expect(try Money.fromDecimalString("71.39", currency: .eur).minorUnits == 7139)
        #expect(try Money.fromDecimalString("0", currency: .eur).minorUnits == 0)
        #expect(try Money.fromDecimalString("5", currency: .eur).minorUnits == 500)
        #expect(try Money.fromDecimalString("-12.05", currency: .eur).minorUnits == -1205)
        #expect(try Money.fromDecimalString("+12.05", currency: .eur).minorUnits == 1205)
        #expect(try Money.fromDecimalString("12,05-", currency: .eur).minorUnits == -1205)
    }

    @Test("German and English grouping")
    func groupedStrings() throws {
        #expect(try Money.fromDecimalString("1.234,56", currency: .eur).minorUnits == 123_456)
        #expect(try Money.fromDecimalString("1,234.56", currency: .eur).minorUnits == 123_456)
        #expect(try Money.fromDecimalString("1.234.567,89", currency: .eur).minorUnits == 123_456_789)
        #expect(try Money.fromDecimalString("1,234,567.89", currency: .eur).minorUnits == 123_456_789)
        #expect(try Money.fromDecimalString("1.234", currency: .eur).minorUnits == 123_400)
        #expect(try Money.fromDecimalString("1,234", currency: .eur).minorUnits == 123_400)
        #expect(try Money.fromDecimalString("0.123", currency: .eur).minorUnits == 12)
        #expect(try Money.fromDecimalString("1 234,56", currency: .eur).minorUnits == 123_456)
    }

    @Test("Currency exponent")
    func exponents() throws {
        #expect(try Money.fromDecimalString("100", currency: .jpy).minorUnits == 100)
        #expect(try Money.fromDecimalString("100.4", currency: .jpy).minorUnits == 100)
        #expect(try Money.fromDecimalString("100.5", currency: .jpy).minorUnits == 101)
        #expect(try Money.fromDecimalString("1.234", currency: CurrencyCode("KWD")).minorUnits == 1234)
    }

    @Test("Half-up rounding")
    func rounding() throws {
        #expect(try Money.fromDecimalString("0.005", currency: .eur).minorUnits == 1)
        #expect(try Money.fromDecimalString("0.004", currency: .eur).minorUnits == 0)
        #expect(try Money.fromDecimalString("2.6750", currency: .eur).minorUnits == 268)
        #expect(try Money(rounding: #require(Decimal(string: "2.675")), currency: .eur).minorUnits == 268)
        #expect(try Money.fromDecimalString("-0.005", currency: .eur).minorUnits == -1)
    }

    @Test("Malformed input throws")
    func malformed() {
        for input in ["", "abc", "12.34.56.78", "1,2,3", "-", "12€", "1.2.3,4,5"] {
            #expect(throws: MoneyError.self) {
                try Money.fromDecimalString(input, currency: .eur)
            }
        }
        #expect(throws: MoneyError.self) {
            try Money.fromDecimalString("1.00", currency: CurrencyCode("EURO"))
        }
    }

    @Test("Round trip through decimal string")
    func roundTrip() throws {
        for units in [Int64(0), 1, -1, 7139, -123_456_789, 999_999_999_999] {
            let money = Money(minorUnits: units, currency: .eur)
            let parsed = try Money.fromDecimalString(money.decimalString, currency: .eur)
            #expect(parsed == money)
        }
        let yen = Money(minorUnits: 12345, currency: .jpy)
        #expect(yen.decimalString == "12345")
        #expect(try Money.fromDecimalString(yen.decimalString, currency: .jpy) == yen)
    }

    @Test("Codable round trip")
    func codable() throws {
        let money = Money(minorUnits: -7139, currency: .eur)
        let data = try JSONEncoder().encode(money)
        #expect(try JSONDecoder().decode(Money.self, from: data) == money)
    }

    @Test("VAT arithmetic")
    func vat() throws {
        let net = try Money.fromDecimalString("71.39", currency: .eur)
        #expect(try net.vat(ratePercent: 19).minorUnits == 1356) // spec 5.4
        #expect(try net.addingVAT(ratePercent: 19).decimalString == "84.95")

        let gross = try Money.fromDecimalString("119.00", currency: .eur)
        #expect(try gross.netFromGross(ratePercent: 19).decimalString == "100.00")
        #expect(try gross.vatFromGross(ratePercent: 19).decimalString == "19.00")

        let odd = try Money.fromDecimalString("49.95", currency: .eur)
        let oddNet = try odd.netFromGross(ratePercent: 19)
        let oddVat = try odd.vatFromGross(ratePercent: 19)
        #expect(oddNet.minorUnits == 4197)
        #expect(oddVat.minorUnits == 798)
        #expect(try (oddNet + oddVat) == odd)
    }

    @Test("Arithmetic guards currency")
    func currencyMismatch() throws {
        let eur = Money(minorUnits: 100, currency: .eur)
        let usd = Money(minorUnits: 100, currency: .usd)
        #expect(throws: MoneyError.self) { try eur + usd }
        #expect(try (eur + eur).minorUnits == 200)
        #expect((-eur).minorUnits == -100)
    }

    @Test("Decimal value")
    func decimalValue() {
        #expect(Money(minorUnits: 7139, currency: .eur).decimal == Decimal(string: "71.39")!)
        #expect(Money(minorUnits: 7139, currency: .jpy).decimal == Decimal(7139))
    }
}
