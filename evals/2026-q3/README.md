# Studio Linden: Belege für die Q3-2026-Evaluation

43 vollständig erfundene Eingabedateien für eine Hamburger Designerin und Webentwicklerin: 40 PDFs, zwei Bilder und eine HTML-Rechnung. 37 können eine Buchung erzeugen; sechs prüfen, ob der Importer ohne Buchung endet. Zwei Bilder zeigen bereits vorhandene Transaktionen in einem anderen Format. Der Zeitraum reicht von Juli bis zum 23. September 2026. Die Dateien dienen der Evaluation, nicht einer echten Steuererklärung. Die Sollwerte stehen in `ground-truth.json`; der Runner und die Befehle stehen in `../README.md`.

## Manueller Import in Pfennig Dev

1. **Pfennig Dev** öffnen, nicht die installierte Release-App.
2. Im Profil **Mara Winter** eintragen, Kleinunternehmer ausgeschaltet, UStVA vierteljährlich und ohne Dauerfristverlängerung. Die USt-ID **DE000000000** ist für diese erfundenen Daten ungültig.
3. Nur die gezielt gewählten Dateien aus `ausgang/`, `einkauf/`, `reise/`, `extra/` oder `modalities/` importieren. Die Skripte und JSON-Dateien aus `sources/` nicht importieren. Die Bildfälle 41 und 42 wiederholen die Fälle 09 und 17 und sind für isolierte Läufe gedacht.
4. Die PDFs aus `bank/` und `controls/` gehören zur automatischen Evaluation. Sie sollen keine Buchung erzeugen. Die Bankübersichten können im Chat zum Abgleich vorhandener Zahlungen genutzt werden.
5. Importergebnisse mit `ground-truth.json` vergleichen und die Buchungen im Inspector prüfen. Die Soll-Daten sind keine Zusicherung, dass der Agent jedes Dokument fehlerfrei interpretiert.

Die PDF-Erstellung ruft keine KI-API auf. Ein Import in die App oder ein Live-Eval-Lauf nutzt den eingerichteten OpenAI-Zugang und verursacht dessen übliche Nutzungskosten. Der Eval-Runner legt für jeden Fall ein eigenes temporäres Archiv an; er befüllt oder setzt die App-Datenbank nicht zurück.

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

Die Reise gehört zum Website-Kunden **Isarblick Innenräume**. Ausgangsrechnungen haben ein gemeinsames Studio-Design; Lieferanten, Hotel und schmale Bons verwenden unterschiedliche Gestaltungen. Die PDFs tragen keinen Hinweis auf ihren Testzweck; ihre Einordnung als Beispieldaten steht nur hier im Ordner. Alle Domains enden auf `.example`, Steuerkennungen sind ungültige Platzhalter. `extra/` enthält die Fälle 29 bis 36: EU-Wareneinkauf, US-Dienstleistung, Fachbuch mit 7 %, Coworking, Lizenzeinnahme, Teilzahlung, offene Beratung und Grafiktablett. `controls/` enthält die Fälle 37 bis 40: leere Seite, Einladung, Datei ohne Inhalt und ungültige PDF-Datei. `modalities/` enthält die Fälle 41 bis 43: Kassenbon als PNG, Hotelrechnung als JPEG und Software-Rechnung als HTML.

## Erneut erzeugen und prüfen

Vom Projektverzeichnis aus, Python 3.13 mit `uv`; die Skripte deklarieren ihre eigenen PDF-Abhängigkeiten und verändern keine App-Daten:

```sh
uv run --python 3.13 evals/2026-q3/sources/outgoing.py
uv run --python 3.13 evals/2026-q3/sources/purchases.py
uv run --python 3.13 evals/2026-q3/sources/equipment-services.py
uv run --python 3.13 evals/2026-q3/sources/travel.py
uv run --python 3.13 evals/2026-q3/sources/bank.py
uv run --python 3.13 evals/2026-q3/sources/extra.py
uv run --python 3.13 evals/2026-q3/sources/controls.py
uv run --python 3.13 evals/2026-q3/sources/modalities.py
uv run --python 3.13 evals/2026-q3/sources/verify.py
```

Die Gruppenmanifeste enthalten erwartete Beträge in EUR-Cent, Zahlungen und die jeweiligen Szenarien. Im Ausgangsmanifest ist `zahlungen_nach_rechnungsimport` der zunächst erwartete Zustand; `zahlungen` enthält den Zielzustand nach Eintragen der sieben Bankeingänge. Die sieben später zu bezahlenden Rechnungen enthalten deshalb selbst keine Bezahlt-Vermerke. Die Teil-Stornorechnung dokumentiert ihre Erstattung separat. Das Bankmanifest enthält Transaktionen und ihre Rechnungsreferenzen, keine neuen Buchungen. Beim USD-Beleg stehen zusätzlich Originalwährung und Originalbetrag. Steuerquellen für die Reisebelege stehen in `sources/travel-tax-notes.md`. Der gemeinsame Herstellungsplan liegt in `BRIEF.md`.
