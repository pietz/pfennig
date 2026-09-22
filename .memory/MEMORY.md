# Pfennig: Scope und Entscheidungen

Stand: 2026-09-22. Kurze Begründungen für getroffene Entscheidungen, keine neue Gesamtspezifikation. Offene Arbeit und Reihenfolge stehen in `docs/backlog.md` und GitHub, der Umsetzungsstand in `docs/status.md`. Bei Widersprüchen gegen aktuellen Code und neuere Eigentümerentscheidungen prüfen.

## Produktgrenze

| Entscheidung | Begründung |
| --- | --- |
| Lokale Buchhaltung für eine selbstständige Person mit EÜR und Ist-Versteuerung, regelbesteuert oder Kleinunternehmer. UStVA-XML und EÜR-Werte vorbereiten, nicht selbst ans Finanzamt übermitteln. | Ein klarer, kleiner Anwendungsfall statt einer vollständigen Steuerlösung. |
| Einkommensteuerzahlungen nicht in Pfennig führen. Keine zusätzliche Kategorie oder Sonderlogik dafür; irrtümlich erfasste Betriebsausgaben manuell entfernen. | Private Personensteuer, keine Betriebsausgabe (§12 Nr. 3 EStG). Issue #3 ist als außerhalb des Umfangs geschlossen, nicht durch eine neue technische Sperre behoben. |
| Direktes Ablegen erfasst Rechnungen, Quittungen und Gutschriften. Kein automatischer Kontoauszugsabgleich und kein Import beliebiger Unterlagen. | Die Ablage hat einen eindeutigen Auftrag: Buchungen aus Belegen erfassen. Andere Unterlagen brauchen Kontext und gegebenenfalls Rückfragen. |
| Chat und Dateienübersicht sind spätere Themen, derzeit ohne Umsetzungsauftrag. Chat ist grundsätzlich gewünscht; bisherige Ideen stehen in #16, Dateienübersicht in #17. | Erst offene Bestandsthemen abschließen oder entscheiden, bevor größere Funktionen beginnen. Nicht für spätere Funktionen vorbauen. |

## Bewusste Vereinfachungen

- **Agent zuerst, Prompt schlank:** Dokumentverständnis und Zuordnung bleiben beim Agenten. Neue Anweisungen möglichst mit vorhandenen Regeln verbinden oder diese ersetzen, nicht fortlaufend Sonderfälle anhängen. Seltene Fälle lieber manuell korrigieren.
- **Import muss etwas buchen:** `noBooking` bleibt. Eine Abschlussnachricht ohne Buchungsänderung führt zum bestehenden Fehler mit Wiederholen/Verwerfen. Das hält einen erfolglosen oder ungeeigneten Import sichtbar; kein neues Ignorieren-Tool oder Abschlussstatus. Für einen späteren Chat gilt diese Importbedingung nicht.
- **Duplikate:** Identische Dateien werden vor dem Agenten per Hash abgefangen. Für denselben Beleg in einer anderen Datei keine neue Swift-Prüfung oder verpflichtende zusätzliche Agentenabfrage beschlossen. Belegnummern sind weder Primärschlüssel noch eindeutig über verschiedene Aussteller hinweg.
- **Zahlungen:** Eigene Ausgangsrechnungen bleiben ohne Zahlungsnachweis unbezahlt; Ausgaben gelten ohne gegenteilige Angabe als bezahlt. Zahlungssummen entsprechen dem Geldfluss, Beträge sind relativ zur Buchung. Keine zusätzliche Sonderregel für negative Gutschriften.
- **EU-Warenkäufe:** Eigener Wert `innergemeinschaftlicher_erwerb` im vorhandenen Feld `steuerbehandlung`, keine neue Spalte. Kategorien beschreiben den Geschäftszweck und sind nicht zuverlässig Ware/Dienstleistung; deshalb keine Kategorien-Zuordnungstabelle. Unterstützt werden gewöhnliche steuerpflichtige Erwerbe mit 19/7 Prozent zum Belegdatum, Kz 89/93 und abziehbare Vorsteuer in Kz 61. Steuerpflicht setzt die Einordnung des Erwerbs voraus, nicht nur ein EU-Lieferantenland. Keine automatische Erwerbsschwellen-/Verzichtsprüfung, kein zusätzliches Leistungsdatum oder Steuerbehandlung je Position. Abweichende Zeitpunkte und gemischte Behandlungen brauchen manuelle Steuerkorrektur. EU-Warenverkäufe und Drittlandsimporte bleiben getrennt außerhalb dieses Schritts.
- **Ungeklärte Zahlungen:** Eine neue `nur_zahlung`-Anweisung ist ohne automatischen Kontoauszugsimport zurückgestellt. Die unterschiedliche Exportbehandlung von EÜR und UStVA ist weiterhin offen (#20), nicht mitentschieden.
- **Sondervorauszahlung:** Bereits festgesetzten Betrag je Jahr manuell im Profil hinterlegen; bei monatlicher UStVA mit Dauerfristverlängerung im Dezember als Kz 39 anrechnen. Keine Berechnung oder Anmeldung, keine automatische Zahlungsbuchung. Ein abweichender letzter Meldezeitraum wird in ELSTER korrigiert. Grund: den angebotenen Regelfall korrekt abbilden, ohne das ganze Antragsverfahren nachzubauen.

## Zusammenarbeit

Der Eigentümer entscheidet Ziele und relevante Grenzen; der Assistent hält Reihenfolge und offene Punkte zusammen. Ein Thema nach dem anderen. Aktueller Wunsch: direkt zusammenarbeiten, keine neuen Subagenten. Änderungen abschließend ausdrücklich auf unnötige Komplexität prüfen. Die alte Neuaufbau-Spec wurde bewusst entfernt, weil sie den fertigen Aufbau beschrieb und neue Entscheidungen unnötig behinderte.

Quelle zur Einkommensteuer: [§12 EStG](https://www.gesetze-im-internet.de/estg/__12.html).
