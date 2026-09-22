# Aktuell und später

Stand 2026-09-22. GitHub-Issues halten offene Arbeit fest, nicht automatisch freigegebene Implementierungspläne. Der aktuelle Schritt bleibt von nächsten und geparkten Themen getrennt. Neue Umsetzung braucht einen mit dem Eigentümer abgestimmten Umfang, keine neue Gesamtspezifikation.

## Abgeschlossene Schritte

Automatischer Dateieingang nur für Rechnungen, Quittungen und Gutschriften. Kontoauszüge und andere kontextbedürftige Unterlagen kommen später über den Chat. `noBooking` bleibt: ohne geänderte Buchung endet der Lauf mit dem bestehenden Fehler. Prompt und Landingpage sind darauf begrenzt; Tests, Build und Review sind abgeschlossen.

Die fünf Handoff-Vorschläge sind abgeschlossen oder entschieden: Zahlungs-Default für eigene Ausgangsrechnungen, tatsächlich geflossene Zahlungssumme, relative Vorzeichen und SQL-Beschreibung des lesenden AfA-Zugriffs sind umgesetzt. `noBooking` bleibt, keine Sonderregel für negative Gutschriften. Die `nur_zahlung`-Anweisung ist ohne automatischen Kontoauszugsimport zurückgestellt; die Exportpolitik ist separat in #20 entschieden und umgesetzt.

Mehrfachauswahl samt Belegbereinigung, Öffnen über Finder/„Öffnen mit“ und dauerhafter Importabschluss aus dem parallelen Entwicklungsstand sind integriert. Der automatische Eingang bleibt dabei auf Belege begrenzt; die Entwicklungs-App behält ihre eigene Kennung und ihr eigenes Archiv.

Landingpage-Medien bleiben ausstehend: fünf vorgesehene Plätze, Integration nach Bereitstellung der Assets.

## Nächste Schritte

1. Die freigegebenen Bestandsthemen #2, #5, #6, #8 und #20 sind abgeschlossen; #12 ist für EU-Warenkäufe umgesetzt. Nächstes größeres Thema ist Chat #16, dessen konkreter Umsetzungsschritt noch freigegeben werden muss.
2. EU-Warenkäufe aus #12 und die Exportpolitik #20 sind umgesetzt; eigene EU-Warenlieferungen bleiben außerhalb des freigegebenen Umfangs.
3. Jeweils Umfang klären, dann bauen oder die Grenze ausdrücklich festhalten. Keine pauschale Umsetzung aller Issues und keine neuen größeren Funktionen vor den Bestandsthemen.

## Größere Funktionen zurückgestellt

- **Chat [#16](https://github.com/pietz/pfennig/issues/16).** Kommt grundsätzlich, aber erst nach den Bestandsthemen. Besprochene Richtung: nativer Chatbereich, Gesprächsmenü ohne zweite Sidebar, neues Gespräch und manuelles Löschen, dauerhafter nötiger Verlauf als JSON ohne Dateibytes, bestehende Tools und gemeinsamer Prompt. Details im Issue. Noch keine Implementierung, Schemaänderung oder Archivumstellung.
- **Dateienübersicht [#17](https://github.com/pietz/pfennig/issues/17).** Gespeicherte Dateien und ihre Buchungsverknüpfungen sichtbar machen, auch ohne zugehörige Buchung. Platz und Aktionen noch abzustimmen. Ebenfalls kein aktueller Umsetzungsauftrag.

## Weitere offene Themen

### Eingang und Prüfung

- Zusätzliche technische Duplikaterkennung bleibt außerhalb des Umfangs; konkrete Zweifel können über die bestehende Notiz-/Prüflogik sichtbar werden.
- **Unsicherheiten und Rückfragen [#5](https://github.com/pietz/pfennig/issues/5), umgesetzt.** Prompt nutzt bestehende `notizen` für relevante Zusatzinformationen oder konkrete Unsicherheiten mit Grund/Prüfhinweis, ohne Feldwiederholungen; echte unbekannte Steuerzuordnung bleibt `unklar`. Defaults nicht problematisieren, inhaltliche Nutzernotizen erhalten. Implementiert, getestet und unabhängig geprüft. Keine neue UI oder Rückfragelogik; ein späterer Fragekanal gehört zum Chat #16.
- **Kontoabgleich [#7](https://github.com/pietz/pfennig/issues/7), offen.** Sammelüberweisungen, Mahnungen, Korrekturen, Raten und Erstattungen; Kontoabdeckung vor einer Aussage „abgeglichen“. Künftig im Chat-Kontext, nicht automatisch beim Ablegen.
- **Plattformauszahlungen [#6](https://github.com/pietz/pfennig/issues/6), mit vorhandenen Primitiven umgesetzt.** Belegte Einnahmen und einbehaltene Gebühren können getrennte bezahlte Buchungen mit derselben Belegdatei sein; die Nettoüberweisung ist keine zusätzliche Einnahme. Keine dedizierten Integrationen oder automatische Abstimmung, auch nicht für gelegentliche Hyperwallet-Auszahlungen. Bloße Auszahlungsbestätigungen liefern nicht zwingend alle Buchungsangaben; kein pauschales Hochrechnen bei Wiederverkäufern/Merchants of Record. Keine Erweiterung auf automatischen Kontoauszugsimport.
- ZUGFeRD-XML auslesen: heute nur PDF-Bild; eingebettetes XML bewusst nicht extrahiert. Textformate einschließlich eigenständiger XML-Rechnungen sind bereits unterstützt.
- Bewirtung: Anlass und Teilnehmer sowie fehlende Angaben klären. Die 70-Prozent-Kürzung und Vorsteuerbehandlung sind bereits umgesetzt.
- **Live-API-Tests:** `scripts/test-live.sh` bietet einen optionalen Lauf mit synthetischer PDF-Rechnung, Rechnungs-Doppelimport und unverändert abgewiesenem CSV-Kontoauszug. Noch nicht live ausgeführt; braucht eine separate ausdrückliche Freigabe für API-/Schlüsselbundzugriff. Normale Tests und CI überspringen ihn. XRechnung als weiterer Live-Fall bleibt offen.

### Steuerlicher Umfang und Übernahme

- **Ungeklärte Zahlungen im Export [#20](https://github.com/pietz/pfennig/issues/20), entschieden und umgesetzt.** Ungeprüfte Buchungen und ausreichend eingeordnete `nur_zahlung` bleiben enthalten. EÜR nutzt vorhandene Angaben; bei `unklar` fehlt der UStVA die Zuordnung. Beide Exporte zeigen dazu einen zusätzlichen Hinweis unabhängig vom Prüfstatus, UStVA nennt die nicht berücksichtigten Buchungen ausdrücklich. Export bleibt möglich, keine Berechnungsänderung, kein neues Feld oder Warnsystem.

- **Bestehende Finanzen übernehmen [#2](https://github.com/pietz/pfennig/issues/2), im abgestimmten Umfang abgeschlossen.** Zeiträume lassen sich im Exportfenster als anderweitig erledigt markieren, ohne Datei oder Übermittlung. Die Datenübernahme bleibt manuell: offene Rechnungen und Altanlagen im unterstützten linearen AfA-Schema passen in bestehende Buchungen; unbekannte Angaben müssen geklärt werden. Keine Startdatumseinstellung oder Migration. Bei unterjährigem Wechsel vollständige Jahres-EÜR aus beiden Datenbeständen sicherstellen; Anlageverzeichnisse als Kontextunterlagen bleiben beim späteren Chat.
- **Einkommensteuerzahlungen [#3](https://github.com/pietz/pfennig/issues/3), geschlossen als außerhalb des Umfangs.** Keine neue Kategorie oder Sonderlogik. Begründung und bewusste Grenze stehen in `.memory/MEMORY.md`.
- **Sondervorauszahlung [#8](https://github.com/pietz/pfennig/issues/8), umgesetzt.** Festgesetzten Betrag je Jahr im Profil hinterlegen; Kz 39 mindert im Dezember die Zahllast bei monatlicher UStVA mit Dauerfristverlängerung. Keine Berechnung/Anmeldung oder automatische Zahlungsbuchung; andere letzte Meldezeiträume manuell in ELSTER korrigieren.
- **Innergemeinschaftliche Waren [#12](https://github.com/pietz/pfennig/issues/12), teilweise umgesetzt.** Steuerpflichtige EU-Warenkäufe mit eigenem Enumwert auf Kz 89/93 und 61 statt Dienstleistungs-§13b. Keine neuen Felder, Kategorienableitung oder Schwellenautomatik. Gemischte Steuerbehandlungen und abweichende Erwerbs-/Rechnungszeitpunkte bleiben manuell. Eigene EU-Warenlieferungen (Kz 41) sind ausdrücklich zurückgestellt; deshalb bleibt das Issue offen.
- Zusammenfassende Meldung; Umsatzsteuer-Jahreserklärung; Kleinunternehmer-Grenzen; Einkommensteuerschätzung und Rücklage. Jeweils eigener Umfang und amtliche Prüfung nötig.
- Wertabgaben, Kleinunternehmer-Hinweis bei §13b, regionale Feiertage über ein Bundesland und Storno statt Löschen bereits exportierter Buchungen bleiben geparkt. §13b mit 7 Prozent ist umgesetzt (#10 geschlossen).
- Anlagevermögen, lineare AfA und AVEÜR sind gebaut (#1 geschlossen). Weitere Anlagefälle bleiben außerhalb des heutigen Umfangs: Fahrzeuge, Gebäude/Grundstücke, immaterielle Anlagen, Verkauf/Privatentnahme, degressive AfA, §7g, Sammelposten und nachträgliche Anschaffungskosten.

### Arbeiten mit vorhandenen Daten

- **Aktivitätsverlauf anzeigen [#18](https://github.com/pietz/pfennig/issues/18), nicht geplant.** Eigentümerentscheidung vom 22. September: keine Kernfunktion, deshalb aus dem aktuellen Produktumfang gestrichen. Die bestehende Protokollierung bleibt für einen möglichen späteren Bedarf erhalten; keine UI dafür bauen.
- **Anfragekosten berechnen [#19](https://github.com/pietz/pfennig/issues/19), offen.** Übernommene unerfüllte Anforderung: gespeicherte Tokens mit einer Preistabelle im Code auswerten. Kein Dashboard oder Abrechnungssystem, noch kein Implementierungsplan.
- Agentenzugriff auf Aktivitäten und Rückgängigmachen bleiben nicht beschlossene Ideen.
- Übergabe an den Steuerberater: Jahresordner mit Belegen, Buchungsliste und Steuerwerten; Nutzen eines etablierten Formats vorab klären.
- Erwartete wiederkehrende Belege: zurückgestellt; ein Hinweis ersetzt die fehlende Rechnung nicht.
