# Aktuell und später

Stand 2026-09-23, nach Release 0.9.0. GitHub-Issues halten offene Arbeit fest, nicht automatisch freigegebene Implementierungspläne. Neue Umsetzung braucht einen mit dem Eigentümer abgestimmten Umfang. Entscheidungen stehen in `.memory/MEMORY.md`, der Umsetzungsstand in `docs/status.md`. Abgeschlossen oder entschieden: #1, #2, #3, #5, #6, #8, #10, #12, #18, #20.

## Nächste Schritte

1. **Stabilisierung von 0.9.0.** Echter Einsatz von 0.9.0, Live-API-Test mit `scripts/test-live.sh`, kontrollierte Eval-Läufe mit `evals/` und ELSTER-Prüfung der neuen Kennzahlen 89/93/61/39. Befunde daraus werden die nächste Arbeitsliste. Eine Luna/medium-Baseline über den gesamten Eval-Satz liegt lokal vor; Modell-, Reasoning- und Promptvergleich folgen.
2. **Chat [#16](https://github.com/pietz/pfennig/issues/16), erster Schritt gebaut, Eigentümerprüfung ausstehend.** Ein Agent für Import und Chat, zustandslos, Verlauf ohne Dateibytes in `gespraeche`. Schemaänderung mit [Arbeitsblatt](maintenance/0.10.0.md) für bestehende Archive; Live-API-Prüfung steht aus.
3. **Dateienübersicht [#17](https://github.com/pietz/pfennig/issues/17) und Anfragekosten [#19](https://github.com/pietz/pfennig/issues/19)** bleiben zurückgestellt, bis der Einsatz konkreten Bedarf zeigt.

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
