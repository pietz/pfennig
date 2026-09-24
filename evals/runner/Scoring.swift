import Agent
import Core
import Foundation

struct GroundTruth: Decodable {
    struct Profile: Decodable {
        let name: String
        let ustid: String
        let kleinunternehmer: Bool
    }

    let profile: Profile
    /// The day the agent sees as today, so a corpus scores the same on any day.
    let today: LocalDate
    let cases: [EvalCase]

    /// Decodes and checks a truth file. Without the key check a misspelled
    /// key would drop silently, and a malformed value would fail or pass
    /// every run.
    static func load(_ data: Data, root: URL) throws -> GroundTruth {
        try checkKeys(JSONSerialization.jsonObject(with: data), level: "truth")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let truth = try decoder.decode(GroundTruth.self, from: data)
        try truth.validate(at: root)
        return truth
    }

    /// The keys of each level, named by the key that holds it. Case notes
    /// such as `label_uncertainties` and `source_amounts` document a label
    /// and are not scored.
    private static let allowedKeys: [String: Set<String>] = [
        "truth": ["profile", "today", "cases"],
        "profile": ["name", "ustid", "kleinunternehmer"],
        "cases": [
            "id", "file", "expected", "converted_eur_tolerance_cents", "expected_failure", "strict_nulls",
            "accepted_no_booking", "label_uncertainties", "source_amounts"
        ],
        "expected": [
            "richtung", "art", "accepted_arts", "datum", "belegnummer", "accepted_receipt_numbers",
            "faelligkeit", "accepted_due_dates", "gegenpartei_name", "accepted_counterparties",
            "gegenpartei_land", "accepted_countries", "kategorie", "accepted_categories", "steuerbehandlung",
            "privatanteil_prozent", "nutzungsdauer_jahre", "waehrung", "originalbetrag", "netto_cents",
            "steuer_cents", "brutto_cents", "positionen_nach_satz", "zahlungen"
        ],
        "positionen_nach_satz": ["steuersatz", "accepted_rates", "netto_cents", "steuer_cents"],
        "zahlungen": ["datum", "betrag"]
    ]

    private static func checkKeys(_ value: Any, level: String) throws {
        if let items = value as? [Any] {
            for item in items {
                try checkKeys(item, level: level)
            }
            return
        }
        guard let object = value as? [String: Any], let allowed = allowedKeys[level] else { return }
        if let unknown = Set(object.keys).subtracting(allowed).sorted().first {
            throw EvalError.invalid("Unknown key \(unknown) in \(level)")
        }
        for (key, child) in object where allowedKeys[key] != nil {
            try checkKeys(child, level: key)
        }
    }

    private func validate(at root: URL) throws {
        guard cases.isEmpty == false, Set(cases.map(\.id)).count == cases.count else {
            throw EvalError.invalid("Ground truth is empty or has duplicate case IDs.")
        }
        for item in cases {
            func require(_ condition: Bool, _ problem: String) throws {
                guard condition else { throw EvalError.invalid("Case \(item.id): \(problem)") }
            }
            try require(FileManager.default.fileExists(atPath: root.appending(path: item.file).path), "missing file")
            try require(item.convertedEurToleranceCents >= 0, "negative tolerance")
            guard let expected = item.expected else {
                try require([nil, "invalid_pdf"].contains(item.expectedFailure), "unknown expected_failure")
                continue
            }
            try require(item.expectedFailure == nil, "expected_failure next to an expected booking")
            guard let richtung = Richtung(rawValue: expected.richtung) else {
                throw EvalError.invalid("Case \(item.id): unknown richtung")
            }
            let categories = Set(Kategorie.fuer(richtung).map(\.schluessel))
            let positions = expected.positionenNachSatz ?? []
            let dates = [expected.datum] + [expected.faelligkeit].compactMap(\.self)
                + (expected.acceptedDueDates ?? []).compactMap(\.self) + (expected.zahlungen ?? []).map(\.datum)
            let decimals = [expected.originalbetrag].compactMap(\.self)
                + positions.flatMap { [$0.steuersatz] + ($0.acceptedRates ?? []) }
            try require(expected.arts.allSatisfy { Art(rawValue: $0) != nil }, "unknown art")
            try require(expected.categories.allSatisfy(categories.contains), "unknown category")
            try require(expected.countries.allSatisfy { $0.wholeMatch(of: /[A-Z]{2}/) != nil }, "invalid country")
            try require(
                expected.steuerbehandlung.map { Steuerbehandlung(rawValue: $0) != nil } ?? true,
                "unknown steuerbehandlung"
            )
            try require(dates.allSatisfy { LocalDate($0) != nil }, "invalid date")
            try require(decimals.allSatisfy { $0.wholeMatch(of: /-?\d+(\.\d+)?/) != nil }, "invalid decimal")
            if item.strictNulls == true {
                // These have no empty state in a booking, so null can only mean unscored.
                let settled: [Any?] = [
                    expected.privatanteilProzent, expected.nettoCents, expected.steuerCents,
                    expected.bruttoCents, expected.positionenNachSatz, expected.zahlungen
                ]
                try require(
                    settled.allSatisfy { $0 != nil }
                        && positions.allSatisfy { $0.nettoCents != nil && $0.steuerCents != nil }
                        && (expected.zahlungen ?? []).allSatisfy { $0.betrag != nil },
                    "strict_nulls leaves an amount or share unscored"
                )
            }
            if let net = expected.nettoCents, let tax = expected.steuerCents, let gross = expected.bruttoCents {
                try require(net + tax == gross, "inconsistent gross amount")
                if expected.positionenNachSatz != nil {
                    try require(
                        positions.reduce(0) { $0 + ($1.nettoCents ?? 0) } == net
                            && positions.reduce(0) { $0 + ($1.steuerCents ?? 0) } == tax,
                        "inconsistent positions"
                    )
                }
            }
        }
    }
}

struct EvalCase: Decodable {
    let id: String
    let file: String
    let expected: ExpectedBooking?
    let convertedEurToleranceCents: Int64
    let expectedFailure: String?
    /// Null means "must be empty" rather than "not settled by the document".
    let strictNulls: Bool?
    let acceptedNoBooking: Bool?
}

struct ExpectedBooking: Decodable {
    let richtung: String
    let art: String
    let acceptedArts: [String]?
    let datum: String
    let belegnummer: String?
    let acceptedReceiptNumbers: [String?]?
    let faelligkeit: String?
    let acceptedDueDates: [String?]?
    let gegenparteiName: String
    let acceptedCounterparties: [String]?
    let gegenparteiLand: String
    let acceptedCountries: [String?]?
    let kategorie: String
    let acceptedCategories: [String]?
    let steuerbehandlung: String?
    let privatanteilProzent: Int?
    let nutzungsdauerJahre: Int?
    let waehrung: String?
    let originalbetrag: String?
    let nettoCents: Int64?
    let steuerCents: Int64?
    let bruttoCents: Int64?
    let positionenNachSatz: [ExpectedRate]?
    let zahlungen: [ExpectedPayment]?

    var arts: [String] {
        [art] + (acceptedArts ?? [])
    }

    var categories: [String] {
        [kategorie] + (acceptedCategories ?? [])
    }

    var countries: [String] {
        [gegenparteiLand] + (acceptedCountries ?? []).compactMap(\.self)
    }
}

struct ExpectedRate: Decodable {
    let steuersatz: String
    let acceptedRates: [String]?
    let nettoCents: Int64?
    let steuerCents: Int64?
}

struct ExpectedPayment: Decodable {
    let datum: String
    let betrag: Int64?
}

enum EvalError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}

enum EvalScoring {
    /// The agent never saw the document: the API refused it or could not be
    /// reached. Matched against `AgentError`'s own wording, so a changed
    /// message cannot quietly reclassify a failure.
    static func isInfrastructureError(_ error: String?) -> Bool {
        guard let error else { return false }
        return (100 ... 599).contains { isAPIError(error, status: $0) }
            || error.hasPrefix(AgentError.network("").localizedDescription)
            || error == AgentError.missingKey.localizedDescription
    }

    static func isAPIError(_ error: String?, status: Int) -> Bool {
        error?.hasPrefix(AgentError.api(status: status, text: "").localizedDescription) == true
    }

    static func mismatches(
        _ item: EvalCase,
        outcome: String,
        error: String?,
        bookings: [Buchung],
        fileID: Int64?
    ) -> [String] {
        let noBooking = error == AgentError.noBooking.localizedDescription
        guard let expected = item.expected else {
            var findings: [String] = []
            if outcome != "failed" {
                findings.append("Expected failure, got \(outcome): \(error ?? "")")
            } else if item.expectedFailure == "invalid_pdf" {
                if noBooking == false, [400, 422].contains(where: { isAPIError(error, status: $0) }) == false {
                    findings.append("Expected document rejection, got: \(error ?? "")")
                }
            } else if noBooking == false {
                findings.append("Expected noBooking, got: \(error ?? "")")
            }
            if bookings.isEmpty == false {
                findings.append("Expected no bookings, got \(bookings.count)")
            }
            return findings
        }
        if item.acceptedNoBooking == true, outcome == "failed", noBooking, bookings.isEmpty {
            return []
        }
        var findings: [String] = []
        if outcome != "booked" {
            findings.append("Import \(outcome): \(error ?? "")")
        }
        guard bookings.count == 1, let actual = bookings.first else {
            findings.append("Expected one booking, got \(bookings.count)")
            return findings
        }
        let strict = item.strictNulls == true
        let tolerance = item.convertedEurToleranceCents

        /// A field without an expectation is unscored, unless nulls are strict
        /// or alternatives name what an empty field stands beside.
        func check(
            _ field: String,
            _ actualValue: String?,
            _ expectedValue: String?,
            accepted: [String?] = [],
            normalize: (String?) -> String? = { $0 }
        ) {
            guard expectedValue != nil || strict || accepted.isEmpty == false else { return }
            let options = Set(([expectedValue] + accepted).map(normalize))
            guard options.contains(normalize(actualValue)) == false else { return }
            let wanted = options.map { $0 ?? "nil" }.sorted()
            let described = wanted.count == 1 ? wanted[0] : "one of \(wanted)"
            findings.append("\(field): expected \(described), got \(normalize(actualValue) ?? "nil")")
        }
        func amount(_ field: String, _ actualValue: Int64, _ expectedValue: Int64?, tolerance: Int64 = 0) {
            guard let expectedValue, abs(actualValue - expectedValue) > tolerance else { return }
            findings.append("\(field): expected \(expectedValue) ±\(tolerance), got \(actualValue)")
        }

        check("richtung", actual.richtung.rawValue, expected.richtung)
        check("art", actual.art.rawValue, expected.art, accepted: expected.acceptedArts ?? [])
        check("datum", actual.datum.description, expected.datum)
        check(
            "belegnummer",
            actual.belegnummer,
            expected.belegnummer,
            accepted: expected.acceptedReceiptNumbers ?? []
        )
        check(
            "faelligkeit",
            actual.faelligkeit?.description,
            expected.faelligkeit,
            accepted: expected.acceptedDueDates ?? []
        )
        check(
            "gegenpartei_name",
            actual.gegenparteiName,
            expected.gegenparteiName,
            accepted: expected.acceptedCounterparties ?? [],
            normalize: normalized
        )
        check(
            "gegenpartei_land",
            actual.gegenparteiLand,
            expected.gegenparteiLand,
            accepted: expected.acceptedCountries ?? []
        )
        check("kategorie", actual.kategorie, expected.kategorie, accepted: expected.acceptedCategories ?? [])
        check("steuerbehandlung", actual.steuerbehandlung?.rawValue, expected.steuerbehandlung)
        check(
            "privatanteil_prozent",
            String(actual.privatanteilProzent),
            expected.privatanteilProzent.map(String.init)
        )
        check(
            "nutzungsdauer_jahre",
            actual.nutzungsdauerJahre.map(String.init),
            expected.nutzungsdauerJahre.map(String.init)
        )
        check("waehrung", actual.waehrung, expected.waehrung)
        check(
            "originalbetrag",
            actual.originalbetrag.map { NSDecimalNumber(decimal: $0).stringValue },
            expected.originalbetrag,
            normalize: { $0.map(rate) }
        )
        amount("netto_cents", actual.netto.value, expected.nettoCents, tolerance: tolerance)
        amount("steuer_cents", actual.steuer.value, expected.steuerCents)
        amount("brutto_cents", actual.brutto.value, expected.bruttoCents, tolerance: tolerance)

        if let targets = expected.positionenNachSatz {
            let actualRates = Dictionary(grouping: actual.positionen) {
                NSDecimalNumber(decimal: $0.steuersatz).stringValue
            }
            if actualRates.count != targets.count {
                findings.append("steuersaetze: expected \(targets.count) groups, got \(actualRates.count)")
            }
            for target in targets {
                let accepted = ([target.steuersatz] + (target.acceptedRates ?? [])).map(rate)
                guard let match = accepted.first(where: { actualRates[$0] != nil }),
                      let positions = actualRates[match]
                else {
                    findings.append("steuersatz: expected one of \(accepted), got \(actualRates.keys.sorted())")
                    continue
                }
                amount(
                    "satz \(match) netto",
                    positions.reduce(0) { $0 + $1.netto.value },
                    target.nettoCents,
                    tolerance: tolerance
                )
                amount("satz \(match) steuer", positions.reduce(0) { $0 + $1.steuer.value }, target.steuerCents)
            }
        }
        if let payments = expected.zahlungen {
            let actualDates = Set(actual.zahlungen.map(\.datum.description)).sorted()
            let expectedDates = Set(payments.map(\.datum)).sorted()
            if actualDates != expectedDates {
                findings.append("zahlungsdaten: expected \(expectedDates), got \(actualDates)")
            }
            // A payment without an amount is the EUR amount no document
            // states, such as a card charge in USD: it settles the rest.
            let paid = actual.zahlungen.reduce(0) { $0 + $1.betrag.value }
            if payments.contains(where: { $0.betrag == nil }), paid != actual.brutto.value {
                findings.append("zahlungen: expected \(actual.brutto.value) in total, got \(paid)")
            }
            for (date, due) in Dictionary(grouping: payments, by: \.datum).sorted(by: { $0.key < $1.key })
                where due.allSatisfy({ $0.betrag != nil })
            {
                let expectedAmounts = due.compactMap(\.betrag).sorted()
                let actualAmounts = actual.zahlungen.filter { $0.datum.description == date }.map(\.betrag.value)
                    .sorted()
                if actualAmounts != expectedAmounts {
                    findings.append("zahlung \(date): expected \(expectedAmounts), got \(actualAmounts)")
                }
            }
        }
        if fileID.map({ actual.belege.contains($0) }) != true {
            findings.append("Receipt is not attached")
        }
        if actual.geprueftAm != nil {
            findings.append("Booking should remain unreviewed")
        }
        return findings
    }

    /// One spelling per decimal value, so "19", "19.0" and "19.00" agree.
    private static func rate(_ text: String) -> String {
        NSDecimalNumber(string: text, locale: Locale(identifier: "en_US_POSIX")).stringValue
    }

    /// The words of a name, so "Wortspur Freie Texte · Jana Feld" and
    /// "Jana Feld – Wortspur Freie Texte" agree.
    private static func normalized(_ value: String?) -> String? {
        value?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .split(whereSeparator: { $0.isLetter == false && $0.isNumber == false })
            .sorted()
            .joined(separator: " ")
    }
}
