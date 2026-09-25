import Core
import Foundation

/// The UStVA of each quarter and the Anlage EÜR of one year, computed with
/// the app's own code from the bookings a run left, one set per repetition.
/// A corpus of a whole year then compares with the figures that were filed.
enum TaxTotals {
    struct Year: Encodable {
        let repetition: Int
        /// Kennzahl to cents, per quarter "Q1" to "Q4".
        let ustva: [String: [String: Int64]]
        /// Line of the Anlage EÜR to cents; the nicht abziehbare column of a
        /// line carries the suffix "n".
        let euer: [String: Int64]
        let gewinn: Int64
    }

    private struct Run: Decodable {
        struct Case: Decodable {
            let repetition: Int
            let bookings: [Buchung]
        }

        let cases: [Case]
    }

    private struct Truth: Decodable {
        struct Profile: Decodable {
            let kleinunternehmer: Bool
        }

        let profile: Profile
    }

    static func compute(report: URL, year: Int) throws -> [Year] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(Run.self, from: Data(contentsOf: report))
        let truth = try decoder.decode(
            Truth.self,
            from: Data(contentsOf: report.deletingLastPathComponent().appending(path: "truth-snapshot.json"))
        )
        let profile = Profil(kleinunternehmer: truth.profile.kleinunternehmer)
        return Dictionary(grouping: run.cases, by: \.repetition).keys.sorted().map { repetition in
            let bookings = run.cases.filter { $0.repetition == repetition }.flatMap(\.bookings)
            let ustva = Dictionary(uniqueKeysWithValues: (1 ... 4).map { quarter in
                let result = UStVA.calculate(
                    bookings, zeitraum: Zeitraum(jahr: year, einteilung: .quartal(quarter)), profile: profile
                )
                return ("Q\(quarter)", Dictionary(uniqueKeysWithValues: result.zeilen.map {
                    ("\($0.kennzahl.nummer)", $0.betrag.value)
                }))
            })
            let euer = EUeR.calculate(bookings, jahr: year, profile: profile)
            return Year(
                repetition: repetition,
                ustva: ustva,
                euer: Dictionary(uniqueKeysWithValues: euer.zeilen.map {
                    ("\($0.zeile)\($0.nichtAbziehbar ? "n" : "")", $0.betrag.value)
                }),
                gewinn: euer.ergebnis.value
            )
        }
    }
}
