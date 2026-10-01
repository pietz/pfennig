# Aktuell und später

Stand 2026-10-01, nach Release 0.9.0. GitHub-Issues halten offene Arbeit fest, nicht automatisch freigegebene Implementierungspläne. Neue Umsetzung braucht einen mit dem Eigentümer abgestimmten Umfang. Entscheidungen stehen in `.memory/MEMORY.md`, der Umsetzungsstand in `docs/status.md`. Abgeschlossen oder entschieden: #1, #2, #3, #5, #6, #8, #10, #12, #18, #20.

## Nächste Schritte

1. **Stabilisierung von 0.9.0.** Echter Einsatz von 0.9.0, Live-API-Test mit `scripts/test-live.sh` (braucht separate Freigabe für API-/Schlüsselbundzugriff), Durchlauf der Q3-Beispieldaten aus `sample-data/2026-q3/` und ELSTER-Prüfung der neuen Kennzahlen 89/93/61/39. Befunde daraus werden die nächste Arbeitsliste.
2. **Chat [#16](https://github.com/pietz/pfennig/issues/16), erster Schritt gebaut, Eigentümerprüfung ausstehend.** Ein Agent für Import und Chat, zustandslos, Verlauf ohne Dateibytes in `gespraeche`. Schemaänderung mit [Arbeitsblatt](maintenance/0.10.0.md) für bestehende Archive; Live-API-Prüfung steht aus.
3. **Dateienübersicht [#17](https://github.com/pietz/pfennig/issues/17) und Anfragekosten [#19](https://github.com/pietz/pfennig/issues/19)** bleiben zurückgestellt, bis der Einsatz konkreten Bedarf zeigt.

Außerdem offen: Landingpage-Medien, fünf vorgesehene Plätze, Integration nach Bereitstellung der Assets.

## Geparkt

### Apple Intelligence als optionale KI

Wieder aufnehmen, sobald der Eigentümer macOS 27 installiert hat (2026-10-01). Anlass: Stay Steady nutzt lokale KI; Apples neueres Modell könnte für Pfennig ausreichend sein und API-Einrichtung sowie laufende API-Kosten vermeiden. Keine gemessene Qualität gegenüber dem derzeitigen GPT-5.6 Luna und kein Auftrag zur Integration.

- Das über Foundation Models tatsächlich verfügbare macOS-27-Modell mit Luna vergleichen. Bildverarbeitung, Kontextbudget und Werkzeugaufrufe auf dem Testgerät prüfen; Grenzen von macOS 26 nicht ungeprüft übertragen. [Apple: neue Framework-Funktionen](https://developer.apple.com/videos/play/wwdc2026/241/).
- Vorhandene synthetische Belege aus `sample-data/2026-q3/` verwenden: zuerst denselben extrahierten Text für beide Modelle, dann vollständige Dokumentverarbeitung. Korrekte Beträge, Steuerbehandlung, Zahlungsstatus, SQL-Werkzeugabläufe, Wiederholbarkeit, Laufzeit und manuellen Korrekturaufwand vergleichen.
- Danach Aufwand einer wählbaren lokalen KI im bestehenden Agenten bewerten. Apples Private Cloud Compute separat betrachten: Serververarbeitung, Nutzungslimits und [App-Store-/Entitlement-Voraussetzungen](https://developer.apple.com/private-cloud-compute/).
- Geschäftsidee prüfen: kostenlose lokale Basis-KI, stärkere KI als Pro-Angebot eventuell im Abonnement. Erst nach belegtem Qualitätsunterschied und Klärung der laufenden Kosten entscheiden; Modellwahl, Preise, Abrechnung und Ablösung des eigenen API-Schlüssels sind offen.

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
