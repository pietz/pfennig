import Foundation
import Kern

/// The result of one historical foreign-currency lookup. The rate is fetched
/// once and all supplied major-unit amounts are converted locally to EUR cents.
public struct Umrechnungsergebnis: Codable, Hashable, Sendable {
    public let waehrung: String
    public let angefordertesDatum: Datum
    public let kursdatum: Datum
    public let kurs: Decimal
    public let eurCent: [Int64]
    public let quelle: String

    public var notiz: String {
        let kursText = NSDecimalNumber(decimal: kurs)
            .description(withLocale: Locale(identifier: "en_US_POSIX"))
        return "\(quelle), \(waehrung)/EUR, Kurs \(kursText), Kursdatum \(kursdatum)."
    }
}

/// The only network-backed tool besides OpenAI's Responses request. Frankfurter
/// supplies rates only; this type performs the Decimal conversion in Swift.
public enum Umrechnen {
    public static let quelle = "Frankfurter reference rate (default blended)"
    static let adresse = URL(string: "https://api.frankfurter.dev/v2")!

    private struct Rate: Decodable {
        let date: Datum
        let base: String
        let quote: String
        let rate: Decimal
    }

    public enum Fehler: Error, LocalizedError {
        case ungueltigeArgumente
        case netzwerk(String)
        case api(status: Int, text: String)
        case unbrauchbareAntwort
        case betragZuGross

        public var errorDescription: String? {
            switch self {
            case .ungueltigeArgumente:
                "waehrung, datum und betraege müssen gültig sein."
            case let .netzwerk(text):
                "Die Frankfurter-Verbindung kam nicht zustande: \(text)"
            case let .api(status, text):
                "Frankfurter hat mit \(status) geantwortet: \(text)"
            case .unbrauchbareAntwort:
                "Frankfurter hat keine lesbare Kursantwort geliefert."
            case .betragZuGross:
                "Ein Betrag passt nicht in EUR-Cent."
            }
        }
    }

    /// Fetches one pair and converts every amount with exact Decimal arithmetic.
    public static func berechnen(
        waehrung: String,
        datum: Datum,
        betraege: [Decimal],
        transport: @escaping Transport
    ) async throws -> Umrechnungsergebnis {
        let code = waehrung.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3,
              code.unicodeScalars.allSatisfy({ ("A" ... "Z").contains($0) })
        else { throw Fehler.ungueltigeArgumente }

        var komponenten = URLComponents(
            url: adresse.appending(path: "rate/\(code)/EUR"),
            resolvingAgainstBaseURL: false
        )
        komponenten?.queryItems = [URLQueryItem(name: "date", value: datum.description)]
        guard let url = komponenten?.url else { throw Fehler.ungueltigeArgumente }

        var anfrage = URLRequest(url: url)
        anfrage.httpMethod = "GET"
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")

        let daten: Data
        let antwort: HTTPURLResponse
        do {
            (daten, antwort) = try await transport(anfrage)
        } catch let fehler as Fehler {
            throw fehler
        } catch {
            throw Fehler.netzwerk(error.localizedDescription)
        }
        guard antwort.statusCode == 200 else {
            throw Fehler.api(
                status: antwort.statusCode,
                text: Self.fehlertext(daten) ?? String(decoding: daten.prefix(400), as: UTF8.self)
            )
        }
        guard let rate = try? JSONDecoder().decode(Rate.self, from: daten),
              rate.base.uppercased() == code,
              rate.quote.uppercased() == "EUR",
              rate.rate > 0
        else { throw Fehler.unbrauchbareAntwort }

        let hundert = Decimal(100)
        let eurCent = try betraege.map { betrag in
            var roh = betrag * rate.rate * hundert
            var gerundet = Decimal()
            NSDecimalRound(&gerundet, &roh, 0, .plain)
            let zahl = NSDecimalNumber(decimal: gerundet)
            guard zahl.compare(NSDecimalNumber(value: Int64.min)) != .orderedAscending,
                  zahl.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending
            else { throw Fehler.betragZuGross }
            return zahl.int64Value
        }

        return Umrechnungsergebnis(
            waehrung: code,
            angefordertesDatum: datum,
            kursdatum: rate.date,
            kurs: rate.rate,
            eurCent: eurCent,
            quelle: quelle
        )
    }

    /// Dispatches the JSON arguments of the Responses function tool and always
    /// returns a short tool answer. A rate failure is an answer to the agent;
    /// the existing agent and Inbox error path handles an unresolved run.
    public static func ausfuehren(_ argumente: String, transport: @escaping Transport) async -> String {
        do {
            guard let daten = argumente.data(using: .utf8),
                  let objekt = try JSONSerialization.jsonObject(with: daten) as? [String: Any],
                  let waehrung = objekt["waehrung"] as? String,
                  let datumtext = objekt["datum"] as? String,
                  let datum = Datum(datumtext),
                  let roheBetrage = objekt["betraege"] as? [Any],
                  roheBetrage.isEmpty == false
            else { throw Fehler.ungueltigeArgumente }

            let betraege = try roheBetrage.map { wert -> Decimal in
                guard let text = wert as? String, let betrag = Decimal(text: text) else {
                    throw Fehler.ungueltigeArgumente
                }
                return betrag
            }
            let ergebnis = try await berechnen(
                waehrung: waehrung, datum: datum, betraege: betraege, transport: transport
            )
            return try Self.text(ergebnis)
        } catch let fehler as Fehler {
            return "Fehler: \(fehler.localizedDescription)"
        } catch {
            return "Fehler: Die Umrechnung konnte nicht ausgeführt werden: \(error.localizedDescription)"
        }
    }

    private static func text(_ ergebnis: Umrechnungsergebnis) throws -> String {
        let objekt: [String: Any] = [
            "waehrung": ergebnis.waehrung,
            "angefordertes_datum": ergebnis.angefordertesDatum.description,
            "kursdatum": ergebnis.kursdatum.description,
            "kurs": NSDecimalNumber(decimal: ergebnis.kurs)
                .description(withLocale: Locale(identifier: "en_US_POSIX")),
            "quelle": ergebnis.quelle,
            "eur_cent": ergebnis.eurCent,
            "notiz": ergebnis.notiz
        ]
        let daten = try JSONSerialization.data(withJSONObject: objekt, options: [.withoutEscapingSlashes])
        return String(decoding: daten, as: UTF8.self)
    }

    private static func fehlertext(_ daten: Data) -> String? {
        guard let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any] else { return nil }
        return objekt["message"] as? String ?? (objekt["error"] as? [String: Any])?["message"] as? String
    }
}
