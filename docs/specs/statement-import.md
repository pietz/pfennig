# Kontoauszug-Import und Abgleich

**Status:** Approved 2026-09-14. Decisions: Privat-Einordnung je Gegenpartei wird gemerkt, aber nur solange die Gegenpartei nie geschäftlich gebucht wurde; Reihenfolge Automatisierungsstufe, CSV, Matcher, PDF; Testmaterial liefert der Nutzer außerhalb des Repos, Fixtures werden anonymisiert.

Ausbau der [Workflow-Spezifikation](document-to-tax-workflow.md) für Kontoauszüge. Bankunabhängig: PDF-Auszüge liest das multimodale Modell, CSV-Auszüge ein deterministischer Importer mit modellgestützter Spaltenzuordnung. Keine Bankanbindung, keine bankspezifischen Adapter.

## Ziel

Der Nutzer zieht einen Kontoauszug in dieselbe Ablagefläche wie Belege. Pfennig erkennt ihn als Auszug, liest die einzelnen Kontobewegungen, ordnet sie bestehenden Vorgängen zu, erzeugt für geschäftliche Bewegungen ohne Beleg einen Vorgang mit fehlendem Beleg, und legt private sowie interne Bewegungen als reine Kontobewegungen ab. Wiederholte oder überlappende Auszüge erzeugen nichts doppelt. Erstattungen erscheinen als Zahlung in Gegenrichtung auf dem Ursprungsvorgang.

## Bausteine

### 1. Automatisierungsstufe (Voraussetzung)

Einstellung mit drei Werten: **Manuell** (Standard), **Ausgewogen**, **Automatisch**, gespeichert in `settings`. Eine einzige Entscheidungsfunktion beantwortet für jeden Vorschlag: sofort übernehmen oder in Prüfen legen. Sie gilt für Belegimporte und Kontobewegungen gleichermaßen.

- Manuell: jeder Vorschlag wird bestätigt, auch eindeutige Zuordnungen.
- Ausgewogen: eindeutige Zuordnungen und vollständig validierte Standardfälle werden übernommen; alles mit Warnung, Konkurrenz oder fehlenden Fakten wird Vorschlag.
- Automatisch: alles wird übernommen, was deterministisch möglich ist; unlösbare Fälle bleiben als Ausnahme in Prüfen, es gibt aber keinen Bestätigungsschritt.

### 2. Erkennung und Eingang

CSV-Dateien werden angenommen und sind immer Auszüge. PDFs werden nach der Archivierung mit einer kurzen Klassifikation unterschieden: Beleg oder Kontoauszug. Das Original wird wie jeder Beleg archiviert und dedupliziert. Fortschritt, Wiederholung und Fehlerliste laufen über die vorhandene Importmechanik.

### 3. Bewegungen lesen

**PDF:** eigenes Extraktionsschema mit Kontokennung (IBAN oder Kontoname), Zeitraum, Anfangs- und Endsaldo und einer Liste von Bewegungen: Buchungsdatum, Betrag mit Vorzeichen, Währung, Gegenpartei, Verwendungszweck, Gegen-IBAN falls vorhanden. Kontrolle: Anfangssaldo plus Summe der Bewegungen muss den Endsaldo ergeben; sonst gilt der Auszug als unvollständig und wird nicht als Erfolg behandelt. Seitenlimit für Auszüge höher als für Belege.

**CSV:** Der Importer liest die Datei lokal. Die Spaltenzuordnung (Datum, Betrag oder Soll/Haben, Gegenpartei, Verwendungszweck, IBAN) wird einmal pro Kopfzeile bestimmt: deterministisch über bekannte Kopfbezeichnungen aus `docs/statement-formats.md`, bei Unbekanntem fragt Pfennig das Modell nach der Zuordnung und speichert sie je Kopfzeilen-Fingerabdruck. Zahlen und Datumsformate werden lokal geparst.

Beide Wege erzeugen dieselben `statement_lines` mit dem bestehenden Zeilen-Fingerabdruck. Eine bereits vorhandene Zeile desselben Kontos wird übersprungen.

### 4. Einordnung

Jede Bewegung wird eingeordnet als **geschäftlich**, **privat**, **intern** (Übertrag zwischen eigenen Konten) oder **Steuerzahlung**.

- Intern: Gegen-IBAN ist ein bereits importiertes eigenes Konto.
- Steuerzahlung: Gegenpartei ist ein Finanzamt oder der Verwendungszweck enthält Steuernummer und UStVA-Kennung.
- Privat: nur durch den Nutzer. Eine Entscheidung wird je Gegenpartei gemerkt und für spätere Bewegungen derselben Gegenpartei vorgeschlagen, solange keine Bewegung dieser Gegenpartei geschäftlich gebucht wurde; danach wird wieder gefragt.
- Alles andere: geschäftlich, mit Zuordnungsversuch.

Private und interne Bewegungen bleiben Kontobewegungen ohne Vorgang und sind in Prüfen nicht sichtbar, sobald eingeordnet.

### 5. Zuordnung

Für jede geschäftliche Bewegung sucht Pfennig Vorgänge im Datumsfenster mit offenem Betrag. Punkte nach `MatchingPolicy`: exakter Betrag, Rechnungsnummer im Verwendungszweck, Gegenpartei-Name ähnlich, Datum nah. Ergebnis:

- **Eindeutig** (Schwelle erreicht und deutlicher Abstand zum Zweitbesten): Zahlung mit Zuordnung anlegen. Sofort in Ausgewogen und Automatisch, als Vorschlag in Manuell.
- **Mehrdeutig**: Vorschlag mit den Kandidaten, Nutzer wählt.
- **Kein Kandidat, Betrag in Gegenrichtung zu einem bezahlten Vorgang derselben Gegenpartei**: Erstattungsvorschlag.
- **Kein Kandidat**: Vorgang „Nur Zahlung“ mit fehlendem Beleg, Richtung nach Vorzeichen. Wenn später der Beleg kommt, wird er diesem Vorgang zugeordnet statt einen neuen zu erzeugen: der Belegimport prüft vor dem Anlegen, ob ein „Nur Zahlung“-Vorgang mit passendem Betrag und Gegenpartei existiert.

Teilzahlungen: eine Bewegung kleiner als der offene Betrag wird als Teilzahlung zugeordnet, wenn sonst eindeutig. Sammelzahlungen und Gebührenabzüge bleiben zunächst Ausnahme.

### 6. Prüfen und Start

Prüfen bekommt den Abschnitt **Kontobewegungen**: mehrdeutige Zuordnungen, Erstattungsvorschläge, unklare Einordnung, unvollständige Auszüge. Jede Zeile bietet die Aktionen: Vorgang wählen, Privat, Intern, Vorgang ohne Beleg anlegen. Start zählt sie in „Offen“. Vorgänge „Nur Zahlung“ erscheinen in Buchungen mit Belegstatus fehlend, wie heute.

## Nicht enthalten

Bankanbindung, bankspezifische Adapter, Fremdwährungsgebühren, Sammelzahlungen auf mehrere Rechnungen, Kontostände als Anzeige, Regeln über die gemerkte Privat-Einordnung hinaus, Lernen von Kategorien aus Bewegungen.

## Abnahme

- CSV und PDF desselben Zeitraums ergeben dieselben Bewegungen, der zweite Import erzeugt nichts Neues.
- Eine überlappende Folgeperiode importiert nur die neuen Bewegungen.
- Rechnung zuerst, dann Auszug: die Bewegung wird der Rechnung zugeordnet, der Zahlungsstatus wird bezahlt.
- Auszug zuerst, dann Rechnung: der Belegimport ergänzt den „Nur Zahlung“-Vorgang statt einen zweiten anzulegen.
- Eine Rückbuchung von Amazon erscheint als Erstattungsvorschlag auf dem bezahlten Vorgang.
- Ein PDF mit falscher Saldensumme wird als unvollständig markiert.
- In Manuell landet jede Zuordnung in Prüfen, in Ausgewogen nur mehrdeutige.
- Private Bewegungen erzeugen keine Ausgaben; eine einmal privat markierte Gegenpartei wird beim nächsten Mal so vorgeschlagen.

## Reihenfolge

1. Automatisierungsstufe und Entscheidungsfunktion, auch für Belegimporte.
2. CSV-Importer mit Spaltenzuordnung, `statement_lines`, Einordnung intern/Steuer.
3. Matcher, Erstattungsvorschlag, „Nur Zahlung“-Vorgang, Prüfen-Abschnitt.
4. PDF-Auszug-Extraktion mit Saldenkontrolle.
5. Belegimport ergänzt bestehende „Nur Zahlung“-Vorgänge.
