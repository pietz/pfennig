# Dokumente ablegen, Ausnahmen prüfen, Steuerdaten vorbereiten

**Status:** Approved 2026-09-14 (user approval in working session; spec was developed jointly)

## Ziel und Umfang

Pfennig nimmt deutschen Freiberuflern und Einzelunternehmern mit EÜR und Ist-Versteuerung möglichst viel laufende Buchhaltungsarbeit ab. Belege und Zahlungen werden gemeinsam organisiert; daraus entstehen nachvollziehbare Steuervorbereitungen. Der Nutzer bearbeitet Ausnahmen statt jeden normalen Vorgang erneut zu bestätigen. Die angestrebten „90%“ alltäglicher Anwendungsfälle sind eine Produktrichtung, keine behauptete Messgröße.

Dieser Ausbau umfasst automatische Übernahme sicherer Fälle, Beleg-/Zahlungsabgleich, CSV- und PDF-Kontoauszüge, XRechnung/ZUGFeRD sowie UStVA-/EÜR-Vorbereitung mit Aufgaben auf Start. Regelbesteuerung und die bisherigen Kleinunternehmer-Fälle bleiben im Umfang.

Nicht enthalten sind Chat, Rechnungsstellung, direkte Bankanbindung, direkte Steuerübermittlung, Herstellerregistrierung, vollständige Einkommensteuer- oder Umsatzsteuerjahreserklärung, ZM, vollständige Anlagenverwaltung und Periodensperren. Nicht unterstützte steuerliche Fälle bleiben sichtbar bearbeitbar, statt unbemerkt falsch in einen vollständigen Bericht einzugehen.

## Verhalten

### Ein Eingang, ein Vorgang

PDFs, Bilder, CSV-Kontoauszüge und E-Rechnungen gelangen über denselben Drag-and-drop-Eingang in die Anwendung, auch als gemischte Dateiauswahl. Pfennig erkennt die Rolle des Dokuments, erhält das Original und zeigt Verarbeitung oder eine konkrete offene Frage. Nicht unterstützte und nicht lesbare Dateien werden nicht stillschweigend übersprungen.

Eine Rechnung kann vor der Zahlung eintreffen oder umgekehrt. Später eintreffende Informationen ergänzen den bestehenden Geschäftsvorgang. Bereits manuell erfasste Zahlungen werden beim Abgleich berücksichtigt. Wiederholte Dateien und überlappende Kontoauszüge dürfen keine zusätzlichen Einnahmen, Ausgaben oder Zahlungen erzeugen; tatsächlich verschiedene gleich hohe Zahlungen bleiben unterscheidbar.

Geschäftliche Kontobewegungen ohne Beleg können einen Vorgang mit fehlendem Beleg erzeugen. Fehlende Rechnungsdaten oder Vorsteuer werden nicht erfunden. Private und interne Bewegungen bleiben nachvollziehbare Kontobewegungen, keine Betriebseinnahmen oder -ausgaben. Unklare Einordnungen benötigen eine Entscheidung. Teilzahlungen werden unterstützt; mehrdeutige Zuordnungen und nicht sicher auflösbare Differenzen bleiben zur Prüfung offen. Zuordnungen sind korrigierbar und lösbar.

### Automatik und Ausnahmen

Der Nutzer wählt in den Einstellungen eine Automatisierungsstufe. **Manuell** (Standard): jeder neue oder geänderte Vorgang aus einem Import wird vom Nutzer bestätigt. **Ausgewogen**: vollständig validierte, unterstützte Standardfälle mit eindeutiger Zuordnung werden ohne Einzelbestätigung übernommen; alles andere bleibt Ausnahme. **Automatisch**: es gibt keinen Bestätigungsschritt mehr; unklare Angaben bleiben leer oder als offene Ausnahme markiert statt erfunden zu werden. Die folgenden Regeln beschreiben, was in den Stufen Ausgewogen und Automatisch als sicher gilt.

Eindeutige Zuordnungen und vollständig validierte, unterstützte Standardfälle werden ohne Einzelbestätigung übernommen. Dafür müssen die benötigten Fakten vorliegen, die deterministischen Prüfungen bestehen und relevante Widersprüche oder konkurrierende Zuordnungen ausgeschlossen sein. Die Selbsteinschätzung des Modells reicht nicht. Manuelle Änderungen dürfen nicht still überschrieben werden.

Fehlende Informationen, Warnungen und Konflikte werden dauerhaft am betroffenen Vorgang oder Import vermerkt und über „Prüfen“ beziehungsweise Start erreichbar. Die konkrete Korrektur, Ergänzung oder Zuordnung löst die jeweilige Ausnahme. Es ist keine Chat-Unterhaltung erforderlich. Technische Fehlschläge bleiben wiederholbar; bereits erfolgreich bearbeitete Dateien bleiben erhalten. Automatisch übernommene Vorgänge bleiben direkt einsehbar und editierbar.

### Dokumentverständnis

Der Kontoauszugimport ist bankunabhängig. PDF-Kontoauszüge werden wie Belege visuell vom multimodalen Modell gelesen; für CSV-Auszüge gibt es einen deterministischen Import auf ein normalisiertes Bewegungsformat, das Modell darf dabei nur beim Erkennen der Spaltenzuordnung helfen. Es werden keine bankspezifischen Adapter vorausgebaut.

PDF-/Bildbelege und PDF-Kontoauszüge werden mit dem multimodalen Modell ausgewertet. Das Ergebnis sind strukturierte Fakten für die gemeinsame Normalisierung, Validierung und Persistenz, nicht ungeprüfte Datenbankänderungen. Kontoauszüge werden als einzelne Kontobewegungen verarbeitet. Verfügbare Summen und Salden dienen der Gegenprüfung; abgeschnittene oder unvollständige Verarbeitung darf nicht als erfolgreicher vollständiger Auszug erscheinen.

Strukturierte Rechnungsdaten aus XRechnung in UBL/CII und aus eingebettetem ZUGFeRD-XML werden lokal gelesen. Bevorzugt werden eigene Formatadapter auf einem vorhandenen nativen XML-Parser, keine selbst entwickelte XML-Grammatik. Die Fakten benötigen keine erneute KI-Extraktion; bei offenen Einordnungen kann das Modell ergänzen. Unbekannte oder widersprüchliche strukturierte Inhalte dürfen nicht als geprüfte Rechnung durchlaufen. Interne Verarbeitung und mögliche Werkzeuge erzeugen keine zusätzlichen Benutzermodi.

### Steueraufgaben und Ausgabe

Onboarding und Einstellungen erfassen den geltenden UStVA-Rhythmus: monatlich, quartalsweise oder keine regelmäßigen Voranmeldungen. Pfennig bestimmt die rechtliche Verpflichtung nicht eigenmächtig aus Umsätzen. Eine jährliche Umsatzsteuererklärung ist keine jährliche UStVA. Kleinunternehmer-Sonderfälle wie Reverse Charge bleiben auch ohne regelmäßige Voranmeldungen erkennbar.

Start verlinkt die zutreffenden periodischen Steueraufgaben und Jahresvorbereitung. Termine beruhen auf bekannten Verpflichtungen und zutreffenden Fristdaten; fehlende Angaben werden gezielt erfragt, nicht durch scheinbar sichere Termine ersetzt. Eine Aufgabe öffnet die konkrete Vorbereitung mit Zeitraum, berechneten Formularwerten und relevanten Ausnahmen, keine zweite dauerhafte Analyse-Seite.

Alle relevanten gespeicherten Vorgänge werden automatisch berücksichtigt. Der Nutzer wählt nicht erneut die einzubeziehenden Buchungen aus. Pfennig bestimmt steuerlichen Zeitraum und Anteil nach den anwendbaren Regeln; Buchhaltungsbestand und steuerlicher Beitrag sind nicht identisch. Beispielsweise zählt eine unbezahlte Ausgangsrechnung unter Ist-Versteuerung noch nicht als vereinnahmter steuerpflichtiger Umsatz. Teilzahlungen tragen in ihren jeweiligen Zeiträumen bei. Jede Formularsumme ist auf Vorgänge und Zahlungen zurückführbar.

UStVA und EÜR verwenden eigene, geprüfte Berechnungen und jahresbezogene Formularzuordnungen, nicht die Start-Bruttosummen. Fehlende materielle Angaben, ungeklärte Steuerbehandlung und nicht unterstützte Jahreskorrekturen bleiben sichtbar; eine solche Ausgabe ist als unvollständiger Entwurf erkennbar. Auch ein leerer Zeitraum wird nachvollziehbar dargestellt, nicht mit fehlenden Daten oder aufgehobener Meldepflicht gleichgesetzt.

Die erste Lieferung darf aus kopierbaren Formularwerten und nachvollziehbarer Ausgabe bestehen. Ein verifizierter UStVA-XML-Export zum manuellen ELSTER-Upload wird früh verfolgt, ist aber keine Voraussetzung für diese erste Lieferung. Ein EÜR-Dateiimport wird ohne Nachweis nicht versprochen. Pfennig übermittelt nicht selbst. Export bedeutet nur Vorbereitung; eine externe Abgabe darf nur nach Nutzerbestätigung als erledigt gelten und sperrt keine Buchungen.

## Systemgrenzen und Bestand

Originale, Buchungen und Bearbeitungsstand bleiben lokal erhalten und ohne Modellzugang einsehbar. KI-Verarbeitung folgt der bestehenden Freigabe und Konfiguration. Steuerberechnung, Geldbeträge, Validierung und autorisierte Schreiboperationen bleiben deterministisch. Bestehende Archive und manuelle Änderungen werden erhalten.

Heute benötigen Importvorschläge Einzelbestätigung; Kontoauszugabgleich, E-Rechnungsimport und fertige Steuerberichte fehlen. Diese Spezifikation beschreibt Zielverhalten, nicht den aktuellen Implementierungsstand. Vorhandene UStVA-/EÜR-Mappings sind ungeprüft. Die bisherige Auswahl „Jährlich“ darf bei der Umstellung nicht ungefragt als rechtlich bestätigte Befreiung interpretiert werden; die zutreffende Einstellung muss bestätigt werden.

## Abnahme

- Derselbe Geschäftsvorgang entsteht bei Rechnung zuerst und bei Zahlung zuerst; spätere Belege, manuelle Zahlungen, Teilzahlungen und wiederholte Auszüge erzeugen keine Doppelbuchung.
- Sichere Standardfälle durchlaufen den Eingang ohne Einzelbestätigung. Mehrdeutige Zahlungen, widersprüchliche Beträge und geschützte manuelle Werte führen dagegen zur passenden sichtbaren Ausnahme.
- Ein mehrseitiger PDF-Kontoauszug und ein CSV-Auszug desselben Kontos liefern dieselben Bewegungen. Unvollständige Extraktion wird nicht als vollständiger Erfolg behandelt.
- UBL, CII und ZUGFeRD führen über denselben Buchungsablauf; strukturierte Fakten werden ohne erneute KI-Extraktion übernommen.
- Steueraufgaben folgen der bestätigten Konfiguration. Relevante Kleinunternehmer-Reverse-Charge-Fälle werden nicht durch deaktivierte regelmäßige Voranmeldungen verborgen.
- UStVA/EÜR berücksichtigen Zahlungstermine, Vorsteuerbedingungen, Kleinunternehmerbehandlung und bekannte Ausnahmen korrekt. Jede Formularsumme bleibt nachvollziehbar; keine zweite Auswahl sämtlicher Buchungen ist erforderlich.
- Kopieren oder Exportieren markiert nichts als abgegeben. Offene materielle Fälle verhindern eine irreführend vollständige Ausgabe. Historische Daten bleiben zugänglich.

## Entscheidungsgrundlage

Der Nutzer hat automatische Übernahme sicherer Fälle (Q1 A), CSV einschließlich PDF-Kontoauszügen (Q2 B) und eine erste Ausgabe ohne zwingenden XML-Export (Q3 A) ausdrücklich gewählt. Der gemeinsame Dokumenteneingang, Ausnahmen statt Routinebestätigungen, die Aufgaben auf Start und der Verzicht auf Chat sind festgelegte Produktrichtung.

Fachliche Ausgangspunkte: [§18 UStG](https://www.gesetze-im-internet.de/ustg_1980/__18.html), die [Recherche zu Steuerberechnung und ELSTER](../research-user-workflow.md) und die [OpenAI-Dokumentation zu Dateieingaben](https://developers.openai.com/api/docs/guides/file-inputs). Die öffentliche ELSTER-Uploadmöglichkeit ist belegt, ein aktueller Pfennig-XML-Import hingegen noch nicht validiert.
