import Tax

/// Renders a prepared `UStVAReturn` as plain text for the clipboard, so the
/// user can type the values into the Mein-ELSTER form without the XML upload.
/// This is the path that always works; the XML export stays experimental.
public enum UStVAValueList {
    /// One line per Kennzahl plus the Zahllast, in German notation:
    ///
    /// ```
    /// UStVA Q3 2026
    /// Entwurf, 2 offene Fälle
    /// Kz 81: 12.345 €
    /// Kz 66: 1.234,56 €
    /// Kz 83: 1.111,11 €
    /// Zahllast: 1.111,11 €
    /// ```
    public static func text(for result: UStVAReturn) -> String {
        var lines = ["UStVA \(UStVAPeriodText.title(result.period))"]
        if result.isDraft {
            let count = result.exceptions.count
            lines.append(count == 1 ? "Entwurf, 1 offener Fall" : "Entwurf, \(count) offene Fälle")
        }
        for line in result.lines where line.kennzahl != 83 {
            lines.append("Kz \(line.kennzahl): \(amount(of: line)) €")
        }
        lines.append("Kz 83: \(UStVAAmounts.germanDecimal(result.payableMinor)) €")
        let label = result.payableMinor < 0 ? "Erstattung" : "Zahllast"
        lines.append("\(label): \(UStVAAmounts.germanDecimal(abs(result.payableMinor))) €")
        return lines.joined(separator: "\n")
    }

    /// Base Kennzahlen show whole euros with the cents cut off, as on the form.
    private static func amount(of line: UStVAReturn.Line) -> String {
        line.isBase
            ? UStVAAmounts.germanInteger(UStVAAmounts.wholeEuros(line.amountMinor))
            : UStVAAmounts.germanDecimal(line.amountMinor)
    }
}
