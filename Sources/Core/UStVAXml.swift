import Foundation

/// Writes a computed UStVA as the XML file the form "XML-Daten hochladen" of
/// Mein ELSTER takes. Pfennig does not transmit: the user uploads the file in
/// their own session, checks the filled form and sends it themselves.
///
/// What is verified: only the content below
/// `/Elster/DatenTeil/Nutzdatenblock/Nutzdaten/Anmeldungssteuern` is uploaded,
/// the character set is ISO-8859-15, and the value of Kz 83 is taken over as
/// the user's own figure instead of being recalculated
/// (docs/research-ustva-xml.md). The file Pfennig wrote for Q3 2026 was
/// accepted by Mein ELSTER on 2026-09-14 and filled the form, without being
/// sent; it began with
///
///     <?xml version="1.0" encoding="ISO-8859-15" standalone="no"?>
///     <Anmeldungssteuern xmlns="http://finkonsens.de/elster/elsteranmeldung/ustva/v2026" version="2026">
///
/// so namespace and version carry the year of the period, not the 2023 of the
/// example on the help page. The `<Unternehmer>` block is left out, the
/// Mein-ELSTER session carries the identity anyway.
public enum UStVAXml {
    /// ISO-8859-15, the character set the elster.de help page names and the
    /// accepted file used.
    public static let kodierung = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)
        )
    )

    public static func xml(_ ustva: UStVA) -> String {
        var content: [String] = []
        content.append(element("Jahr", String(ustva.zeitraum.jahr)))
        content.append(element("Zeitraum", ustva.zeitraum.code))
        if let steuernummer = steuernummer(ustva.steuernummer) {
            content.append(element("Steuernummer", steuernummer))
        }
        for zeile in ustva.zeilen where zeile.kennzahl.nummer != 83 {
            content.append(element("Kz\(zeile.kennzahl.nummer)", value(zeile)))
        }
        // Kz 83 is always written: the help page states the uploaded value is
        // taken over instead of being recalculated.
        content.append(element("Kz83", punkt(ustva.zahllast)))

        // Namespace and version follow the year of the period.
        let jahr = ustva.zeitraum.jahr
        let namensraum = "http://finkonsens.de/elster/elsteranmeldung/ustva/v\(jahr)"
        return """
        <?xml version="1.0" encoding="ISO-8859-15" standalone="no"?>
        <Anmeldungssteuern xmlns="\(namensraum)" version="\(jahr)">
          <Steuerfall>
            <Umsatzsteuervoranmeldung>
        \(content.map { "      \($0)" }.joined(separator: "\n"))
            </Umsatzsteuervoranmeldung>
          </Steuerfall>
        </Anmeldungssteuern>

        """
    }

    /// The file as it goes to disk. A character that ISO-8859-15 does not
    /// carry is replaced rather than losing the file.
    public static func daten(_ ustva: UStVA) -> Data {
        let text = xml(ustva)
        return text.data(using: kodierung, allowLossyConversion: true) ?? Data(text.utf8)
    }

    // MARK: - Bausteine

    /// A Bemessungsgrundlage carries whole euros with the cents cut off, a tax
    /// Kennzahl two decimals with a dot.
    private static func value(_ zeile: UStVA.Zeile) -> String {
        zeile.kennzahl.istBemessung ? String(Kennzahl.volleEuro(zeile.betrag)) : punkt(zeile.betrag)
    }

    /// `1234.56`, the machine notation of the payload.
    private static func punkt(_ betrag: Cent) -> String {
        let vorzeichen = betrag.value < 0 ? "-" : ""
        let betrag = betrag.value.magnitude
        return "\(vorzeichen)\(betrag / 100)." + String(format: "%02d", betrag % 100)
    }

    /// ELSTER expects the 13 digit federal Steuernummer. Separators around 13
    /// digits are dropped; anything else, typically a state format such as
    /// `12/345/67890`, goes in unchanged, because converting between the two
    /// needs the Bundesfinanzamtsnummer and would be guesswork.
    private static func steuernummer(_ raw: String) -> String? {
        let geputzt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard geputzt.isEmpty == false else { return nil }
        let ziffern = geputzt.filter(\.isNumber)
        return ziffern.count == 13 ? ziffern : geputzt
    }

    private static func element(_ name: String, _ value: String) -> String {
        "<\(name)>\(maskiert(value))</\(name)>"
    }

    private static func maskiert(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
