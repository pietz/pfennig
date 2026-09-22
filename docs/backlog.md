# Aktuell und später

Stand 2026-09-22. GitHub-Issues halten offene Arbeit fest, nicht automatisch freigegebene Implementierungspläne. Der aktuelle Schritt bleibt von nächsten und geparkten Themen getrennt. Neue Umsetzung braucht einen mit dem Eigentümer abgestimmten Umfang, keine neue Gesamtspezifikation.

## Abgeschlossene Schritte

Automatischer Dateieingang nur für Rechnungen, Quittungen und Gutschriften. Kontoauszüge und andere kontextbedürftige Unterlagen kommen später über den Chat. `noBooking` bleibt: ohne geänderte Buchung endet der Lauf mit dem bestehenden Fehler. Prompt und Landingpage sind darauf begrenzt; Tests, Build und Review sind abgeschlossen.

Die fünf Handoff-Vorschläge sind abgeschlossen oder entschieden: Zahlungs-Default für eigene Ausgangsrechnungen, tatsächlich geflossene Zahlungssumme, relative Vorzeichen und SQL-Beschreibung des lesenden AfA-Zugriffs sind umgesetzt. `noBooking` bleibt, keine Sonderregel für negative Gutschriften. Die `nur_zahlung`-Anweisung ist ohne automatischen Kontoauszugsimport zurückgestellt; die Exportpolitik bleibt separat offen in #20.

Landingpage-Medien bleiben ausstehend: fünf vorgesehene Plätze, Integration nach Bereitstellung der Assets.

## Nächste Schritte

1. Bestehende Korrektheitsfragen einzeln behandeln, zuerst die Steuer-Issues #3, #8 und #12. Jeweils Umfang klären, dann bauen oder die Grenze ausdrücklich festhalten.
2. Übrige offene Bestandsthemen durchgehen und priorisieren, bevor neue größere Funktionen beginnen. Keine pauschale Umsetzung aller Issues.

## Größere Funktionen zurückgestellt

- **Chat [#16](https://github.com/pietz/pfennig/issues/16).** Kommt grundsätzlich, aber erst nach den Bestandsthemen. Besprochene Richtung: nativer Chatbereich, Gesprächsmenü ohne zweite Sidebar, neues Gespräch und manuelles Löschen, dauerhafter nötiger Verlauf als JSON ohne Dateibytes, bestehende Tools und gemeinsamer Prompt. Details im Issue. Noch keine Implementierung, Schemaänderung oder Archivumstellung.
- **Dateienübersicht [#17](https://github.com/pietz/pfennig/issues/17).** Gespeicherte Dateien und ihre Buchungsverknüpfungen sichtbar machen, auch ohne zugehörige Buchung. Platz und Aktionen noch abzustimmen. Ebenfalls kein aktueller Umsetzungsauftrag.

## Weitere offene Themen

### Eingang und Prüfung

- Warnungen und Duplikaterkennung: als eigenes Thema klären, nicht in den aktuellen Importumbau aufnehmen.
- **Unsicherheiten und Rückfragen [#5](https://github.com/pietz/pfennig/issues/5), offen.** Unsichere Angaben sichtbar machen; konkrete Verbindung mit Chat #16 noch klären.
- **Kontoabgleich [#7](https://github.com/pietz/pfennig/issues/7), offen.** Sammelüberweisungen, Mahnungen, Korrekturen, Raten und Erstattungen; Kontoabdeckung vor einer Aussage „abgeglichen“. Künftig im Chat-Kontext, nicht automatisch beim Ablegen.
- **Plattformauszahlungen [#6](https://github.com/pietz/pfennig/issues/6), offen.** Umsatz, Gebühren und tatsächliche Auszahlung aus Abrechnungen unterscheiden, nicht aus dem Plattformnamen ableiten.
- ZUGFeRD-XML auslesen: heute nur PDF-Bild; eingebettetes XML bewusst nicht extrahiert. Textformate einschließlich eigenständiger XML-Rechnungen sind bereits unterstützt.
- Bewirtung: Anlass und Teilnehmer sowie fehlende Angaben klären. Die 70-Prozent-Kürzung und Vorsteuerbehandlung sind bereits umgesetzt.
- Live-API-Tests mit fiktionalen Dokumenten als separater, ausdrücklich freigegebener Lauf, nicht Teil der normalen Tests.

### Steuerlicher Umfang und Übernahme

- **Ungeklärte Zahlungen im Export [#20](https://github.com/pietz/pfennig/issues/20), offen.** EÜR kann `nur_zahlung` und `unklar` berücksichtigen, UStVA schließt `unklar` aus. Gewünschte Exportpolitik separat entscheiden, keine neue Agentenregel im aktuellen Import.

- **Bestehende Finanzen übernehmen [#2](https://github.com/pietz/pfennig/issues/2), offen.** Extern gemeldete Zeiträume, offene Rechnungen mit unbekanntem Zahlungsstand und alte Anlagebestände ohne doppelte Zahlungen übernehmen. Kontextbedürftige Unterlagen künftig im Chat; kein automatischer Import eines Anlageverzeichnisses im aktuellen Schritt.
- **Einkommensteuer-Vorauszahlungen [#3](https://github.com/pietz/pfennig/issues/3), offen.** Dürfen den EÜR-Gewinn nicht mindern; passende Abbildung ohne EÜR-/UStVA-Wirkung klären.
- **Sondervorauszahlung [#8](https://github.com/pietz/pfennig/issues/8), offen.** Kz 39 im Dezember bei monatlicher UStVA mit Dauerfristverlängerung berücksichtigen.
- **Innergemeinschaftliche Waren [#12](https://github.com/pietz/pfennig/issues/12), offen.** Erwerbe auf Kz 89/93 und 61 statt Dienstleistungs-§13b; ebenso fehlt Kz 41 für innergemeinschaftliche Lieferungen.
- Zusammenfassende Meldung; Umsatzsteuer-Jahreserklärung; Kleinunternehmer-Grenzen; Einkommensteuerschätzung und Rücklage. Jeweils eigener Umfang und amtliche Prüfung nötig.
- Wertabgaben, Kleinunternehmer-Hinweis bei §13b, regionale Feiertage über ein Bundesland und Storno statt Löschen bereits exportierter Buchungen bleiben geparkt. §13b mit 7 Prozent ist umgesetzt (#10 geschlossen).
- Anlagevermögen, lineare AfA und AVEÜR sind gebaut (#1 geschlossen). Weitere Anlagefälle bleiben außerhalb des heutigen Umfangs: Fahrzeuge, Gebäude/Grundstücke, immaterielle Anlagen, Verkauf/Privatentnahme, degressive AfA, §7g, Sammelposten und nachträgliche Anschaffungskosten.

### Arbeiten mit vorhandenen Daten

- **Aktivitätsverlauf anzeigen [#18](https://github.com/pietz/pfennig/issues/18), offen.** Übernommene unerfüllte Anforderung aus dem Neuaufbau: vorhandene Änderungen lesbar anzeigen, ohne Undo oder Agentenzugriff. Noch kein Implementierungsplan.
- **Anfragekosten berechnen [#19](https://github.com/pietz/pfennig/issues/19), offen.** Übernommene unerfüllte Anforderung: gespeicherte Tokens mit einer Preistabelle im Code auswerten. Kein Dashboard oder Abrechnungssystem, noch kein Implementierungsplan.
- Agentenzugriff auf Aktivitäten und Rückgängigmachen bleiben separate, nicht beschlossene Ideen, ausdrücklich nicht Teil von #18.
- Übergabe an den Steuerberater: Jahresordner mit Belegen, Buchungsliste und Steuerwerten; Nutzen eines etablierten Formats vorab klären.
- Erwartete wiederkehrende Belege: zurückgestellt; ein Hinweis ersetzt die fehlende Rechnung nicht.
