# Backlog

Ideen aus der Produktdiskussion am 2026-09-16, vom Eigentümer als lohnend eingestuft. Offene Ideen brauchen vor dem Bau eine Entscheidung des Eigentümers und einen vereinbarten Plan; eine separate Spezifikation ist nicht erforderlich. Die Reihenfolge innerhalb eines Themas ist eine Empfehlung.

Arbeitsteilung mit den GitHub-Issues: ein konkreter Fehler mit bekannter Behebung wird ein Issue, eine Produktfrage, die zuerst eine Entscheidung braucht, steht hier. Wo ein Thema beides hat, wird es getrennt und beide Seiten verweisen aufeinander.

## 1. Genauigkeit des Eingangs

Was hier besser wird, verbessert jede Zahl dahinter.

- **Textformate im Eingang.** Entschieden am 2026-09-16: Textdateien gehen als Klartext an den Agenten, ohne Parser. Damit liest der Agent XRechnungen und beliebige CSV- oder JSON-Exporte. Umgesetzt.
- **ZUGFeRD-XML auslesen.** Zurückgestellt. Ein ZUGFeRD-PDF trägt das XML als Anhang; heute liest der Agent nur das Bild. Rechtlich gilt das XML, praktisch stimmen beide fast immer überein. Falls Ziffernfehler aus dem Bild auftreten, den Anhang über CGPDF holen und als Text neben das PDF legen, etwa fünfzig Zeilen.
- **Kontoauszüge und Abgleich.** Begonnen am 2026-09-16 als Absatz in der Anleitung (siehe Ergänzung Dateien); noch ungetestet mit echten Auszügen. Anders als ein Beleg ist eine Kontobewegung kein eigenes Dokument, sondern muss gegen bestehende Buchungen abgeglichen werden: Zahlungsdatum und Betrag an die passende Rechnung, Rest als `nur_zahlung` oder `ignoriert`. Braucht ein eigenes Konzept für den Agentenlauf mit Zugriff auf die offenen Buchungen. Größte Lücke im Kernablauf, weil die Ist-Versteuerung am Zahlungsdatum hängt.
- **Bewirtung: Anlass und Teilnehmer erfragen.** Ein Bewirtungsbeleg ist nur mit Anlass und Teilnehmern vollständig; beides steht selten auf dem Beleg. Der Agent kann heute nicht nachfragen, also fehlen die Angaben still. Braucht eine Entscheidung zum Fragekanal, siehe Issue #5. Die 70/30-Aufteilung selbst ist seit 0.6.0 umgesetzt.

## 2. Steuerliche Vollständigkeit

Pflichten und Fehler, die die Zielgruppe regelmäßig treffen.

- **Zusammenfassende Meldung.** Wer Kz-21-Umsätze hat, schuldet quartalsweise eine ZM an das BZSt: je EU-Kunde USt-IdNr und Summe, fällig am 25. des Folgemonats. Alle Felder liegen in den Buchungen; im Kern ein zweiter Export plus Frist auf der Startseite.
- **Umsatzsteuer-Jahreserklärung.** Dieselben Kennzahlen über das Jahr summiert, als XML für Mein ELSTER wie die UStVA. Aufbau muss wie bei der UStVA aus öffentlichen Quellen rekonstruiert und per Testupload geprüft werden.
- **Anlagevermögen und AfA.** Umgesetzt und mit 0.6.0 veröffentlicht: `nutzungsdauer_jahre` an der Buchung, Nutzungsdauer aus der mitgelieferten `afa_tabelle`, lineare AfA auf EÜR-Zeile 34 und die Anlage AVEÜR im Export. Bewusst nicht abgedeckt bleiben Fahrzeuge, Gebäude, immaterielle Wirtschaftsgüter, Abgang und Privatentnahme, degressive AfA und Sammelposten.
- **Kleinunternehmer-Grenzen.** Einnahmen des Vorjahres gegen 25.000 Euro und des laufenden Jahres gegen 100.000 Euro auf der Startseite. Das Überschreiten der zweiten Grenze wirkt sofort, nicht erst zum Jahreswechsel.
- **Steuerschätzung und Rücklage.** Offene UStVA-Zahllast plus geschätzte Einkommensteuer auf den Jahresgewinn, als eine Zahl auf der Startseite: was vom Kontostand nicht dem Nutzer gehört. Braucht Grundfreibetrag, Tarif und ein paar Annahmen (Familienstand, Kirchensteuer, sonstige Einkünfte), die ehrlich als Schätzung ausgewiesen werden.

## 3. Arbeiten mit den Daten

- **Agent zum Sprechen.** Ein Gespräch mit dem Agenten über die Buchhaltung: Fragen zu Buchungen und Zeiträumen, Nachfragen, Dokumente im Gespräch ablegen. Chat liegt außerhalb des bisherigen Produktumfangs; dafür braucht es eine neue Grundsatzentscheidung des Eigentümers. Offene Fragen: eigener Bereich oder Teil der Buchungsansicht, welche Werkzeuge der Gesprächsagent bekommt, ob er schreiben darf.
- **Aktivitäten lesen und rückgängig machen.** Der Agent bekommt Lesezugriff auf `aktivitaeten`, um frühere Änderungen zu verstehen. Der Nutzer kann eine Aktivität auf `vorher` zurücksetzen; das JSON liegt bereits vor.
- **Übergabe an den Steuerberater.** Ein Jahresordner mit Belegen nach Datum und Gegenpartei benannt, Buchungsliste und EÜR-Werte als CSV. Prüfen, ob ein etabliertes Format lohnt (DATEV-Buchungsstapel, CSV-Konventionen der gängigen Kanzleisoftware) oder ob ein sauberer Ordner reicht.
- **Live-API-Tests.** Ein optionaler erster Ablauf ist unter `scripts/test-live.sh` gebaut: synthetische PDF-Rechnung, CSV-Kontoauszug mit Zuordnung und Doppelimport, gegen Luna bei niedrigem Aufwand. Normale Tests und CI lassen ihn aus. Der erste Live-Lauf und eine Ergänzung um XRechnung stehen noch aus.

- **Reste aus dem Steuer-Review (2026-09-17).** Kleinunternehmer mit §13b-Eingang schulden die Steuer, ohne dass Pfennig die EÜR daran erinnert; Kz 87 (§13b-Eingang zu 7 Prozent) fehlt; unentgeltliche Wertabgaben bei nachträglicher Privatnutzung; regionale Feiertage bei Fristen (Fronleichnam, Reformationstag) über ein Bundesland im Profil; Storno statt Löschen für bereits exportierte Zeiträume.

## Verworfen oder zurückgestellt

- **Erwartete wiederkehrende Belege.** Für Abos fehlt am Ende trotzdem die Rechnung; der Hinweis allein spart wenig. Zurückgestellt.

## Empfohlene Reihenfolge

1. Textformate im Eingang: umgesetzt.
2. Kontoauszüge und Abgleich: die größte Lücke im Kernablauf. Das Konzept dafür klärt zugleich, wie ein Agentenlauf mit Kontext auf bestehende Buchungen aussieht, und bereitet damit den Gesprächsagenten vor.
3. Anlagevermögen und AfA: umgesetzt.
4. Kleinunternehmer-Grenzen, ZM und Jahreserklärung: kleine Exporte und Anzeigen auf vorhandenen Daten.
5. Gesprächsagent: als Produktentscheidung, sobald 2 steht.
