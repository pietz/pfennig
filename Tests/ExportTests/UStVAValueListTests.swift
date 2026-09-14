import Domain
@testable import Export
import Tax
import Testing

@Suite("UStVAValueList")
struct UStVAValueListTests {
    @Test("Base Kennzahlen show truncated whole euros, tax Kennzahlen two decimals")
    func germanFormatting() {
        let result = UStVAFixture.quarterly(
            lines: [
                UStVAFixture.line(81, "Umsätze 19 %", isBase: true, 1_234_599),
                UStVAFixture.line(66, "Vorsteuer", isBase: false, 25235)
            ],
            payableMinor: 209_339
        )
        let text = UStVAValueList.text(for: result)
        #expect(text == """
        UStVA Q3 2026
        Kz 81: 12.345 €
        Kz 66: 252,35 €
        Kz 83: 2.093,39 €
        Zahllast: 2.093,39 €
        """)
    }

    @Test("A negative Kz 83 is labelled as Erstattung with a positive amount")
    func refund() {
        let result = UStVAFixture.quarterly(lines: [], payableMinor: -123_456)
        let text = UStVAValueList.text(for: result)
        #expect(text.contains("Kz 83: -1.234,56 €"))
        #expect(text.hasSuffix("Erstattung: 1.234,56 €"))
    }

    @Test("Drafts carry a header line with the number of open cases")
    func draftHeader() {
        let one = UStVAFixture.quarterly(exceptions: [UStVAFixture.exception()])
        #expect(UStVAValueList.text(for: one).contains("Entwurf, 1 offener Fall"))

        let two = UStVAFixture.quarterly(exceptions: [
            UStVAFixture.exception("A"),
            UStVAFixture.exception("B")
        ])
        let lines = UStVAValueList.text(for: two).split(separator: "\n")
        #expect(lines[0] == "UStVA Q3 2026")
        #expect(lines[1] == "Entwurf, 2 offene Fälle")
    }

    @Test("A clean return has no draft line")
    func noDraftLine() {
        #expect(!UStVAValueList.text(for: UStVAFixture.quarterly()).contains("Entwurf"))
    }

    @Test("Monthly periods are titled with the German month name")
    func monthlyTitle() {
        let result = UStVAReturn(
            period: UStVAPeriod(year: 2026, month: 7),
            formYear: 2026,
            taxNumber: nil,
            isSmallBusiness: false,
            lines: [],
            payableMinor: 0,
            exceptions: []
        )
        #expect(UStVAValueList.text(for: result).hasPrefix("UStVA Juli 2026"))
    }

    @Test("An empty period lists zero values instead of failing")
    func emptyPeriod() {
        let result = UStVAFixture.quarterly(lines: [], payableMinor: 0)
        #expect(UStVAValueList.text(for: result) == """
        UStVA Q3 2026
        Kz 83: 0,00 €
        Zahllast: 0,00 €
        """)
    }

    @Test("A Kz 83 line in the return is not listed twice")
    func kz83NotDuplicated() {
        let result = UStVAFixture.quarterly(
            lines: [UStVAFixture.line(83, "Zahllast", isBase: false, 700)],
            payableMinor: 700
        )
        let text = UStVAValueList.text(for: result)
        #expect(text.components(separatedBy: "Kz 83:").count == 2)
    }
}
