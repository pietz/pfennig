# Änderungen

## 0.5.0 (2026-09-16)

- Neue Startseite mit Begrüßung, Jahresauswahl, Einnahmen, Ausgaben und Saldo des Jahres nach Zahlungsdatum, den To-Dos „Prüfen“, „Belege nachtragen“ und „Überfällig“ sowie den drei dringendsten Fristen für UStVA und EÜR; ein Klick führt in die gefilterte Buchungsliste oder in den Export
- Zahlungen vereinfacht: eine Zahlung ist nur noch Datum und vorzeichenbehafteter Betrag, negativ für eine Erstattung; geprüft wird die ganze Buchung, nicht mehr jede Zahlung
- Statusfilter „Überfällig“ in der Buchungsansicht
- Eine Buchung ohne zu zahlenden Betrag gilt als bezahlt; der Klick in der Bezahlt-Spalte war bei ihr vorher wirkungslos
- Der Agent nimmt beim Import vollständig betriebliche Nutzung an, sofern Dokument oder Nutzer keinen privaten Anteil angeben
- Kompaktere Standardfenstergröße, der Inspector startet ausgeblendet

Hinweise:

- Vorabversion ohne Schemamigration. Das Zahlungsformat in der Datenbank hat sich geändert; das Entwicklungsarchiv des Eigentümers wurde mit Backup umgestellt. Andere Archive aus 0.4.0 benötigen vor Nutzung einen abgestimmten Neuaufbau; das App-Update selbst löscht oder ersetzt keine Daten.
- Die bekannte falsche Zuordnung ausländischer Umsatzsteuer als Vorsteuer in der EÜR ist noch nicht behoben. Entsprechende EÜR-Werte nicht ungeprüft übernehmen.

## 0.4.0 (2026-09-16)

- Optional Belegnummer und Fälligkeit im Inspector; überfällige Buchungen werden gekennzeichnet
- Kürzerer Agentenkontext mit Stammdaten, Buchungsschema und Kategorien; Dateieingang als separate Nachricht
- Agentenzugriff ausschließlich auf `buchungen`; interne Tabellen bleiben unzugänglich
- Ausgaben gelten beim Import als bezahlt, sofern das Dokument nichts Gegenteiliges erkennen lässt; ohne Zahlungsdatum gilt das Belegdatum

Hinweise:

- Vorabversion ohne Schemamigration. Das Entwicklungsarchiv des Eigentümers wurde bereits mit Backup für die neuen Felder neu aufgebaut. Andere Archive aus 0.3.0 benötigen vor Nutzung einen abgestimmten Neuaufbau; das App-Update selbst löscht oder ersetzt keine Daten.
- Bestehende Buchungen werden durch den neuen Prompt nicht rückwirkend korrigiert.
- Die bekannte falsche Zuordnung ausländischer Umsatzsteuer als Vorsteuer in der EÜR ist noch nicht behoben. Entsprechende EÜR-Werte nicht ungeprüft übernehmen.

## 0.2.0 (2026-09-15)

- Fremdwährungsbelege mit historischem Frankfurter-Referenzkurs, exakter Originalwährung und EUR-Cent-Beträgen
- Sparkle 2 mit „Nach Updates suchen“, normalem Hintergrundprüfzyklus, Standard-Installationsbestätigung und signiertem Appcast-Release-Werkzeug

## 0.1.0 (2026-09-15)

Erste Version des Neuaufbaus nach `docs/specs/pfennig-neu.md`.

- Ein Fenster: Tabelle der Buchungen mit Firma, Datum, Betrag und Bezahlt-Status, Inspector mit flachen Abschnitten, Suche, Richtungsfilter, Fußzeile mit Summen
- Drag-and-drop von PDF, PNG, JPEG und CSV; bis zu zehn Dateien gleichzeitig
- KI-Agent über die OpenAI Responses API mit einem einzigen Werkzeug `sql`, abgesichert durch SQLite-Autorisierer, Transaktion mit Prüfregeln und automatischem Aktivitätslog
- Neue Buchungen des Agenten erscheinen ungeprüft und werden im Inspector bestätigt
- Beleg-Vorschau, Original öffnen, Beleg entfernen
- Einstellungen: Profil (Name, Adresse, Steuernummer, USt-ID, Kleinunternehmer, UStVA-Rhythmus, Dauerfristverlängerung), KI-Zugang (Schlüssel mit Verbindungsprüfung, Modell, Denkaufwand, Fast Mode), Erscheinungsbild
- Export: UStVA-Kennzahlen als XML für den Upload in Mein ELSTER (Aufbau am 14.09.2026 mit einem Testupload verifiziert), EÜR-Zeilen als CSV, Warnung bei Änderungen in exportierten Zeiträumen

Bekannte Grenzen:

- Kontoauszüge werden noch nicht verarbeitet; Zahlungen kommen aus dem Beleg oder werden manuell erfasst
- Innergemeinschaftliche Lieferungen und Erwerbe, Ausfuhren und Einfuhrumsatzsteuer sind nicht abgebildet
- Die EÜR-Zeilennummern stammen aus dem Formular 2023/2024 und sind für 2026 ungeprüft
- Fremdwährungsbelege verwenden den historischen Frankfurter-Referenzkurs; dieser ist kein bank- oder steuerlich vorgeschriebener Kurs
- Auf macOS 26 zeigt das System das Icon in seiner eigenen Kachel
