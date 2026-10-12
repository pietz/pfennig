import Agent
import Core
import Foundation
import FoundationModels
import ImageIO
import PDFKit
import Vision

@Generable struct VATFacts: Codable {
    @Guide(description: "Umsatzsteuersatz in Prozent als Dezimaltext, z.B. 19 oder 7.") var rate: String
    @Guide(
        description: "Ausgewiesener Nettobetrag dieser Steuergruppe in EUR, Dezimalpunkt, z.B. 12.34."
    ) var net: String?
    @Guide(description: "Ausgewiesener Steuerbetrag dieser Gruppe in EUR, Dezimalpunkt.") var tax: String?
}

@Generable struct Facts: Codable {
    @Guide(description: "Belegdatum als YYYY-MM-DD. Deutsche Datumsangaben sind Tag.Monat.Jahr.") var date: String?
    @Guide(description: "Aussteller/Lieferant, nicht Rechnungsempfänger.") var issuer: String?
    var number: String?
    @Guide(description: "Ausgewiesene Gesamtsumme netto in EUR mit Dezimalpunkt.") var net: String?
    @Guide(description: "Ausgewiesene gesamte Umsatzsteuer in EUR mit Dezimalpunkt.") var tax: String?
    @Guide(description: "Ausgewiesene Endsumme brutto in EUR mit Dezimalpunkt.") var gross: String?
    @Guide(
        description: "Die verschiedenen ausgewiesenen Umsatzsteuersätze mit ihren Beträgen.",
        .maximumCount(8)
    ) var vat: [VATFacts]
}

@Generable struct StrictVATFacts: Codable {
    @Guide(description: "Umsatzsteuersatz in Prozent als Dezimaltext, z.B. 19 oder 7.") @Guide(
        .pattern(#/[0-9]+(?:\.[0-9]+)?/#)
    ) var rate: String
    @Guide(description: "Ausgewiesener Nettobetrag dieser Steuergruppe in EUR, Dezimalpunkt, z.B. 12.34.") @Guide(
        .pattern(#/-?[0-9]+\.[0-9]{2}/#)
    ) var net: String?
    @Guide(description: "Ausgewiesener Steuerbetrag dieser Gruppe in EUR, Dezimalpunkt.") @Guide(
        .pattern(#/-?[0-9]+\.[0-9]{2}/#)
    ) var tax: String?
}

@Generable struct StrictFacts: Codable {
    @Guide(description: "Belegdatum als YYYY-MM-DD. Deutsche Datumsangaben sind Tag.Monat.Jahr.") @Guide(
        .pattern(#/[0-9]{4}-[0-9]{2}-[0-9]{2}/#)
    ) var date: String?
    @Guide(description: "Aussteller/Lieferant, nicht Rechnungsempfänger.") var issuer: String?
    var number: String?
    @Guide(description: "Ausgewiesene Gesamtsumme netto in EUR mit Dezimalpunkt.") @Guide(
        .pattern(#/-?[0-9]+\.[0-9]{2}/#)
    ) var net: String?
    @Guide(description: "Ausgewiesene gesamte Umsatzsteuer in EUR mit Dezimalpunkt.") @Guide(
        .pattern(#/-?[0-9]+\.[0-9]{2}/#)
    ) var tax: String?
    @Guide(description: "Ausgewiesene Endsumme brutto in EUR mit Dezimalpunkt.") @Guide(
        .pattern(#/-?[0-9]+\.[0-9]{2}/#)
    ) var gross: String?
    @Guide(
        description: "Die verschiedenen ausgewiesenen Umsatzsteuersätze mit ihren Beträgen.",
        .maximumCount(8)
    ) var vat: [StrictVATFacts]
}

@Generable struct Datum: Codable {
    @Guide(.range(1900 ... 2100)) var jahr: Int
    @Guide(.range(1 ... 12)) var monat: Int
    @Guide(.range(1 ... 31)) var tag: Int
}

@Generable struct Nettozeile: Codable {
    @Guide(
        description: "Eine ausgewiesene Nettozeile oder die ausgewiesene Netto-Gesamtsumme bei nur einem Steuersatz. Geld in ganzen EUR-Cent, z.B.12,34 EUR=1234."
    ) var nettoCent: Int
    @Guide(
        description: "Ausgewiesener Umsatzsteuersatz dieser Nettozeile in Prozent, z.B.7 oder19."
    ) var steuersatz: Int
}

@Generable struct BelegFakten: Codable {
    @Guide(
        description: "Belegdatum, nicht Aufenthalts- oder Zahlungsdatum. Deutsche Reihenfolge: Tag,Monat,Jahr."
    ) var datum: Datum?
    var aussteller: String?
    var belegnummer: String?
    @Guide(description: "Ausgewiesene Endsumme netto in ganzen EUR-Cent.") var gesamtNettoCent: Int?
    @Guide(description: "Ausgewiesene gesamte Umsatzsteuer in ganzen EUR-Cent.") var gesamtSteuerCent: Int?
    @Guide(description: "Ausgewiesene Endsumme brutto in ganzen EUR-Cent.") var gesamtBruttoCent: Int?
    @Guide(
        description: "Nur ausgewiesene Nettobeträge mit ihrem Steuersatz. Sind nur Netto-Gesamtsumme und ein Satz ausgewiesen, eine Zeile für die Gesamtsumme. Keine Bruttobeträge hier.",
        .maximumCount(12)
    ) var nettozeilen: [Nettozeile]
    func normalized() -> Facts {
        let text: (Int?) -> String? = { $0.map { NSDecimalNumber(decimal: Cent(Int64($0)).betrag).stringValue } }
        var groups: [Int: (Cent, Cent)] = [:]
        for line in nettozeilen {
            let net = Cent(Int64(line.nettoCent))
            let tax = Position.steuer(netto: net, steuersatz: Decimal(line.steuersatz))
            let previous = groups[line.steuersatz] ?? (.null, .null)
            groups[line.steuersatz] = (previous.0 + net, previous.1 + tax)
        }
        return Facts(
            date: datum.map { String(format: "%04d-%02d-%02d", $0.jahr, $0.monat, $0.tag) },
            issuer: aussteller,
            number: belegnummer,
            net: text(gesamtNettoCent),
            tax: text(gesamtSteuerCent),
            gross: text(gesamtBruttoCent),
            vat: groups.sorted { $0.key < $1.key }.map { VATFacts(
                rate: String($0.key),
                net: NSDecimalNumber(decimal: $0.value.0.betrag).stringValue,
                tax: NSDecimalNumber(decimal: $0.value.1.betrag).stringValue
            ) }
        )
    }
}

@Generable struct Eurobetrag: Codable {
    @Guide(description: "Ganze Euro, z.B.123 bei123,00EUR oder12 bei12,34EUR.", .range(0 ... 100_000_000)) var euro: Int
    @Guide(description: "Cent-Nachkommastellen, z.B.0 bei123,00EUR oder34 bei12,34EUR.", .range(0 ... 99)) var cent: Int
    var money: Cent {
        Cent(Int64(euro) * 100 + Int64(cent))
    }
}

@Generable struct Leistungszeile: Codable {
    @Guide(
        description: "Name der tatsächlichen Leistung/Artikelzeile, nie Netto/Gesamt/Steuerübersicht."
    ) var leistung: String
    var netto: Eurobetrag
    @Guide(description: "Ausgewiesener Steuersatz für genau diese Nettozeile, z.B.7 oder19.") var steuersatz: Int
}

@Generable struct EuroFakten: Codable {
    @Guide(
        description: "Ausdrückliches Beleg-/Rechnungsdatum, nicht Beginn eines Leistungszeitraums und nicht Zahlungsdatum."
    ) var datum: Datum?
    @Guide(description: "Aussteller/Lieferant, nicht Kunde.") var aussteller: String?
    var belegnummer: String?
    var gesamtNetto: Eurobetrag?
    var gesamtSteuer: Eurobetrag?
    var gesamtBrutto: Eurobetrag?
    @Guide(
        description: "Nur echte Leistungszeilen mit ausgewiesenen Nettobeträgen. Nettosumme/Steuerübersicht nicht zusätzlich als Leistung erfassen. Wenn nur eine Netto-Gesamtsumme und ein Steuersatz ausgewiesen sind, genau eine zusammengefasste Leistung.",
        .maximumCount(12)
    ) var leistungen: [Leistungszeile]
    func normalized() -> Facts {
        let text: (Eurobetrag?) -> String? = { $0.map { NSDecimalNumber(decimal: $0.money.betrag).stringValue } }
        var groups: [Int: (Cent, Cent)] = [:]
        for line in leistungen {
            let net = line.netto.money, tax = Position.steuer(
                netto: line.netto.money,
                steuersatz: Decimal(line.steuersatz)
            )
            let previous = groups[line.steuersatz] ?? (.null, .null)
            groups[line.steuersatz] = (previous.0 + net, previous.1 + tax)
        }
        return Facts(
            date: datum.map { String(format: "%04d-%02d-%02d", $0.jahr, $0.monat, $0.tag) },
            issuer: aussteller,
            number: belegnummer,
            net: text(gesamtNetto),
            tax: text(gesamtSteuer),
            gross: text(gesamtBrutto),
            vat: groups.sorted { $0.key < $1.key }.map { VATFacts(
                rate: String($0.key),
                net: NSDecimalNumber(decimal: $0.value.0.betrag).stringValue,
                tax: NSDecimalNumber(decimal: $0.value.1.betrag).stringValue
            ) }
        )
    }
}

@Generable struct CoreEuroFakten: Codable {
    @Guide(
        description: "Ausdrückliches Beleg-/Rechnungsdatum, nicht Beginn eines Leistungszeitraums und nicht Zahlungsdatum."
    ) var datum: Datum?
    @Guide(description: "Aussteller/Lieferant, nicht Kunde.") var aussteller: String?
    var belegnummer: String?
    var gesamtNetto: Eurobetrag?
    var gesamtBrutto: Eurobetrag?
    @Guide(
        description: "Nur echte Leistungszeilen mit ausgewiesenen Nettobeträgen. Nettosumme/Steuerübersicht nicht zusätzlich als Leistung erfassen. Wenn nur eine Netto-Gesamtsumme und ein Steuersatz ausgewiesen sind, genau eine zusammengefasste Leistung.",
        .maximumCount(12)
    ) var leistungen: [Leistungszeile]
    func normalized() -> Facts {
        let text: (Eurobetrag?) -> String? = { $0.map { NSDecimalNumber(decimal: $0.money.betrag).stringValue } }
        var groups: [Int: (Cent, Cent)] = [:]
        for line in leistungen {
            let net = line.netto.money, tax = Position.steuer(
                netto: line.netto.money,
                steuersatz: Decimal(line.steuersatz)
            )
            let previous = groups[line.steuersatz] ?? (.null, .null)
            groups[line.steuersatz] = (previous.0 + net, previous.1 + tax)
        }
        return Facts(
            date: datum.map { String(format: "%04d-%02d-%02d", $0.jahr, $0.monat, $0.tag) },
            issuer: aussteller,
            number: belegnummer,
            net: text(gesamtNetto),
            tax: NSDecimalNumber(decimal: groups.values.reduce(Cent.null) { $0 + $1.1 }.betrag).stringValue,
            gross: text(gesamtBrutto),
            vat: groups.sorted { $0.key < $1.key }.map { VATFacts(
                rate: String($0.key),
                net: NSDecimalNumber(decimal: $0.value.0.betrag).stringValue,
                tax: NSDecimalNumber(decimal: $0.value.1.betrag).stringValue
            ) }
        )
    }
}

actor State {
    let sqlTool: SQLTool
    var calls: [[String: String]] = []
    var touched = Set<Int64>()
    init(_ repository: Repository) throws {
        sqlTool = try SQLTool(repository)
    }

    func link(booking: Int, file: Int) throws -> String {
        let rows = try sql("SELECT belege FROM buchungen WHERE id=\(booking)")
        guard let object = try? JSONSerialization.jsonObject(with: Data(rows.utf8)) as? [[String: Any]],
              let stored = object.first?["belege"] as? String,
              let ids = try? JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [Int]
        else {
            return "Fehler: Die bestehende Buchung konnte nicht gelesen werden."
        }
        let combined = Array(Set(ids + [file])).sorted()
        let json = try String(decoding: JSONEncoder().encode(combined), as: UTF8.self)
        return try sql("UPDATE buchungen SET belege='\(json)' WHERE id=\(booking)")
    }

    func sql(_ sql: String) throws -> String {
        try Task.checkCancellation()
        guard calls.count < 12 else { throw NSError(domain: "ProbeToolBudget", code: 12) }
        let result = sqlTool.execute(sql)
        calls.append(["sql": sql, "output": result.text])
        touched.formUnion(result.touched)
        return result.text
    }
}

struct SQLBridge: Tool {
    let name = "sql"
    let description = "Liest oder schreibt Buchungen. Genau eine SQL-Anweisung. SELECT liefert JSON, Schreiben liefert ok oder einen Fehler."
    let state: State
    @Generable struct Arguments { var sql: String }
    func call(arguments: Arguments) async throws -> String {
        try await state.sql(arguments.sql)
    }
}

struct ShareBridge: Tool {
    let name = "privatanteil_setzen"
    let description = "Setzt den Privatanteil einer bestehenden Buchung über geprüftes SQL. Nur nach Nutzerangabe."
    let state: State
    @Generable struct Arguments { var id: Int; @Guide(.range(0 ... 100)) var prozent: Int }
    func call(arguments: Arguments) async throws -> String {
        try await state
            .sql("UPDATE buchungen SET privatanteil_prozent = \(arguments.prozent) WHERE id = \(arguments.id)")
    }
}

struct LinkBridge: Tool {
    let name = "beleg_anhaengen"
    let description = "Hängt eine bereits gespeicherte Datei an eine bestehende Buchung an, ohne Duplikate."
    let state: State
    @Generable struct Arguments { var buchung: Int; var datei: Int }
    func call(arguments: Arguments) async throws -> String {
        try await state.link(booking: arguments.buchung, file: arguments.datei)
    }
}

@main struct Probe {
    static let root = URL(fileURLWithPath: "evals/2026-q3")
    static func images(_ url: URL) throws -> [CGImage] {
        if url.pathExtension == "pdf" {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount > 0 else { throw NSError(
                domain: "InvalidPDF",
                code: 1
            ) }
            return try (0 ..< pdf.pageCount).map { index in
                let page = pdf.page(at: index)!
                let size = page.bounds(for: .mediaBox).size
                let thumbnail = page.thumbnail(
                    of: CGSize(width: size.width * 2, height: size.height * 2),
                    for: .mediaBox
                )
                guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else { throw NSError(
                    domain: "Render",
                    code: 1
                ) }
                return image
            }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            nil
        ) else { throw NSError(domain: "Image", code: 1) }
        return [image]
    }

    static func ocr(_ images: [CGImage], preserveLines: Bool = false) throws -> String {
        try images.enumerated().map { index, image in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            let observations = (request.results ?? []).compactMap { item -> (CGRect, String)? in
                guard let text = item.topCandidates(1).first?.string else { return nil }
                return (item.boundingBox, text)
            }
            var rows: [[(CGRect, String)]] = []
            if preserveLines {
                for observation in observations.sorted(by: { $0.0.midY > $1.0.midY }) {
                    if let row = rows.indices.last, let first = rows[row].first,
                       abs(first.0.midY - observation.0.midY) < max(first.0.height, observation.0.height) * 0.55
                    {
                        rows[row].append(observation)
                    } else {
                        rows.append([observation])
                    }
                }
            } else {
                rows = observations.map { [$0] }
            }
            return "Seite \(index + 1):\n" + rows
                .map { $0.sorted { $0.0.minX < $1.0.minX }.map(\.1).joined(separator: " | ") }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func documentOCR(_ images: [CGImage]) async throws -> String {
        var text = ""
        for (index, image) in images.enumerated() {
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.recognitionLanguages = [
                Locale.Language(identifier: "de"),
                Locale.Language(identifier: "en")
            ]
            for observation in try await request.perform(on: image) {
                text += "SEITE \(index + 1), VOLLTEXT:\n\(observation.document.text.transcript)\n"
                for (tableIndex, table) in observation.document.tables.enumerated() {
                    text += "TABELLE \(tableIndex + 1):\n"
                    for row in table.rows {
                        text += row
                            .map {
                                "[Spalten \($0.columnRange.lowerBound)...\($0.columnRange.upperBound)] \($0.content.text.transcript.replacingOccurrences(of: "\n", with: " "))"
                            }.joined(separator: " | ") + "\n"
                    }
                }
            }
        }
        return text
    }

    static func cents(_ value: String?) -> Int64? {
        guard let value, value.range(of: "^[+-]?[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).int64Value
    }

    static func mismatch(_ facts: Facts, expected: [String: Any]) -> [String] {
        var errors: [String] = []
        for (key, actual) in [
            ("netto_cents", cents(facts.net)),
            ("steuer_cents", cents(facts.tax)),
            ("brutto_cents", cents(facts.gross))
        ] {
            if actual != (expected[key] as? NSNumber)?
                .int64Value
            {
                errors.append("\(key): \(actual.map(String.init) ?? "nil")")
            }
        }
        if facts.date != expected["datum"] as? String {
            errors.append("date: \(facts.date ?? "nil")")
        }
        let number = expected["belegnummer"] as? String
        let accepted = ([number].compactMap(\.self)) + (expected["accepted_receipt_numbers"] as? [String] ?? [])
        if !accepted.contains(facts.number ?? "") {
            errors.append("number: \(facts.number ?? "nil")")
        }
        let names = ([expected["gegenpartei_name"] as? String].compactMap(\.self)) +
            (expected["accepted_counterparties"] as? [String] ?? [])
        let normalize: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        if !names
            .contains(where: { normalize($0) == normalize(facts.issuer ?? "") })
        {
            errors.append("issuer: \(facts.issuer ?? "nil")")
        }
        let expectedVAT = (expected["positionen_nach_satz"] as? [[String: Any]] ?? [])
            .map {
                ($0["steuersatz"] as? String ?? "") + ":" + String(($0["netto_cents"] as? NSNumber)?.int64Value ?? -1) +
                    ":" + String(($0["steuer_cents"] as? NSNumber)?.int64Value ?? -1)
            }.sorted()
        let actualVAT = facts.vat
            .map { $0.rate + ":" + String(cents($0.net) ?? -1) + ":" + String(cents($0.tax) ?? -1) }.sorted()
        if expectedVAT != actualVAT {
            errors.append("vat: \(actualVAT)")
        }
        return errors
    }

    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard (4 ... 5).contains(args.count)
        else { fatalError("extract|workflow mode case output-directory [prepared-OCR-text]") }
        let kind = args[0], mode = args[1], id = args[2], output = URL(fileURLWithPath: args[3])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: output.path])
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let truth = try JSONSerialization
            .jsonObject(with: Data(contentsOf: root.appending(path: "ground-truth.json"))) as! [String: Any]
        let item = (truth["cases"] as! [[String: Any]]).first { $0["id"] as? String == id }!
        let filePaths = item["files"] as! [String]
        let preparationStarted = Date()
        let sourceImages = try filePaths.flatMap { try images(root.appending(path: $0)) }
        let text: String = if args.count == 5 {
            try String(contentsOfFile: args[4], encoding: .utf8)
        } else if mode.hasPrefix("document") {
            try await documentOCR(sourceImages)
        } else {
            try ocr(sourceImages, preserveLines: mode.contains("lines"))
        }
        try text.write(to: output.appending(path: "ocr.txt"), atomically: true, encoding: .utf8)
        let preparationSeconds = Date().timeIntervalSince(preparationStarted)
        let folder = FileManager.default.temporaryDirectory.appending(path: "pfennig-apple-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try Repository(path: folder.appending(path: "probe.sqlite"))
        try repository.saveProfile(Profil(name: "Studio Linden", ustid: "DE000000000"))
        let state = try State(repository)
        var instructions = "Extrahiere nur belegte Dokumentfakten. Der Aussteller ist der Lieferant, nicht der Kunde. EUR-Beträge als exakte Dezimaltexte mit Punkt. Keine Buchungen, Annahmen oder erfundenen Angaben. Fehlende Werte bleiben null. Deutsche Datumsangaben sind Tag.Monat.Jahr."
        if mode.contains("facts") {
            instructions = "Extrahiere nur belegte Dokumentfakten, Lieferant statt Kunde, deutsche Datumsreihenfolge Tag.Monat.Jahr. Alle Geldbeträge in ganzen EUR-Cent, z.B.12,34EUR=1234. Keine Annahmen oder erfundenen Werte. Nettosummen nicht zusätzlich als Leistungszeile erfassen."
        }
        if mode.contains("units") {
            instructions = "Extrahiere nur belegte Dokumentfakten, Lieferant statt Kunde, deutsche Datumsreihenfolge Tag.Monat.Jahr. Beträge getrennt in ganze Euro und Cent-Nachkommastellen:12,34EUR ist euro12,cent34;123,00EUR ist euro123,cent0. Keine Gesamt-Centzahl in euro eintragen. Keine Annahmen oder erfundenen Werte. Nettosummen/Steuerübersicht nicht zusätzlich als Leistungszeile erfassen."
        }
        var task = "Lies diesen Beleg vollständig und liefere die Fakten einschließlich aller Umsatzsteuergruppen."
        var tools: [any Tool] = []
        if kind == "workflow" {
            tools = [SQLBridge(state: state)]
            if mode
                .hasPrefix("guided")
            {
                tools = id == "s7-chat-private-share" ? [ShareBridge(state: state)] : [LinkBridge(state: state)]
            }
            instructions = try mode == "full" ? try AgentInstructions.build(repository) : """
            Du führst den konkreten Nutzerauftrag in der lokalen Buchhaltung aus. Verwende Werkzeuge für Änderungen, SQL nie als Antworttext. Nur SELECT/INSERT/UPDATE buchungen, SELECT afa_tabelle. Geld in ganzen EUR-Cent. Positionen/Zahlungen/Belege sind JSON wie im Schema. id, geprueft_am und Zeitstempel nie setzen. Eine Buchung pro Vorgang. Unternehmen Studio Linden ist regelbesteuert. Ausgaben gelten bezahlt, außer ausdrücklich offen; eigene Ausgangsrechnungen bleiben ohne Nachweis unbezahlt. Kategorie gemäß Geschäftszweck: \(Kategorie.fuer(.ausgabe).map(\.schluessel).joined(separator: ", ")). Vorhandene Buchungen nachschlagen und ergänzen statt doppelt buchen.
            \(repository.schemaText())
            """
            if let seeds = item["archive"] as? [[String: Any]], let seed = seeds.first {
                let positionData = try JSONSerialization.data(withJSONObject: seed["positionen_nach_satz"]!)
                let positionJSON = try JSONSerialization.jsonObject(with: positionData) as! [[String: Any]]
                let positions = positionJSON.map { Position(
                    netto: Cent(($0["netto_cents"] as! NSNumber).int64Value),
                    steuersatz: Decimal(string: $0["steuersatz"] as! String)!,
                    steuer: Cent(($0["steuer_cents"] as! NSNumber).int64Value)
                ) }
                let payments = (seed["zahlungen"] as? [[String: Any]] ?? []).map { Zahlung(
                    datum: LocalDate($0["datum"] as! String)!,
                    betrag: Cent(($0["betrag"] as! NSNumber).int64Value)
                ) }
                let seedFile = try repository.saveFile(Datei(
                    sha256: "synthetic-original",
                    dateiname: "original.pdf",
                    endung: "pdf",
                    groesse: 0
                ))
                let booking = try repository.save(
                    Buchung(
                        richtung: .ausgabe,
                        art: .rechnung,
                        datum: LocalDate(seed["datum"] as! String)!,
                        titel: seed["titel"] as! String,
                        belegnummer: seed["belegnummer"] as? String,
                        kategorie: seed["kategorie"] as? String,
                        gegenparteiName: seed["gegenpartei_name"] as? String,
                        gegenparteiLand: "DE",
                        positionen: positions,
                        steuerbehandlung: .inland,
                        zahlungen: payments,
                        belege: [seedFile]
                    ),
                    akteur: .nutzer
                )
                try repository.confirm(id: booking.id!)
            }
            if id == "s7-chat-private-share" {
                task = item["chat"] as! String
            } else {
                let fileID = try repository.saveFile(Datei(
                    sha256: "synthetic-new",
                    dateiname: "receipt",
                    endung: "pdf",
                    groesse: 0
                ))
                task = "Datei \(fileID) wurde hinzugefügt. Erfasse oder ergänze diesen Beleg jetzt in der Datenbank."
            }
            if mode.hasPrefix("guided") || mode == "rows" {
                let rows = try JSONEncoder().encode(repository.allBookings())
                task += "\nRelevante bestehende Buchungen als sichtbarer Kontext:\n" + String(
                    decoding: rows,
                    as: UTF8.self
                )
            }
        }
        try instructions.write(to: output.appending(path: "instructions.txt"), atomically: true, encoding: .utf8)
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        let prompt = mode
            .hasPrefix("vision") ?
            Prompt {
                task; for (i, image) in sourceImages
                    .enumerated()
                {
                    "Seite \(i + 1)"; Attachment(image).label("Seite\(i + 1)")
                }
            } :
            Prompt(task + "\nDokumenttext (generische OCR):\n" + text)
        let started = Date()
        var record: [String: Any] = [
            "kind": kind,
            "mode": mode,
            "case": id,
            "availability": String(describing: SystemLanguageModel.default.availability),
            "ocrCharacters": text.count,
            "preparationSeconds": preparationSeconds,
            "toolBudget": 12,
            "sampling": "greedy",
            "modelContextSize": SystemLanguageModel.default.contextSize
        ]
        do {
            if kind == "extract" {
                let bytes: Data
                if mode.contains("core-units") {
                    let response = try await session.respond(
                        to: prompt,
                        generating: CoreEuroFakten.self,
                        options: GenerationOptions(
                            samplingMode: .greedy,
                            maximumResponseTokens: 800,
                            toolCallingMode: .disallowed
                        )
                    )
                    record["rawCoreEuroFacts"] = try JSONSerialization
                        .jsonObject(with: JSONEncoder().encode(response.content))
                    record["taxSource"] = "Core.Position.steuer applied to generated net/rate lines, then summed with Cent."
                    bytes = try JSONEncoder().encode(response.content.normalized())
                } else if mode.contains("units") {
                    let response = try await session.respond(
                        to: prompt,
                        generating: EuroFakten.self,
                        options: GenerationOptions(
                            samplingMode: .greedy,
                            maximumResponseTokens: 800,
                            toolCallingMode: .disallowed
                        )
                    )
                    record["rawEuroFacts"] = try JSONSerialization
                        .jsonObject(with: JSONEncoder().encode(response.content))
                    bytes = try JSONEncoder().encode(response.content.normalized())
                } else if mode.contains("facts") {
                    let response = try await session.respond(
                        to: prompt,
                        generating: BelegFakten.self,
                        options: GenerationOptions(
                            samplingMode: .greedy,
                            maximumResponseTokens: 600,
                            toolCallingMode: .disallowed
                        )
                    )
                    record["rawGermanFacts"] = try JSONSerialization
                        .jsonObject(with: JSONEncoder().encode(response.content))
                    bytes = try JSONEncoder().encode(response.content.normalized())
                } else if mode.contains("strict") {
                    let response = try await session.respond(
                        to: prompt,
                        generating: StrictFacts.self,
                        options: GenerationOptions(
                            samplingMode: .greedy,
                            maximumResponseTokens: 600,
                            toolCallingMode: .disallowed
                        )
                    )
                    bytes = try JSONEncoder().encode(response.content)
                } else {
                    let response = try await session.respond(
                        to: prompt,
                        generating: Facts.self,
                        options: GenerationOptions(
                            samplingMode: .greedy,
                            maximumResponseTokens: 600,
                            toolCallingMode: .disallowed
                        )
                    )
                    bytes = try JSONEncoder().encode(response.content)
                }
                record["facts"] = try JSONSerialization.jsonObject(with: bytes)
                record["mismatches"] = try mismatch(
                    JSONDecoder().decode(Facts.self, from: bytes),
                    expected: (item["expected"] as! [[String: Any]])[0]
                )
            } else {
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(
                        samplingMode: .greedy,
                        maximumResponseTokens: 900,
                        toolCallingMode: (mode == "allowed" || mode == "guided-allowed") ? .allowed : .required
                    )
                )
                record["answer"] = response.content
            }
        } catch { record["error"] = String(reflecting: error) }
        record["seconds"] = Date().timeIntervalSince(started)
        record["totalProbeSeconds"] = Date().timeIntervalSince(preparationStarted)
        record["inputTokens"] = session.usage.input.totalTokenCount
        record["outputTokens"] = session.usage.output.totalTokenCount
        record["calls"] = await state.calls
        record["touched"] = await state.touched.sorted()
        record["bookings"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(repository.allBookings()))
        let bytes = try JSONSerialization.data(
            withJSONObject: record,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try bytes.write(to: output.appending(path: "result.json"))
        print(String(decoding: bytes, as: UTF8.self))
    }
}
