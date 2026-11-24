import Core
import Foundation

enum TaxEvaluation {
    static var description: [String: Any] {
        [
            "type": "function",
            "name": "steuerauswertung",
            "description": """
            Berechnet die UStVA oder EÜR anhand der aktuellen Buchungen und des Profils mit der Formularzuordnung 2026. \
            Liefert Formularzeilen, Summen, Buchungsbeiträge und Prüfhinweise. Beträge sind in EUR-Cent. \
            Das Werkzeug liest nur. Für UStVA genau einen Monat oder ein Quartal angeben, für EÜR beide auf null setzen.
            """,
            "parameters": [
                "type": "object",
                "properties": [
                    "art": ["type": "string", "enum": ["ustva", "euer"]],
                    "jahr": ["type": "integer"],
                    "monat": ["type": ["integer", "null"], "description": "1 bis 12 oder null."],
                    "quartal": ["type": ["integer", "null"], "description": "1 bis 4 oder null."]
                ],
                "required": ["art", "jahr", "monat", "quartal"],
                "additionalProperties": false
            ],
            "strict": true
        ]
    }

    private struct Arguments: Decodable {
        let art: Zeitraumart
        let jahr: Int
        let monat: Int?
        let quartal: Int?

        var zeitraum: Zeitraum? {
            guard (1 ... 9999).contains(jahr) else { return nil }
            let einteilung: Zeitraum.Einteilung
            switch (art, monat, quartal) {
            case (.euer, nil, nil): einteilung = .jahr
            case let (.ustva, monat?, nil) where (1 ... 12).contains(monat): einteilung = .monat(monat)
            case let (.ustva, nil, quartal?) where (1 ... 4).contains(quartal): einteilung = .quartal(quartal)
            default: return nil
            }
            return Zeitraum(jahr: jahr, einteilung: einteilung)
        }
    }

    private struct Betrag: Encodable {
        let titel: String
        let betrag: Cent
    }

    private struct Zeile: Encodable {
        let nummer: Int
        let titel: String
        let betrag: Cent
        let buchungsbeitraege: [Buchungsbeitrag]
        var rundungsdifferenz: Cent?
        var profilbeitrag: Betrag?
        var richtung: Richtung?
        var nichtAbziehbar: Bool?
    }

    private struct Komponente: Encodable {
        let kennzahl: Int
        let betrag: Cent
    }

    private struct Auswertung: Encodable {
        let art: Zeitraumart
        let zeitraum: String
        let zeilen: [Zeile]
        let summen: [String: Cent]
        let zahllastKomponenten: [Komponente]?
        let ungepruefteBuchungen: Int
        let buchungenOhneSteuerbehandlung: Int
    }

    static func execute(_ arguments: String, repository: Repository) -> String {
        guard let arguments = try? JSONDecoder().decode(Arguments.self, from: Data(arguments.utf8)),
              let zeitraum = arguments.zeitraum
        else {
            return "Fehler: Jahr und Art angeben. Für UStVA genau einen Monat (1–12) oder ein Quartal (1–4) angeben, für EÜR keines von beiden."
        }

        do {
            let (buchungen, profil) = try repository.taxSnapshot()
            let zeilen: [Zeile]
            let summen: [String: Cent]
            let komponenten: [Komponente]?
            switch zeitraum.art {
            case .ustva:
                let auswertung = UStVA.calculate(buchungen, zeitraum: zeitraum, profile: profil)
                zeilen = auswertung.zeilen.map { zeile in
                    Zeile(
                        nummer: zeile.id, titel: zeile.kennzahl.titel, betrag: zeile.meldebetrag,
                        buchungsbeitraege: zeile.buchungsbeitraege,
                        rundungsdifferenz: zeile.rundungsdifferenz == .null ? nil : zeile.rundungsdifferenz,
                        profilbeitrag: zeile.profilbetrag.map { Betrag(titel: "Sondervorauszahlung", betrag: $0) }
                    )
                }
                summen = ["zahllast": auswertung.zahllast]
                komponenten = auswertung.zeilen.compactMap { zeile in
                    zeile.zahllastbeitrag.map { Komponente(kennzahl: zeile.id, betrag: $0) }
                }
            case .euer:
                let auswertung = EUeR.calculate(buchungen, jahr: zeitraum.jahr, profile: profil)
                zeilen = auswertung.zeilen.map { zeile in
                    let differenz = zeile.rundungsdifferenz
                    return Zeile(
                        nummer: zeile.zeile, titel: zeile.bezeichnung, betrag: zeile.betrag,
                        buchungsbeitraege: zeile.buchungsbeitraege,
                        rundungsdifferenz: differenz == .null ? nil : differenz,
                        richtung: zeile.richtung, nichtAbziehbar: zeile.nichtAbziehbar
                    )
                }
                summen = [
                    "einnahmen": auswertung.einnahmen,
                    "ausgaben": auswertung.ausgaben,
                    "gewinn": auswertung.ergebnis
                ]
                komponenten = nil
            }
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try String(decoding: encoder.encode(Auswertung(
                art: zeitraum.art,
                zeitraum: zeitraum.name,
                zeilen: zeilen,
                summen: summen,
                zahllastKomponenten: komponenten,
                ungepruefteBuchungen: zeitraum.ungeprueft(buchungen, profile: profil),
                buchungenOhneSteuerbehandlung: zeitraum.fehlendeSteuerbehandlungen(buchungen, profile: profil)
            )), as: UTF8.self)
        } catch {
            return "Fehler: Steuerauswertung konnte nicht gelesen werden. \(error.localizedDescription)"
        }
    }
}
