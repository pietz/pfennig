# Pfennig neu: Spezifikation für den Neuaufbau

**Status:** in Arbeit, wird Thema für Thema gemeinsam geschrieben (2026-09-14). Nur bestätigte Abschnitte gelten.

Gliederung:

1. Zweck und Grenzen
2. Datenmodell
3. Oberfläche
4. Eingang: Dateien und Agent
5. Ausgang: Steuerdaten
6. Technik und Zielgröße
7. Was bewusst nicht gebaut wird

---

## 1. Zweck und Grenzen

Pfennig ist eine lokale macOS-App für deutsche Freiberufler und Einzelunternehmer mit EÜR und Ist-Versteuerung, regelbesteuert oder Kleinunternehmer. Sie sammelt Einnahmen und Ausgaben aus Dokumenten, die der Nutzer per Drag-and-drop ablegt: Rechnungen, Belege, Gutschriften, Kontoauszüge. Ein KI-Agent liest die Dateien, ordnet sie den bestehenden Einträgen zu oder legt neue an, und speichert das Ergebnis strukturiert in einer lokalen SQLite-Datenbank. Der Nutzer sieht eine Tabelle seiner Buchungen und kann jeden Eintrag im Seitenmenü ansehen und korrigieren. Am Ende hilft die App, die Steuerdaten für UStVA und EÜR vorzubereiten, ohne selbst zu übermitteln.

Die App wirkt nicht wie eine KI-Anwendung. Sie ist eine ruhige Tabelle, hinter der ein Agent die Arbeit macht. Deterministischer Code gibt es nur für das Schema, Geldbeträge, Steuerregeln und die Grenzen, innerhalb derer der Agent schreiben darf.

Nicht enthalten: Bankanbindung, Rechnungsstellung, Bilanz, Lohn, Chat, direkte ELSTER-Übermittlung, Herstellerregistrierung, bankspezifische Parser, regelbasierte Zuordnungslogik.

## 2. Datenmodell

Pfennig speichert Wissen über die Buchhaltung, nicht Protokoll über die Arbeit der App. Ein Freiberufler hat wenige hundert Buchungen im Jahr; alles passt in den Speicher. SQLite ist eine Datei mit sicherem Schreiben und Änderungsbeobachtung, kein Abfragesystem. Swift lädt und rechnet.

**Vier Tabellen.** Eine trägt die Buchhaltung, drei sind klein und dienen ihr.

`entries`, eine Zeile pro Buchung:
- Identität und Einordnung: `id`, `direction` (income/expense), `kind` (invoice, receipt, credit_note, tax_payment, payment_only, ignored, other), `date` (Belegdatum), `title`, `category` (feste EÜR-Kategorienliste im Code, IDs unwiderruflich), `private_share_percent`, `notes`
- Gegenpartei als Text: `counterparty_name`, `counterparty_country`, `counterparty_vat_id`. Die USt-IdNr. gehört zum Beleg, nicht zu einem Stammsatz.
- Beträge in EUR-Cent als feste Spalten: `net_19`, `tax_19`, `net_7`, `tax_7`, `net_0`. `gross_minor` ist eine generierte Spalte (Summe der fünf). Es gibt keine redundanten Summenspalten. Bei Reverse Charge steht die Bemessungsgrundlage im Bucket ihres Satzes (`net_19` oder `net_7`) mit Steuer 0; `tax_treatment` macht den Fall eindeutig.
- Fremdwährung: `currency` und `gross_original_minor` bewahren den Originalbetrag des Belegs.
- Steuer: `tax_treatment` (domestic_vat, reverse_charge, small_business, exempt, non_taxable, unknown)
- Zustand: `reviewed_at` (NULL = ungeprüft), `edited_by_user_at`, `created_at`, `updated_at`. Hat der Nutzer einen Eintrag geändert, darf der Agent ihn weiter bearbeiten, aber nie still: jede Agentenänderung an einem solchen Eintrag setzt ihn unabhängig von der Automatisierungsstufe auf ungeprüft und steht im Journal. Schreibwerkzeuge übergeben `updated_at` als Version; veraltete Schreibvorgänge werden abgelehnt.
- Zwei JSON-Spalten: `payments` = Liste von {id, date, amount_minor, direction, reviewed}, deterministisch nach (date, id) sortiert; Teilzahlungen sind mehrere Einträge, eine Erstattung hat die Gegenrichtung, eine unklare Zuordnung ist `reviewed = false`. `files` = Liste von SHA-256-Hashes der Belege (keine Kontoauszüge).

Eine Kontobewegung, die zu keinem Beleg passt, ist ein Eintrag mit `kind = payment_only` (unklar, ungeprüft, Titel aus dem Verwendungszweck) oder `kind = ignored` (privat, interner Übertrag; im Ledger ausgeblendet). So erkennt der Agent bereits verarbeitete Auszüge wieder, ohne eigene Tabelle.

`files`: `sha256` (PK), `filename`, `ext`, `byte_size`, `kind` (receipt/statement), `page_count`, `imported_at`. Dedupe ist „Hash existiert“. Kontoauszüge hängen an keinem Eintrag.

`history`: ein Log, `id`, `entry_id`, `at`, `actor` (user/agent), `patch_json`. Ein Insert pro Schreibvorgang im Repository. Ersetzt Herkunft, Audit und Vorschlagstabellen, gibt Undo und zeigt, was der Agent geändert hat. Der Agent darf es lesen, nicht schreiben. Das genaue Spaltendesign wird vor der Umsetzung noch einmal geprüft.

Eine Tabelle `periods` für abgegebene und anstehende Zeiträume ist Thema 5 und nicht Teil der ersten Version.

`settings`, Schlüssel und Wert. Enthält auch das Profil: Steuernummer, USt-ID, Kleinunternehmer, UStVA-Rhythmus, Dauerfristverlängerung, Automatisierungsstufe. Der Agent hat keinen Werkzeugzugriff auf diese Tabelle.

**Das Dateisystem übernimmt den Rest.** Originale liegen im Archivordner als `<sha256>.<ext>`. Abgelegte Dateien landen in `Inbox/` und wandern nach erfolgreicher Verarbeitung ins Archiv; Inbox ist Fortschritt und Wiederholung zugleich.

**Bewusst nicht:** Tabellen für Zahlungen, Gegenparteien, Kategorien, Zuordnungen, Vorschläge, Herkunft, Modellläufe, Importläufe. Eine Zahlung gehört zu genau einer Buchung; eine Überweisung für zwei Rechnungen sind zwei Zahlungseinträge. Ein Beleg mit zwei Kategorien wird in zwei Buchungen geteilt. Bekannte Gegenparteien sind eine in Swift aus den Einträgen gruppierte Liste, kein Stammsatz.

*Herkunft: Zwei-Tabellen-Entwurf vom Nutzer bestätigt; `files` und `history` aus einer unabhängigen Kritik übernommen und bestätigt. Noch nicht einzeln bestätigt und daher vorläufig: generiertes `gross_minor` ohne Summenspalten, `gross_original_minor`, Zahlungs-`id`/`reviewed`, die „nie still“-Regel mit Version, die Reverse-Charge-Bucket-Regel, `kind = ignored`.*

## 3. Oberfläche

Ein Fenster. Es besteht aus der Tabelle, dem Inspector rechts und einer Toolbar. Keine Sidebar, keine weiteren Seiten.

**Tabelle.** Eine Zeile pro Eintrag. Standardspalten sind wenige: Datum, Gegenpartei, Titel, Betrag, Zahlungsstand und Beleg als Symbol. Weitere Spalten (etwa Kategorie, Steuersatz, Art) kann der Nutzer über die Spaltenauswahl der Tabelle einblenden. Die Fußzeile zeigt Einnahmen, Ausgaben und Saldo der aktuell sichtbaren Zeilen.

**Inspector.** Rechts, standardmäßig sichtbar. Er zeigt alle Informationen eines Eintrags, die nicht in eine Tabelle gehören: Beleg mit Vorschau, Grunddaten, Beträge, Steuer, Zahlungen, Notizen, bei ungeprüften Einträgen eine Bestätigen-Aktion. Umsetzung als `.inspector` mit einem Formular im Stil `.grouped`. Alle Abschnitte sind flach und immer sichtbar, keine Akkordeons; ein leerer Abschnitt wird weggelassen, nicht eingeklappt.

**Toolbar.** Ein Dropdown Alle / Einnahmen / Ausgaben, ein Suchfeld, das ausgewählte Spalten in Echtzeit durchsucht, ein Fortschrittsanzeiger, während der Agent arbeitet, ein Plus für manuelle Einträge. Keine Jahresauswahl im ersten Schritt.

**Drag-and-drop** gilt für das ganze Fenster.

**Einstellungen** sind das normale macOS-Einstellungsfenster (Menü und Tastenkürzel, optional Zahnrad in der Toolbar): Profil, Automatisierungsstufe, KI-Zugang, Erscheinungsbild.

**Wegfall:** Startseite, Prüfen-Seite, Sidebar, UStVA-Aufgabenfenster. Erster Schritt ist Eingang, Speicherung und Anzeige sauber, minimal und solide. Wie die Daten danach für Steuerzwecke bereitgestellt werden, folgt in Abschnitt 5 und wird erst gebaut, wenn die Basis steht.
