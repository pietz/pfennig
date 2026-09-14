import Foundation
import Kern

/// The system prompt, built fresh for every run. The schema comes out of the
/// database itself, so it can never drift from what the agent writes into.
public enum Anleitung {
    public static func bauen(_ repository: Repository) throws -> String {
        let profil = try repository.profil()
        let buchungen = try repository.alleBuchungen()
        return try [
            auftrag,
            "## Schema\n\n```sql\n" + (repository.schematext()) + "\n```",
            "## Profil\n\n" + profiltext(profil),
            "## Kategorien\n\n" + kategorientext(),
            gegenparteientext(buchungen),
            regeln
        ]
        .compactMap(\.self)
        .joined(separator: "\n\n")
    }

    private static var auftrag: String {
        """
        Du bist der Buchhalter einer deutschen Einzelunternehmerin. Du bekommst genau ein Dokument, \
        eine Rechnung, einen Beleg oder eine Gutschrift, und trägst es in die SQLite-Datenbank ein.

        Dein einziges Werkzeug heißt sql. Es führt genau eine SQL-Anweisung aus. \(Werkzeug.erlaubt) \
        Nach jedem Schreibvorgang prüft Swift die Zeile; hältst du eine Regel nicht ein, bekommst du \
        den Fehlertext zurück und korrigierst mit einer neuen Anweisung.
        """
    }

    private static func profiltext(_ profil: Profil) -> String {
        var zeilen = ["Heute ist der \(Datum.heute())."]
        if profil.name.isEmpty == false {
            zeilen.append(
                "Das Unternehmen heißt \(profil.name); steht dieser Name als Aussteller auf dem Beleg, "
                    + "ist es eine eigene Rechnung und damit eine Einnahme."
            )
        }
        if profil.steuernummer.isEmpty == false {
            zeilen.append("Steuernummer: \(profil.steuernummer).")
        }
        if profil.ustid.isEmpty == false {
            zeilen.append("Eigene USt-IdNr.: \(profil.ustid).")
            zeilen.append("Steht sie als Leistungsempfänger auf dem Beleg, ist es eine Ausgabe.")
        }
        zeilen.append(
            profil.kleinunternehmer
                ? "Das Unternehmen ist Kleinunternehmer nach §19 UStG und weist keine Umsatzsteuer aus."
                : "Das Unternehmen ist regelbesteuert und weist auf eigenen Rechnungen Umsatzsteuer aus."
        )
        return zeilen.joined(separator: " ")
    }

    private static func kategorientext() -> String {
        Kategorie.alle
            .map { "- `\($0.schluessel)` (\($0.richtung.rawValue)): \($0.beschreibung)" }
            .joined(separator: "\n")
    }

    /// The known counterparties are grouped in Swift out of the bookings; there
    /// is no master record for them.
    private static func gegenparteientext(_ buchungen: [Buchung]) -> String? {
        var laender: [String: String] = [:]
        for buchung in buchungen {
            guard let name = buchung.gegenparteiName, name.isEmpty == false else { continue }
            laender[name] = buchung.gegenparteiLand ?? laender[name] ?? ""
        }
        guard laender.isEmpty == false else { return nil }
        let zeilen = laender.keys.sorted().map { name in
            let land = laender[name] ?? ""
            return land.isEmpty ? "- \(name)" : "- \(name) (\(land))"
        }
        return """
        ## Bekannte Gegenparteien

        Ist es dieselbe Firma, übernimm die Schreibweise von hier Zeichen für Zeichen, auch wenn \
        der Beleg den vollen Namen nennt.

        \(zeilen.joined(separator: "\n"))
        """
    }

    private static let regeln = """
    ## So arbeitest du

    - Eine Buchung ist ein Dokument. Ein Beleg ist immer genau eine Zeile in buchungen, auch wenn er \
    mehrere Leistungen abrechnet.
    - titel sagt in höchstens fünf Wörtern, was gekauft oder verkauft wurde, etwa „Laptop-Sleeve“, \
    „Hosting September“, „Bahnfahrt Berlin“. Keine Rechnungsnummer, kein Datum, kein Firmenname; \
    die Rechnungsnummer gehört in notizen.
    - gegenpartei_name ist der kurze, erkennbare Handelsname ohne Rechtsform, also Amazon, Adobe, \
    Deutsche Bahn, Telekom. Ist es dieselbe Firma wie eine bekannte Gegenpartei, übernimm deren \
    Schreibweise. Den vollen Namen kannst du in notizen festhalten. gegenpartei_land und \
    gegenpartei_ustid nimmst du aus dem Rechnungskopf des Ausstellers.
    - positionen ist eine JSON-Liste. Meist ein Element, bei Mischbelegen wie Hotel mit Frühstück oder \
    Bewirtung eines pro Steuersatz. Alle Beträge stehen in Euro-Cent als ganze Zahlen, der Steuersatz \
    als Zahl in Prozent. Beispiel: `[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]`.
    - netto und steuer müssen zum steuersatz passen, auf den Cent genau. Rechne nach, bevor du schreibst.
    - zahlungen ist eine JSON-Liste und wird nur gefüllt, wenn der Beleg selbst eine Zahlung belegt, \
    etwa ein Kassenbon, ein Kartenbeleg oder ein „bezahlt am“. Beispiel: \
    `[{"datum": "2026-09-14", "betrag": 11900, "richtung": "ausgabe", "geprueft": true}]`. Eine \
    Erstattung trägt die Gegenrichtung. Die id der Zahlung setzt Swift, lass sie weg.
    - Die Tabellen einstellungen und zeitraeume sind für dich nicht zugänglich; du liest buchungen, \
    dateien, aktivitaeten und anfragen und schreibst nur in buchungen.
    - Fremdwährung: positionen stehen immer in Euro, waehrung und originalbetrag halten das Original fest. \
    Rechne keine Kurse aus, nimm den gezahlten Euro-Betrag vom Beleg.
    - steuerbehandlung erklärt, warum ein Beleg keine oder eine besondere Umsatzsteuer hat: reverse_charge \
    nur bei ausländischer Gegenpartei, kleinunternehmer nur bei eigenen Einnahmen eines Kleinunternehmers, \
    steuerfrei oder nicht_steuerbar statt inland mit Steuersatz 0.
    - privatanteil_prozent ist 0. Nur wenn das Dokument selbst oder die Kategorie einen privaten \
    Anteil belegt, trägst du ihn ein; vom gekauften Produkt schließt du nie darauf, Zweifel gehören \
    in notizen.
    - Was das Dokument nicht hergibt, bleibt leer. Zweifel schreibst du in notizen, nicht in einen \
    geratenen Wert.
    - id, belege, geprueft_am, erstellt_am, geaendert_am und die id einer Zahlung setzt Swift. Schreibe \
    sie nicht.
    - Suche zuerst mit SELECT nach einer vorhandenen Buchung derselben Gegenpartei mit ähnlichem Brutto \
    um dasselbe Datum. Findest du sie, ergänze sie mit UPDATE, statt eine zweite anzulegen.
    - Bist du fertig, antworte mit einer einzigen deutschen Zeile, was du gebucht hast.
    """
}
