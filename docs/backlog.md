# Aktuell und später

Stand 2026-11-09, nach Release 0.12.0. GitHub-Issues halten offene Arbeit fest, nicht automatisch freigegebene Implementierungspläne. Neue Umsetzung braucht einen mit dem Eigentümer abgestimmten Umfang. Entscheidungen stehen in `.memory/MEMORY.md`, der Umsetzungsstand in `docs/status.md`. Abgeschlossen oder entschieden: #1, #2, #3, #5, #6, #8, #10, #12, #18, #20.

## Nächste Schritte

1. **Zuverlässigkeitsrelease 0.11.2 im Einsatz prüfen.** Archivkorrektur, Belegwiederholung und verständliche Startfehler sind veröffentlicht; synthetischer Archiverhalt ist geprüft. Der Eigentümer hat den normalen App-Updatezyklus und den erneuten Vercel-Import erfolgreich durchgeführt. Ein echter Sparkle-Updatezyklus mit signierten Builds in einem getrennten macOS-Testkonto bleibt eigene Abnahme; Quellcode- und Archivtests ersetzen ihn nicht. Veröffentlichung und Installation brauchen einen ausdrücklichen Eigentümerauftrag.
2. **Luna mit unabhängigen Fällen weiter absichern.** Die beauftragten öffentlichen Vergleichsläufe sind abgeschlossen: final 51/52, Reihenfolgenvergleich 11/12 statt 2/12. Nächster begrenzter Vorschlag sind bislang unbenutzte Fälle für gleiche Beträge, ähnliche Rechnungsnummern und fehlende Zuordnungen; keine neue Umsetzung ohne abgestimmten Umfang. Bekannte Lücken sind Coworking-Kategorie und gelegentlich ausgelassene Suche. Zurückgestellt (2026-11-24): Im Chat-Kontoabgleich (`stress-07`) beschreibt der Agent eine gefundene Zahlung, statt sie an der Rechnung zu erfassen. [Nachweise](luna-reliability-20261012.md). Apple-KI bleibt ausschließlich unter `evals/apple-ai/`, ohne Produktionsintegration.
3. **Steuerjahr 2027 amtlich verifizieren, vom Eigentümer beauftragt.** Neue BMF-Formulare und Anleitungen für UStVA und EÜR getrennt mit den vorhandenen Kennzahlen und Zeilen vergleichen. Stand 2026-11-24 sind weder UStVA- noch EÜR-Vordrucke 2027 veröffentlicht; der Export bleibt bis dahin auf 2026 begrenzt. [ELSTER plant UStVA 2027 für den 01.01.2027](https://www.elster.de/eportal/infoseite/bereitstellungstermine); ein späterer Eigentümer-Testimport ohne Übermittlung muss die XML-Kompatibilität belegen. Auch die 2026-Kennzahlen 89/93/61/39 brauchen noch eine eigene ELSTER-Abnahme. [Nachweise und Prüfplan](reliability-advisor-20261012.md).
4. **Chat [#16](https://github.com/pietz/pfennig/issues/16) im Alltag prüfen.** Ein Agent für Import und Chat, zustandslos, Verlauf ohne Dateibytes in `gespraeche`; seit 0.10.0 veröffentlicht. Dateienübersicht [#17](https://github.com/pietz/pfennig/issues/17) und Anfragekosten [#19](https://github.com/pietz/pfennig/issues/19) bleiben zurückgestellt, bis der Einsatz konkreten Bedarf zeigt.

Außerdem offen: Landingpage-Medien, fünf vorgesehene Plätze, Integration nach Bereitstellung der Assets.

## Geparkt

### Apple Intelligence als optionale KI

Neue Eigentümerrichtung vom 2026-11-08: offizielle Apple-KI früh unterstützen, OpenAI erhalten und Anthropic/OpenRouter untersuchen. [Gemeinsamer Architekturvorschlag und begrenzter erster Schritt](../plans/ai-providers.md). Der kleinere Responses-Einstieg mit OpenAI/OpenRouter wurde am 2026-11-09 beauftragt und umgesetzt, mit 0.12.0 veröffentlicht; Live-OpenRouter-Abnahme bleibt offen. Die weitergehende Anbieterarchitektur bleibt ein Vorschlag.

Am 2026-11-08 erneut untersucht: Die Siri-AI-Vorschau in macOS 27.3 öffnet eigene App-Werkzeuge und App Skills. Sie belegt kein stärkeres direkt aufrufbares Modell-Backend für den vorhandenen Import/Chat. Die bisherigen schwachen Ergebnisse stammen bereits von macOS 27.0.1, einschließlich Bildverarbeitung. PCC bleibt eine eigene mögliche Route ohne Nutzer-API-Schlüssel, mit ungeklärtem tatsächlichem Zugriff und App-Store-Vertriebsvoraussetzungen. [Neue Untersuchung und begrenzter Prüfplan](../evals/apple-ai/reports/siri-ai-273-investigation-20261108.md).

- Auf einem geeigneten Testgerät zuerst tatsächliche Modellfähigkeiten und die eingefrorenen bisherigen Vergleichsfälle prüfen; dieses Gerät hat macOS 15.8.1/SDK 26.2. Keine neue native Qualitätsmessung in dieser Untersuchung.
- Siri-Werkzeuge und Skills wären ein zusätzlicher Ausführungspfad. Vor einem isolierten Prototyp den begrenzten Umfang abstimmen; zuerst Suche und eine typisierte Änderung mit synthetischen Daten, danach Dokumentübergabe und vollständige Buchung testen. Die Vorschau ist noch nicht für reguläre Kunden verfügbar.
- Vor einem PCC-Vergleich erfolgreichen Zugriff nachweisen; Entitlement-/Kontoeinrichtung und ein möglicher App-Store-Vertrieb bleiben Eigentümerentscheidungen. Keine Produktionsintegration beschlossen.
- Kostenlose lokale Basis-KI und stärkere Pro-KI bleiben unentschiedene Produktideen. Erst belegte Qualität, Nutzungslimits und Vertriebsvoraussetzungen klären.

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
