# Aktuell und später

Stand 2026-10-12, nach Release 0.11.2. GitHub-Issues halten offene Arbeit fest, nicht automatisch freigegebene Implementierungspläne. Neue Umsetzung braucht einen mit dem Eigentümer abgestimmten Umfang. Entscheidungen stehen in `.memory/MEMORY.md`, der Umsetzungsstand in `docs/status.md`. Abgeschlossen oder entschieden: #1, #2, #3, #5, #6, #8, #10, #12, #18, #20.

## Nächste Schritte

1. **Zuverlässigkeitsrelease 0.11.2 im Einsatz prüfen.** Archivkorrektur, Belegwiederholung und verständliche Startfehler sind veröffentlicht; synthetischer Archiverhalt ist geprüft. Der Eigentümer hat den normalen App-Updatezyklus und den erneuten Vercel-Import erfolgreich durchgeführt. Ein echter Sparkle-Updatezyklus mit signierten Builds in einem getrennten macOS-Testkonto bleibt eigene Abnahme; Quellcode- und Archivtests ersetzen ihn nicht. Veröffentlichung und Installation brauchen einen ausdrücklichen Eigentümerauftrag.
2. **Luna mit unabhängigen Fällen weiter absichern.** Die beauftragten öffentlichen Vergleichsläufe sind abgeschlossen: final 51/52, Reihenfolgenvergleich 11/12 statt 2/12. Nächster begrenzter Vorschlag sind bislang unbenutzte Fälle für gleiche Beträge, ähnliche Rechnungsnummern und fehlende Zuordnungen; keine neue Umsetzung ohne abgestimmten Umfang. Bekannte Lücken sind Coworking-Kategorie und gelegentlich ausgelassene Suche. [Nachweise](luna-reliability-20261012.md). Apple-KI bleibt ausschließlich unter `evals/apple-ai/`, ohne Produktionsintegration.
3. **Steuerjahr 2027 amtlich verifizieren, vom Eigentümer beauftragt.** Neue BMF-Formulare und Anleitungen für UStVA und EÜR getrennt mit den vorhandenen Kennzahlen und Zeilen vergleichen. Der Export bleibt bis dahin auf 2026 begrenzt. [ELSTER plant UStVA 2027 für den 01.01.2027](https://www.elster.de/eportal/infoseite/bereitstellungstermine); ein späterer Eigentümer-Testimport ohne Übermittlung muss die XML-Kompatibilität belegen. Auch die 2026-Kennzahlen 89/93/61/39 brauchen noch eine eigene ELSTER-Abnahme. [Nachweise und Prüfplan](reliability-advisor-20261012.md).
4. **Steuerbeträge auf Buchungen zurückführen, nur Vorschlag.** Der Eigentümer ist offen dafür; vor Umsetzung den kleinen, aber rechnungsrelevanten Core-/UI-Umfang abstimmen. Beiträge in den bestehenden Berechnungen erfassen und tatsächliche Gesamtrundung sowie Profilbeträge gesondert zeigen; keine zweite Berechnung pro Buchung. [Begrenzter Entwurf](reliability-advisor-20261012.md#bounded-tax-total-drilldown-proposal).
5. **Chat [#16](https://github.com/pietz/pfennig/issues/16) im Alltag prüfen.** Ein Agent für Import und Chat, zustandslos, Verlauf ohne Dateibytes in `gespraeche`; seit 0.10.0 veröffentlicht. Dateienübersicht [#17](https://github.com/pietz/pfennig/issues/17) und Anfragekosten [#19](https://github.com/pietz/pfennig/issues/19) bleiben zurückgestellt, bis der Einsatz konkreten Bedarf zeigt.

Außerdem offen: ausgewählter Einstellungstab im dunklen Modus mit zu wenig Kontrast. Eine globale hellere Akzentfarbe macht Tabellenmarkierungen schlechter lesbar; lokale SwiftUI-Tints erreichen die nativen Einstellungstabs nicht. Vor weiterer Umsetzung einen begrenzten Farb-/Auswahlumfang abstimmen, keine AppKit-Introspektion oder eigene Tab-Oberfläche ergänzen. [Native Prüfung](macos27-ui-check.md).

Außerdem offen: Landingpage-Medien, fünf vorgesehene Plätze, Integration nach Bereitstellung der Assets.

## Geparkt

### Eingang und Prüfung

- Kontoabgleich [#7](https://github.com/pietz/pfennig/issues/7): Sammelüberweisungen, Mahnungen, Korrekturen, Raten und Erstattungen; Kontoabdeckung vor einer Aussage „abgeglichen“. Künftig im Chat-Kontext, nicht beim Ablegen.
- Kontextunterlagen wie Kontoauszüge und Anlageverzeichnisse kommen später über den Chat.
- ZUGFeRD: eingebettetes XML in PDFs wird nicht ausgelesen.
- Bewirtung: Anlass, Teilnehmer und fehlende Angaben klären.
- XRechnung als weiterer Live-Testfall.

### Steuerlicher Umfang

- Eigene EU-Warenlieferungen (Kz 41).
- Zusammenfassende Meldung, Umsatzsteuer-Jahreserklärung, Kleinunternehmer-Grenzen, Einkommensteuerschätzung und Rücklage. Jeweils eigener Umfang und amtliche Prüfung nötig.
- Wertabgaben, Kleinunternehmer-Hinweis bei §13b, regionale Feiertage über ein Bundesland, Storno statt Löschen bereits exportierter Buchungen.
- Weitere Anlagefälle: Fahrzeuge, Gebäude/Grundstücke, immaterielle Anlagen, Verkauf/Privatentnahme, degressive AfA, §7g, Sammelposten, nachträgliche Anschaffungskosten.

### Arbeiten mit vorhandenen Daten

- Agentenzugriff auf Aktivitäten und Rückgängigmachen: nicht beschlossene Ideen.
- Übergabe an den Steuerberater: Jahresordner mit Belegen, Buchungsliste und Steuerwerten; Nutzen eines etablierten Formats vorab klären.
- Erwartete wiederkehrende Belege; ein Hinweis ersetzt die fehlende Rechnung nicht.
