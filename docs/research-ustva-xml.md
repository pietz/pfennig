# Recherche: UStVA-XML-Upload und Abgabe ohne ERiC/Hersteller-ID (Q3 2026)

Stand: 14.09.2026. Nur öffentliche Quellen, keine Registrierung, kein Login, kein Testupload. Ergänzt `docs/research-user-workflow.md` und `docs/backlog.md` Abschnitt C, wiederholt deren Kernaussagen nicht im Detail.

## Ergebnis in einem Satz

Der von ELSTER dokumentierte XML-Upload ist real und ohne Hersteller-Registrierung nutzbar, aber die öffentlich zugängliche Anleitung zeigt nur den Umschlag (`<Anmeldungssteuern>`, Namespace, Version, Zeichensatz) und verweist für den vollständigen Kennzahlen-Datensatz ausdrücklich auf die ERiC-Dokumentation im Entwicklerbereich. Ein vollständiger, geprüfter 2026-Formatvertrag ist damit weiterhin nicht öffentlich nachgewiesen.

## 1. Struktur des XML-Uploads (elster.de/eportal/helpGlobal?themaGlobal=ustva_upload)

Die Hilfeseite zeigt für das Formular Umsatzsteuervoranmeldung genau dieses Beispiel:

```xml
<?xml version="1.0" encoding="ISO-8859-15" standalone="no"?>
<Anmeldungssteuern xmlns="http://finkonsens.de/elster/elsteranmeldung/ustva/v2023" version="2023">
[...]
</Anmeldungssteuern>
```

Wörtlich bestätigt:
- Es wird nur der Inhalt unterhalb von `/Elster/DatenTeil/Nutzdatenblock/Nutzdaten/Anmeldungssteuern` hochgeladen, nicht der komplette ELSTER-Transferumschlag.
- Zeichensatz: ISO-8859-15.
- Der Wert aus `kz83` wird ins manuelle Eingabefeld im Formular übernommen (Zahllast/Erstattung wird also nicht aus den anderen Kz automatisch neu berechnet, sondern `kz83` gilt als vom Nutzer vorgegeben).
- Alle Inhalte unterhalb von `/Anmeldungssteuern/Steuerfall` werden übernommen, außer: `Umsatzsteuervoranmeldung/Kz09`, `Berater/Namensvorsatz`, `Berater/Namenszusatz`, `Berater/GKPLZ`, `Unternehmer/Namensvorsatz`, `Unternehmer/Namenszusatz`, `Unternehmer/GKPLZ`, `Mandant/Name`, `Mandant/Vorname`, `Mandant/MandantenNr`.
- Für den vollständigen Aufbau verweist die Seite explizit auf den Bereich "Benutzergruppen > Entwickler" auf elster.de, Seite "ERiC", Paket `ERiC-*-Dokumentation.zip` mit Schemata (`Dokumentation/Schnittstellenbeschreibungen`) und jährlichen Plausibilitätsprüfungen (`Dokumentation/Plausipruefungen`).

**Wichtig:** Das Beispiel enthält keine einzige Kz-Zeile, nur `[...]` als Platzhalter. Der Namespace zeigt `v2023`/`version="2023"` als letztes auf der Hilfeseite gezeigtes Beispiel; ob für den Besteuerungszeitraum 2026 dieselbe Schemaversion gilt oder eine neue (z. B. `v2026`), ist aus dieser Seite nicht ablesbar. Der Entwicklerbereich selbst ist login-pflichtig (die Seite `elster.de/elsterweb/entwickler/infoseite/eric` zeigt einen Anmeldebildschirm), so dass die vollständige Schemadefinition ohne Entwicklerkonto nicht direkt einsehbar war.

Aus dem ELSTER-Anwenderforum (sekundär, nicht offiziell, aber konsistent mit obigem Umschlag) stammt folgendes Nutzerbeispiel für den inneren Aufbau:

```xml
<Umsatzsteuervoranmeldung>
  <Jahr>2023</Jahr>
  <Zeitraum>01</Zeitraum>
  <Steuernummer>1096081508187</Steuernummer>
  <Kz09>...</Kz09>
  ...
</Umsatzsteuervoranmeldung>
```

Ein Forumsteilnehmer bestätigt dort außerdem, dass der Block `<Unternehmer>` beim Web-Upload nicht zwingend nötig ist und dass auch UTF-8 statt ISO-8859-15 akzeptiert wurde. Das sind Erfahrungsberichte, keine offizielle Zusage.

**Periodencodes (Zeitraum):** `01`-`12` für Monate, `41`-`44` für die vier Kalendervierteljahre. Diese Zuordnung stammt nicht von elster.de selbst, sondern aus dem quelloffenen Projekt geierlein (`ustva.xsl`) und passt zur allgemein bekannten ELSTER-Konvention; sie ist plausibel, aber hier nicht durch eine elster.de-Seite direkt belegt. Für Q3 2026 wäre das entsprechend `Zeitraum = 43`.

**Ein vollständiges, minimal gültiges 2026-Beispiel mit Kz 81/86/66/46/47/67/83 kann aus den öffentlich zugänglichen Seiten nicht seriös zusammengestellt werden.** Die offizielle Seite liefert nur den Umschlag, keine Feldreihenfolge, keine Pflichtfeld-Liste, kein Schema. Ein selbst konstruierter Datensatz wäre Spekulation, kein geprüfter Vertrag, und wird hier deshalb nicht als "vollständiges Beispiel" ausgegeben.

## 2. Verfügbarkeit und Ablauf des Uploads

Die Seite "UStVA" unter allen Formularen (`elster.de/eportal/formulare-leistungen/alleformulare/ustvaeru`) bietet für 2026 (neben 2022-2025) den Formularaufruf an und nennt im Ablauf: "Falls Sie Software von anderen Anbietern nutzen, die eine XML-Datei erzeugen kann, so können Sie auch Ihre XML-Daten von externen Anbietern im nächsten Schritt hochladen." Das setzt keine Entwicklerregistrierung voraus, sondern nur einen normalen authentifizierten Mein-ELSTER-Zugang; der Upload ist ein alternativer Weg zur manuellen Formulareingabe innerhalb desselben Formularaufrufs.

Die Hilfeseite selbst macht keine Aussage zu Dateigrößenbeschränkung, "ein Formular pro Datei" oder Anhängen; das war aus den geprüften offiziellen Seiten nicht zu belegen. Im Anwenderforum kursieren Werte wie 20 MB allgemeine Übertragungsgröße bzw. 10 MB pro Datei/14 MB gesamt für Belegnachreichungen, aber diese Angaben stammen aus Forumsbeiträgen, nicht aus einer offiziellen Grenzwert-Dokumentation für den XML-Formular-Upload, und werden deshalb als unsicher eingestuft.

Zum Ablauf nach dem Upload macht die Hilfeseite nur indirekt eine Aussage: Werte werden "in das Formular übernommen", `kz83` geht in das manuelle Eingabefeld. Das impliziert ein befülltes Formular zur Prüfung vor Absenden, ein expliziter Beleg für einen separaten Prüfbildschirm wurde aber nicht gefunden; dies folgt aus der allgemeinen Funktionsweise von Mein-ELSTER-Formularen (Eingabe/Import, dann Prüfen-Schritt, dann Absenden), nicht aus einem wörtlichen Zitat.

## 3. Anlage EÜR: kein Upload bestätigt (Vorbefund bestätigt)

Die Navigation der Hilfeseite "Benutzeranleitung zum Hochladen von Formulardaten" listet nur zwei Formulare: "Formular Umsatzsteuervoranmeldung" und "Formular Mitteilung nach § 146a Abs. 4 AO". Anlage EÜR taucht dort nicht auf. Das ist ein direktes strukturelles Indiz (nicht nur Fehlen eines Hinweises), dass für EÜR kein analoger XML-Upload-Weg vorgesehen ist. Der bisherige Befund aus `docs/research-user-workflow.md` wird damit bestätigt, nicht widerlegt.

## 4. Relevante Kennzahlen für Freiberufler

Aus dem BMF-Vordruckmuster 2026 (USt 1 A, per PDF-Auswertung, Wortlaut nicht Zeichen für Zeichen zitierbar aus der PDF-Extraktion, Zuordnung aber mit dem seit Jahren stabilen ELSTER-Kz-Schema und Drittquellen wie onlinebilanz.de konsistent):

| Kz | Bedeutung |
|---|---|
| 81 | Umsätze zu 19 % |
| 86 | Umsätze zu 7 % |
| 66 | Abziehbare Vorsteuerbeträge |
| 46 | Leistungen nach §13b Abs. 1 Nr. 1-3 (z. B. Bauleistungen, im Ausland ansässiger Leistender bei bestimmten Fällen) |
| 47 | Leistungen nach §13b Abs. 2 (u. a. Abs. 2 Nr. 1: sonstige Leistungen eines im Ausland ansässigen Unternehmers, praktisch der typische Fall für ausländisches SaaS) |
| 67 | Vorsteuer aus den §13b-Leistungen (Kz 46/47), analog zum Vorsteuerabzug bei Reverse Charge |
| 84 | Leistungen im Sinne des §13b Abs. 2 Nr. 5 (bestimmte weitere Reverse-Charge-Tatbestände) |
| 85 | Leistungen von im Ausland ansässigen Unternehmern (weitere Abgrenzung zu 46/47) |
| 83 | Verbleibende Umsatzsteuer-Vorauszahlung/Zahllast bzw. Überschuss, wird beim XML-Upload als vom Nutzer berechneter Wert übernommen |
| 500 | Neu ab Besteuerungszeitraum 2026: ergänzende Angaben zur Steueranmeldung, ersetzt die bisherige pauschale Kz 23 (z. B. Kz 500 = 2 für abweichende Rechtsauffassung, Kz 500 = 3 für Antrag auf personelle Prüfung) |

Für Kleinunternehmer mit reiner §13b-Zahllast sind praktisch nur Kz 46/47/67/83 (bzw. 84/85 je nach Leistungsart) sowie ggf. Kz 500 relevant, keine Kz 81/86/66. Quelle: BMF-Vordruckmuster 2026 (siehe Quellenliste); eine wortgetreue Ausfüllanleitung (USt 1 E 2026) wurde als PDF gefunden, aber inhaltlich nicht Zeile für Zeile im Volltext extrahiert, daher als "recherchiert, nicht wortwörtlich verifiziert" markiert.

## 5. Fristen (§18 UStG, §19 UStG, §46-48 UStDV)

Wörtlich aus gesetze-im-internet.de:

- **§18 Abs. 1 UStG:** Voranmeldung ist "bis zum zehnten Tag nach Ablauf jedes Voranmeldungszeitraums" zu übermitteln, Vorauszahlung ist am selben Tag fällig.
- **§18 Abs. 2 UStG:** Voranmeldungszeitraum ist grundsätzlich das Kalendervierteljahr. Monatlich, wenn die Steuer des Vorjahres mehr als 9.000 Euro betrug. Befreiung von der Abgabepflicht möglich, wenn die Vorjahressteuer nicht mehr als 2.000 Euro betrug. Für Existenzgründer gilt im laufenden und folgenden Kalenderjahr grundsätzlich der Kalendermonat (diese Ausnahme für Neugründer ist laut Sekundärquellen bis 31.12.2026 ausgesetzt, das war primärquellenseitig hier nicht abschließend nachgeprüft).
- **§18 Abs. 4a UStG:** Voranmeldungspflicht besteht auch für Steuer nach §1 Abs. 1 Nr. 5, §13b Abs. 5 oder §25b Abs. 2, unabhängig von Abs. 1-3, nur für die betroffenen Zeiträume.
- **§18 Abs. 6 UStG:** Ermächtigung des BMF, die Fristen per Rechtsverordnung um einen Monat zu verlängern (Basis für die Dauerfristverlängerung).
- **§46 UStDV:** Fristverlängerung um einen Monat auf Antrag, kann bei Gefährdung des Steueranspruchs abgelehnt/widerrufen werden.
- **§47 UStDV:** Sondervorauszahlung (1/11 der Vorjahresvorauszahlungen) nur bei monatlicher Abgabepflicht, nicht bei Quartalszahlern.
- **§48 Abs. 1 UStDV:** Antrag auf Fristverlängerung ist "bis zu dem Zeitpunkt zu beantragen, an dem die Voranmeldung ... erstmals ... zu übermitteln ist", also faktisch bis zur regulären Abgabefrist des ersten betroffenen Zeitraums.

Für Q3 2026 (Kalendervierteljahr, Zeitraum 43) bedeutet das: reguläre Frist 10. Oktober 2026, mit genehmigter Dauerfristverlängerung 10. November 2026. Diese Zuordnung folgt direkt aus §18 Abs. 1 UStG, ist aber selbst nicht wörtlich auf einer Seite als Datum benannt (die Rechnung von "Zeitraumende + 10 Tage" ist eine direkte Anwendung des Gesetzestextes).

**§19 UStG (Neufassung ab 2025):** Umsatz eines im Inland ansässigen Kleinunternehmers ist steuerfrei, wenn der Vorjahresumsatz 25.000 Euro und der laufende Umsatz 100.000 Euro nicht übersteigt. §19 Abs. 1 Satz 1 UStG schließt ausdrücklich die "Erklärungspflichten (§18 Absatz 1 bis 4)" aus, das heißt, ein reiner Kleinunternehmer hat grundsätzlich keine laufende UStVA-Pflicht mehr. Wörtlich: "§149 Absatz 1 Satz 2 der Abgabenordnung und §18 Absatz 4a dieses Gesetzes bleiben unberührt." Damit bleibt die Pflicht zur Abgabe explizit bestehen, wenn §13b-Steuer entsteht (also z. B. bei Bezug von ausländischen SaaS-Leistungen als Kleinunternehmer), unabhängig von der sonstigen Befreiung.

## 6. Öffentliche REST/HTTP-API ohne ERiC/Hersteller-ID

Nicht gefunden, und die Quellenlage deutet aktiv dagegen: Der einzige dokumentierte programmatische Übermittlungsweg ist ERiC (lokale Bibliothek, Entwicklerregistrierung/Hersteller-ID nötig). Der Entwicklerbereich von elster.de ist selbst login-pflichtig. Der XML-Upload in Mein ELSTER ist kein API-Endpunkt, sondern eine Datei-Upload-Funktion innerhalb der interaktiven Portal-Sitzung eines normalen Nutzers, ohne dokumentierte HTTP-Schnittstelle für Drittsoftware. Das bestätigt den Vorbefund aus `docs/backlog.md` Abschnitt C.

## Verifiziert vs. unsicher

**Verifiziert (wörtlich/direkt aus Primärquelle):**
- Umschlagstruktur `<Anmeldungssteuern xmlns=... version="2023">`, Zeichensatz ISO-8859-15, Nutzdaten-Pfad, Ausnahmeliste, kz83-Sonderbehandlung, Verweis auf ERiC-Doku (elster.de Hilfeseite).
- Jahr 2026 als angebotene UStVA-Formularversion; XML-Upload als expliziter alternativer Eingabeweg (elster.de Formularseite).
- EÜR nicht in der Liste der Upload-fähigen Formulare (elster.de Hilfeseite-Navigation).
- §18 Abs. 1, 2, 4a, 6 UStG; §19 Abs. 1 UStG; §46-48 UStDV (gesetze-im-internet.de, Wortlaut zitiert).
- Entwicklerbereich/ERiC-Zugang ist login-pflichtig.

**Unsicher/abgeleitet, nicht direkt aus Primärquelle:**
- Zeitraum-Codes 41-44 (Quartale) und 01-12 (Monate): aus Drittquelle (Open-Source-Projekt geierlein), nicht von elster.de bestätigt, aber gängige Konvention.
- Konkreter Feldaufbau/Reihenfolge innerhalb von `Anmeldungssteuern/Steuerfall/Umsatzsteuervoranmeldung` mit allen Kz: nur aus Forumsbeispielen, keine offizielle Schema-Referenz ohne Entwicklerkonto eingesehen.
- Ob die Schemaversion für den Besteuerungszeitraum 2026 weiterhin `v2023`/`version="2023"` ist oder sich geändert hat: unbekannt.
- Datei-/Größenbeschränkungen, "ein Formular pro Datei", genauer Ablauf nach Upload (Prüfbildschirm): aus Forumsbeiträgen bzw. Analogieschluss, nicht offiziell dokumentiert.
- Genaue Wortlaute der Kz-Bezeichnungen im BMF-Vordruck/USt 1 E 2026: aus PDF-Extraktion zusammengefasst, nicht zeichengenau zitiert.
- Aussetzung der Neugründer-Monatspflicht bis 31.12.2026: nur aus Sekundärquelle, nicht primärquellenseitig in dieser Recherche verifiziert.

**Fazit für die Produktplanung:** Der bereits dokumentierte Ansatz bleibt richtig: XML-Machbarkeit früh und separat mit einem echten (freigegebenen) Testupload prüfen, ohne Herstellerregistrierung, und die fachliche UStVA-Vorbereitung nicht davon abhängig machen. Ein vollständiger, öffentlich verifizierter 2026-Formatvertrag existiert weiterhin nicht; nur ein tatsächlicher Upload-Test in Mein ELSTER (mit ausdrücklicher Freigabe, ohne Absenden) kann das schließen.

## Quellen

- https://www.elster.de/eportal/helpGlobal?themaGlobal=ustva_upload
- https://www.elster.de/eportal/formulare-leistungen/alleformulare/ustvaeru
- https://www.elster.de/elsterweb/entwickler/infoseite/eric
- https://www.elster.de/elsterweb/infoseite/entwickler
- https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/2025-12-29-vordruckmuster-USt-voranmeldung-2026.pdf
- https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/Umsatzsteuer-Anwendungserlass/2025-03-18-sonderregelung-kleinunternehmer.pdf
- https://www.gesetze-im-internet.de/ustg_1980/__18.html
- https://www.gesetze-im-internet.de/ustg_1980/__19.html
- https://www.gesetze-im-internet.de/ustdv_1980/__46.html
- https://www.gesetze-im-internet.de/ustdv_1980/__47.html
- https://www.gesetze-im-internet.de/ustdv_1980/__48.html
- https://forum.elster.de/anwenderforum/forum/elster-webanwendungen/mein-elster/429585-xml-import-uva-scheitert-und-fix-des-tags-anmeldungssteuern-nutzt-nichts (sekundär, Forum)
- https://forum.elster.de/anwenderforum/forum/elster-webanwendungen/mein-elster/470206-umsatzsteuervornmeldung-formular-2026-xml-datendatei (sekundär, Forum)
- https://github.com/stesie/geierlein/blob/master/chrome/content/xsl/ustva.xsl (sekundär, Open Source, Zeitraum-Codes)
