# Landingpage-Medien: Was jede Stelle zeigt

Arbeitsstand 2026-09-21. Brief für die Aufnahme der Screenshots und Screencasts aus `Pfennig Dev.app` mit Demodaten. Die Seite ist `daft.html`, die Slots stehen dort als `daft-assets/preview.svg`.

## Grundsätze

- **Ein Video, sonst Standbilder.** Bewegung nur da, wo sie etwas erklärt, das ein Bild nicht kann: den Vorgang vom Ablegen bis zur Buchung. Alles andere ist Zustand und wird als Bild gezeigt. Die App soll ruhig wirken, die Seite auch.
- **Der Hero ist ein Bild, kein Video.** Der erste Blick muss sofort da sein und die Headline stützen: eine ruhige Tabelle. Ein autoplayendes Video über der Falz konkurriert mit der Headline, lädt langsamer und der Agentenlauf dauert real 10 bis 30 Sekunden, was sich als Schleife schlecht kürzen lässt. Der Vorgang bekommt stattdessen die erste Vertiefung, wo der Leser schon weiß, worum es geht.
- **Größe folgt Inhalt.** Ein ganzes Fenster braucht Breite, ein Sheet oder ein Kartenpaar nicht. Auf der Seite stehen die Slots bei 1280 px Viewport so: Hero 1140, Belege 768, Zahlungen und Überblick je 554, Steuer 672.
- **Hell, Standardschrift, Standardfenster.** Alle Aufnahmen im hellen Erscheinungsbild, Fenstergröße so, dass das Seitenverhältnis 5:3 ergibt (zum Beispiel 1200 × 720 Punkte). Aufnahme in 2x. Kein Schatten, kein Schreibtischhintergrund: nur das Fenster, eckig beschnitten, die Seite rundet die Ecken selbst. Dunkle Varianten später, wenn überhaupt.
- **Formate.** Bilder als PNG (UI mit Text bleibt scharf), Breite exakt das Doppelte der Slotbreite reicht: Hero 2400 px, Belege 1600 px, Halbbreite 1200 px, Steuer 1400 px. Video als MP4 (H.264, ohne Ton, 30 fps, höchstens 3 MB) plus ein PNG als Poster; kein GIF.

## Demodaten, die alle Bilder brauchen

Erfundener Betrieb, erfundene Gegenparteien, Beträge zwischen 20 und 5.000 Euro. Etwa 15 bis 20 Buchungen über zwei bis drei Monate, damit die Tabelle voll wirkt, aber nicht scrollt. Darin sichtbar:

- Einnahmen (grün) und Ausgaben gemischt, mehrere Kategorien mit unterschiedlichen Symbolen.
- Mindestens je eine Zeile mit Status „Geprüft“, „Zu prüfen“ und „Beleg fehlt“.
- Bezahlt-Spalte gemischt: die meisten bezahlt, zwei offen, davon eine überfällig.
- Eine Reverse-Charge-Rechnung eines ausländischen Anbieters, eine Fremdwährungsrechnung, ein Anlagegut (Laptop) mit Nutzungsdauer.
- Belege als echte PDFs, damit die Vorschau im Inspector etwas zeigt: schlichte, glaubwürdige Rechnungen ohne echte Firmennamen und Logos.
- Ein Kontoauszug als CSV, der zu den Rechnungen passt, mit einer Teilzahlung und einer Bewegung ohne Beleg.

## Die fünf Slots

### 1. Hero: Bild, 1140 px breit

**Zeigt:** Das ganze Fenster auf „Buchungen“. Inspector rechts geöffnet auf einer geprüften Ausgabe mit Belegvorschau (die PDF-Miniatur muss zu sehen sein). Tabelle mit 12 bis 15 Zeilen, Fußzeile mit Einnahmen, Ausgaben, Saldo. Filter auf „Alle“.

**Warum:** Es ist das Versprechen der Headline in einem Bild: eine Tabelle, daneben der Beleg, kein KI-Interface. Der Inspector ist offen, weil die Tabelle allein wie eine Tabellenkalkulation aussieht; die Belegvorschau sagt „Dokumente rein“.

**Aufnahme:** Fenster 1200 × 720 Punkte, Screenshot in 2x, auf das Fenster beschnitten. Keine Auswahl-Hervorhebung außer der Zeile, die der Inspector zeigt.

### 2. Aus Belegen werden Buchungen: Video, 768 px breit

**Zeigt:** Den Vorgang. Drei PDFs werden aus dem Finder auf das Fenster gezogen, der Rahmen erscheint, der Spinner läuft, drei neue Zeilen erscheinen mit Status „Zu prüfen“. Klick auf eine davon, der Inspector öffnet sich mit der Belegvorschau neben Aussteller, Betrag, Steuer und Kategorie. Kurzer Halt, dann Klick auf „Bestätigen“, der Status wechselt auf „Geprüft“. Ende, Schleife.

**Warum:** Das ist der einzige Moment, in dem Bewegung Information ist. Der Leser sieht die drei Schritte Ablegen, Prüfen, Bestätigen als einen Zug.

**Aufnahme:** 15 bis 20 Sekunden fertig geschnitten. Die Wartezeit auf den Agenten hart kürzen: Spinner zwei Sekunden zeigen, dann Schnitt auf das Ergebnis. Der Finder darf am Rand ins Bild ragen, aber nur die drei Dateien, kein Schreibtisch. Cursor sichtbar, ruhige Bewegungen. Letztes Bild zwei Sekunden halten, bevor die Schleife neu startet. Poster: das letzte Bild.

### 3. Zahlungen? Zugeordnet: Bild, 554 px breit

**Zeigt:** Einen Ausschnitt der Tabelle, nicht das ganze Fenster. Sechs bis acht Zeilen mit den Spalten Unternehmen, Datum, Betrag, Bezahlt. Bezahlt-Spalte gemischt: bezahlt, bezahlt, offen, bezahlt, überfällig. Eine Zeile mit Titel aus einem Verwendungszweck (`nur_zahlung`), damit „Zahlung ohne Beleg bleibt sichtbar“ ein Bild hat.

**Warum:** Halbe Breite verträgt kein ganzes Fenster; die Schrift würde unlesbar. Der Ausschnitt zeigt genau die eine Spalte, um die es im Text geht.

**Aufnahme:** Screenshot des Fensters, dann Beschnitt auf den Tabellenbereich mit 5:3-Verhältnis, ohne Sidebar und Toolbar. Wenn der Beschnitt zu eng wirkt, den Inspector-Abschnitt „Zahlungen“ mit einer Teilzahlung als Alternative aufnehmen.

### 4. Wissen, was noch offen ist: Bild, 554 px breit

**Zeigt:** Die Startseite. Begrüßung, Datum, die drei Jahreswerte, darunter die zwei Karten „To Dos“ (Prüfen 3, Belege nachtragen 1, Überfällig 1) und „Fristen“ (UStVA mit gelber oder grüner Ampel, EÜR grün). Keine roten Ampeln; die Seite soll Ruhe ausstrahlen, nicht Alarm.

**Warum:** Der Text beschreibt genau diese Seite. Sie ist kompakt genug für die halbe Breite, wenn die Sidebar wegfällt.

**Aufnahme:** Fenster in Standardgröße 840 × 500, Screenshot, Beschnitt auf den Inhaltsbereich ohne Sidebar, 5:3.

### 5. Deine Zahlen sind bereit: Bild, 672 px breit

**Zeigt:** Das Export-Sheet für die UStVA, Zeitraum drittes Quartal 2026, mit den Kennzahlen und Beträgen, dem Hinweis auf ungeprüfte Buchungen im Zeitraum und dem Link zu Mein ELSTER. Formular vorausgewählt, nichts aufgeklappt.

**Warum:** Ein Sheet ist ein kleines Objekt; in voller Breite wirkt es aufgeblasen. Bei 672 px steht es in natürlicher Größe und die Zahlen bleiben lesbar.

**Aufnahme:** Sheet geöffnet, Screenshot, Beschnitt auf das Sheet mit etwas Fenster als Rand, 5:3 auffüllen. Wenn das Sheet höher als breit ist, den Beschnitt auf 4:3 ändern und mir sagen, dann passe ich das Seitenverhältnis in der Seite an.

## Was nicht aufgenommen wird

- Kein Video für Zahlungen, Überblick oder Export. Wenn das Belege-Video sitzt und noch Luft ist, wäre der Kontoauszug-Import (CSV ablegen, Bezahlt-Spalte füllt sich) der zweite Kandidat, an derselben Stelle wie Bild 3.
- Keine Einstellungen, kein KI-Zugang, kein Schlüsselfeld. Technik steht im Text bei Kosten, nicht in Bildern.
- Keine Fehlerzustände, keine gescheiterten Läufe.

## Ablage

Dateien nach `landing-concepts/daft-assets/` als `hero.png`, `belege.mp4` und `belege.png`, `zahlungen.png`, `start.png`, `export.png`. Ich hänge sie dann in `daft.html` ein und ersetze die Platzhalter.
