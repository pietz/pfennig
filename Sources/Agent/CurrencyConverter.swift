import Core
import Foundation

/// The result of one historical foreign-currency lookup. The rate is fetched
/// once and all supplied major-unit amounts are converted locally to EUR cents.
public struct ConversionResult: Codable, Hashable, Sendable {
    public let waehrung: String
    public let requestedDate: LocalDate
    public let rateDate: LocalDate
    public let kurs: Decimal
    public let eurCent: [Int64]
    public let source: String

    public var notiz: String {
        let rateText = NSDecimalNumber(decimal: kurs)
            .description(withLocale: Locale(identifier: "en_US_POSIX"))
        return "\(source), \(waehrung)/EUR, Kurs \(rateText), Kursdatum \(rateDate)."
    }
}

/// The only network-backed tool besides OpenAI's Responses request. Frankfurter
/// supplies rates only; this type performs the Decimal conversion in Swift.
public enum CurrencyConverter {
    public static let source = "Frankfurter reference rate (default blended)"
    static let endpoint = URL(string: "https://api.frankfurter.dev/v2")!

    private struct Rate: Decodable {
        let date: LocalDate
        let base: String
        let quote: String
        let rate: Decimal
    }

    public enum ConversionError: Error, LocalizedError {
        case invalidArguments
        case network(String)
        case api(status: Int, text: String)
        case unreadableResponse
        case amountTooLarge

        public var errorDescription: String? {
            switch self {
            case .invalidArguments:
                "waehrung, datum und betraege müssen gültig sein."
            case let .network(text):
                "Die Frankfurter-Verbindung kam nicht zustande: \(text)"
            case let .api(status, text):
                "Frankfurter hat mit \(status) geantwortet: \(text)"
            case .unreadableResponse:
                "Frankfurter hat keine lesbare Kursantwort geliefert."
            case .amountTooLarge:
                "Ein Betrag passt nicht in EUR-Cent."
            }
        }
    }

    /// Fetches one pair and converts every amount with exact Decimal arithmetic.
    public static func calculate(
        waehrung: String,
        datum: LocalDate,
        betraege: [Decimal],
        transport: @escaping Transport
    ) async throws -> ConversionResult {
        let code = waehrung.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3,
              code.unicodeScalars.allSatisfy({ ("A" ... "Z").contains($0) })
        else { throw ConversionError.invalidArguments }

        var components = URLComponents(
            url: endpoint.appending(path: "rate/\(code)/EUR"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "date", value: datum.description)]
        guard let url = components?.url else { throw ConversionError.invalidArguments }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch let failure as ConversionError {
            throw failure
        } catch {
            throw ConversionError.network(error.localizedDescription)
        }
        guard response.statusCode == 200 else {
            throw ConversionError.api(
                status: response.statusCode,
                text: Self.errorText(data) ?? String(decoding: data.prefix(400), as: UTF8.self)
            )
        }
        guard let rate = try? JSONDecoder().decode(Rate.self, from: data),
              rate.base.uppercased() == code,
              rate.quote.uppercased() == "EUR",
              rate.rate > 0
        else { throw ConversionError.unreadableResponse }

        let hundred = Decimal(100)
        let eurCent = try betraege.map { amount in
            var raw = amount * rate.rate * hundred
            var rounded = Decimal()
            NSDecimalRound(&rounded, &raw, 0, .plain)
            let number = NSDecimalNumber(decimal: rounded)
            guard number.compare(NSDecimalNumber(value: Int64.min)) != .orderedAscending,
                  number.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending
            else { throw ConversionError.amountTooLarge }
            return number.int64Value
        }

        return ConversionResult(
            waehrung: code,
            requestedDate: datum,
            rateDate: rate.date,
            kurs: rate.rate,
            eurCent: eurCent,
            source: source
        )
    }

    /// Dispatches the JSON arguments of the Responses function tool and always
    /// returns a short tool answer. A rate failure is an answer to the agent;
    /// the existing agent and Inbox error path handles an unresolved run.
    public static func execute(_ arguments: String, transport: @escaping Transport) async -> String {
        do {
            guard let data = arguments.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let waehrung = object["waehrung"] as? String,
                  let dateText = object["datum"] as? String,
                  let datum = LocalDate(dateText),
                  let rawAmounts = object["betraege"] as? [Any],
                  rawAmounts.isEmpty == false
            else { throw ConversionError.invalidArguments }

            let betraege = try rawAmounts.map { value -> Decimal in
                guard let text = value as? String, let amount = Decimal(text: text) else {
                    throw ConversionError.invalidArguments
                }
                return amount
            }
            let result = try await calculate(
                waehrung: waehrung, datum: datum, betraege: betraege, transport: transport
            )
            return try Self.text(result)
        } catch let failure as ConversionError {
            return "Fehler: \(failure.localizedDescription)"
        } catch {
            return "Fehler: Die Umrechnung konnte nicht ausgeführt werden: \(error.localizedDescription)"
        }
    }

    private static func text(_ result: ConversionResult) throws -> String {
        let object: [String: Any] = [
            "waehrung": result.waehrung,
            "angefordertes_datum": result.requestedDate.description,
            "kursdatum": result.rateDate.description,
            "kurs": NSDecimalNumber(decimal: result.kurs)
                .description(withLocale: Locale(identifier: "en_US_POSIX")),
            "quelle": result.source,
            "eur_cent": result.eurCent,
            "notiz": result.notiz
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func errorText(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["message"] as? String ?? (object["error"] as? [String: Any])?["message"] as? String
    }
}
