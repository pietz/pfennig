# Pfennig neu: Spezifikation für den Neuaufbau

**Status:** bestätigt (2026-09-14). Alle sieben Abschnitte sind gemeinsam entschieden und gelten als Grundlage für den Neuaufbau.

**Ergänzung Fremdwährung (2026-09-15):** Fremdwährungen und ein zweites Agentenwerkzeug sind freigegeben. Die Buchhaltung und alle Summen bleiben in EUR. Es gibt keine währungsspezifische Präzision, keine Kursgewinn- und Verlustrechnung und keinen Revaluierungsmechanismus.

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

Pfennig ist eine lokale macOS-App für deutsche Freiberufler und Einzelunternehmer mit EÜR und Ist-Versteuerung, regelbesteuert oder Kleinunternehmer. Sie sammelt Einnahmen und Ausgaben aus Dokumenten, die der Nutzer per Drag-and-drop ablegt: Rechnungen, Belege, Gutschriften, Kontoauszüge. Ein KI-Agent liest die Dateien, ordnet sie den bestehenden Einträgen zu oder legt neue an, und speichert das Ergebnis strukturiert in einer lokalen SQLite-Datenbank. Kontoauszüge kommen als zweiter Schritt nach Rechnungen und Belegen. Der Nutzer sieht eine Tabelle seiner Buchungen und kann jeden Eintrag im Inspector rechts ansehen und korrigieren. Am Ende hilft die App, die Steuerdaten für UStVA und EÜR vorzubereiten, ohne selbst zu übermitteln.

Die App wirkt nicht wie eine KI-Anwendung. Sie ist eine ruhige Tabelle, hinter der ein Agent die Arbeit macht. Deterministischer Code gibt es nur für das Schema, Geldbeträge, Steuerregeln und die Grenzen, innerhalb derer der Agent schreiben darf.

Nicht enthalten: Bankanbindung, Rechnungsstellung, Bilanz, Lohn, Chat, direkte ELSTER-Übermittlung, Herstellerregistrierung, bankspezifische Parser, regelbasierte Zuordnungslogik.

## 2. Datenmodell

Pfennig speichert Wissen über die Buchhaltung, nicht Protokoll über die Arbeit der App. Ein Freiberufler hat wenige hundert Buchungen im Jahr; alles passt in den Speicher. SQLite ist eine Datei mit sicherem Schreiben und Änderungsbeobachtung, kein Abfragesystem. Swift lädt, sortiert und rechnet. Tabellen, Spalten und Werte sind deutsch benannt, weil die Fachbegriffe deutsch sind und die App in Deutschland bleibt; etablierte Fremdwörter wie Reverse Charge bleiben.

**Fünf Tabellen in der Basis.** Eine trägt die Buchhaltung, vier sind klein und dienen ihr. Abschnitt 5 ergänzt mit dem Export `zeitraeume` als sechste Tabelle.

`buchungen`, eine Zeile pro Dokument. Ein Beleg ist immer genau ein Eintrag.
- `id` (hochzählende Ganzzahl), `richtung` (einnahme/ausgabe), `art` (rechnung, beleg, gutschrift, steuerzahlung, nur_zahlung, ignoriert, sonstiges), `datum` (Belegdatum), `belegnummer` (optional, wie auf dem Beleg angegeben), `faelligkeit` (optional, gültiges Datum), `titel`, `kategorie` (feste EÜR-Kategorienliste im Code, Schlüssel unwiderruflich), `privatanteil_prozent`, `notizen`
- Gegenpartei als Text: `gegenpartei_name`, `gegenpartei_land`, `gegenpartei_ustid`. Die USt-IdNr. gehört zum Beleg, nicht zu einem Stammsatz.
- `positionen`, JSON-Liste von {netto, steuersatz, steuer} in EUR-Cent. Meist ein Element, bei Mischbelegen (Hotel mit Frühstück, Bewirtung) mehrere. Beliebige Sätze, auch ausländische. Keine Summenspalten; Brutto, Netto und Steuer rechnet Swift.
- `waehrung` und `originalbetrag`: nur bei Fremdwährungsbelegen gefüllt, leer heißt Euro. `originalbetrag` ist eine exakte Dezimalzahl in den Haupteinheiten der Originalwährung, ohne Rundung auf zwei Stellen. Die Positionen stehen immer in Euro. Ein tatsächlich gezahlter EUR-Betrag geht vor einer Referenzumrechnung; sonst trägt der Agent das Ergebnis des Umrechnungswerkzeugs ein.
- `steuerbehandlung` (inland, reverse_charge, kleinunternehmer, steuerfrei, nicht_steuerbar, unklar). Beantwortet, warum ein Beleg keine oder eine besondere Umsatzsteuer hat.
- `zahlungen`, JSON-Liste von {datum, betrag}. `betrag` ist ein vorzeichenbehafteter Betrag in EUR-Cent relativ zur Buchung: positiv für eine Zahlung, negativ für eine Erstattung. Teilzahlungen sind mehrere Elemente. Eine Zahlung gehört zu genau einem Eintrag; eine Überweisung für zwei Rechnungen sind zwei Zahlungselemente. Geprüft wird ausschließlich die Buchung als Ganzes über `geprueft_am`.
- `belege`, JSON-Liste von SHA-256-Hashes der zugehörigen Dateien (keine Kontoauszüge).
- `geprueft_am` (leer = ungeprüft), `erstellt_am`, `geaendert_am`.

Kategorie und Privatanteil gelten für den ganzen Beleg. Bei zwei Kategorien auf einem Beleg zählt die dominante; ein Randfall, der bewusst nicht abgebildet wird. Einnahmen und Ausgaben stehen in derselben Tabelle, unterschieden durch die Richtung.

Eine Kontobewegung ohne passenden Beleg ist ein Eintrag mit `art = nur_zahlung` (unklar, ungeprüft, Titel aus dem Verwendungszweck) oder `art = ignoriert` (privat, interner Übertrag; in der Tabelle ausgeblendet). So erkennt der Agent bereits verarbeitete Auszüge wieder, ohne eigene Tabelle.

`dateien`: `sha256` (Schlüssel), `dateiname`, `endung`, `groesse`, `art` (beleg/kontoauszug), `seiten`, `importiert_am`. Dedupe ist „Hash existiert“. Kontoauszüge hängen an keinem Eintrag.

`aktivitaeten`: ein Log, `id`, `buchung_id`, `zeitpunkt`, `akteur` (nutzer/agent), `vorher` (JSON der Zeile, leer bei Neuanlage), `nachher` (JSON der Zeile). Ein Insert pro Schreibvorgang im Repository. Ersetzt Herkunft, Audit und Vorschlagstabellen und zeigt, was der Agent geändert hat; angezeigt, kein Undo in der ersten Version. Das SQL-Werkzeug des Agenten hat keinen Zugriff auf diese Tabelle.

`anfragen`: eine Anfrage an den Agenten pro Datei, `id`, `datei_sha256`, `modell`, `gestartet_am`, `beendet_am`, `status` (erfolg/fehler), `eingabe_tokens`, `ausgabe_tokens`, `konversation` (JSON ohne Dateibytes: Text, Werkzeugaufrufe, Antworten). Kosten rechnet Swift aus einer Preistabelle im Code, damit Preisänderungen rückwirkend stimmen. Das SQL-Werkzeug des Agenten hat keinen Zugriff auf diese Tabelle.

`einstellungen`, Schlüssel und Wert. Enthält auch das Profil: Steuernummer, USt-ID, Kleinunternehmer, UStVA-Rhythmus, Dauerfristverlängerung. Der Agent hat keinen Werkzeugzugriff auf diese Tabelle.

Eine Tabelle für abgegebene Zeiträume kommt mit dem Export in Thema 5.

**Das Dateisystem übernimmt den Rest.** Alles liegt unter `~/Library/Application Support/Pfennig/`: die Datenbank, `Archiv/` mit den Originalen als `<sha256>.<endung>` und `Inbox/`. Abgelegte Dateien landen in `Inbox/` und wandern nach erfolgreicher Verarbeitung ins Archiv; Inbox ist Fortschritt und Wiederholung zugleich.

**Bewusst nicht:** Tabellen für Zahlungen, Positionen, Gegenparteien, Kategorien, Zuordnungen, Vorschläge, Herkunft, Importläufe. Keine UUIDs. Keine Regel, die vom Nutzer bearbeitete Einträge vor dem Agenten schützt; die Aktivitäten zeigen jede Änderung. Keine Versionsprüfung; parallele Läufe könnten in seltenen Fällen dieselbe Rechnung doppelt anlegen, was der Nutzer beim Prüfen sieht. Bekannte Gegenparteien werden weder als Stammsatz noch als automatisch geladener Agentenkontext geführt.

## 3. Oberfläche

Ein Fenster. Der Hauptraum besteht aus einer linken Navigation mit genau „Buchungen“ sowie der Tabelle, dem Inspector und der Toolbar. Weitere Hauptseiten gibt es nicht.

Die Buchungsansicht verwendet dauerhaft die freigegebene verfeinerte native Gestaltung: randlose 40-Punkt-Zeilen, kleine neutrale Kategorie-Symbole, ruhige abgeleitete Prüfstatus und grüne Einnahmen bei primären Ausgaben. Die Ansicht arbeitet mit den echten Buchungen aus AppModel und Repository; es gibt keine Vergleichsseiten oder Beispieldaten.

**Tabelle.** Eine Zeile pro Eintrag. Standardspalten sind wenige: Unternehmen (Gegenpartei mit Titel als Unterzeile, Kategorie-Symbol und Belegsymbol), Datum, Betrag, Bezahlt (Zahlungsstand als Symbol und Text, abgeleitet aus Zahlungssumme gegen Brutto: offen bis zur vollständigen Zahlung, danach bezahlt; ein Klick schaltet zwischen vollständig bezahlt heute und unbezahlt um) und Status (Geprüft, Zu prüfen oder Beleg fehlt, aus den vorhandenen Buchungsdaten abgeleitet). Weitere Spalten (etwa Kategorie, Steuersatz, Art) kann der Nutzer über die Spaltenauswahl der Tabelle einblenden. Die Fußzeile zeigt Einnahmen, Ausgaben und Saldo der aktuell sichtbaren Zeilen.

Der Status ist abgeleitet: Fehlt bei `art = rechnung`, `beleg` oder `gutschrift` der Anhang (`belege` ist leer), hat Beleg fehlt Vorrang; ansonsten entscheidet der Zeitstempel `geprueft_am` zwischen Geprüft und Zu prüfen. Der Filter Zu prüfen meint `geprueft_am` leer und umfasst damit auch Buchungen mit fehlendem Anhang; dies ist keine rechtliche Vollständigkeitsprüfung.

**Startansicht.** Das Fenster hat eine Standardgröße von 840 × 500 Punkten. Der rechte Inspector ist beim Start ausgeblendet und über den bestehenden Toolbar-Schalter erreichbar.

**Inspector.** Rechts, standardmäßig ausgeblendet. Er zeigt alle Informationen eines Eintrags, die nicht in eine Tabelle gehören: Beleg mit Vorschau, Grunddaten einschließlich der optionalen Belegnummer und Fälligkeit, Beträge, Steuer, Zahlungen, Notizen, bei ungeprüften Einträgen eine Bestätigen-Aktion. Eine Fälligkeit ist als Überfällig markiert, wenn sie vor dem lokalen heutigen Datum liegt und die Buchung nicht vollständig bezahlt ist. Umsetzung als `.inspector` mit einem Formular im Stil `.grouped`. Alle Abschnitte sind flach und immer sichtbar, keine Akkordeons; ein leerer Abschnitt wird weggelassen, nicht eingeklappt.

**Toolbar.** Ein Dropdown Alle / Einnahmen / Ausgaben, ein Dropdown Alle Status / Zu prüfen / Ohne Beleg, ein Suchfeld, das ausgewählte Spalten in Echtzeit durchsucht, ein Fortschrittsanzeiger, während der Agent arbeitet, ein Plus für manuelle Einträge sowie Export, Einstellungen und Inspector. Keine Jahresauswahl im ersten Schritt.

**Drag-and-drop** gilt für das ganze Fenster.

**Einstellungen** sind das normale macOS-Einstellungsfenster (Menü und Tastenkürzel, Zahnrad in der Toolbar): Profil, KI-Zugang (Schlüssel, Verbindungstest, Modell, Aufwand, schnellere Verarbeitung), Erscheinungsbild.

**Wegfall:** Startseite, Prüfen-Seite, Vergleichsseiten und UStVA-Aufgabenfenster; der Hauptraum bleibt auf die Buchungsansicht begrenzt. Erster Schritt ist Eingang, Speicherung und Anzeige sauber, minimal und solide. Wie die Daten danach für Steuerzwecke bereitgestellt werden, folgt in Abschnitt 5 und wird erst gebaut, wenn die Basis steht.

## 4. Eingang: Dateien und Agent

**Grundsatz.** Die Verarbeitung durch den KI-Agenten ist der Kern und immer die erste Lösung, die in Betracht kommt. Deterministischer Code im Eingang beschränkt sich auf das, was der Agent nicht kann oder nicht soll: Dateien hashen und verschieben, Formate zulassen, Werkzeugaufrufe prüfen.

**Weg einer Datei.** Der Nutzer zieht eine oder mehrere Dateien auf das Fenster. Für jede Datei:

1. Swift berechnet den Hash und kopiert sie nach `Inbox/`.
2. Existiert der Hash schon in `dateien`, ist die Datei fertig; kurze Rückmeldung „bereits vorhanden“.
3. Sonst startet ein Agentenlauf für diese Datei. Bis zu zehn Dateien werden gleichzeitig verarbeitet; die Datenbank bleibt konsistent, weil jede SQL-Anweisung des Agenten in einer eigenen Transaktion läuft.
4. Nach Erfolg wandert die Datei als `<hash>.<endung>` ins Archiv, bekommt eine Zeile in `dateien` und verlässt die Inbox. Das sql-Werkzeug meldet Swift die berührten Buchungs-IDs; an diese hängt Swift den Hash.
5. Bei Fehler bleibt sie in der Inbox mit Fehlertext, in der App sichtbar mit „Erneut versuchen“ und „Verwerfen“. Buchungen, die der abgebrochene Lauf angelegt hat, entfernt Swift vor einem erneuten Versuch, damit nichts doppelt entsteht.

Der Fortschrittsanzeiger in der Toolbar zeigt den Stand, solange die Inbox nicht leer ist. Beim App-Start wird eine nicht leere Inbox abgearbeitet. Zugelassen sind PDF, Bilder und CSV; die Datei geht so, wie sie ist, an den Agenten.

**Ein Agent, zwei Werkzeuge.** Der Agent arbeitet von Anfang an in einer Werkzeugschleife über die Responses API. Sein erstes Werkzeug ist `sql`: er liest und schreibt `buchungen` direkt mit SELECT, INSERT und UPDATE. Das zweite Werkzeug ist `umrechnen(waehrung, datum, betraege)`. Es fragt genau einmal den historischen Frankfurter-v2-Kurs für das Währungspaar und Datum ab und rechnet alle gelieferten Originalbeträge mit Swift `Decimal` in EUR-Cent um. Die öffentliche API erhält nur Währung und Datum, nicht Beträge oder Dokumente. Die Standardrate ist Frankfurters gemischte Referenzrate, ausdrücklich kein Bank- oder steuerlich vorgeschriebener Kurs. Rate, tatsächliches Kursdatum und Quelle stehen in der bestehenden Anfragekonversation. Es gibt keinen getrennten Extraktionspfad mit eigenem Ausgabeschema; was die App später zusätzlich kann (Kontoauszüge, Zuordnungen), ändert nur die Anleitung, nicht den Mechanismus.

Der Agent erhält dynamisch aus der Datenbank selbst die tatsächliche CREATE-Anweisung ausschließlich für `buchungen`, damit sie immer aktuell ist. Aufzählungen wie richtung, art und steuerbehandlung sind als CHECK-Bedingungen im Schema hinterlegt und dadurch im Schematext sichtbar. Für JSON-Spalten steht die Struktur als Kommentar im Schema.

**Drei Grenzen in Swift.**
1. Erlaubte Anweisungen über den SQLite-Autorisierer: SELECT, INSERT und UPDATE ausschließlich auf `buchungen`; kein DELETE, keine Schemaänderung, kein Zugriff auf andere Tabellen.
2. Jeder Aufruf läuft in einer Transaktion. Danach laufen die Prüfregeln über die geänderten Zeilen; bestehen sie, wird committet, sonst Rollback, und der Fehlertext geht als Werkzeugantwort an den Agenten, der korrigiert.
3. Vor und nach dem Aufruf werden die berührten Zeilen verglichen; die Differenz landet automatisch in `aktivitaeten`.

**Kontext des Agenten.** Pro Datei ein Aufruf der Responses API. Die Nutzer-Nachricht ist ein beschreibendes Ereignis mit Dateiname und Anhang, kein Arbeitsauftrag. Der kurze dauerhafte Systemtext beschreibt Pfennig und Buchungen, gefolgt von zwei Regeln: Ausgaben gelten beim Import als bezahlt, sofern das Dokument nichts Gegenteiliges erkennen lässt; fehlt das Zahlungsdatum, gilt das Belegdatum. Vollständig betriebliche Nutzung wird angenommen, sofern das Dokument oder der Nutzer keinen privaten Anteil angibt. Danach folgen das neutrale Profil als Markdown-Liste mit `heute`, `name`, `ustid` und dem rohen Boolean `kleinunternehmer`, ein kurzer Hinweis auf die von der Anwendung verwalteten Felder direkt über der tatsächlichen CREATE-Anweisung nur für `buchungen` und die nach Einnahmen und Ausgaben gruppierten Kategorieschlüssel. Fehlender Name und fehlende USt-ID werden ausdrücklich als nicht angegeben bezeichnet. Steuernummer, Kategoriebeschreibungen, bekannte Gegenparteien und weitere fachliche oder anbieterspezifische Regeln stehen nicht im Kontext. Modell (gpt-5.6-sol, -terra, -luna), Reasoning-Aufwand und schnellere Verarbeitung (OpenAI Priority Processing, etwa doppelter Preis) wählt der Nutzer im Tab „KI-Zugang“ der Einstellungen.

**Was der Agent füllt.** Der Agent pflegt die Buchungsfelder anhand des Dokuments und der Nutzerangaben. Von der Anwendung verwaltet und vom Agenten nicht gesetzt werden `id`, `belege`, `geprueft_am`, `erstellt_am` und `geaendert_am`. Pro sql-Aufruf entsteht oder ändert sich eine vollständige Buchung (mindestens eine Position), weil die Prüfregeln nach jedem Aufruf laufen. Ein erfolgreicher Import muss mindestens eine Buchung ändern.

**Prüfregeln in Swift.** Schema und CHECK-Bedingungen garantieren Form und Typen; die Prüfregeln decken Inhalt ab, den das Schema nicht ausdrücken kann. Jede Regel ist eine kleine Funktion in einer Liste, eine neue Regel ist eine neue Funktion:
- Jede Position: netto und steuer passen zum steuersatz, Toleranz 1 Cent. Mindestens eine Position.
- kategorie ist ein bekannter Schlüssel, datum ist gültig und nicht weit in der Zukunft. Eine ausgefüllte faelligkeit ist ein gültiges Datum; es gibt keine Prüfung ihrer Reihenfolge zum Belegdatum. belegnummer wird als Text übernommen, ohne Nummerierungsprüfung.
- steuerbehandlung passt zu Land und Profil: reverse_charge nur bei ausländischer Gegenpartei, kleinunternehmer nur bei Einnahmen eines Kleinunternehmers, inland mit Steuersatz 0 nur bei steuerfrei oder nicht_steuerbar.
- Zahlungen: Betrag ungleich null, Datum gültig.

Schlägt eine Regel fehl, bekommt der Agent den Fehlertext zurück. Gibt er nach wenigen Versuchen auf, bleibt die Datei mit dem Fehlertext in der Inbox. Ob die Zahlen zum Beleg passen, prüft Swift nicht; das ist die Aufgabe des Nutzers.

**Prüfen statt Automatisierungsstufe.** Es gibt keine Automatisierungsstufe. Jede Buchung des Agenten wird sofort geschrieben, mit leerem `geprueft_am`, in der Tabelle als farbiges Symbol sichtbar. Der Nutzer bestätigt sie im Inspector; danach ist sie eine normale Buchung. Mehr Logik gibt es nicht.

## 5. Ausgang: Steuerdaten

Ein Knopf „Export“ in der Toolbar öffnet ein Sheet. Vorausgewählt ist die UStVA für den Zeitraum, der sich aus Rhythmus, Dauerfristverlängerung und heutigem Datum ergibt; wählbar sind andere Zeiträume und die EÜR eines Jahres.

- **UStVA** wird als XML gespeichert, wie es Mein ELSTER im Formular „XML-Daten hochladen“ annimmt, ohne Herstellerregistrierung. Der Nutzer lädt die Datei hoch, prüft das vorausgefüllte Formular und sendet selbst ab. Das Sheet zeigt den Link dazu. Der Aufbau des XML ist aus öffentlichen Quellen rekonstruiert und wurde am 2026-09-14 mit einem Testupload der Q3-2026-Datei in Mein ELSTER verifiziert: die Datei wurde angenommen und die Kennzahlen ins Formular übernommen, ohne Absenden.
- **EÜR** wird als CSV mit Formularzeile, Bezeichnung und Betrag gespeichert; für die Anlage EÜR gibt es keinen Upload, die Werte werden abgetippt.

Berechnung (Ist-Versteuerung nach Zahlungsdatum, Vorsteuer, Reverse Charge, Kleinunternehmer, geprüfte Kennzahlen) und XML-Exporter werden aus dem alten Code übernommen. Mit dem Export kommt eine kleine Tabelle `zeitraeume` (jahr, art, index, exportiert_am), damit die App anstehende Zeiträume erinnern und nachträgliche Änderungen in exportierten Zeiträumen warnen kann. Keine Übermittlung aus der App.

## 6. Technik und Vorgehen

**Struktur.** Ein Swift-Package mit drei Zielen: `Core` (Schema, Geld, Datum, Repository, Prüfregeln, Steuerrechnung, Export), `Agent` (Responses-Client, Werkzeugschleife, sql- und umrechnen-Werkzeug, Aktivitätsvergleich), `App` (SwiftUI). Tests je Ziel. Werkzeuge wie bisher: XcodeGen, `scripts/build.sh`, swiftformat, GRDB für SQLite.

**Übernommen aus dem alten Code**, kopiert und angepasst, nicht importiert: Money, LocalDate, UStVA-Berechnung mit den geprüften Kennzahlen 2026, EÜR-Zeilen, XML-Exporter, Kategorienliste, Responses-Client, Keychain-Zugriff, PDF-Vorschau. Alles andere wird nicht angesehen.

**Größe.** Es gibt kein Zeilenbudget. Die Vorgabe an jeden implementierenden Agenten lautet: einfach und solide bauen, keine Prüfungen und Abstraktionen für Fälle, die nicht in dieser Spec stehen, keine Vorsorge für spätere Erweiterungen. Die App wird durch die Entscheidungen in dieser Spec von selbst deutlich kleiner als die alte.

**Vorgehen.** Der alte Stand wird als Tag `legacy-2026-09-14` archiviert, der Rewrite ersetzt ihn im selben Repository. Reihenfolge: Schema und Repository; Tabelle mit Inspector und manueller Eingabe; Agent mit sql-Werkzeug; Export. Nach jedem Abschnitt läuft die App und der Nutzer testet. Nach jedem Abschnitt prüft ein Review-Agent auf Überbau. Vor 1.0 gibt es genau eine Schemadefinition, keine Migrationen und keinen Abwärtskompatibilitätscode.

**Aktualisierungen.** Die App verwendet Sparkle 2 mit der Standardoberfläche und einem Menüpunkt „Nach Updates suchen“. Sparkle prüft nach seiner normalen Einwilligung im Hintergrund und zeigt die Standard-Bestätigung vor der Installation. Updates sind mit Developer ID signierte und von Apple notarisierte ZIPs mit ausschließlich der App; Appcast und ZIP liegen als Assets in den GitHub Releases. Es gibt keine eigene Update-Oberfläche, kein Backend und keine erzwungenen Aktualisierungen. Die Ed25519-Schlüssel bleiben beim Eigentümer; nur der öffentliche Schlüssel steht im App-Bundle.

## 7. Was bewusst nicht gebaut wird

- Bankanbindung, Rechnungsstellung, Bilanz, Lohn
- Chat mit dem Agenten
- Direkte ELSTER-Übermittlung, Herstellerregistrierung, ERiC
- Bankspezifische Parser, Vorverarbeitung von Dateien in Swift, regelbasierte Zuordnung
- Automatisierungsstufen, Schutzregeln für bearbeitete Buchungen, Versionsprüfung
- Stammdaten für Gegenparteien, Kategorien in der Datenbank
- Weitere Tabellen neben den fünf aus Abschnitt 2, insbesondere für Zahlungen, Positionen, Zuordnungen, Vorschläge, Herkunft
- Kursgewinn- und Verlustrechnung, Fremdwährungsrevaluierung und sonstige Währungsbuchhaltung
- Startseite, Prüfen-Seite, eine Sidebar mit weiteren Seiten neben den drei freigegebenen Buchungsansichten, Jahresauswahl
- Migrationen und Abwärtskompatibilitätscode vor 1.0
- Mehrere Mandanten, mehrere Nutzer, Cloud-Sync
