import Core
import Foundation

/// The system prompt, built fresh for every run. The schema comes out of the
/// database itself, so it can never drift from what the agent writes into.
public enum AgentInstructions {
    public static func build(_ repository: Repository) throws -> String {
        let profile = try repository.profile()
        return try [
            environment,
            rules,
            "## Profil\n\n" + profileText(profile),
            "## Schema\n\n" + appManagedFields + "\n\n```sql\n" + (repository.schemaText()) + "\n```",
            "## Kategorien\n\n" + categoryText()
        ]
        .joined(separator: "\n\n")
    }

    private static let environment = """
    Du bist der Buchhaltungsassistent in Pfennig, einer lokalen Anwendung für deutsche Selbstständige mit EÜR und Ist-Versteuerung.

    Du pflegst die Buchhaltungsdaten des Unternehmens anhand von Dokumenten und Nutzerangaben in der Datenbank. Pfennig zeigt diese Daten dem Nutzer an, der sie prüfen und bearbeiten kann.

    Eine Buchung fasst einen Geschäftsvorgang mit seinen Belegen, Positionen und Zahlungen zusammen. Mit deinen Werkzeugen kannst du vorhandene Buchungen nachschlagen und bearbeiten. Änderungen werden automatisch protokolliert und dem Nutzer zur Prüfung vorgelegt.
    """

    private static let rules = """
    ## Regeln

    - Ausgaben gelten beim Import als bezahlt, sofern das Dokument nichts Gegenteiliges erkennen lässt; fehlt das Zahlungsdatum, verwende das Belegdatum.
    - Gehe von vollständig betrieblicher Nutzung aus, sofern das Dokument oder der Nutzer keinen privaten Anteil angibt.
    - Ist die hinzugefügte Datei ein Beleg zu einer Buchung (Rechnung, Quittung, Gutschrift), trage ihre id in belege dieser Buchung ein. Ein Kontoauszug ist kein Beleg und steht in keiner belege-Liste.
    - Ein Kontoauszug bringt Zahlungen zu bestehenden Buchungen. Suche zu jeder Bewegung die passende Buchung nach Betrag, Datum und Gegenpartei und trage die Zahlung in zahlungen ein. Eine Bewegung ohne passende Buchung wird eine Buchung mit art nur_zahlung, dem Verwendungszweck als titel, einer Position über den Betrag ohne Steuer und steuerbehandlung unklar; private Bewegungen und Übertragungen zwischen eigenen Konten werden ignoriert. Prüfe vorher, was schon da ist, und lege keine Zahlung und keine Bewegung doppelt an.
    """

    private static let appManagedFields = """
    Von der Anwendung verwaltet, nicht setzen: id, geprueft_am, erstellt_am und geaendert_am.
    """

    private static func profileText(_ profile: Profil) -> String {
        """
        - heute: \(LocalDate.today())
        - name: \(profile.name.isEmpty ? "nicht angegeben" : profile.name)
        - ustid: \(profile.ustid.isEmpty ? "nicht angegeben" : profile.ustid)
        - kleinunternehmer: \(profile.kleinunternehmer)
        """
    }

    private static func categoryText() -> String {
        [Richtung.einnahme, .ausgabe].map { richtung in
            """
            \(richtung == .einnahme ? "Einnahmen" : "Ausgaben"):
            \(Kategorie.fuer(richtung).map { "- `\($0.schluessel)`" }.joined(separator: "\n"))
            """
        }
        .joined(separator: "\n\n")
    }
}
