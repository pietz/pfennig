import Domain
@testable import Export
import Foundation
import Tax
import Testing

/// Builds returns by hand; the calculator lives in another module.
enum UStVAFixture {
    static func line(
        _ kennzahl: Int,
        _ title: String,
        isBase: Bool,
        _ amountMinor: Int64,
        isVerified: Bool = true
    ) -> UStVAReturn.Line {
        UStVAReturn.Line(
            kennzahl: kennzahl,
            title: title,
            isBase: isBase,
            amountMinor: amountMinor,
            isVerified: isVerified,
            contributions: []
        )
    }

    static func exception(_ message: String = "Unklare Behandlung") -> UStVAReturn.Exception {
        UStVAReturn.Exception(
            kind: .unknownTreatment,
            transactionID: "t1",
            paymentID: nil,
            message: message
        )
    }

    /// Q3 2026, Regelbesteuerung, one 19 % revenue line and input VAT.
    static func quarterly(
        lines: [UStVAReturn.Line]? = nil,
        payableMinor: Int64 = 209_339,
        taxNumber: String? = "1096081508187",
        exceptions: [UStVAReturn.Exception] = []
    ) -> UStVAReturn {
        UStVAReturn(
            period: UStVAPeriod(year: 2026, quarter: 3),
            formYear: 2026,
            taxNumber: taxNumber,
            isSmallBusiness: false,
            lines: lines ?? [
                line(81, "Steuerpflichtige Umsätze 19 %", isBase: true, 1_234_599),
                line(66, "Abziehbare Vorsteuerbeträge", isBase: false, 25235)
            ],
            payableMinor: payableMinor,
            exceptions: exceptions
        )
    }
}

@Suite("UStVAXMLExporter")
struct UStVAXMLExporterTests {
    @Test("Envelope, namespace and version follow the documented upload structure")
    func envelope() {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly(), schemaYear: 2023)
        #expect(export.xml.contains(
            "<Anmeldungssteuern xmlns=\"http://finkonsens.de/elster/elsteranmeldung/ustva/v2023\" version=\"2023\">"
        ))
        #expect(export.xml.contains("<Steuerfall>"))
        #expect(export.xml.contains("<Umsatzsteuervoranmeldung>"))
        #expect(export.xml.hasSuffix("</Anmeldungssteuern>\n"))
        #expect(export.warnings.isEmpty)
    }

    @Test("Element order is deterministic: Jahr, Zeitraum, Steuernummer, Kennzahlen, Kz 83 last")
    func elementOrder() {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly())
        let order = ["<Jahr>", "<Zeitraum>", "<Steuernummer>", "<Kz81>", "<Kz66>", "<Kz83>"]
        var searchStart = export.xml.startIndex
        for token in order {
            let found = export.xml.range(of: token, range: searchStart ..< export.xml.endIndex)
            #expect(found != nil, "\(token) missing or out of order")
            searchStart = found?.upperBound ?? searchStart
        }
    }

    @Test("Kz 83 is always written, also when the return has no lines at all")
    func kz83AlwaysPresent() {
        let empty = UStVAFixture.quarterly(lines: [], payableMinor: 0)
        let export = UStVAXMLExporter.export(empty)
        #expect(export.xml.contains("<Kz83>0.00</Kz83>"))
    }

    @Test("A Kz 83 line in the return does not produce a duplicate element")
    func kz83NotDuplicated() {
        let result = UStVAFixture.quarterly(
            lines: [UStVAFixture.line(83, "Zahllast", isBase: false, 209_339)],
            payableMinor: 209_339
        )
        let export = UStVAXMLExporter.export(result)
        #expect(export.xml.components(separatedBy: "<Kz83>").count == 2)
        #expect(export.xml.contains("<Kz83>2093.39</Kz83>"))
    }

    @Test("Quarterly periods use the codes 41-44")
    func quarterlyPeriodCodes() {
        for quarter in 1 ... 4 {
            let result = UStVAReturn(
                period: UStVAPeriod(year: 2026, quarter: quarter),
                formYear: 2026,
                taxNumber: "1096081508187",
                isSmallBusiness: false,
                lines: [],
                payableMinor: 0,
                exceptions: []
            )
            let export = UStVAXMLExporter.export(result)
            #expect(export.xml.contains("<Zeitraum>\(40 + quarter)</Zeitraum>"))
        }
    }

    @Test("Monthly periods use the zero-padded codes 01-12")
    func monthlyPeriodCodes() {
        let january = UStVAReturn(
            period: UStVAPeriod(year: 2026, month: 1),
            formYear: 2026,
            taxNumber: "1096081508187",
            isSmallBusiness: false,
            lines: [],
            payableMinor: 0,
            exceptions: []
        )
        #expect(UStVAXMLExporter.export(january).xml.contains("<Zeitraum>01</Zeitraum>"))

        let december = UStVAReturn(
            period: UStVAPeriod(year: 2026, month: 12),
            formYear: 2026,
            taxNumber: "1096081508187",
            isSmallBusiness: false,
            lines: [],
            payableMinor: 0,
            exceptions: []
        )
        #expect(UStVAXMLExporter.export(december).xml.contains("<Zeitraum>12</Zeitraum>"))
        #expect(UStVAXMLExporter.export(december).xml.contains("<Jahr>2026</Jahr>"))
    }

    @Test("Base Kennzahlen cut the cents off instead of rounding")
    func baseTruncation() {
        let result = UStVAFixture.quarterly(lines: [
            UStVAFixture.line(81, "Umsätze 19 %", isBase: true, 1_234_599),
            UStVAFixture.line(86, "Umsätze 7 %", isBase: true, 99),
            UStVAFixture.line(47, "Leistungen §13b", isBase: true, -1999)
        ])
        let export = UStVAXMLExporter.export(result)
        #expect(export.xml.contains("<Kz81>12345</Kz81>"))
        #expect(export.xml.contains("<Kz86>0</Kz86>"))
        #expect(export.xml.contains("<Kz47>-19</Kz47>"))
    }

    @Test("Tax Kennzahlen keep two decimals with a dot")
    func taxDecimals() {
        let result = UStVAFixture.quarterly(
            lines: [UStVAFixture.line(66, "Vorsteuer", isBase: false, 25235)],
            payableMinor: -5001
        )
        let export = UStVAXMLExporter.export(result)
        #expect(export.xml.contains("<Kz66>252.35</Kz66>"))
        #expect(export.xml.contains("<Kz83>-50.01</Kz83>"))
    }

    @Test("ISO-8859-15 is the default declaration and encoding")
    func isoLatin9Declaration() throws {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly())
        #expect(export.xml.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-15\" standalone=\"no\"?>"))
        let roundTrip = try #require(
            String(data: export.data, encoding: UStVAXMLExporter.Encoding.isoLatin9.stringEncoding)
        )
        #expect(roundTrip == export.xml)
        // ISO-8859-15 is a single-byte encoding: no UTF-8 multi-byte sequences.
        #expect(export.data.count == export.xml.unicodeScalars.count)
    }

    @Test("UTF-8 can be selected and is declared as such")
    func utf8Declaration() throws {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly(), encoding: .utf8)
        #expect(export.xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>"))
        let roundTrip = try #require(String(data: export.data, encoding: .utf8))
        #expect(roundTrip == export.xml)
    }

    @Test("A 13-digit Steuernummer passes through, separators are removed")
    func elsterTaxNumber() {
        let plain = UStVAXMLExporter.export(UStVAFixture.quarterly(taxNumber: "1096081508187"), schemaYear: 2023)
        #expect(plain.xml.contains("<Steuernummer>1096081508187</Steuernummer>"))
        #expect(plain.warnings.isEmpty)

        let spaced = UStVAXMLExporter.export(UStVAFixture.quarterly(taxNumber: "109/608/15081 87"), schemaYear: 2023)
        #expect(spaced.xml.contains("<Steuernummer>1096081508187</Steuernummer>"))
        #expect(spaced.warnings.isEmpty)
    }

    @Test("A state-format Steuernummer is passed through unchanged and warned about")
    func stateFormatTaxNumberWarns() {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly(taxNumber: "12/345/67890"), schemaYear: 2023)
        #expect(export.xml.contains("<Steuernummer>12/345/67890</Steuernummer>"))
        #expect(export.warnings.count == 1)
        #expect(export.warnings[0].contains("13-stellige"))
    }

    @Test("A missing Steuernummer omits the element and warns")
    func missingTaxNumberWarns() {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly(taxNumber: nil), schemaYear: 2023)
        #expect(!export.xml.contains("<Steuernummer>"))
        #expect(export.warnings.count == 1)
    }

    @Test("An undocumented schema year is flagged")
    func schemaYearWarning() {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly())
        #expect(export.xml.contains("version=\"2026\""))
        #expect(export.xml.contains("ustva/v2026"))
        #expect(export.warnings.contains { $0.contains("v2026") })
    }

    @Test("Unverified Kennzahlen are flagged")
    func unverifiedKennzahlWarning() {
        let result = UStVAFixture.quarterly(lines: [
            UStVAFixture.line(84, "Leistungen §13b Abs. 2 Nr. 5", isBase: true, 10000, isVerified: false)
        ])
        let export = UStVAXMLExporter.export(result, schemaYear: 2023)
        #expect(export.warnings == ["Kz 84 ist noch nicht gegen das Vordruckmuster geprüft."])
    }

    @Test("XML special characters in passed-through values are escaped")
    func escaping() {
        let export = UStVAXMLExporter.export(UStVAFixture.quarterly(taxNumber: "12<3&4"))
        #expect(export.xml.contains("<Steuernummer>12&lt;3&amp;4</Steuernummer>"))
    }

    @Test("File name carries year and period, drafts get the -entwurf marker")
    func filenames() {
        #expect(UStVAXMLExporter.export(UStVAFixture.quarterly()).filename == "UStVA-2026-Q3.xml")

        let draft = UStVAFixture.quarterly(exceptions: [UStVAFixture.exception()])
        #expect(UStVAXMLExporter.export(draft).filename == "UStVA-2026-Q3-entwurf.xml")

        let monthly = UStVAReturn(
            period: UStVAPeriod(year: 2026, month: 7),
            formYear: 2026,
            taxNumber: nil,
            isSmallBusiness: false,
            lines: [],
            payableMinor: 0,
            exceptions: []
        )
        #expect(UStVAXMLExporter.suggestedFilename(for: monthly) == "UStVA-2026-07.xml")
    }
}
