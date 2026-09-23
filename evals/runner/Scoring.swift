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
    let cases: [EvalCase]

    func validate(at root: URL) throws {
        guard cases.isEmpty == false, Set(cases.map(\.id)).count == cases.count else {
            throw EvalError.invalid("Ground truth is empty or has duplicate case IDs.")
        }
        for item in cases {
            guard FileManager.default.fileExists(atPath: root.appending(path: item.file).path) else {
                throw EvalError.invalid("Missing PDF: \(item.file)")
            }
            guard let expected = item.expected else { continue }
            guard item.convertedEurToleranceCents >= 0 else {
                throw EvalError.invalid("Negative tolerance: \(item.id)")
            }
            if let net = expected.nettoCents, let tax = expected.steuerCents, let gross = expected.bruttoCents {
                guard net + tax == gross else { throw EvalError.invalid("Inconsistent gross amount: \(item.id)") }
                if let positions = expected.positionenNachSatz {
                    guard positions.reduce(0, { $0 + ($1.nettoCents ?? 0) }) == net,
                          positions.reduce(0, { $0 + ($1.steuerCents ?? 0) }) == tax
                    else { throw EvalError.invalid("Inconsistent positions: \(item.id)") }
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
    let strictNulls: Bool?
    let acceptedNoBooking: Bool?
}

struct ExpectedBooking: Decodable {
    let richtung: String
    let art: String
    let acceptedArts: [String]?
    let datum: String
    let belegnummer: String?
    let faelligkeit: String?
    let gegenparteiName: String
    let acceptedCounterparties: [String]?
    let gegenparteiLand: String
    let acceptedCountries: [String]?
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
        if case let .invalid(message) = self {
            message
        } else {
            nil
        }
    }
}

enum EvalScoring {
    static func mismatches(
        _ item: EvalCase,
        outcome: String,
        error: String?,
        bookings: [Buchung],
        fileID: Int64?
    ) -> [String] {
        guard let expected = item.expected else {
            var findings: [String] = []
            if outcome != "failed" {
                findings.append("Expected failure, got \(outcome): \(error ?? "")")
            } else if item.expectedFailure == "invalid_pdf" {
                let rejected = error == AgentError.noBooking.localizedDescription
                    || error?.hasPrefix("OpenAI hat mit 400 geantwortet:") == true
                    || error?.hasPrefix("OpenAI hat mit 422 geantwortet:") == true
                if rejected == false {
                    findings.append("Expected document rejection, got: \(error ?? "")")
                }
            } else if error != AgentError.noBooking.localizedDescription {
                findings.append("Expected noBooking, got: \(error ?? "")")
            }
            if bookings.isEmpty == false {
                findings.append("Expected no bookings, got \(bookings.count)")
            }
            return findings
        }
        if item.acceptedNoBooking == true,
           outcome == "failed",
           error == AgentError.noBooking.localizedDescription,
           bookings.isEmpty
        {
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
        func check(_ field: String, _ actualValue: String?, _ expectedValue: String?) {
            if actualValue != expectedValue {
                findings.append("\(field): expected \(expectedValue ?? "nil"), got \(actualValue ?? "nil")")
            }
        }
        func amount(_ field: String, _ actualValue: Int64, _ expectedValue: Int64, tolerance: Int64 = 0) {
            if abs(actualValue - expectedValue) > tolerance {
                findings.append("\(field): expected \(expectedValue) ±\(tolerance), got \(actualValue)")
            }
        }
        check("richtung", actual.richtung.rawValue, expected.richtung)
        let arts = Set([expected.art] + (expected.acceptedArts ?? []))
        if arts.contains(actual.art.rawValue) == false {
            findings.append("art: expected one of \(arts.sorted()), got \(actual.art.rawValue)")
        }
        check("datum", actual.datum.description, expected.datum)
        if expected.belegnummer != nil || item.strictNulls == true {
            check("belegnummer", actual.belegnummer, expected.belegnummer)
        }
        if expected.faelligkeit != nil || item.strictNulls == true {
            check("faelligkeit", actual.faelligkeit?.description, expected.faelligkeit)
        }
        let counterparties = Set([expected.gegenparteiName] + (expected.acceptedCounterparties ?? []))
            .compactMap { normalized($0) }
        let actualCounterparty = normalized(actual.gegenparteiName)
        if actualCounterparty.map({ counterparties.contains($0) }) != true {
            findings
                .append(
                    "gegenpartei_name: expected one of \(counterparties.sorted()), got \(normalized(actual.gegenparteiName) ?? "nil")"
                )
        }
        let countries = Set([expected.gegenparteiLand] + (expected.acceptedCountries ?? []))
        if countries.contains(actual.gegenparteiLand ?? "") == false {
            findings
                .append(
                    "gegenpartei_land: expected one of \(countries.sorted()), got \(actual.gegenparteiLand ?? "nil")"
                )
        }
        let categories = Set([expected.kategorie] + (expected.acceptedCategories ?? []))
        if actual.kategorie.map(categories.contains) != true {
            findings.append("kategorie: expected one of \(categories.sorted()), got \(actual.kategorie ?? "nil")")
        }
        if let tax = expected.steuerbehandlung {
            check("steuerbehandlung", actual.steuerbehandlung?.rawValue, tax)
        }
        if let privateShare = expected.privatanteilProzent, actual.privatanteilProzent != privateShare {
            findings.append("privatanteil_prozent: expected \(privateShare), got \(actual.privatanteilProzent)")
        }
        if expected.nutzungsdauerJahre != nil || item.strictNulls == true,
           actual.nutzungsdauerJahre != expected.nutzungsdauerJahre
        {
            findings
                .append(
                    "nutzungsdauer_jahre: expected \(String(describing: expected.nutzungsdauerJahre)), got \(String(describing: actual.nutzungsdauerJahre))"
                )
        }
        if expected.waehrung != nil || item.strictNulls == true {
            check("waehrung", actual.waehrung, expected.waehrung)
        }
        if let original = expected.originalbetrag {
            if actual.originalbetrag != Decimal(string: original) {
                findings
                    .append("originalbetrag: expected \(original), got \(String(describing: actual.originalbetrag))")
            }
        } else if item.strictNulls == true, actual.originalbetrag != nil {
            findings.append("originalbetrag: expected nil, got \(String(describing: actual.originalbetrag))")
        }
        let conversionTolerance = item.convertedEurToleranceCents
        if let net = expected
            .nettoCents
        {
            amount("netto_cents", actual.netto.value, net, tolerance: conversionTolerance)
        }
        if let tax = expected.steuerCents {
            amount("steuer_cents", actual.steuer.value, tax)
        }
        if let gross = expected.bruttoCents {
            amount(
                "brutto_cents",
                actual.brutto.value,
                gross,
                tolerance: conversionTolerance
            )
        }

        let actualRates = Dictionary(
            grouping: actual.positionen,
            by: { NSDecimalNumber(decimal: $0.steuersatz).stringValue }
        )
        if let targetRates = expected.positionenNachSatz {
            if actualRates.count != targetRates.count {
                findings.append("steuersaetze: expected \(targetRates.count) groups, got \(actualRates.count)")
            }
            for target in targetRates {
                let accepted = [target.steuersatz] + (target.acceptedRates ?? [])
                guard let rate = accepted.first(where: { actualRates[$0] != nil }),
                      let positions = actualRates[rate]
                else {
                    findings.append("steuersatz: expected one of \(accepted), got \(actualRates.keys.sorted())")
                    continue
                }
                if let net = target.nettoCents {
                    amount(
                        "satz \(rate) netto",
                        positions.reduce(0) { $0 + $1.netto.value },
                        net,
                        tolerance: conversionTolerance
                    )
                }
                if let tax = target.steuerCents {
                    amount("satz \(rate) steuer", positions.reduce(0) { $0 + $1.steuer.value }, tax)
                }
            }
        }
        if let payments = expected.zahlungen {
            let actualDates = actual.zahlungen.map(\.datum.description).sorted()
            let expectedDates = payments.map(\.datum).sorted()
            if actualDates != expectedDates {
                findings.append("zahlungsdaten: expected \(expectedDates), got \(actualDates)")
            }
            for payment in payments {
                guard let amount = payment.betrag else { continue }
                let actualAmounts = actual.zahlungen.filter { $0.datum.description == payment.datum }
                    .map(\.betrag.value)
                if actualAmounts != [amount] {
                    findings.append("zahlung \(payment.datum): expected \(amount), got \(actualAmounts)")
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

    private static func normalized(_ value: String?) -> String? {
        value?.split(whereSeparator: \.isWhitespace).joined(separator: " ").folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "de_DE")
        )
    }
}
