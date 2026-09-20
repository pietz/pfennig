# Änderungen

## 0.7.2 (2026-09-20)

- Dateien der unterstützten Formate lassen sich aus dem Finder oder mit `open -a Pfennig …` in Pfennig öffnen und gehen durch denselben Eingang wie abgelegte Dateien. Pfennig steht dafür als alternative App bereit, übernimmt aber keine Standardzuordnungen

## 0.7.1 (2026-09-20)

- Buchungen lassen sich mit Befehlsklick oder Umschaltklick gemeinsam auswählen und nach einer Bestätigung zusammen löschen. Bei einer Auswahl bleibt der normale Inspector sichtbar, bei mehreren zeigt er nur deren Anzahl

## 0.7.0 (2026-09-20)

- Bestätigen prüft nur noch die Regeln, die eine Buchung ungültig machen. Eine Rechnung, deren Rundung je Zeile um mehr als einen Cent abweicht, und eine echt vorausdatierte Rechnung lassen sich jetzt bestätigen; für den Agenten gelten beide Regeln unverändert weiter
- Eine Eingangsrechnung darf einen anderen Steuersatz als 19 oder 7 tragen, etwa den Pauschalsatz nach §24 UStG; bei Einnahmen bleiben 19 und 7 verbindlich, Steuersatz 0 gehört in beiden Richtungen auf steuerfrei oder nicht_steuerbar
- UStVA und EÜR: Die Zehn-Prozent-Grenze des Vorsteuerabzugs entfällt. Sie gilt nur für Gegenstände, und Pfennig unterscheidet Gegenstand und Leistung nicht; auch ein kleiner betrieblicher Anteil bleibt damit abziehbar
- Der Agent erfährt in der Werkzeugbeschreibung, dass er `afa_tabelle` lesen darf. Bisher widersprach sie der Regel, die Nutzungsdauer von dort zu holen
- `scripts/release.sh` führt die Tests aus, bevor es etwas entfernt

## 0.6.0 (2026-09-18)

- Inspector: Bei `reverse_charge` bleibt die Positionssteuer bei Änderungen von Netto und Satz null und das Steuerfeld ist deaktiviert; beim Wechsel auf `reverse_charge` wird vorhandene Steuer geleert, beim Wechsel weg davon neu aus Netto und Satz berechnet
- Bestätigen prüft die gespeicherte Buchung mit denselben Prüfregeln wie der Agent; bei Fehlern bleibt der Prüfstatus unverändert und die Meldung erscheint im bestehenden Fehlerhinweis. Der Wechsel einer Ausgabe zu einer Einnahme löscht die Nutzungsdauer
- UStVA: Kz 67 zählt bei Reverse-Charge-Dienstleistungen nur den betrieblichen Anteil der geschuldeten Steuer; die Zehn-Prozent-Grenze wird dort nicht angewandt, sie betrifft Gegenstände (§15 Abs. 1 UStG)
- EÜR: Ein Anlagegut gehört in jedes Jahr seiner laufenden AfA, also auch in Fristen, Ungeprüft-Hinweis und Änderungswarnung bereits exportierter Jahre; für die UStVA bleiben Beleg- und Zahlungsdatum maßgeblich
- EÜR: Ein Anlagegut ohne Kategorie steht mit seiner AfA auf Zeile 34 und in der Anlage AVEÜR, statt aus der Rechnung zu verschwinden
- Eingang: Eine übrig gebliebene Inbox-Kopie einer bereits verarbeiteten Datei wird beim Start entfernt, statt sich bei jedem Start erneut zu melden
- EÜR-Export: Textzellen des CSV stehen in Anführungszeichen, eingebettete Anführungszeichen werden verdoppelt; ein Titel mit Semikolon oder Zeilenumbruch verschiebt keine Spalten mehr

- UStVA: Eine sonstige Leistung an ein EU-Unternehmen steht mit ihrem vollen Netto im Zeitraum des Belegdatums in Kz 21. Anzahlungen und späte Zahlungen verschieben sie nicht mehr, denn Kz 21 folgt der Leistungsausführung (Anleitung USt 1 E 2026 zu Zeile 35, §18b Satz 3 UStG); das Belegdatum steht dafür ein. Kz 45 zählt weiter je Zahlung
- UStVA: Ein §13b-Bezug zu 7 Prozent ist darstellbar. Eine Position mit `reverse_charge` trägt jetzt den Steuersatz, den der Leistungsempfänger schuldet (19 oder 7), und `steuer` 0; Kz 47, 85 und 67 rechnen mit diesem Satz statt pauschal mit 19 Prozent. Ein E-Book aus Irland wurde bisher um zwölf Punkte zu hoch gemeldet
- UStVA: Ein nicht steuerbarer Umsatz steht nur noch in Kz 45, wenn `gegenpartei_land` gesetzt und nicht DE ist. Nicht steuerbare Inlandsumsätze gehören dort nicht hin (Anleitung zu Zeile 36) und bleiben aus dem Formular

- Anlagevermögen: Eine Ausgabe mit `nutzungsdauer_jahre` ist ein Anlagegut. Sie steht in der EÜR nicht mehr auf ihrer Kategoriezeile, sondern mit der AfA des Jahres auf Zeile 34, linear ab dem Anschaffungsmonat und im letzten Jahr mit dem Rest; ihre Vorsteuer zählt unverändert im Zahlungszeitraum. Der Inspector zeigt bei Ausgaben das Feld „Nutzungsdauer in Jahren“, der EÜR-Export bekommt einen zweiten Block für die Anlage AVEÜR mit Einzelliste, und der Agent findet die Nutzungsdauer in der neuen Tabelle `afa_tabelle`, der amtlichen AfA-Tabelle (BMF vom 15.12.2000, Computerhardware nach BMF vom 22.02.2022)
- Dateien werden zuerst gespeichert, dann läuft der Agent; er hängt den Beleg selbst an die Buchung, wodurch „Beleg fehlt“ nicht mehr kurz aufblitzt. Kontoauszüge kann der Agent jetzt verarbeiten: Zahlungen zu bestehenden Buchungen, Bewegungen ohne Buchung als `nur_zahlung`, private als `ignoriert`
- Dateien bleiben im Archiv, auch wenn ihre Buchung gelöscht oder der Beleg abgehängt wird; eine Datei mit gelungenem Lauf geht nicht erneut zum Agenten, eine ohne läuft beim erneuten Ablegen noch einmal
- Mehrere gleichzeitig abgelegte Dateien scheiterten mit „Die Verbindung zu OpenAI kam nicht zustande: Die Nachricht ist zu lang“, sobald macOS für den Host HTTP/3 gelernt hatte. Jede Anfrage nutzt jetzt eine eigene ephemere Verbindung, die bei HTTP/2 bleibt; ein gescheiterter Verbindungsaufbau wird zusätzlich einmal wiederholt

Hinweise:

- Schemawechsel ohne Migration: `dateien` hat eine hochzählende `id`, `belege` sind Datei-IDs, die Spalte `art` entfällt; `aktivitaeten.nachher` darf leer sein. Das Entwicklungsarchiv des Eigentümers wurde mit Backup zurückgesetzt bzw. angepasst
- Schemawechsel ohne Migration: `buchungen` hat die Spalte `nutzungsdauer_jahre`, dazu kommt die Tabelle `afa_tabelle`, die die App bei jedem Start aus der mitgelieferten CSV neu füllt

- Der Eingang nimmt neben PDF und Bildern jetzt auch WebP sowie Textdateien an (XML, CSV, TXT, JSON, HTML); Textdateien gehen bis 1 MB als Klartext an den Agenten, damit liest er auch XRechnungen. Windows-1252-kodierte Bank-Exporte kommen mit Umlauten an
- UStVA: Reverse-Charge-Einnahmen an Kunden außerhalb der EU stehen in Kz 45 statt in Kz 21; Kz 21 bleibt für Leistungen an EU-Unternehmer
- UStVA und EÜR: Die Vorsteuer in Kz 66 und in der EÜR-Zeile „Gezahlte Vorsteuer“ zählt nur den betrieblichen Anteil einer Ausgabe mit Privatanteil; unter zehn Prozent betrieblicher Nutzung entfällt sie ganz
- Fristen für UStVA und EÜR rücken auf den nächsten Werktag, wenn sie auf ein Wochenende oder einen bundesweiten Feiertag fallen
- Der Agent bekommt klarere Rückmeldungen: `inland` nur mit 19 oder 7 Prozent, `reverse_charge` ohne Steuer in den Positionen
- Das Löschen einer Buchung steht jetzt im Aktivitätenprotokoll
- EÜR: Die Zeilennummern folgen jetzt der amtlichen Anlage EÜR 2026 (BMF vom 01.09.2026) statt einem alten Platzhalter; Einnahmen stehen je nach Steuerbehandlung auf Zeile 12, 15 oder 16, die Umsatzsteuer auf 17 und 58, der Export trägt die amtlichen Zeilentitel und nennt in der Kopfzeile das Formularjahr
- EÜR: Ein Privatanteil kürzt nur noch Ausgaben; bei einer Einnahme blieb er bisher fälschlich vom Umsatz abgezogen
- EÜR: In der Zeile „Gezahlte Vorsteuer“ steht nur noch die nach §15 UStG abziehbare Vorsteuer. Ausländische oder steuerfreie Rechnungen und Ausgaben unter zehn Prozent betrieblicher Nutzung stehen jetzt brutto auf ihrer Kategoriezeile, wie es die Anleitung zu Zeile 58 verlangt; bisher galt jede gezahlte Steuer als Vorsteuer und der nicht abziehbare Teil fiel aus dem Gewinn heraus
- EÜR: Bewirtungsaufwendungen stehen in Zeile 64 jetzt in beiden Spalten des Formulars, 30 Prozent nicht abziehbar und 70 Prozent abziehbar (§4 Abs. 5 Satz 1 Nr. 2 EStG); nur die 70 Prozent mindern den Gewinn, die Vorsteuer bleibt voll abziehbar
- UStVA: Griechenland wird auch unter der umsatzsteuerlichen Kennung `EL` als EU-Mitgliedstaat erkannt, nicht nur unter `GR`
- Der Agent behandelt den Inhalt einer Datei als Daten und Beweismaterial, nicht als Anweisung
- Ein fehlgeschlagener Eintrag ins Anfragenprotokoll bricht einen erfolgreichen Import nicht mehr ab und löscht keine Buchungen mehr
- Drag-and-drop funktioniert auch auf der Startseite
- Eine Datei, die während des letzten laufenden Imports abgelegt wird, bleibt nicht mehr liegen
- „Neue Buchung“ setzt auch den Statusfilter zurück, damit die neue Buchung sichtbar ist
- Die Einstellungen melden, wenn der Schlüssel nicht im Schlüsselbund gespeichert werden konnte, statt einen hinterlegten Schlüssel anzuzeigen

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
