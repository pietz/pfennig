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
swift scripts/make-icon.swift       # Release-Icon neu erzeugen
swift scripts/make-icon.swift --dev # Debug-Icon neu erzeugen
```

Debug-Builds heißen „Pfennig Dev“ (`com.pietz.pfennig.dev`) und liegen unter `build/Build/Products/Debug/Pfennig Dev.app`. Ihre Datenbank, Originale und Inbox liegen getrennt in `~/Library/Application Support/Pfennig-Dev/`. Release-Builds behalten Name, Kennung und Datenordner der installierten App. Es gibt keinen Umschalter; die Build-Konfiguration entscheidet. Debug-Builds haben keine Sparkle-Updates. Bestehende Daten werden weder kopiert noch zurückgesetzt; der erste Entwicklungsstart beginnt mit einem leeren Archiv.

Das Profil liegt in der jeweiligen Datenbank, Darstellung und Fensterzustand gehören zur jeweiligen App-Kennung. Der OpenAI-Schlüssel bleibt im bestehenden gemeinsamen Schlüsselbund-Eintrag: Ändern oder Löschen in einer App betrifft auch die andere. Die neue App-Kennung kann eine einmalige macOS-Zugriffsbestätigung erfordern.

Die Arbeitsregeln stehen in `AGENTS.md`, der aktuelle Stand in `docs/status.md` und die nächsten sowie geparkten Themen in `docs/backlog.md` und den GitHub-Issues. Releases sind in `docs/releasing.md` beschrieben.

## Lizenz

GNU General Public License, Version 3. Siehe `LICENSE`.
