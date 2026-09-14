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
