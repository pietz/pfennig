# Recherche: vom Beleg zum nutzbaren Steuerergebnis

Stand: 14.09.2026. Öffentliche Quellen und aktueller Code nach `e84acc2`, mit drei unabhängigen Luna-5.6-Recherchen. Keine privaten Belege, Kontozugänge, Registrierungen oder Übermittlungen verwendet. Dies ist eine Umsetzungsempfehlung, keine abgeschlossene steuerliche Prüfung.

## Empfehlung in einem Satz

**Als Nächstes einen UStVA-Zeitraum nachvollziehbar vorbereiten, danach Zahlungen per Kontoauszug abgleichen und die EÜR schließen; E-Rechnungen als begrenzten zusätzlichen Importweg ergänzen.** Den UStVA-XML-Upload früh und separat auf Machbarkeit prüfen, ohne Herstellerregistrierung und ohne die fachliche Auswertung davon abhängig zu machen.

Private Belegqualitätstests übernimmt der Nutzer separat. Sie bleiben wichtig für belastbare Nutzung, blockieren aber diese Produktplanung nicht. Start und Buchungen brauchen dafür keinen erneuten Umbau.

## 1. Welcher Nutzeraufwand verschwindet?

| Heute noch beim Nutzer | Nächster sinnvoller Schritt in Pfennig |
|---|---|
| Buchungen für die UStVA zeitlich und steuerlich gruppieren, summieren und in Felder übertragen | Zeitraum wählen, Ausnahmen bearbeiten, Formularwerte mit nachvollziehbaren Einzelbeträgen erhalten |
| Jede Zahlung einzeln erfassen und mit Belegen vergleichen | Einen Kontoauszug importieren, eindeutige Zuordnungen bestätigen, nur die übrigen Bewegungen klären |
| Beleg und spätere Zahlung doppelt erfassen | Gegenstück am bestehenden Vorgang ergänzen, unabhängig davon, welches zuerst eintrifft |
| Jahresausgaben und Einnahmen für die EÜR nachrechnen | Zahlungsbezogene Jahresauswertung mit Formularpositionen und klar benannten Ergänzungen |
| Strukturierte Rechnungsdaten erneut abtippen oder per KI auslesen lassen | XML lokal lesen und durch denselben prüfbaren Buchungsvorschlag führen |

Wettbewerber zeigen den Wert der gesamten Kette: Vorbereitung, Prüfung einzelner Summen, Übergabe/Abgabe und anschließende Zahlung. Nicht jedes Glied muss in Pfennig automatisiert sein. [Lexware UStVA](https://help.lexware.de/de-form/articles/548028-wie-mache-ich-meine-umsatzsteuer-voranmeldung) und [sevdesk UStVA](https://hilfe.sevdesk.de/de/articles/9310598-umsatzsteuervoranmeldung-ustva) beschreiben diese Abläufe. Lexware trennt seine [EÜR-Auswertung](https://help.lexware.de/de-form/articles/548064-die-neue-einnahmenuberschussrechnung-in-lexware-office) von der [Übergabe an smartsteuer](https://help.lexware.de/de-form/articles/548760-wie-ubertrage-ich-meine-daten-aus-lexware-office-an-smartsteuer). Das sind Workflow-Beispiele, keine steuerlichen Rechtsquellen.

## 2. ELSTER: was nachgewiesen ist und was nicht

### UStVA: manueller XML-Upload ist ausdrücklich vorgesehen

Die [öffentliche ELSTER-Uploadanleitung](https://www.elster.de/eportal/helpGlobal?themaGlobal=ustva_upload) belegt mehr als nur einen allgemeinen Importknopf:

- XML-Upload für alle angebotenen UStVA-Jahresversionen; die [Formularseite](https://www.elster.de/eportal/formulare-leistungen/alleformulare/ustvaeru) bietet auch 2026 an.
- Nur der Inhalt der `Nutzdaten` wird hochgeladen, nicht der komplette ELSTER-Übermittlungsumschlag.
- Öffentliches Strukturbeispiel mit `Anmeldungssteuern`, Namespace und Version für 2023 sowie Zeichensatz ISO-8859-15.
- `kz83` wird als manuell eingegebener Wert übernommen. Einige andere Felder werden ausdrücklich nicht importiert. Dateiupload ersetzt daher weder Pfennigs Berechnung noch die Kontrolle im Portal.
- Vollständige Schemata, Schemadokumentation und jährliche Plausibilitätsregeln verweist ELSTER in das ERiC-Dokumentationspaket.

**Folgerung:** Ein rein lokaler Dateiexport ohne eingebundene ERiC-Bibliothek ist ein plausibler Weg. Die öffentliche Uploadanleitung nennt keine erforderliche Hersteller-ID für diesen Weg. Das ist aber noch kein Beweis, dass ein von Pfennig erzeugter aktueller Datensatz akzeptiert wird. Das 2023-Beispiel ist unvollständig und kein geprüfter 2026-Formatvertrag.

**Kleiner nächster Machbarkeitstest, noch nicht ausgeführt:** Ein öffentlich nachvollziehbares aktuelles Minimalformat für die unterstützten Felder bestimmen, eine rein synthetische Datei erzeugen und später mit ausdrücklicher Nutzerfreigabe in Mein ELSTER importieren, ohne abzusenden. Erfolg heißt: Zeitraum, Identifikation und alle unterstützten Werte werden korrekt übernommen; ausgelassene Felder sind bekannt. Kein Erfolgskriterium ist bloß syntaktisch gültiges XML.

**Abbruchgrenze:** Wenn sich das aktuelle Format nicht ausreichend ohne Registrierung belegen und testen lässt, bleibt zunächst die kopierbare Formularhilfe. Keine Anmeldung als Hersteller, keine Umgehung geschützter Downloads, kein kostenpflichtiger Gateway. Einen solchen Test erst nach gesondertem Umsetzungsauftrag beginnen.

### EÜR: kein entsprechender öffentlicher Uploadweg bestätigt

Die geprüften [EÜR-Formularinformationen](https://www.elster.de/eportal/formulare-leistungen/alleformulare/euer) belegen die elektronische Abgabe, aber keinen analogen externen XML-Upload. Daraus folgt nicht, dass EÜR technisch unübermittelbar wäre. Es fehlt der Nachweis für den hier gewünschten Selbstbedienungs-Dateiimport.

Deshalb: zunächst formularnahe Übertragungshilfe, kopierbare Werte und nachvollziehbarer Bericht. PDF und CSV sind Unterlagen bzw. Arbeitshilfen, nicht automatisch importierbare Formulardaten. Die [allgemeine CSV-Importhilfe](https://www.elster.de/eportal/helpGlobal?themaGlobal=anleitung_zur_importfunktion_eop) ist kein Beleg für einen UStVA-/EÜR-CSV-Import.

### Direkte Übermittlung bleibt draußen

[ELSTER-Entwicklerzugang](https://www.elster.de/elsterweb/infoseite/entwickler) und [ERiC](https://www.elster.de/elsterweb/entwickler/infoseite/eric) sind ein anderer Integrationsweg mit Registrierung, Bibliotheken und Authentifizierung. Der persönliche ELSTER-Zugang des Nutzers ist nicht dasselbe wie ein Herstellerzugang. Pfennig soll weder Zertifikate verwalten noch selbst Steuererklärungen absenden.

## 3. Erstes lieferbares Steuerergebnis: UStVA

**Nutzerablauf:** „UStVA vorbereiten“ öffnen → Jahr und Monat/Quartal wählen → konkrete Ausnahmen bearbeiten → Kennzahlen prüfen → Werte kopieren oder später geprüfte XML-Datei exportieren → selbst im Portal kontrollieren und abgeben.

Ein aufgabenbezogenes Fenster oder Sheet genügt. Oben Zeitraum und vorläufige Zahllast/Erstattung, darunter Formularpositionen; jede Summe öffnet ihre Belege und Zahlungen. Nur echte Probleme erscheinen in einer Prüfliste mit direkter Korrekturmöglichkeit. Keine neue dauerhafte Analyse-Seite, keine Statuslandschaft und keine Anzeige „abgegeben“ nach bloßem Export.

### Was der Code wirklich hergibt

Die Tabellen für Vorgänge, Steuerkomponenten, Zahlungen und Zuordnungen sind eine brauchbare Grundlage. Die Dateiexporte und steuerlichen Aggregationen sind dagegen Platzhalter. Die Form-Mappings sind ausdrücklich ungeprüft. `StartOverviewQuery` summiert erfasste Bruttobeträge und ist **keine** Basis zur Übernahme von Steuerwerten.

| Materielle Lücke | Kleine, fachlich notwendige Lösung |
|---|---|
| Aktuelle Ableitung legt volle Steuer auf das erste Zahlungsdatum | Ausgangsumsatzsteuer unter Ist-Versteuerung aus jeder datierten Zahlungszuordnung berechnen; Mischsteuersätze und Centreste deterministisch verteilen |
| Rechnungsdatum ersetzt aktuell den Besitz einer ordnungsgemäßen Rechnung | Voraussetzungen für Vorsteuer und zutreffendes Datum erfassen/bestätigen; Importdatum nicht als Empfangsdatum erfinden; Vorschüsse gesondert behandeln |
| Reverse Charge verwendet pauschal Rechnungsdatum | Typische EU-Dienstleistungen und andere einschlägige Auslandsleistungen nach §13b unterscheiden; fehlende entscheidende Fakten prüfbar lassen |
| Fehlendes Land/Leistungsart bzw. Beträge werden teilweise für die Ableitung vorbesetzt | Reports prüfen die zugrunde liegenden Fakten, statt fehlende Werte als bestätigtes Inlandsgeschäft oder echte Null auszugeben |
| Fremdwährungsbeträge sind nicht automatisch in EUR umgerechnet | Nur belegte EUR-Steuerwerte aufnehmen; fehlende Umrechnung als bearbeitbare Ausnahme zeigen, Originalbeträge erhalten |
| Negative Gutschriften sind erfassbar, Beziehungen und Rückzahlungsabgleich fehlen | Einfache Korrektur-/Erstattungsfälle explizit unterscheiden und testen; kein blindes Verrechnen allein wegen negativem Vorzeichen |

Die Regeln müssen getrennt geprüft werden: [§13 UStG](https://www.gesetze-im-internet.de/ustg_1980/__13.html), [§13b UStG](https://www.gesetze-im-internet.de/ustg_1980/__13b.html), [§15 UStG](https://www.gesetze-im-internet.de/ustg_1980/__15.html). Insbesondere ist die pauschale heutige Reverse-Charge-Datumsregel nicht berichtstauglich. Für EU-Dienstleistungen nach §13b Abs. 1 ist die Leistung maßgeblich; Abs. 2 hat andere Entstehungsregeln. Vorauszahlungen brauchen eine eigene Prüfung.

**Zielumfang:** bestätigte EUR-Fälle, inländische 7%/19%-Umsätze, Mischbelege, übliche Vorsteuer, typische Reverse-Charge-Dienstleistungen einschließlich Kleinunternehmer ohne Vorsteuerabzug. Zunächst darf eine kleinere korrekt berechnete Teilmenge als Entwurf sichtbar werden; ungeklärte relevante Fälle verhindern die Kennzeichnung als vollständig vorbereitet.

**Abnahme:** zwei Teilzahlungen in verschiedenen Quartalen; Mischsteuersatz mit centgenauer Restsumme; unbezahlte, aber vorsteuerberechtigte Eingangsrechnung; Rechnung erst im Folgezeitraum erhalten; normale gegenüber Kleinunternehmer-Reverse-Charge-Ausgabe; fehlende Beträge, EUR-Umrechnung und einfache Erstattung. Jede Kennzahl muss auf Quellen zurückführbar sein. Manuelle Zahlungen reichen für diesen ersten Bericht, Bankimport ist keine technische Vorbedingung.

Das [BMF-Vordruckmuster UStVA 2026](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/2025-12-29-vordruckmuster-USt-voranmeldung-2026.html) ist die Referenz für die noch ausstehende vollständige Prüfung der Formularfelder und Rundungsvorgaben. Die Recherche ersetzt diese Feldprüfung nicht.

## 4. Kontoauszug und Beleg zusammenführen

**Erster Umfang:** ein tatsächlich verwendetes CSV-Format, gewähltes Konto, Importvorschau und wiederholbarer Import ohne zusätzliche Bewegungen. Kein Bankzugang und kein universeller CSV-Konfigurator vor dem ersten brauchbaren Format.

- Original und normalisierte Auszugszeilen erhalten. Geschäftlich, privat, intern und ungeklärt unterscheiden. Kreditkartenabrechnung/Übertrag nicht erneut als Ausgabe zählen.
- Geschäftliche Zahlung einem vorhandenen Vorgang zuordnen. Betrag, Verwendungszweck/Rechnungsnummer, Gegenpartei und Datum liefern Vorschläge; Mehrdeutigkeit bleibt manuell.
- Ohne passenden Beleg darf ein geschäftlicher Vorgang mit fehlendem Beleg entstehen. Ein späterer Beleg ergänzt ihn, statt einen zweiten Aufwand anzulegen.
- Bereits manuell erfasste Zahlungen beim Abgleich wiedererkennen, nicht einfach zusätzlich importieren. Zuordnung muss korrigierbar und lösbar sein.
- Teilzahlungen von Beginn an berücksichtigen. Sammelzahlungen, Gebühren und Fremdwährungsdifferenzen zunächst manuell behandeln, nicht automatisch passend rechnen.

Vorhanden sind `Account`, `StatementLine`, `Payment`, `PaymentAllocation` sowie Dateifingerprints und Matching-Konstanten. Es fehlen Parser, Kandidatensuche/Matcher und eine atomare Operation zum Verknüpfen **bestehender** Zahlungen. Das ist ein Ausbau des bestehenden Modells, kein Schema-Neuentwurf.

**Abnahme:** Rechnung zuerst, Zahlung zuerst, manuelle Zahlung vor Auszugsimport, identischer und überlappender Auszug, zwei gleich hohe Kandidaten, Teilzahlung und interner Übertrag. Für Steuerberichte muss der Nutzer die Vollständigkeit seiner erfassten Kontobewegungen prüfen können; das Datum der neuesten importierten Zeile beweist sie nicht.

## 5. EÜR: Jahresergebnis statt Start-Bruttosumme

Nach derselben nachvollziehbaren Berichtsbasis: tatsächlich vereinnahmte/gezahlte Beträge gemäß [§11 EStG](https://www.gesetze-im-internet.de/estg/__11.html), Kategorien und zutreffende Formularpositionen. Vereinnahmte Umsatzsteuer, gezahlte abziehbare Vorsteuer und Zahlungen/Erstattungen vom Finanzamt getrennt behandeln. Kleinunternehmer-Ausgaben grundsätzlich mit nicht abziehbarer Steuer als Kosten berücksichtigen.

Private/nicht abziehbare Anteile und einfache Jahreswechselkorrekturen müssen gezielt bearbeitbar sein. Anlagefälle und fehlende AfA/AVEÜR dürfen nicht als gewöhnlicher Vollaufwand durchlaufen. Dafür zunächst eine klare Ergänzungsliste statt kompletter Anlagenverwaltung. Die Zehn-Tage-Regel nicht pauschal auf alle Januarzahlungen anwenden.

Jahresformulare versionieren: Die geprüften ELSTER-Seiten bieten EÜR 2025 an; eine Datei namens `EUeR_2026.swift` beweist weder veröffentlichte noch geprüfte 2026-Zuordnungen. Referenz: [BMF Anlage EÜR 2025](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2025-08-29-anlage-EUER-2025.html).

**Abnahme:** bezahlte/unbezahlte Rechnung, Teilzahlung über Jahreswechsel, Netto/Vorsteuer gegenüber Kleinunternehmer-Bruttokosten, Umsatzsteuerzahlung/-erstattung, private Anteile und offen ausgewiesener Anlagefall. Unvollständige Auswertungen bleiben Entwürfe.

## 6. E-Rechnungen: kleiner weiterer Eingang

Standalone-XRechnung in UBL/CII lokal parsen, anschließend ZUGFeRD/Factur-X mit eingebettetem CII-XML. Originaldatei archivieren und dieselbe Normalisierung, deterministische Ableitung und Prüfung verwenden. Strukturierte Beträge benötigen keine KI-Extraktion; Kategorievorschläge können separat bleiben.

Die [KoSIT-Bundles](https://xeinkauf.de/xrechnung/versionen-und-bundles/) stellen Spezifikation und Testmaterial bereit; aktuell XRechnung 3.0.2, Bundle vom 31.08.2026. [FeRD](https://www.ferd-net.de/standards/zugferd) beschreibt das Hybridformat und stellt das aktuelle ZUGFeRD-2.5.2-Paket bereit. Unterstützte Profile/Versionen gezielt benennen, nicht beliebiges XML als gültige E-Rechnung behandeln.

Foundation XMLParser ist ein naheliegender lokaler Parser. Das Auslesen eingebetteter PDF-Dateien muss gesondert erprobt werden; [Core Graphics liefert PDF-Streamdaten](https://developer.apple.com/documentation/coregraphics/cgpdfstreamcopydata(_:_:)), aber das ist noch kein fertiger ZUGFeRD-Importer. Keine Java-Laufzeit oder Netzwerkvalidierung vorsorglich einführen. Keine externen XML-Entitäten laden. Strukturiertes Einlesen und vollständige Normvalidierung sind unterschiedliche Zusagen.

**Abnahme:** offizielle UBL-/CII-Beispiele, Mischsteuersätze, Gutschrift, hybride PDF/XML-Rechnung, wiederholter Import und ungültige/unsupported Datei. Bei Fehlern Original behalten und verständlich zur Prüfung führen.

## 7. Ehrliche Ersatzgrenze

UStVA ist nicht die jährliche Umsatzsteuererklärung. EÜR ist nicht die vollständige Einkommensteuererklärung. Relevante EU-Umsätze können zusätzlich eine [Zusammenfassende Meldung](https://www.elster.de/eportal/formulare-leistungen/alleformulare/zmdo) erfordern. Diese Grenzen erklären, nicht nebenbei weitere Steuerprodukte bauen.

Bericht und Abgleich sollen die manuelle Zuordnung, Nachrechnung und Übertragung für die unterstützten Fälle deutlich reduzieren. Ob Pfennig damit die bisherige laufende Buchhaltung des Nutzers ersetzen kann, muss sich am vollständigen realen Ablauf zeigen. Ein vollständiger Ersatz des Accountable-Steuerpakets ist damit noch nicht erreicht. Kalender, Regeln, Periodensperren und DATEV kommen nach einem funktionierenden Ausgang. Ein einfacher CSV-Nachweis mit Beleg-/Zahlungsreferenzen gehört schon zum Berichtsausbau; Sicherung und Wiederherstellung bleiben separate Sicherheitsaufgaben.
