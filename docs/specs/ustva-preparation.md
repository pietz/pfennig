# UStVA-Vorbereitung

**Status:** Approved 2026-09-14. Decisions: Vorsteuer bei max(Rechnung, Zahlung); Ausnahmen warnen statt blockieren; Erstnutzer ohne Dauerfristverlängerung, Testtermin 10.10.2026.

Ausbau der [Workflow-Spezifikation](document-to-tax-workflow.md), Abschnitt „Steueraufgaben und Ausgabe“, für die Umsatzsteuer-Voranmeldung. Fachliche Grundlage: [Implementierungslücken](../research-user-workflow.md) und [XML-Upload-Recherche](../research-ustva-xml.md). Erstes Zielereignis: die Voranmeldung Q3 2026 des Erstnutzers (Regelbesteuerung, quartalsweise, Ist-Versteuerung).

## Ziel

Pfennig berechnet für einen Voranmeldungszeitraum die Formularwerte der UStVA aus den gespeicherten Vorgängen und Zahlungen, zeigt sie mit Rückverfolgung auf Einzelvorgänge, listet offene Ausnahmen und stellt die Werte kopierbar sowie als XML-Datei zum manuellen Upload in Mein ELSTER bereit. Pfennig übermittelt nicht.

## Fachliche Regeln (Ist-Versteuerung)

- **Umsatzsteuer auf Einnahmen** entsteht je Zahlung im Zeitraum des Zahlungsdatums. Teilzahlungen tragen anteilig bei: die Zuordnung einer Zahlung zu einem Vorgang wird proportional auf dessen Steuerkomponenten (7 %, 19 %, steuerfrei) verteilt, Rundung centgenau mit Restverteilung, so dass die Summe aller Anteile den Vorgang exakt ergibt. Unbezahlte Ausgangsrechnungen zählen nicht.
- **Vorsteuer auf Ausgaben** wird im Zeitraum von max(Rechnungsdatum, Zahlungsdatum) angesetzt, ebenfalls anteilig je Zahlung. Das ist konservativ gegenüber §15 UStG (Vorsteuer wäre schon mit Rechnungsbesitz zulässig) und kommt ohne neues Feld „Rechnung liegt vor“ aus. Anzahlungen ohne Rechnung bleiben Ausnahme.
- **Reverse Charge §13b** (typisch: ausländisches SaaS): Steuer und, bei Regelbesteuerung, die gleich hohe Vorsteuer entstehen mit Ausführung der Leistung, praktisch mit dem Rechnungsdatum. Zahlungsdatum ist hier nicht maßgeblich. Kleinunternehmer schulden die Steuer ohne Vorsteuer.
- **Kleinunternehmer** haben keine Kz 81/86/66. Entsteht §13b-Steuer, ist eine Voranmeldung nur für die betroffenen Zeiträume Pflicht (§18 Abs. 4a UStG); Pfennig zeigt dann die Aufgabe trotz Einstellung „keine regelmäßigen Voranmeldungen“.
- **Gutschriften und Erstattungen** mindern den Zeitraum, in dem der Geldfluss stattfindet.
- Alle Berechnungen sind deterministisch in Swift auf Minor-Units. Start-Summen werden nicht wiederverwendet.

## Kennzahlen 2026

Erste Lieferung: Kz 81, 86 (Bemessungsgrundlagen 19 %/7 %, volle Euro), Kz 66 (Vorsteuer), Kz 46/47 mit Kz 67 (§13b Leistungen aus dem Ausland und zugehörige Vorsteuer), Kz 83 (Zahllast, berechnet). Weitere Kennzahlen des vorhandenen Mappings werden nur ausgegeben, wenn Vorgänge sie tatsächlich befüllen, und bleiben als „ungeprüft“ gekennzeichnet. Das Mapping wird gegen das BMF-Vordruckmuster 2026 abgeglichen und die Verifikation im Code dokumentiert.

## Ausnahmen

Ein Vorgang des Zeitraums wird zur Ausnahme, wenn: Steuerbehandlung `unknown`, EUR-Betrag fehlt, Steuerkomponenten nicht zur Bruttosumme passen, Zahlung ohne Vorgang oder Vorgang mit Ausgabe ohne Beleg, §13b mit ungeklärtem Leistungsort/Leistungsempfängertyp. Ausnahmen werden im Aufgabenfenster oberhalb der Werte gelistet und öffnen den Vorgang im Inspector. Die Werte werden trotzdem berechnet und als **Entwurf** markiert.

Vorschlag: Kopieren und XML-Export bleiben bei offenen Ausnahmen möglich, aber mit sichtbarem Hinweis „Entwurf, n offene Fälle“; die Datei trägt den Zusatz `-entwurf` im Namen. Kein hartes Blockieren, weil der Nutzer die finale Autorität ist und ein wissentlich unvollständiger Fall (z. B. fehlender Kleinbeleg) die Meldung nicht verhindern darf.

## Aufgabe auf Start und Aufgabenfenster

- Start zeigt einen Abschnitt „Steuern“ mit der nächsten fälligen Voranmeldung: Zeitraum, Frist (10. des Folgemonats, plus ein Monat bei Dauerfristverlängerung), Zahllast-Vorschau, Anzahl offener Fälle. Weitere zurückliegende, nicht als erledigt markierte Zeiträume erscheinen darunter.
- Die Aufgabe öffnet ein Fenster „UStVA Q3 2026“ mit Zeitraumwahl, Ausnahmen, Formularwerten je Kennzahl mit aufklappbarer Einzelaufstellung (Vorgang, Zahlung, Anteil), Zahllast, Buttons „Werte kopieren“, „XML exportieren“, „Als übermittelt markieren“.
- „Als übermittelt markieren“ speichert Datum und Zahllast je Zeitraum, sperrt nichts und ist rückgängig machbar. Spätere Änderungen an Vorgängen eines übermittelten Zeitraums erzeugen einen Hinweis auf Start („Zeitraum verändert seit Übermittlung“), keine Korrekturbuchung.
- Einstellungen erhalten: Dauerfristverlängerung ja/nein. Der bisherige Wert „Jährlich“ für den UStVA-Rhythmus wird zu „Keine regelmäßigen Voranmeldungen“ und muss beim ersten Öffnen der Aufgabe bestätigt werden.

## XML-Export

Datei nach der rekonstruierten Struktur des Mein-ELSTER-Uploads (`Anmeldungssteuern` mit Namespace/Version, `Steuerfall/Umsatzsteuervoranmeldung` mit Jahr, Zeitraum 01–12 bzw. 41–44, Steuernummer, Kz-Elementen), Kodierung ISO-8859-15 mit UTF-8 als Fallback-Option. Das Format ist nicht offiziell öffentlich dokumentiert; der Export ist deshalb als „experimentell“ beschriftet, bis ein Testupload durch den Nutzer in Mein ELSTER (ohne Absenden) das Formular korrekt befüllt hat. Danach wird das Label entfernt. Schlägt der Test fehl, bleiben die kopierbaren Werte der Weg.

## Nicht enthalten

Anlage EÜR (eigene Spezifikation), Dauerfristverlängerungsantrag und Sondervorauszahlung, Berichtigungen bereits übermittelter Zeiträume als Korrekturbuchung, Periodensperren, Kz 500 und sonstige Zusatzangaben, Soll-Versteuerung.

## Abnahme

- Zwei Teilzahlungen einer 19 %-Rechnung in Q3 und Q4 erscheinen anteilig in beiden Quartalen; die Summe entspricht der Rechnung.
- Ein Mischbeleg 7 %/19 % mit einer Zahlung verteilt Bemessungsgrundlagen und Steuer centgenau.
- Ausländisches SaaS erzeugt bei Regelbesteuerung Kz 47 und gleich hohe Kz 67 im Rechnungsmonat; bei Kleinunternehmer nur Kz 47 und die Aufgabe erscheint trotz „keine regelmäßigen Voranmeldungen“.
- Eine Ausgabe mit Rechnung in Q3 und Zahlung in Q4 zählt zur Vorsteuer in Q4.
- Ein Vorgang mit unbekannter Behandlung erscheint als Ausnahme, die Werte sind als Entwurf markiert, Export bleibt möglich.
- Ein leerer Zeitraum zeigt Nullwerte und die Aufgabe, keinen Fehler.
- Kopieren und Export markieren nichts als übermittelt; „Als übermittelt markieren“ sperrt keine Buchung.
- Jede Formularsumme ist durch die Einzelaufstellung reproduzierbar.
