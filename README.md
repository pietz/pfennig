<img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Pfennig" width="128">

# Pfennig

Lokale macOS-Buchhaltung für deutsche Freiberufler und Einzelunternehmer mit EÜR und Ist-Versteuerung, regelbesteuert oder Kleinunternehmer.

Rechnungen und Belege werden als PDF oder Bild auf das Fenster gezogen. Ein KI-Agent liest jede Datei und schreibt die Buchung direkt in die lokale SQLite-Datenbank, innerhalb von Grenzen, die Swift setzt. Der Nutzer prüft und bestätigt in einer Tabelle mit Inspector. Die UStVA wird als XML für den Upload in Mein ELSTER exportiert, die EÜR-Werte als CSV.

## Voraussetzungen

- macOS 15 oder neuer, Apple Silicon
- ein eigener OpenAI- oder OpenRouter-API-Schlüssel (getrennt im macOS-Schlüsselbund gespeichert)

## Installation

Die signierte und notarisierte App liegt als ZIP bei den GitHub-Releases. Entpacken, nach „Programme“ ziehen, starten. Beim ersten Start in den Einstellungen das Profil ausfüllen, unter „KI-Zugang“ den Anbieter auswählen und dessen API-Schlüssel eintragen. Modell-IDs lassen sich frei eingeben oder aus Vorschlägen übernehmen. Das gewählte Modell muss Werkzeuge und die jeweiligen Dateiformate unterstützen; eigene IDs sind nicht qualitätsgeprüft. Die Auswahl gilt für neue Gespräche und Importe; bestehende Gespräche behalten ihren Anbieter und ihr Modell.

Alle Daten liegen unter `~/Library/Application Support/Pfennig/`: die Datenbank, das Archiv der Originale und die Inbox.

## Entwicklung

```sh
scripts/bootstrap.sh   # XcodeGen, SwiftFormat, Pakete
scripts/test.sh        # Swift-Testing-Suiten
scripts/build.sh       # App-Bundle bauen
scripts/run.sh         # bauen und starten
swift scripts/make-icon.swift       # Release-Icon neu erzeugen
swift scripts/make-icon.swift --dev # Debug-Icon neu erzeugen
```

Debug-Builds heißen „Pfennig Dev“ (`com.pietz.pfennig.dev`) und liegen unter `build/Build/Products/Debug/Pfennig Dev.app`. Ihre Datenbank, Originale und Inbox liegen getrennt in `~/Library/Application Support/Pfennig-Dev/`. Die installierte App unter `/Applications/Pfennig.app` bleibt beim letzten offiziellen Release und verwendet `~/Library/Application Support/Pfennig/`. Es gibt keinen Umschalter; die Build-Konfiguration entscheidet. Debug-Builds haben keine Sparkle-Updates. Bestehende Daten werden weder kopiert noch zurückgesetzt; der erste Entwicklungsstart beginnt mit einem leeren Archiv. Wenn ein neuer Build das Schema ändert, wird das jeweilige Archiv nach Sicherung und bei beendeter App separat anhand von `docs/maintenance/` korrigiert. Die App migriert es nicht automatisch.

Das Profil liegt in der jeweiligen Datenbank, Darstellung und Fensterzustand gehören zur jeweiligen App-Kennung. Die Schlüssel sind je Anbieter getrennt, werden aber zwischen Entwicklungs- und Release-App geteilt: Ändern oder Löschen in einer App betrifft auch die andere. Der bestehende OpenAI-Eintrag bleibt erhalten. Die neue App-Kennung kann eine einmalige macOS-Zugriffsbestätigung erfordern.

Die Arbeitsregeln stehen in `AGENTS.md`, der aktuelle Stand in `docs/status.md` und die nächsten sowie geparkten Themen in `docs/backlog.md` und den GitHub-Issues. Releases sind in `docs/releasing.md` beschrieben.

## Lizenz

GNU General Public License, Version 3. Siehe `LICENSE`.

## Optionaler Agenten-Akzeptanztest

`scripts/test-live.sh` prüft mit Luna und niedrigem Denkaufwand eine synthetische
PDF-Rechnung samt erneutem Import sowie die Ablehnung eines CSV-Kontoauszugs
ohne Buchungsänderung. Der OpenAI-Live-Test verwendet den OpenAI-API-Schlüssel aus dem
Schlüsselbund und verursacht API-Kosten. Er arbeitet ausschließlich mit erzeugten
Testdokumenten und einem temporären Archiv, das danach entfernt wird.

Normale Tests und CI führen diesen Test nicht aus. Der Live-Test bewertet die
resultierenden Buchungen statt einer bestimmten Antwort oder SQL-Abfolge. Ein
Fehlschlag ist zu untersuchen; ein einzelner erfolgreicher Lauf belegt keine
allgemeine Importgenauigkeit. Private Belege werden nie als Testdaten verwendet.
