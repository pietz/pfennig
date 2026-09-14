# Produkt-Backlog: vom Beleg zur Steuerabgabe

Planungsübersicht nach `c5e1832`. Prioritäten sind Empfehlungen, keine Zusage für den nächsten Release. GitHub Issues bleiben die technischen Arbeitspakete; diese Übersicht ordnet den Nutzerablauf. Produktscope: deutsche Selbstständige, EÜR, Ist-Versteuerung, Regelbesteuerung und Kleinunternehmer.

> Belege ablegen → prüfen und zuordnen → Zahlen nachvollziehen → Steuerdaten vorbereiten → selbst abgeben.

## A. Was bereits funktioniert

| Abschnitt | Vorhanden | Grenze |
|---|---|---|
| Ablage | Lokales SQLite-Archiv und unveränderte Originalbelege; Dateien wieder öffnen | Noch kein geführter Sicherungs-/Wiederherstellungsworkflow |
| Eingang | PDF-/Bildimport, strukturierte KI-Extraktion, mehrere Dateien, Wiederholung fehlgeschlagener Importe | Qualität an vielfältigen echten Belegen noch nicht ausreichend belegt |
| Prüfung | Vorschläge prüfen, bearbeiten, bestätigen oder ablehnen; direkte manuelle Buchungen | Nicht jede steuerliche Ausnahme wird automatisch gelöst |
| Nachvollziehbarkeit | Interne Änderungs-/Herkunftshistorie und Schutz manueller Änderungen; exakte Dateiduplikate erkennen | Keine allgemeine semantische Dublettenerkennung |
| Beleg ergänzen | Fehlenden Beleg an bestehende Buchung hängen | Späteren Beleg automatisch einer Kontobewegung zuordnen fehlt |
| Zahlungen | Manuelle Zahlungen und Teilzahlungen | Kein nutzbarer Kontoauszugimport oder automatisches Matching |
| Fachliche Basis | Häufige 7%/19%-Fälle, Mischbelege, §19 und typische Reverse-Charge-Dienstleistungen | Keine fertige UStVA-/EÜR-Auswertung, kein vollständiges AfA-System |
| Start | Echte Jahressummen, offene Prüfungen, fehlende Belege, Filter-Verlinkungen | Bruttoübersicht, keine steuerliche Gewinnermittlung; noch keine echten Termine |
| Offline | Bestehende Daten ohne KI/Netz nutzbar, Belege im Finder zugänglich | Kein benutzerfreundlicher Buchungs-/Steuerexport |

## B. Fehlende Bausteine nach Priorität

### P0: Vertrauen in den heutigen Kern

Vor einer Empfehlung für ernsthafte Nutzung mit echten Buchhaltungsdaten. Nicht Voraussetzung, um den Quellcode als ausdrücklich experimentelle Preview zu veröffentlichen.

| Aufgabe | Kleiner, überprüfbarer Abschluss |
|---|---|
| **Echte Belege testen** | Kuratierten privaten Testbestand durch den vollständigen Import-/Prüfablauf laufen lassen; materielle Fehler dokumentieren und beheben |
| **Daten herausbekommen** | Verständlicher CSV-Buchungsexport mit Belegreferenzen; Originaldateien bleiben zugänglich |
| **Sichern und wiederherstellen** | Konsistente lokale Archivkopie und verifizierter Wiederherstellungsweg, zunächst ohne Cloud-/Backup-Automatik |
| **Erstinstallation und Updates absichern** | Frisches macOS-Benutzerkonto testen, unterstützte KI-Einstellungen prüfen, klare Grenzen dokumentieren; veröffentlichte Archive bei Updates erhalten |

### P1: Den vollständigen Buchhaltungsablauf schließen

| Funktion | Erster sinnvoller Umfang |
|---|---|
| **UStVA-Vorbereitung** | Geprüfte, formjahrbezogene Kennzahlen; jede Summe führt zu ihren Buchungen; offene/unsupported Fälle sichtbar; kopierbare Übertragungshilfe |
| **EÜR-Vorbereitung** | Zahlungsgerechte Jahresauswertung nach Kategorien/Formularpositionen; nachvollziehbare Einzelbeträge; Anlagen und nicht unterstützte Korrekturen separat ausweisen |
| **Kontoauszugimport + Matching** | Ein tatsächlich verwendetes CSV-Format; privat/intern/geschäftlich unterscheiden; eindeutige Zuordnungen, mehrdeutige Fälle manuell prüfen |
| **Beleg zuerst oder Zahlung zuerst** | Gegenstück am selben Vorgang ergänzen statt doppelt buchen; fehlende Belege aus geschäftlichen Kontobewegungen entdecken |
| **E-Rechnungen lesen** | XRechnung und ZUGFeRD, UBL/CII gezielt abdecken; strukturierte Rechnungsdaten lokal auslesen, Original erhalten; KI nur für verbleibende Vorschläge |

UStVA und EÜR brauchen eigene fachliche Berechnungen, nicht einfach die Start-Summen. Manuell erfasste Zahlungen erlauben einen ersten Report bereits vor dem Bankimport; für komfortable Vollständigkeit ist der Abgleich aber wesentlich. Die vorhandenen Formular-Mappings sind ausdrücklich ungeprüft und keine freigegebene Abgabegrundlage.

### P2: Bedienaufwand reduzieren

| Funktion | Anlass / Grenze |
|---|---|
| **UStVA-XML-Export untersuchen** | Mein ELSTER bietet ausdrücklich XML-Upload an; erst Format, Zugänglichkeit und Importfähigkeit eines Exports verifizieren |
| Wiederkehrende Anbieterregeln | Wiederholt bestätigte Kategorien/Zuordnungen vorschlagen; kein freies Regelwerk vorsorglich bauen |
| Weitere Kontoformate | Erst aus realem Nutzerbedarf, nicht alle Banken auf einmal |
| Anstehende Termine auf Start | Nur bekannte Verpflichtungen und zutreffende Termine, keine leeren Kalenderfunktionen |
| Perioden prüfen/festhalten/sperren | Auf nutzbaren Auswertungen aufbauen; Freigabe, Abgabe und Sperre nicht vermischen |
| Häufige Abweichungen beim Matching | Gebühren, Fremdwährung und Sammelzahlungen erweitern, wenn der einfache Ablauf erprobt ist |

### P3: Bewusst zurückgestellt

- Iteratives Tool Calling für schwierige Zuordnungen: erst wenn ein konkreter Fall den Mehrwert zeigt; keine neue Harness-Abhängigkeit nötig.
- DATEV-Adapter und weitere Übergabeformate: nach einem brauchbaren einfachen Export.
- Vollständige Anlagen-/AfA-Verwaltung: vorerst Anlagekandidaten sichtbar manuell prüfen.
- Direkte ELSTER-Übermittlung: derzeit nicht geplant, da Herstellerregistrierung ausdrücklich nicht gewünscht ist.
- Keine Erweiterung zu Rechnungsstellung, CRM, Bilanzbuchhaltung oder Einkommensteuerberatung.

## C. Output ohne eigenen ELSTER-Übermittlungsdienst

| Weg | Einschätzung |
|---|---|
| Formularnahe UStVA-/EÜR-Übertragungshilfe | **Empfohlener Einstieg.** Ziffer berechnet und erklärt; Nutzer prüft und überträgt in Mein ELSTER |
| Kopierbare Werte, druckbarer Bericht/PDF, CSV | Sinnvoll für Übertragung, eigene Unterlagen oder Steuerberatung; nicht automatisch ein akzeptiertes ELSTER-Importformat |
| UStVA-XML zum manuellen Hochladen | **Konkreter Untersuchungskandidat.** Offiziell dokumentierter Upload, aber der benötigte Formatvertrag und Ziffers Zugang dazu sind noch zu klären |
| EÜR-Dateiimport | Auf der geprüften Formularseite kein entsprechender externer Import dokumentiert; nicht versprechen |
| Direkte Übermittlung mit ERiC | Lokale C-Bibliothek möglich, aber Entwicklerregistrierung/Hersteller-ID erforderlich; das ist unabhängig vom persönlichen ELSTER-Zugang |

Ein ausgefülltes PDF ersetzt nicht die reguläre elektronische Abgabe. Eine einfache öffentliche UStVA-/EÜR-REST-API ohne diesen Integrationsaufwand ist hier nicht belegt. Auch eine Drittanbieter-API würde zusätzliche externe Verarbeitung und einen Anbieter statt einer rein lokalen Lösung bedeuten.

Offizielle Quellen:
- [UStVA-Formular mit Hinweis auf externen XML-Upload](https://www.elster.de/eportal/formulare-leistungen/alleformulare/ustvaeru)
- [Anlage EÜR: authentifizierte elektronische Übermittlung](https://www.elster.de/eportal/formulare-leistungen/alleformulare/euer)
- [Mein ELSTER: unterstützte CSV-Importformulare](https://www.elster.de/eportal/helpGlobal?themaGlobal=anleitung_zur_importfunktion_eop)
- [Entwicklerregistrierung und ERiC](https://www.elster.de/elsterweb/infoseite/entwickler)

## D. Vorschlag für die nächsten Schritte

1. **Realitätsprüfung:** 30–50 bewusst verschiedene echte Belege, darunter Scans/Fotos, lange Rechnungen, Mischsteuersätze, Fremdwährung, Gutschriften und §19-Fälle. Erwartete Kernwerte manuell festhalten; nicht nur messen, ob JSON zurückkommt, sondern ob ein brauchbarer Buchungsvorschlag entsteht.
2. **Sicherer Ausgang:** CSV-Export sowie Sicherung/Wiederherstellung. Damit ist die frühe Version kein Datensackgassen-Projekt.
3. **Erstes Steuerergebnis:** Einen UStVA-Zeitraum bis zur kopierbaren Übertragungshilfe vollständig durchgehen; XML-Machbarkeit parallel kurz klären, aber nicht zum Blocker machen.
4. **Weniger Handarbeit:** Ein Kontoformat und beidseitigen Beleg-/Zahlungsabgleich schließen; E-Rechnungen als begrenzten weiteren Eingang hinzufügen.
5. **Jahresabschluss vorbereiten:** EÜR-Ausgabe vervollständigen, anschließend Periodenfreigabe und Komfortfunktionen.

Private Testbelege bleiben außerhalb des Repositories. Eine Übertragung an OpenAI erfolgt nur nach ausdrücklicher Freigabe; auch Antworten und Logs können private Daten enthalten. Öffentliches Regressionstestmaterial muss freigegeben oder sinnvoll anonymisiert sein.

## E. Datenmodell und erste Veröffentlichung

Die Trennung von Geschäftsvorgang, Beleg, Zahlung und Zuordnung passt zu beiden Eingangswegen; es gibt derzeit keinen konkreten Grund für einen Schema-Neuentwurf. Die Breite des vorbereiteten Modells ist aber kein Beleg, dass alle Workflows bereits funktionieren. Stabilität wird mit realen Fällen, Abgleich und wiederherstellbaren Archiven nachgewiesen, nicht mit weiteren Tabellen.

**Open-Source-Preview: ja**, mit ehrlicher Beschreibung als lokale Belegerfassung/Buchhaltung im frühen Stadium. **Vollständiger Accountable-Ersatz: noch nicht**, besonders wegen Abgleich und Steuerausgabe. Release-Technik und Freigaben bleiben separat in [status.md](status.md) und [releasing.md](releasing.md) geführt; diese Planung autorisiert keine Veröffentlichung, Übermittlung oder privaten Belegtests.
