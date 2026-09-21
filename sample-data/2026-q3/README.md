# Studio Linden: Beispieldaten für Q3 2026

28 vollständig erfundene PDF-Dokumente für eine Hamburger Designerin und Webentwicklerin. Zeitraum Juli bis September 2026, Datenstand 21. September. Für die Vorbereitung der Q3-UStVA im Oktober, nicht für eine echte Steuererklärung.

## Import in Pfennig Dev

1. **Pfennig Dev** öffnen, nicht die installierte Release-App.
2. Im Profil **Mara Winter** eintragen, Kleinunternehmer ausgeschaltet, UStVA vierteljährlich und ohne Dauerfristverlängerung. Die Demo-USt-ID **DE000000000** ist bewusst ungültig und nur für diese fiktionalen Daten bestimmt.
3. Zuerst die 26 PDFs aus `ausgang/`, `einkauf/` und `reise/` auf das App-Fenster ziehen und die Verarbeitung abschließen lassen. Nur PDFs importieren, nicht die Skripte oder JSON-Dateien aus `sources/`.
4. Danach die beiden PDFs aus `bank/` importieren, am besten einzeln nacheinander. Sie enthalten ausschließlich Zahlungseingänge zu bereits vorhandenen Ausgangsrechnungen. Die sieben Eingänge sollen deren Zahlungen ergänzen, nicht sieben zusätzliche Buchungen erzeugen. Die Bankübersichten sind bewusst gefiltert und zeigen keine Ausgaben, Erstattungen oder Kontosalden.
5. Importergebnisse mit den Soll-Daten in `sources/` vergleichen und die Buchungen im Inspector prüfen. Die Soll-Daten sind keine Zusicherung, dass der Agent jedes Dokument fehlerfrei interpretiert. Erwartet sind insgesamt 26 Buchungen aus 28 Dateien; eine Website-Rechnung und die Rechnung der Texterin bleiben offen.

Die PDF-Erstellung ruft keine KI-API auf. Der spätere Import in die App verarbeitet die Dateien über den dort eingerichteten OpenAI-Zugang und verursacht dessen übliche Nutzungskosten. Diese Dateien wurden noch nicht importiert. Es gibt hier kein automatisches Befüllen oder Zurücksetzen der Datenbank.

Die Beispieldaten sind zeitlich fest: Wenn man sie später öffnet, ändern sich offene Fristen und Überfällig-Anzeigen entsprechend dem tatsächlichen Datum. Prüfstatus entsteht erst in Pfennig, er wird nicht durch die PDFs vorgegeben.

## Inhalt

| Nr. | Gruppe | Beleg / Szenario |
| --- | --- | --- |
| 01 | Ausgang | Markenauftritt, deutsche Einnahme, bezahlt |
| 02 | Ausgang | Website-Projektphase 1, bezahlt |
| 03 | Ausgang | Website-Projektphase 2, noch offen |
| 04 | Ausgang | Design für österreichischen Geschäftskunden, Reverse Charge |
| 05 | Ausgang | Teil-Stornorechnung und Erstattung zu 01 |
| 06 | Einkauf | Designsoftware aus Irland, Reverse Charge |
| 07 | Einkauf | US-Entwicklerwerkzeug in USD mit EUR-Kartenabrechnung |
| 08 | Einkauf | Deutsches Hosting |
| 09 | Einkauf | Schreibwaren-Kassenbon |
| 10 | Einkauf | Gedruckte Portfolio-Karten |
| 11 | Einkauf | Mobilfunk, 30 % Privatanteil |
| 12 | Einkauf | Laptop als Anlagegut |
| 13 | Einkauf | Beruflicher Onlinekurs |
| 14 | Einkauf | Texte einer freien Mitarbeiterin, überfällig und unbezahlt |
| 15 | Reise | Hin- und Rückflug Hamburg–München |
| 16 | Reise | Flughafentaxi am 14. September |
| 17 | Reise | Hotel vom 14. bis 16. September |
| 18 | Reise | Kundenbewirtung am 15. September |
| 19 | Reise | Nahverkehr zum Workshop am 15. September |
| 20 | Reise | S-Bahn zum Flughafen am 16. September |
| 21 | Ausgang | Website-Wartung Juli |
| 22 | Ausgang | Website-Wartung August |
| 23 | Ausgang | Website-Wartung September |
| 24 | Ausgang | Weiterer kleiner Gestaltungsauftrag |
| 25 | Einkauf | Domain-Verlängerung |
| 26 | Einkauf | Berufshaftpflicht ohne Umsatzsteuer |
| 27 | Bank | Gefilterte Zahlungseingänge Juli/August |
| 28 | Bank | Gefilterte Zahlungseingänge September |

Die Reise gehört zum Website-Kunden **Isarblick Innenräume**. Ausgangsrechnungen haben ein gemeinsames Studio-Design; Lieferanten, Hotel und schmale Bons verwenden unterschiedliche Gestaltungen. Der Hinweis „Fiktiver Musterbeleg · Nicht zur Zahlung“ trennt die Belege von echten Unterlagen. Alle Domains enden auf `.example`, Steuerkennungen sind ungültige Demo-Platzhalter.

## Erneut erzeugen und prüfen

Vom Projektverzeichnis aus, Python 3.13 mit `uv`; die Skripte deklarieren ihre eigenen PDF-Abhängigkeiten und verändern keine App-Daten:

```sh
uv run --python 3.13 sample-data/2026-q3/sources/outgoing.py
uv run --python 3.13 sample-data/2026-q3/sources/purchases.py
uv run --python 3.13 sample-data/2026-q3/sources/equipment-services.py
uv run --python 3.13 sample-data/2026-q3/sources/travel.py
uv run --python 3.13 sample-data/2026-q3/sources/bank.py
uv run --python 3.13 sample-data/2026-q3/sources/verify.py
```

Die Gruppenmanifeste enthalten erwartete Beträge in EUR-Cent, Zahlungen und die jeweiligen Szenarien. Im Ausgangsmanifest ist `zahlungen_nach_rechnungsimport` der zunächst erwartete Zustand; `zahlungen` enthält den Zielzustand nach dem Bankimport. Die sieben später zu bezahlenden Rechnungen enthalten deshalb selbst keine Bezahlt-Vermerke. Die Teil-Stornorechnung dokumentiert ihre Erstattung separat. Das Bankmanifest enthält Transaktionen und ihre Rechnungsreferenzen, keine neuen Buchungen. Beim USD-Beleg stehen zusätzlich Originalwährung und Originalbetrag. Steuerquellen für die Reisebelege stehen in `sources/travel-tax-notes.md`. Der gemeinsame Herstellungsplan liegt in `BRIEF.md`.
