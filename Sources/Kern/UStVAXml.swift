import Foundation

/// Writes a computed UStVA as the XML file the form "XML-Daten hochladen" of
/// Mein ELSTER takes. Pfennig does not transmit: the user uploads the file in
/// their own session, checks the filled form and sends it themselves.
///
/// What is verified (docs/research-ustva-xml.md): only the content below
/// `/Elster/DatenTeil/Nutzdatenblock/Nutzdaten/Anmeldungssteuern` is uploaded,
/// the envelope is `<Anmeldungssteuern xmlns="…/ustva/v2023" version="2023">`,
/// the character set is ISO-8859-15, and the value of Kz 83 is taken over as
/// the user's own figure instead of being recalculated. A file of this shape
/// for Q3 2026 was accepted by Mein ELSTER on 2026-09-14 and filled the form,
/// without being sent. The structure therefore stays as it is.
///
/// The schema version is the one the help page documents and does not follow
/// the year of the period; the year sits in `Jahr`. The `<Unternehmer>` block
/// is left out, the Mein-ELSTER session carries the identity anyway.
public enum UStVAXml {
    /// The only documented schema version.
    public static let schemaversion = 2023

    /// ISO-8859-15, the character set the elster.de help page names.
    public static let kodierung = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)
        )
    )

    public static func xml(_ ustva: UStVA) -> String {
        var inhalt: [String] = []
        inhalt.append(element("Jahr", String(ustva.zeitraum.jahr)))
        inhalt.append(element("Zeitraum", ustva.zeitraum.code))
        if let steuernummer = steuernummer(ustva.steuernummer) {
            inhalt.append(element("Steuernummer", steuernummer))
        }
        for zeile in ustva.zeilen where zeile.kennzahl.nummer != 83 {
            inhalt.append(element("Kz\(zeile.kennzahl.nummer)", wert(zeile)))
        }
        // Kz 83 is always written: the help page states the uploaded value is
        // taken over instead of being recalculated.
        inhalt.append(element("Kz83", punkt(ustva.zahllast)))

        let namensraum = "http://finkonsens.de/elster/elsteranmeldung/ustva/v\(schemaversion)"
        return """
        <?xml version="1.0" encoding="ISO-8859-15" standalone="no"?>
        <Anmeldungssteuern xmlns="\(namensraum)" version="\(schemaversion)">
          <Steuerfall>
            <Umsatzsteuervoranmeldung>
        \(inhalt.map { "      \($0)" }.joined(separator: "\n"))
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
    private static func wert(_ zeile: UStVA.Zeile) -> String {
        zeile.kennzahl.istBemessung ? String(Kennzahl.volleEuro(zeile.betrag)) : punkt(zeile.betrag)
    }

    /// `1234.56`, the machine notation of the payload.
    private static func punkt(_ betrag: Cent) -> String {
        let vorzeichen = betrag.wert < 0 ? "-" : ""
        let betrag = betrag.wert.magnitude
        return "\(vorzeichen)\(betrag / 100)." + String(format: "%02d", betrag % 100)
    }

    /// ELSTER expects the 13 digit federal Steuernummer. Separators around 13
    /// digits are dropped; anything else, typically a state format such as
    /// `12/345/67890`, goes in unchanged, because converting between the two
    /// needs the Bundesfinanzamtsnummer and would be guesswork.
    private static func steuernummer(_ roh: String) -> String? {
        let geputzt = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard geputzt.isEmpty == false else { return nil }
        let ziffern = geputzt.filter(\.isNumber)
        return ziffern.count == 13 ? ziffern : geputzt
    }

    private static func element(_ name: String, _ wert: String) -> String {
        "<\(name)>\(maskiert(wert))</\(name)>"
    }

    private static func maskiert(_ wert: String) -> String {
        wert
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
