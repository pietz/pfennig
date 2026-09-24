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

    private static let bookingKeys: Set<String> = [
        "richtung", "art", "accepted_arts", "datum", "belegnummer", "accepted_receipt_numbers",
        "faelligkeit", "accepted_due_dates", "gegenpartei_name", "accepted_counterparties",
        "gegenpartei_land", "accepted_countries", "kategorie", "accepted_categories", "steuerbehandlung",
        "privatanteil_prozent", "nutzungsdauer_jahre", "waehrung", "originalbetrag", "netto_cents",
        "steuer_cents", "brutto_cents", "positionen_nach_satz", "zahlungen", "belege", "titel"
    ]

    /// The keys of each level, named by the key that holds it. Case notes
    /// such as `label_uncertainties` and `source_amounts` document a label
    /// and are not scored.
    private static let allowedKeys: [String: Set<String>] = [
        "truth": ["profile", "today", "cases"],
        "profile": ["name", "ustid", "kleinunternehmer"],
        "cases": [
            "id", "archive", "files", "chat", "expected", "converted_eur_tolerance_cents", "expected_failure",
            "strict_nulls", "accepted_no_booking", "label_uncertainties", "source_amounts"
        ],
        "archive": bookingKeys,
        "expected": bookingKeys,
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
            let seeds = item.archive ?? []
            let known = Set(item.files + seeds.flatMap(\.belege))
            try require(item.chat != nil || item.files.isEmpty == false, "neither files nor chat")
            try require(item.chat?.isEmpty != true, "empty chat")
            try require(Set(item.files).count == item.files.count, "a file imported twice in one drop")
            try require(
                known.allSatisfy { FileManager.default.fileExists(atPath: root.appending(path: $0).path) },
                "missing file"
            )
            try require(item.expected.allSatisfy { Set($0.belege).isSubset(of: known) }, "unknown file in belege")
            try require(item.convertedEurToleranceCents >= 0, "negative tolerance")
            try require([nil, "invalid_pdf"].contains(item.expectedFailure), "unknown expected_failure")
            for seed in seeds {
                // A seed is written as it stands, so every amount must be given.
                try require(
                    seed.belege.isEmpty == false && seed.steuerbehandlung != nil
                        && (seed.positionenNachSatz ?? []).isEmpty == false
                        && (seed.positionenNachSatz ?? []).allSatisfy { $0.nettoCents != nil && $0.steuerCents != nil }
                        && (seed.zahlungen ?? []).allSatisfy { $0.betrag != nil },
                    "archive booking without files, tax treatment, positions or payment amounts"
                )
            }
            for expected in seeds + item.expected {
                try validate(expected, strict: item.strictNulls == true, require: require)
            }
        }
    }

    private func validate(
        _ expected: ExpectedBooking,
        strict: Bool,
        require: (Bool, String) throws -> Void
    ) throws {
        guard let richtung = Richtung(rawValue: expected.richtung) else {
            return try require(false, "unknown richtung")
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
        if strict {
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

/// One scenario: the bookings the archive starts with, then either files
/// dropped together or a chat message, then every booking the archive should
/// hold. A single document into an empty archive is the simplest case.
struct EvalCase: Decodable {
    let id: String
    /// Written before the run and confirmed, each with its files.
    let archive: [ExpectedBooking]?
    /// Imported side by side as one drop, or attached to `chat`.
    let files: [String]
    /// Sent as a chat message instead of importing `files`.
    let chat: String?
    /// The whole archive after the run, seeded bookings included.
    let expected: [ExpectedBooking]
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
    /// The case's files this booking carries, exactly.
    let belege: [String]
    /// A seed's title, as the agent would have written it. Not scored.
    let titel: String?

    var arts: [String] {
        [art] + (acceptedArts ?? [])
    }

    var categories: [String] {
        [kategorie] + (acceptedCategories ?? [])
    }

    var countries: [String] {
        [gegenparteiLand] + (acceptedCountries ?? []).compactMap(\.self)
    }

    /// The booking a seed writes, from its expected values.
    func seed(files ids: [String: Int64]) throws -> Buchung {
        guard let richtung = Richtung(rawValue: richtung), let art = Art(rawValue: art),
              let datum = LocalDate(datum)
        else { throw EvalError.invalid("Unreadable archive booking \(gegenparteiName)") }
        return Buchung(
            richtung: richtung, art: art, datum: datum, titel: titel ?? gegenparteiName,
            belegnummer: belegnummer, faelligkeit: faelligkeit.flatMap { LocalDate($0) },
            kategorie: kategorie, privatanteilProzent: privatanteilProzent ?? 0,
            nutzungsdauerJahre: nutzungsdauerJahre, gegenparteiName: gegenparteiName,
            gegenparteiLand: gegenparteiLand,
            positionen: (positionenNachSatz ?? []).map {
                Position(
                    netto: Cent($0.nettoCents ?? 0),
                    steuersatz: Decimal(string: $0.steuersatz) ?? 0,
                    steuer: Cent($0.steuerCents ?? 0)
                )
            },
            waehrung: waehrung, originalbetrag: originalbetrag.flatMap { Decimal(string: $0) },
            steuerbehandlung: steuerbehandlung.flatMap { Steuerbehandlung(rawValue: $0) },
            zahlungen: (zahlungen ?? []).compactMap { payment in
                LocalDate(payment.datum).map { Zahlung(datum: $0, betrag: Cent(payment.betrag ?? 0)) }
            },
            belege: belege.compactMap { ids[$0] }
        )
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

/// How one imported file ended.
struct FileRun: Codable, Equatable {
    let file: String
    let outcome: String
    let error: String?
}

/// What a case left behind, the input of scoring. A saved report holds it,
/// so a changed truth label can be scored again without another run.
struct CaseRun {
    var imports: [FileRun] = []
    var chatError: String?
    var bookings: [Buchung]
    /// Archive IDs of the case's files, by truth path.
    var fileIDs: [String: Int64]
    /// Bookings written before the run.
    var seeded: Set<Int64> = []
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

    static func mismatches(_ item: EvalCase, run: CaseRun) -> [String] {
        let noBooking = AgentError.noBooking.localizedDescription
        let created = run.bookings.filter { $0.id.map(run.seeded.contains) != true }
        if item.acceptedNoBooking == true, created.isEmpty,
           run.imports.allSatisfy({ $0.outcome == "failed" && $0.error == noBooking })
        {
            return []
        }
        var findings: [String] = []
        if item.chat != nil, let error = run.chatError {
            findings.append("Chat failed: \(error)")
        }
        // A file some booking should carry must book; any other must be declined.
        let attached = Set(item.expected.flatMap(\.belege))
        for file in run.imports {
            let label = run.imports.count > 1 ? "\(file.file): " : ""
            if attached.contains(file.file) {
                if ["booked", "alreadyPresent"].contains(file.outcome) == false {
                    findings.append("\(label)Import \(file.outcome): \(file.error ?? "")")
                }
            } else if file.outcome != "failed" {
                findings.append("\(label)Expected failure, got \(file.outcome): \(file.error ?? "")")
            } else if item.expectedFailure == "invalid_pdf" {
                if file.error != noBooking,
                   [400, 422].contains(where: { isAPIError(file.error, status: $0) }) == false
                {
                    findings.append("\(label)Expected document rejection, got: \(file.error ?? "")")
                }
            } else if file.error != noBooking {
                findings.append("\(label)Expected noBooking, got: \(file.error ?? "")")
            }
        }

        // Each expected booking takes the remaining booking it fits best.
        let names = Dictionary(run.fileIDs.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var remaining = run.bookings
        for (index, expected) in item.expected.enumerated() {
            let label = item.expected.count > 1 ? "[\(index + 1)] " : ""
            guard remaining.isEmpty == false else {
                findings.append("\(label)missing booking: \(expected.gegenparteiName)")
                continue
            }
            let scored = remaining.indices.map { position in
                (position, fields(expected, remaining[position], item: item, run: run, names: names))
            }
            guard let best = scored.min(by: { $0.1.count < $1.1.count }) else { continue }
            findings += best.1.map { label + $0 }
            remaining.remove(at: best.0)
        }
        for extra in remaining {
            findings.append("unexpected booking: \(extra.titel), \(extra.brutto.value) cents")
        }
        return findings
    }

    /// The field mismatches of one booking against its expectation.
    private static func fields(
        _ expected: ExpectedBooking,
        _ actual: Buchung,
        item: EvalCase,
        run: CaseRun,
        names: [Int64: String]
    ) -> [String] {
        var findings: [String] = []
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
        let expectedFiles = Set(expected.belege)
        let actualFiles = Set(actual.belege.map { names[$0] ?? "file \($0)" })
        if actualFiles != expectedFiles {
            findings.append("belege: expected \(expectedFiles.sorted()), got \(actualFiles.sorted())")
        }
        // Review state is the app's; only a booking the agent wrote is checked.
        if actual.id.map(run.seeded.contains) != true, actual.geprueftAm != nil {
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
