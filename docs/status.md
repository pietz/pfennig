# Status

**2026-09-14.** Der Neuaufbau nach `docs/specs/pfennig-neu.md` beginnt. Der alte Code ist als Tag `legacy-2026-09-14` archiviert und aus dem Arbeitsbaum entfernt. Erhalten: Spec, AGENTS.md, Skripte, `project.yml`, Info.plist, Entitlements, Assets, die Recherche zum UStVA-XML (Upload am 2026-09-14 erfolgreich getestet) und die Notizen zur Responses API.

**Schritt 1: Schema und Repository.** Das Paket hat ein Ziel `Kern` mit Tests. Es enthält die Werttypen `Cent` und `Datum`, die eine Schemadefinition mit den fünf Tabellen aus Abschnitt 2 der Spec (Aufzählungen als CHECK-Bedingungen, JSON-Struktur als Kommentar neben der Spalte, damit der Agent sie im Schematext liest) und die Datensätze `Buchung` mit `Position` und `Zahlung`, `Datei`, `Aktivitaet` und `Anfrage`. Das `Repository` öffnet die Datenbank aus einer Datei oder im Speicher, schreibt zu jedem Schreibvorgang an einer Buchung eine Zeile in `aktivitaeten` mit vorher und nachher, vergibt die Zahlungs-ids und bedient Einstellungen, Dateien und Anfragen; `Archivpfad` legt `~/Library/Application Support/Pfennig/` mit `Archiv/` und `Inbox/` an.

Nächster Schritt: Tabelle mit Inspector und manueller Eingabe. Die Ziele `Agent` und `App` gibt es noch nicht.
