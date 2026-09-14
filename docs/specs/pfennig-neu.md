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

**Zwei Tabellen.**

`entries`, eine Zeile pro Buchung:
- Identität und Einordnung: `id`, `direction` (income/expense), `kind` (invoice, receipt, credit_note, tax_payment, payment_only, other), `date` (Belegdatum), `title`, `category` (feste EÜR-Kategorienliste im Code), `private_share_percent`, `notes`
- Gegenpartei als Text: `counterparty_name`, `counterparty_country`, `counterparty_vat_id`
- Beträge in EUR-Cent: `currency`, `net_minor`, `tax_minor`, `gross_minor`; Steuerkomponenten als feste Spalten `net_19`, `tax_19`, `net_7`, `tax_7`, `net_0`
- Steuer: `tax_treatment` (domestic_vat, reverse_charge, small_business, exempt, non_taxable, unknown)
- Zustand: `review_status` (unreviewed/confirmed), `edited_by_user_at` (gesetzt, sobald der Nutzer den Eintrag ändert; danach darf der Agent nur noch Zahlungen ergänzen), `created_at`, `updated_at`
- Zwei JSON-Spalten: `payments` = Liste von {date, amount_minor, direction}; Teilzahlungen sind mehrere Einträge, eine Erstattung hat die Gegenrichtung. `files` = Liste von SHA-256-Hashes der Originaldateien.

`settings`, Schlüssel und Wert. Enthält auch das Profil: Steuernummer, USt-ID, Kleinunternehmer, UStVA-Rhythmus, Dauerfristverlängerung, Automatisierungsstufe. Der Agent hat keinen Werkzeugzugriff auf diese Tabelle.

**Das Dateisystem übernimmt den Rest.** Originale liegen im Archivordner als `<sha256>.<ext>`; eine erneut abgelegte Datei ist ein Existenztest. Abgelegte Dateien landen in `Inbox/` und wandern nach erfolgreicher Verarbeitung ins Archiv; Inbox ist Fortschritt und Wiederholung zugleich. Bei Kontoauszügen prüft der Agent über die Suche, welche Zahlungen es schon gibt, und trägt nur neue ein; private Gegenparteien merkt er sich als Liste in den Einstellungen.

**Bewusst nicht:** Tabellen für Zahlungen, Gegenparteien, Kategorien, Dokumente, Zuordnungen, Vorschläge, Herkunft, Audit, Modellläufe, Importläufe. Eine Zahlung gehört zu genau einer Buchung; eine Überweisung für zwei Rechnungen sind zwei Zahlungseinträge. Ein Beleg mit zwei Kategorien wird in zwei Buchungen geteilt.

*Anmerkung: Eine unabhängige Kritik dieses Modells wurde eingeholt; Ergänzungen werden hier nachgetragen.*
