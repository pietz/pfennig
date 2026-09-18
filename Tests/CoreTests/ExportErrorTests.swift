import Core
import Testing

@Test func steuerexporteErlaubenNur2026() throws {
    try ExportError.validate(year: 2026)

    do {
        try ExportError.validate(year: 2027)
        Issue.record("Ein Export für 2027 wurde zugelassen.")
    } catch let error as ExportError {
        #expect(error == .unsupportedYear(2027))
        #expect(error
            .localizedDescription ==
            "Der Export für das Steuerjahr 2027 ist nicht möglich. Pfennig unterstützt derzeit nur das Steuerjahr 2026.")
    }
}
