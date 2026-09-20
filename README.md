<img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Pfennig" width="128">

# Pfennig

Lokale macOS-Buchhaltung für deutsche Freiberufler und Einzelunternehmer mit EÜR und Ist-Versteuerung, regelbesteuert oder Kleinunternehmer.

Rechnungen und Belege werden als PDF oder Bild auf das Fenster gezogen. Ein KI-Agent liest jede Datei und schreibt die Buchung direkt in die lokale SQLite-Datenbank, innerhalb von Grenzen, die Swift setzt. Der Nutzer prüft und bestätigt in einer Tabelle mit Inspector. Die UStVA wird als XML für den Upload in Mein ELSTER exportiert, die EÜR-Werte als CSV.

## Voraussetzungen

- macOS 15 oder neuer, Apple Silicon
- ein eigener OpenAI-API-Schlüssel (wird im macOS-Schlüsselbund gespeichert)

## Installation

Die signierte und notarisierte App liegt als ZIP bei den GitHub-Releases. Entpacken, nach „Programme“ ziehen, starten. Beim ersten Start in den Einstellungen das Profil ausfüllen und den API-Schlüssel eintragen.

Alle Daten liegen unter `~/Library/Application Support/Pfennig/`: die Datenbank, das Archiv der Originale und die Inbox.

## Entwicklung

```sh
scripts/bootstrap.sh   # XcodeGen, SwiftFormat, Pakete
scripts/test.sh        # Swift-Testing-Suiten
scripts/build.sh       # App-Bundle bauen
scripts/run.sh         # bauen und starten
```

Die Produktgrenzen und Arbeitsregeln stehen in `AGENTS.md`, die Entwicklungshistorie in `docs/status.md`. Releases sind in `docs/releasing.md` beschrieben.

## Lizenz

GNU General Public License, Version 3. Siehe `LICENSE`.

## Optionaler Agenten-Akzeptanztest

`scripts/test-live.sh` prüft mit Luna und niedrigem Denkaufwand eine synthetische
PDF-Rechnung, die Zuordnung einer CSV-Kontobewegung und den erneuten Import beider
Dateien. Der Aufruf verwendet den in der App eingerichteten API-Schlüssel aus dem
Schlüsselbund und verursacht API-Kosten. Er arbeitet ausschließlich mit erzeugten
Testdokumenten und einem temporären Archiv, das danach entfernt wird.

Normale Tests und CI führen diesen Test nicht aus. Der Live-Test bewertet die
resultierenden Buchungen statt einer bestimmten Antwort oder SQL-Abfolge. Ein
Fehlschlag ist zu untersuchen; ein einzelner erfolgreicher Lauf belegt keine
allgemeine Importgenauigkeit. Private Belege werden nie als Testdaten verwendet.
