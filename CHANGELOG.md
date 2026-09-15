# Änderungen

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
