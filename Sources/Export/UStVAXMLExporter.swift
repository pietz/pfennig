import Foundation
import Tax

/// Writes a prepared `UStVAReturn` as an XML file for the manual form upload
/// in Mein ELSTER (Formular Umsatzsteuervoranmeldung, "Datenimport").
///
/// Pfennig does not transmit. The file is uploaded by the user inside their own
/// Mein-ELSTER session, which fills the form for review before sending.
///
/// **How far the format is verified** (docs/research-ustva-xml.md):
///
/// - Verified from the elster.de help page: only the content below
///   `/Elster/DatenTeil/Nutzdatenblock/Nutzdaten/Anmeldungssteuern` is
///   uploaded, the envelope is
///   `<Anmeldungssteuern xmlns="http://finkonsens.de/elster/elsteranmeldung/ustva/v2023" version="2023">`,
///   the character set is ISO-8859-15, and the value of Kz 83 is taken over as
///   a user-supplied value instead of being recalculated.
/// - Reconstructed from a forum example, not from an official schema: the inner
///   `Steuerfall/Umsatzsteuervoranmeldung` block with `Jahr`, `Zeitraum`,
///   `Steuernummer` and `KzNN` elements, their spelling and their order.
/// - Unverified: the `Zeitraum` codes 41-44 for quarters, whether the schema
///   version for 2026 is still `v2023`, and the decimal notation of the tax
///   Kennzahlen. We write `1234.56` (dot, two decimals) for tax lines and plain
///   truncated euros for base lines, and name the namespace after the form
///   year, which is what every public example does.
/// - The `<Unternehmer>` block is omitted; a forum report says the web upload
///   does not require it, and the user's Mein-ELSTER session supplies the
///   identity anyway.
///
/// Treat the export as experimental until a real test upload (without sending)
/// has filled the form correctly.
public enum UStVAXMLExporter {
    /// ISO-8859-15, the character set named by the elster.de help page, and
    /// the name it is declared under in the XML prologue.
    public static let encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)
        )
    )
    private static let encodingName = "ISO-8859-15"

    /// The produced file plus everything the user should know before uploading.
    public struct Export: Sendable, Equatable {
        /// File content in the requested encoding.
        public let data: Data
        /// Same content as text, for previews and tests.
        public let xml: String
        /// Suggested file name, including the `-entwurf` marker for drafts.
        public let filename: String
        /// Non-blocking notes, e.g. an unconverted Steuernummer or an
        /// undocumented schema version. Shown next to the export action.
        public let warnings: [String]
    }

    /// The only schema version shown on the elster.de help page. The
    /// namespace follows the return's form year, which is the convention every
    /// public example uses; any other year is flagged as unproven.
    public static let documentedSchemaYear = 2023

    /// Builds the upload file.
    public static func export(_ result: UStVAReturn) -> Export {
        var warnings: [String] = []
        let schemaYear = result.formYear
        if schemaYear != documentedSchemaYear {
            warnings.append(
                "Die Schemaversion v\(schemaYear) ist nicht öffentlich dokumentiert; "
                    + "belegt ist nur v\(documentedSchemaYear). Der Upload muss geprüft werden."
            )
        }

        var body: [String] = []
        body.append(element("Jahr", String(result.period.year)))
        body.append(element("Zeitraum", UStVAPeriodText.zeitraumCode(result.period)))
        if let taxNumber = elsterTaxNumber(result.taxNumber, warnings: &warnings) {
            body.append(element("Steuernummer", taxNumber))
        }
        for line in result.lines where line.kennzahl != 83 {
            body.append(element("Kz\(line.kennzahl)", value(of: line)))
            if !line.isVerified {
                warnings.append("Kz \(line.kennzahl) ist noch nicht gegen das Vordruckmuster geprüft.")
            }
        }
        // Kz 83 is always written: the help page states the uploaded value is
        // taken over as the user's own figure instead of being recalculated.
        body.append(element("Kz83", UStVAAmounts.decimalString(result.payableMinor)))

        let namespace = "http://finkonsens.de/elster/elsteranmeldung/ustva/v\(schemaYear)"
        var xml = "<?xml version=\"1.0\" encoding=\"\(encodingName)\" standalone=\"no\"?>\n"
        xml += "<Anmeldungssteuern xmlns=\"\(namespace)\" version=\"\(schemaYear)\">\n"
        xml += "  <Steuerfall>\n"
        xml += "    <Umsatzsteuervoranmeldung>\n"
        xml += body.map { "      \($0)\n" }.joined()
        xml += "    </Umsatzsteuervoranmeldung>\n"
        xml += "  </Steuerfall>\n"
        xml += "</Anmeldungssteuern>\n"

        let data: Data
        if let encoded = xml.data(using: encoding) {
            data = encoded
        } else {
            warnings.append("Nicht alle Zeichen lassen sich in \(encodingName) abbilden; sie wurden ersetzt.")
            data = xml.data(using: encoding, allowLossyConversion: true) ?? Data(xml.utf8)
        }

        return Export(data: data, xml: xml, filename: suggestedFilename(for: result), warnings: warnings)
    }

    /// `UStVA-2026-Q3.xml`, with `-entwurf` while exceptions are open.
    public static func suggestedFilename(for result: UStVAReturn) -> String {
        let token = UStVAPeriodText.fileToken(result.period)
        let draft = result.isDraft ? "-entwurf" : ""
        return "UStVA-\(result.period.year)-\(token)\(draft).xml"
    }

    // MARK: - Building blocks

    /// Base Kennzahlen carry whole euros with the cents cut off; tax
    /// Kennzahlen carry two decimals with a dot.
    private static func value(of line: UStVAReturn.Line) -> String {
        line.isBase
            ? String(UStVA_2026.wholeEuros(line.amountMinor))
            : UStVAAmounts.decimalString(line.amountMinor)
    }

    /// Returns the Steuernummer to write, or `nil` if there is none.
    ///
    /// ELSTER expects the 13-digit federal format. Separators around 13 digits
    /// are removed; anything else (typically a state format such as
    /// `12/345/67890`) is passed through unchanged and flagged, because
    /// converting between the formats needs the Bundesfinanzamtsnummer and
    /// would be guesswork.
    private static func elsterTaxNumber(_ raw: String?, warnings: inout [String]) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            warnings.append("Es ist keine Steuernummer hinterlegt; das Feld fehlt in der Datei.")
            return nil
        }
        let digits = trimmed.filter(\.isNumber)
        if digits.count == 13 {
            return digits
        }
        warnings.append(
            "Die Steuernummer \"\(trimmed)\" ist nicht das 13-stellige ELSTER-Format. "
                + "Sie wurde unverändert übernommen und muss in Mein ELSTER geprüft werden."
        )
        return trimmed
    }

    private static func element(_ name: String, _ value: String) -> String {
        "<\(name)>\(escape(value))</\(name)>"
    }

    private static func escape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
