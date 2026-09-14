import Foundation
import Tax

/// Number formatting shared by the UStVA XML export and the copyable value
/// list. All amounts arrive as EUR minor units (cents).
///
/// Form rule: Bemessungsgrundlagen (base Kennzahlen such as Kz 81, 86, 46) are
/// entered in whole euros with the cents cut off, not rounded - that rule lives
/// in `UStVA_2026.wholeEuros`, so the calculated Zahllast and the exported
/// values cannot drift apart. Tax Kennzahlen (Kz 66, 67, 83) carry two decimals.
enum UStVAAmounts {
    /// Machine format for the XML payload, e.g. `1234.56`, `-19.00`.
    static func decimalString(_ minor: Int64) -> String {
        let sign = minor < 0 ? "-" : ""
        let absolute = minor.magnitude
        return "\(sign)\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }

    /// German grouped integer, e.g. `12.345`.
    static func germanInteger(_ value: Int64) -> String {
        let sign = value < 0 ? "-" : ""
        var digits = String(value.magnitude)
        var grouped = ""
        while digits.count > 3 {
            let cut = digits.index(digits.endIndex, offsetBy: -3)
            grouped = "." + digits[cut...] + grouped
            digits = String(digits[..<cut])
        }
        return sign + digits + grouped
    }

    /// German amount with two decimals, e.g. `1.234,56`.
    static func germanDecimal(_ minor: Int64) -> String {
        let sign = minor < 0 ? "-" : ""
        let absolute = minor.magnitude
        let euros = germanInteger(Int64(absolute / 100))
        return "\(sign)\(euros),\(String(format: "%02d", absolute % 100))"
    }
}
