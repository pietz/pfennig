# Pfennig neu: Spezifikation für den Neuaufbau

**Status:** in Arbeit, wird Thema für Thema gemeinsam geschrieben (2026-09-14). Nur bestätigte Abschnitte gelten.

Gliederung:

1. Zweck und Grenzen
2. Datenmodell
3. Oberfläche
4. Eingang: Dateien und Agent
5. Ausgang: Steuerdaten
6. Technik und Zielgröße
7. Was bewusst nicht gebaut wird

---

## 1. Zweck und Grenzen

Pfennig ist eine lokale macOS-App für deutsche Freiberufler und Einzelunternehmer mit EÜR und Ist-Versteuerung, regelbesteuert oder Kleinunternehmer. Sie sammelt Einnahmen und Ausgaben aus Dokumenten, die der Nutzer per Drag-and-drop ablegt: Rechnungen, Belege, Gutschriften, Kontoauszüge. Ein KI-Agent liest die Dateien, ordnet sie den bestehenden Einträgen zu oder legt neue an, und speichert das Ergebnis strukturiert in einer lokalen SQLite-Datenbank. Der Nutzer sieht eine Tabelle seiner Buchungen und kann jeden Eintrag im Seitenmenü ansehen und korrigieren. Am Ende hilft die App, die Steuerdaten für UStVA und EÜR vorzubereiten, ohne selbst zu übermitteln.

Die App wirkt nicht wie eine KI-Anwendung. Sie ist eine ruhige Tabelle, hinter der ein Agent die Arbeit macht. Deterministischer Code gibt es nur für das Schema, Geldbeträge, Steuerregeln und die Grenzen, innerhalb derer der Agent schreiben darf.

Nicht enthalten: Bankanbindung, Rechnungsstellung, Bilanz, Lohn, Chat, direkte ELSTER-Übermittlung, Herstellerregistrierung, bankspezifische Parser, regelbasierte Zuordnungslogik.

## 2. Datenmodell

Pfennig speichert Wissen über die Buchhaltung, nicht Protokoll über die Arbeit der App. Ein Freiberufler hat wenige hundert Buchungen im Jahr; alles passt in den Speicher. SQLite ist eine Datei mit sicherem Schreiben und Änderungsbeobachtung, kein Abfragesystem. Swift lädt, sortiert und rechnet. Tabellen, Spalten und Werte sind deutsch benannt, weil die Fachbegriffe deutsch sind und die App in Deutschland bleibt; etablierte Fremdwörter wie Reverse Charge bleiben.

**Vier Tabellen.** Eine trägt die Buchhaltung, drei sind klein und dienen ihr.

`buchungen`, eine Zeile pro Dokument. Ein Beleg ist immer genau ein Eintrag.
- `id` (hochzählende Ganzzahl), `richtung` (einnahme/ausgabe), `art` (rechnung, beleg, gutschrift, steuerzahlung, nur_zahlung, ignoriert, sonstiges), `datum` (Belegdatum), `titel`, `kategorie` (feste EÜR-Kategorienliste im Code, Schlüssel unwiderruflich), `privatanteil_prozent`, `notizen`
- Gegenpartei als Text: `gegenpartei_name`, `gegenpartei_land`, `gegenpartei_ustid`. Die USt-IdNr. gehört zum Beleg, nicht zu einem Stammsatz.
- `positionen`, JSON-Liste von {netto, steuersatz, steuer} in EUR-Cent. Meist ein Element, bei Mischbelegen (Hotel mit Frühstück, Bewirtung) mehrere. Beliebige Sätze, auch ausländische. Keine Summenspalten; Brutto, Netto und Steuer rechnet Swift.
- `waehrung` und `originalbetrag`: nur bei Fremdwährungsbelegen gefüllt, leer heißt Euro. Die Positionen stehen immer in Euro, am besten zum tatsächlich gezahlten Betrag vom Konto, sonst zum Kurs am Belegdatum. Swift rechnet keine Kurse.
- `steuerbehandlung` (inland, reverse_charge, kleinunternehmer, steuerfrei, nicht_steuerbar, unklar). Beantwortet, warum ein Beleg keine oder eine besondere Umsatzsteuer hat.
- `zahlungen`, JSON-Liste von {id, datum, betrag, richtung, geprueft}. Die id zählt innerhalb des Eintrags hoch (1, 2, 3). Teilzahlungen sind mehrere Elemente, eine Erstattung hat die Gegenrichtung, eine unsichere Zuordnung ist `geprueft = false`. Eine Zahlung gehört zu genau einem Eintrag; eine Überweisung für zwei Rechnungen sind zwei Zahlungselemente.
- `dateien`, JSON-Liste von SHA-256-Hashes der Belege (keine Kontoauszüge).
- `geprueft_am` (leer = ungeprüft), `erstellt_am`, `geaendert_am`.

Kategorie und Privatanteil gelten für den ganzen Beleg. Bei zwei Kategorien auf einem Beleg zählt die dominante; ein Randfall, der bewusst nicht abgebildet wird. Einnahmen und Ausgaben stehen in derselben Tabelle, unterschieden durch die Richtung.

Eine Kontobewegung ohne passenden Beleg ist ein Eintrag mit `art = nur_zahlung` (unklar, ungeprüft, Titel aus dem Verwendungszweck) oder `art = ignoriert` (privat, interner Übertrag; in der Tabelle ausgeblendet). So erkennt der Agent bereits verarbeitete Auszüge wieder, ohne eigene Tabelle.

`dateien`: `sha256` (Schlüssel), `dateiname`, `endung`, `groesse`, `art` (beleg/kontoauszug), `seiten`, `importiert_am`. Dedupe ist „Hash existiert“. Kontoauszüge hängen an keinem Eintrag.

`aktivitaeten`: ein Log, `id`, `buchung_id`, `zeitpunkt`, `akteur` (nutzer/agent), `aenderung` (JSON mit Vorher und Nachher). Ein Insert pro Schreibvorgang im Repository. Ersetzt Herkunft, Audit und Vorschlagstabellen, gibt Undo und zeigt, was der Agent geändert hat. Der Agent darf es lesen, nicht schreiben. Das genaue Spaltendesign wird vor der Umsetzung noch einmal geprüft.

`einstellungen`, Schlüssel und Wert. Enthält auch das Profil: Steuernummer, USt-ID, Kleinunternehmer, UStVA-Rhythmus, Dauerfristverlängerung, Automatisierungsstufe. Der Agent hat keinen Werkzeugzugriff auf diese Tabelle.

Eine Tabelle für abgegebene und anstehende Zeiträume ist Thema 5 und nicht Teil der ersten Version.

**Das Dateisystem übernimmt den Rest.** Originale liegen im Archivordner als `<sha256>.<endung>`. Abgelegte Dateien landen in `Inbox/` und wandern nach erfolgreicher Verarbeitung ins Archiv; Inbox ist Fortschritt und Wiederholung zugleich.

**Bewusst nicht:** Tabellen für Zahlungen, Positionen, Gegenparteien, Kategorien, Zuordnungen, Vorschläge, Herkunft, Modellläufe, Importläufe. Keine UUIDs. Keine Regel, die vom Nutzer bearbeitete Einträge vor dem Agenten schützt; der Agent arbeitet nach der Automatisierungsstufe, die Aktivitäten zeigen jede Änderung. Keine Versionsprüfung, weil Dateien nacheinander verarbeitet werden. Bekannte Gegenparteien sind eine in Swift aus den Einträgen gruppierte Liste, kein Stammsatz.

## 3. Oberfläche

Ein Fenster. Es besteht aus der Tabelle, dem Inspector rechts und einer Toolbar. Keine Sidebar, keine weiteren Seiten.

**Tabelle.** Eine Zeile pro Eintrag. Standardspalten sind wenige: Datum, Gegenpartei, Titel, Betrag, Zahlungsstand und Beleg als Symbol. Weitere Spalten (etwa Kategorie, Steuersatz, Art) kann der Nutzer über die Spaltenauswahl der Tabelle einblenden. Die Fußzeile zeigt Einnahmen, Ausgaben und Saldo der aktuell sichtbaren Zeilen.

**Inspector.** Rechts, standardmäßig sichtbar. Er zeigt alle Informationen eines Eintrags, die nicht in eine Tabelle gehören: Beleg mit Vorschau, Grunddaten, Beträge, Steuer, Zahlungen, Notizen, bei ungeprüften Einträgen eine Bestätigen-Aktion. Umsetzung als `.inspector` mit einem Formular im Stil `.grouped`. Alle Abschnitte sind flach und immer sichtbar, keine Akkordeons; ein leerer Abschnitt wird weggelassen, nicht eingeklappt.

**Toolbar.** Ein Dropdown Alle / Einnahmen / Ausgaben, ein Suchfeld, das ausgewählte Spalten in Echtzeit durchsucht, ein Fortschrittsanzeiger, während der Agent arbeitet, ein Plus für manuelle Einträge. Keine Jahresauswahl im ersten Schritt.

**Drag-and-drop** gilt für das ganze Fenster.

**Einstellungen** sind das normale macOS-Einstellungsfenster (Menü und Tastenkürzel, optional Zahnrad in der Toolbar): Profil, Automatisierungsstufe, KI-Zugang, Erscheinungsbild.

**Wegfall:** Startseite, Prüfen-Seite, Sidebar, UStVA-Aufgabenfenster. Erster Schritt ist Eingang, Speicherung und Anzeige sauber, minimal und solide. Wie die Daten danach für Steuerzwecke bereitgestellt werden, folgt in Abschnitt 5 und wird erst gebaut, wenn die Basis steht.
