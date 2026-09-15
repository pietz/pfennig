import Foundation
import Kern

/// The file as it goes to the model: PDF and images as base64 data URLs, CSV
/// as plain text. Nothing is prepared or converted, the file goes as it is.
public struct Dateieingabe: Sendable {
    public var name: String
    public var endung: String
    public var sha256: String
    public var daten: Data

    public init(name: String, endung: String, sha256: String, daten: Data) {
        self.name = name
        self.endung = endung
        self.sha256 = sha256
        self.daten = daten
    }

    /// No HEIC: the API does not take it, and Pfennig converts nothing.
    static let erlaubteEndungen = ["pdf", "png", "jpg", "jpeg", "csv"]

    var medientyp: String {
        switch endung.lowercased() {
        case "pdf": "application/pdf"
        case "png": "image/png"
        case "csv": "text/csv"
        default: "image/jpeg"
        }
    }

    /// One content item of the user message.
    var inhalt: [String: Any] {
        let datenadresse = "data:\(medientyp);base64,\(daten.base64EncodedString())"
        switch endung.lowercased() {
        case "pdf":
            return ["type": "input_file", "filename": name, "file_data": datenadresse]
        case "csv":
            return ["type": "input_text", "text": String(decoding: daten, as: UTF8.self)]
        default:
            return ["type": "input_image", "image_url": datenadresse, "detail": "high"]
        }
    }
}

/// What one run left behind.
public struct Laufergebnis: Sendable {
    public var beruehrt: [Int64] = []
    public var angelegt: [Int64] = []
    public var zusammenfassung = ""
}

/// A run that gave up, with the bookings it had already written. Swift removes
/// them before the file is tried again, so nothing doubles.
public struct Laufabbruch: Error, LocalizedError {
    public var angelegt: [Int64]
    public var grund: any Error

    public var errorDescription: String? {
        grund.localizedDescription
    }
}

/// One file, one run: the tool loop over the Responses API. The model is fixed
/// in the code, there is no choice in the settings.
public struct Agentenlauf: Sendable {
    public static let hoechstzahlWerkzeugaufrufe = 25

    let repository: Repository
    let werkzeug: Werkzeug
    /// Read once per run from the Keychain, never kept anywhere else.
    let schluessel: String
    let transport: Transport

    public init(
        repository: Repository,
        werkzeug: Werkzeug,
        schluessel: String,
        transport: @escaping Transport = Responses.netz
    ) {
        self.repository = repository
        self.werkzeug = werkzeug
        self.schluessel = schluessel
        self.transport = transport
    }

    /// The SQL tool the agent gets, in the shape the Responses API expects.
    static var werkzeugbeschreibung: [String: Any] {
        [
            "type": "function",
            "name": "sql",
            "description": """
            Führt genau eine SQL-Anweisung auf der Buchhaltungsdatenbank aus. \(Werkzeug.erlaubt) Ein \
            SELECT antwortet mit den Zeilen als JSON, ein Schreibvorgang mit den berührten Buchungs-IDs \
            oder mit dem Text der verletzten Prüfregel.
            """,
            "parameters": [
                "type": "object",
                "properties": ["sql": ["type": "string", "description": "Eine einzelne SQL-Anweisung."]],
                "required": ["sql"],
                "additionalProperties": false
            ],
            "strict": true
        ]
    }

    /// The sole additional tool: it receives original major-unit amounts and
    /// returns their EUR cents plus the reference-rate provenance.
    static var umrechnenbeschreibung: [String: Any] {
        [
            "type": "function",
            "name": "umrechnen",
            "description": "Holt einmal den historischen Frankfurter-Referenzkurs für eine Währung und ein Datum und rechnet alle gelieferten Originalbeträge in EUR-Cent um. Die API bekommt nur Währung und Datum; die Beträge werden lokal mit Decimal gerechnet.",
            "parameters": [
                "type": "object",
                "properties": [
                    "waehrung": [
                        "type": "string",
                        "description": "Dreistelliger ISO-Währungscode, zum Beispiel USD oder JPY."
                    ],
                    "datum": ["type": "string", "description": "Kursdatum als JJJJ-MM-TT."],
                    "betraege": [
                        "type": "array",
                        "description": "Originalbeträge in exakten Haupteinheiten als Dezimaltexte, ohne Währungssymbol.",
                        "items": ["type": "string"]
                    ]
                ],
                "required": ["waehrung", "datum", "betraege"],
                "additionalProperties": false
            ],
            "strict": true
        ]
    }

    /// Runs the loop and records it in `anfragen`, whatever the outcome.
    public func starten(_ datei: Dateieingabe) async throws -> Laufergebnis {
        let anleitung = try Anleitung.bauen(repository)
        let ki = try repository.kiEinstellungen()
        let anfrage = try repository.anfrageStarten(dateiSha256: datei.sha256, modell: ki.modell.rawValue)
        var protokoll = Protokoll()
        var ergebnis = Laufergebnis()
        do {
            try await schleife(datei, ki: ki, anleitung: anleitung, ergebnis: &ergebnis, protokoll: &protokoll)
            guard ergebnis.beruehrt.isEmpty == false else {
                throw Agentenfehler.keineBuchung
            }
            try repository.anfrageBeenden(
                id: anfrage, status: .erfolg, eingabeTokens: protokoll.eingabeTokens,
                ausgabeTokens: protokoll.ausgabeTokens, konversation: protokoll.alsJSON()
            )
            return ergebnis
        } catch {
            protokoll.schritte.append(["fehler": error.localizedDescription])
            try? repository.anfrageBeenden(
                id: anfrage, status: .fehler, eingabeTokens: protokoll.eingabeTokens,
                ausgabeTokens: protokoll.ausgabeTokens, konversation: protokoll.alsJSON()
            )
            throw Laufabbruch(angelegt: ergebnis.angelegt, grund: error)
        }
    }

    private func schleife(
        _ datei: Dateieingabe,
        ki: KiEinstellungen,
        anleitung: String,
        ergebnis: inout Laufergebnis,
        protokoll: inout Protokoll
    ) async throws {
        let client = Responses(schluessel: schluessel, transport: transport)
        var aufrufe = 0
        var vorherigeAntwort: String?
        var eingabe: [[String: Any]] = [
            ["role": "system", "content": anleitung],
            ["role": "user", "content": [
                datei.inhalt,
                ["type": "input_text", "text": "Verbuche dieses Dokument."]
            ]]
        ]

        while true {
            var koerper: [String: Any] = [
                "model": ki.modell.rawValue,
                "reasoning": ["effort": ki.aufwand.rawValue],
                "tools": [Agentenlauf.werkzeugbeschreibung, Agentenlauf.umrechnenbeschreibung],
                "input": eingabe
            ]
            if ki.schnell {
                // OpenAI's priority processing, about twice the price.
                koerper["service_tier"] = "priority"
            }
            if let vorherigeAntwort {
                koerper["previous_response_id"] = vorherigeAntwort
            }
            let antwort = try await client.senden(koerper)
            protokoll.zaehle(antwort)
            vorherigeAntwort = antwort["id"] as? String
            try Agentenlauf.pruefeStatus(antwort)

            let aufrufeDerRunde = Agentenlauf.werkzeugaufrufe(antwort)
            guard aufrufeDerRunde.isEmpty == false else {
                ergebnis.zusammenfassung = Agentenlauf.text(antwort)
                protokoll.schritte.append(["agent": ergebnis.zusammenfassung])
                return
            }
            aufrufe += aufrufeDerRunde.count
            guard aufrufe <= Agentenlauf.hoechstzahlWerkzeugaufrufe else {
                throw Agentenfehler.zuVieleWerkzeugaufrufe
            }

            eingabe = []
            for aufruf in aufrufeDerRunde {
                let text: String
                switch aufruf.name {
                case "sql":
                    let sql = Agentenlauf.sql(aufruf.arguments)
                    let werkzeugergebnis = werkzeug.ausfuehren(sql)
                    ergebnis.beruehrt = Array(Set(ergebnis.beruehrt).union(werkzeugergebnis.beruehrt)).sorted()
                    ergebnis.angelegt = Array(Set(ergebnis.angelegt).union(werkzeugergebnis.angelegt)).sorted()
                    text = werkzeugergebnis.text
                case "umrechnen":
                    text = await Umrechnen.ausfuehren(aufruf.arguments, transport: transport)
                default:
                    text = "Fehler: Unbekanntes Werkzeug \(aufruf.name). Verwende sql oder umrechnen."
                }
                let schritt = [
                    "werkzeug": aufruf.name,
                    "argumente": aufruf.arguments,
                    "ergebnis": text
                ]
                protokoll.schritte.append(schritt)
                eingabe.append([
                    "type": "function_call_output",
                    "call_id": aufruf.callId,
                    "output": text
                ])
            }
        }
    }

    // MARK: - Antwort lesen

    struct Werkzeugaufruf {
        var name: String
        var callId: String
        var arguments: String
    }

    /// `output` is an array of items, not a single message: a run answers with
    /// reasoning items, `function_call` items and at most one `message`.
    static func werkzeugaufrufe(_ antwort: [String: Any]) -> [Werkzeugaufruf] {
        ausgabe(antwort).compactMap { teil in
            guard teil["type"] as? String == "function_call",
                  let callId = teil["call_id"] as? String
            else { return nil }
            return Werkzeugaufruf(
                name: teil["name"] as? String ?? "",
                callId: callId,
                arguments: teil["arguments"] as? String ?? "{}"
            )
        }
    }

    static func text(_ antwort: [String: Any]) -> String {
        for teil in ausgabe(antwort) where teil["type"] as? String == "message" {
            for stueck in (teil["content"] as? [[String: Any]]) ?? [] {
                if let text = stueck["text"] as? String, stueck["type"] as? String == "output_text" {
                    return text
                }
            }
        }
        return ""
    }

    static func pruefeStatus(_ antwort: [String: Any]) throws {
        let status = antwort["status"] as? String ?? "completed"
        guard status != "completed" else { return }
        let grund = (antwort["incomplete_details"] as? [String: Any])?["reason"] as? String
        throw Agentenfehler.antwort("Der Lauf endete mit Status \(status)\(grund.map { ", Grund \($0)" } ?? ".")")
    }

    /// The model hands the arguments over as a JSON string.
    static func sql(_ arguments: String) -> String {
        guard let daten = arguments.data(using: .utf8),
              let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let sql = objekt["sql"] as? String
        else { return "" }
        return sql
    }

    private static func ausgabe(_ antwort: [String: Any]) -> [[String: Any]] {
        antwort["output"] as? [[String: Any]] ?? []
    }
}

/// What goes into `anfragen.konversation`: the text and the tool exchange,
/// never the bytes of the file.
struct Protokoll {
    var schritte: [[String: String]] = []
    var eingabeTokens = 0
    var ausgabeTokens = 0

    mutating func zaehle(_ antwort: [String: Any]) {
        guard let verbrauch = antwort["usage"] as? [String: Any] else { return }
        eingabeTokens += verbrauch["input_tokens"] as? Int ?? 0
        ausgabeTokens += verbrauch["output_tokens"] as? Int ?? 0
    }

    func alsJSON() -> String {
        guard let daten = try? JSONSerialization.data(withJSONObject: schritte, options: [.withoutEscapingSlashes])
        else { return "[]" }
        return String(decoding: daten, as: UTF8.self)
    }
}
