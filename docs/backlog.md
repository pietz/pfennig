# Backlog

Ideen aus der Produktdiskussion am 2026-09-16, vom Eigentümer als lohnend eingestuft. Nichts hier ist beschlossen oder spezifiziert; jeder Punkt braucht vor dem Bau eine Ergänzung der Spec in `specs/pfennig-neu.md`. Die Reihenfolge innerhalb eines Themas ist eine Empfehlung.

## 1. Genauigkeit des Eingangs

Was hier besser wird, verbessert jede Zahl dahinter.

- **E-Rechnung lesen.** ZUGFeRD-PDFs tragen ein eingebettetes XML, XRechnungen sind reines XML. Swift erkennt beides und gibt dem Agenten das XML neben dem PDF; die Beträge, Sätze und Daten kommen dann aus der Quelle statt aus dem Bild. Kleiner Eingriff, große Wirkung. Empfohlener erster Schritt.
- **Kontoauszüge und Abgleich.** In der Spec als zweiter Schritt genannt, noch nicht gebaut. Anders als ein Beleg ist eine Kontobewegung kein eigenes Dokument, sondern muss gegen bestehende Buchungen abgeglichen werden: Zahlungsdatum und Betrag an die passende Rechnung, Rest als `nur_zahlung` oder `ignoriert`. Braucht ein eigenes Konzept für den Agentenlauf mit Zugriff auf die offenen Buchungen. Größte Lücke im Kernablauf, weil die Ist-Versteuerung am Zahlungsdatum hängt.
- **Bewirtung.** Nur 70 Prozent der Bewirtungskosten sind Betriebsausgabe, die Vorsteuer bleibt voll abziehbar; der Beleg braucht Anlass und Teilnehmer. Heute setzt der Agent meist einen Privatanteil, was die Vorsteuer falsch kürzt. Eigene Behandlung in der EÜR plus Abfrage der fehlenden Angaben.

## 2. Steuerliche Vollständigkeit

Pflichten und Fehler, die die Zielgruppe regelmäßig treffen.

- **Zusammenfassende Meldung.** Wer Kz-21-Umsätze hat, schuldet quartalsweise eine ZM an das BZSt: je EU-Kunde USt-IdNr und Summe, fällig am 25. des Folgemonats. Alle Felder liegen in den Buchungen; im Kern ein zweiter Export plus Frist auf der Startseite.
- **Umsatzsteuer-Jahreserklärung.** Dieselben Kennzahlen über das Jahr summiert, als XML für Mein ELSTER wie die UStVA. Aufbau muss wie bei der UStVA aus öffentlichen Quellen rekonstruiert und per Testupload geprüft werden.
- **Anlagevermögen und AfA.** Anschaffungen über 800 Euro netto sind keine Ausgabe, sondern werden über die Nutzungsdauer abgeschrieben. Heute zieht die EÜR sie voll ab. Konzept gewünscht: Kennzeichnung an der Buchung, Nutzungsdauer aus der AfA-Tabelle, lineare Jahresbeträge in der EÜR, Anlageverzeichnis als Export. Offene Fragen: monatsgenaue Abschreibung im ersten Jahr, Abgang und Privatentnahme, Verhältnis zur festen Kategorienliste.
- **Kleinunternehmer-Grenzen.** Einnahmen des Vorjahres gegen 25.000 Euro und des laufenden Jahres gegen 100.000 Euro auf der Startseite. Das Überschreiten der zweiten Grenze wirkt sofort, nicht erst zum Jahreswechsel.
- **Steuerschätzung und Rücklage.** Offene UStVA-Zahllast plus geschätzte Einkommensteuer auf den Jahresgewinn, als eine Zahl auf der Startseite: was vom Kontostand nicht dem Nutzer gehört. Braucht Grundfreibetrag, Tarif und ein paar Annahmen (Familienstand, Kirchensteuer, sonstige Einkünfte), die ehrlich als Schätzung ausgewiesen werden.

## 3. Arbeiten mit den Daten

- **Agent zum Sprechen.** Ein Gespräch mit dem Agenten über die Buchhaltung: Fragen zu Buchungen und Zeiträumen, Nachfragen, Dokumente im Gespräch ablegen. Die Spec schließt Chat in Abschnitt 7 aus; das ist eine Grundsatzentscheidung des Eigentümers und braucht eine Spec-Änderung. Offene Fragen: eigener Bereich oder Teil der Buchungsansicht, welche Werkzeuge der Gesprächsagent bekommt, ob er schreiben darf.
- **Aktivitäten lesen und rückgängig machen.** Der Agent bekommt Lesezugriff auf `aktivitaeten`, um frühere Änderungen zu verstehen. Der Nutzer kann eine Aktivität auf `vorher` zurücksetzen; das JSON liegt bereits vor.
- **Übergabe an den Steuerberater.** Ein Jahresordner mit Belegen nach Datum und Gegenpartei benannt, Buchungsliste und EÜR-Werte als CSV. Prüfen, ob ein etabliertes Format lohnt (DATEV-Buchungsstapel, CSV-Konventionen der gängigen Kanzleisoftware) oder ob ein sauberer Ordner reicht.

## Verworfen oder zurückgestellt

- **Erwartete wiederkehrende Belege.** Für Abos fehlt am Ende trotzdem die Rechnung; der Hinweis allein spart wenig. Zurückgestellt.

## Empfohlene Reihenfolge

1. E-Rechnung: klein, sofort spürbar, kein Spec-Konflikt.
2. Kontoauszüge und Abgleich: die größte Lücke im Kernablauf. Das Konzept dafür klärt zugleich, wie ein Agentenlauf mit Kontext auf bestehende Buchungen aussieht, und bereitet damit den Gesprächsagenten vor.
3. Anlagevermögen und AfA: verhindert einen echten Fehler in der EÜR, Konzept ausstehend.
4. Kleinunternehmer-Grenzen, ZM und Jahreserklärung: kleine Exporte und Anzeigen auf vorhandenen Daten.
5. Gesprächsagent: als Spec-Entscheidung, sobald 2 steht.
