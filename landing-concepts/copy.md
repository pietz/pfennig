# Landingpage-Text Pfennig

Arbeitsstand 2026-09-21. Reiner Inhalt, keine Gestaltung. Struktur wie am 2026-09-21 mit dem Eigentümer abgestimmt. Grundlage: `docs/specs/pfennig-neu.md`, `docs/status.md` (0.6.0), bestehender Entwurf `daft.html`.

Mit **[?]** markierte Stellen brauchen eine Entscheidung oder Prüfung des Eigentümers.

---

## 1. Hero

Badge: Für deine Selbstständigkeit

# Buchhaltung ohne Buchhaltung.

Du hast dich nicht selbstständig gemacht, um Belege abzutippen.
Pfennig übernimmt die Erfassung. Du behältst den Überblick.

[Kostenlos für Mac laden]

macOS 15 oder neuer · Apple Silicon

Screenshot: die Buchungstabelle mit geöffnetem Inspector.

---

## 2. Drei Karten

**Ablegen statt abtippen.**
Zieh Rechnungen, Belege und Kontoauszüge auf Pfennig. Die App erfasst deine Buchungen und ordnet Zahlungen zu.

**Die Steuer ist vorbereitet.**
Pfennig berechnet deine UStVA und EÜR. Du übernimmst die Angaben in Mein ELSTER und sendest selbst ab.

**Du behältst die Kontrolle.**
Jede erfasste Buchung wartet auf deine Bestätigung. Du siehst das Original daneben und korrigierst, was nicht stimmt.

---

## 3. Belege werden Buchungen

## Aus Belegen werden Buchungen.

Zieh die Rechnung auf das Fenster. Pfennig liest Aussteller, Betrag, Steuer und Kategorie und trägt die Buchung ein. Den Beleg siehst du direkt daneben und prüfst die Angaben am Original.

Das funktioniert auch bei den Fällen, die sonst Arbeit machen: Reverse Charge aus dem Ausland, Rechnungen in Fremdwährung, Belege mit gemischten Steuersätzen, E-Rechnungen als XML.

Screenshot: eine Buchung mit Originalbeleg im Inspector.

---

## 4. Zahlungen

## Zahlungen? Zugeordnet.

Zieh deinen Kontoauszug auf Pfennig. Die App ordnet die Zahlungen deinen Rechnungen zu, auch Teilzahlungen und Erstattungen. Zahlungen ohne passenden Beleg bleiben sichtbar, damit du ihn nachreichen kannst.

Dein Bankkonto musst du dafür nicht verbinden. Du lädst den Auszug bei deiner Bank herunter und legst ihn ab.

Screenshot: Tabelle mit bezahlten Rechnungen und einer offenen.

---

## 5. Überblick

## Wissen, was noch offen ist.

Beim Öffnen siehst du, wo du stehst: was reingekommen ist, was rausgegangen ist und was bleibt. Darunter stehen die Buchungen, die noch geprüft werden wollen, fehlende Belege und überfällige Rechnungen. Ein Klick führt zur passenden Liste.

Die nächsten Fristen für UStVA und EÜR stehen gleich daneben.

Screenshot: Startseite mit Jahreswerten, To-Dos und Fristen.

---

## 6. Steuer

## Deine Zahlen sind bereit.

Pfennig rechnet deine Buchungen nach Zahlungsdatum zusammen, so wie es die Ist-Versteuerung verlangt. Zum Stichtag exportierst du die UStVA als Datei für Mein ELSTER oder die EÜR-Werte für das Jahr, mit AfA und Anlageverzeichnis, wenn du Anlagegüter hast.

Vor dem Export siehst du, ob noch unbestätigte Buchungen im Zeitraum liegen. Danach lädst du die Datei hoch, prüfst das Formular und sendest selbst ab.

Steuerexporte sind derzeit für 2026 verfügbar.

Screenshot: Exportfenster mit Zeitraum und Kennzahlen.

---

## 7. Daten und Kontrolle (neu)

## Deine Buchhaltung bleibt bei dir.

Datenbank und Belegarchiv liegen auf deinem Mac, in einem Ordner, den du jederzeit kopieren kannst. Es gibt kein Konto, keine Cloud und keine Server von uns.

Pfennig nutzt OpenAI, um die Angaben aus deinen Belegen und Rechnungen zu extrahieren. Deine Datenbank bleibt lokal auf deinem Mac.

Jede Buchung bestätigst du selbst. Bis dahin ist sie als ungeprüft markiert. Ans Finanzamt geht nichts, was du nicht selbst abgeschickt hast.

---

## 8. Für wen (als Tabelle)

## Passt Pfennig zu dir?

Pfennig ist für Selbstständige in Deutschland, die ihren Gewinn mit der Einnahmenüberschussrechnung ermitteln: Freiberufler, Einzelunternehmer und kleine Betriebe ohne Bilanzpflicht. Was dazugehört und was nicht:

| Das kann Pfennig | Das ist nicht dabei |
| --- | --- |
| Einnahmenüberschussrechnung (EÜR) | Bilanz und GuV |
| Ist-Versteuerung, regelbesteuert oder Kleinunternehmer | Soll-Versteuerung |
| Rechnungen, Belege, Gutschriften, Kontoauszüge | Bankanbindung |
| Reverse Charge, Fremdwährung, Anlagegüter mit AfA | Rechnungsstellung |
| UStVA als Datei für Mein ELSTER, EÜR-Werte fürs Formular | Übermittlung ans Finanzamt |
| Eine Person, ein Betrieb, ein Mac | Mehrere Mandanten, Lohnabrechnung, Windows |

**[? Zeilenauswahl und Reihenfolge; „kleine Betriebe ohne Bilanzpflicht“ als Formulierung für gewerbliche Einzelunternehmer]**

---

## 9. Kosten (als Pricing-Sektion)

## Was Pfennig kostet.

Pfennig kostet nichts und braucht kein Konto. Nur das Lesen der Belege läuft über ein externes LLM, und dafür gibt es zwei Wege: Du nutzt dein eigenes OpenAI-Konto, oder du machst es dir einfacher über uns. Der Funktionsumfang ist in beiden Fällen gleich.

**Pfennig Abo** · 10 € im Monat (ab Version 1.0)
- Kein Schlüssel, keine Einrichtung
- Monatlich kündbar

**Eigener Schlüssel** · Mit deinem OpenAI-Konto · Nach Nutzung, abgerechnet von OpenAI
- Du richtest ein OpenAI-Konto mit API-Zugang ein
- Pfennig verlangt nichts

---

## 10. FAQ

## Noch ein paar Fragen?

**Wie richte ich Pfennig ein?**
1. Lade Pfennig und zieh die App in deinen Programme-Ordner.
2. Fülle dein Steuerprofil aus und hinterlege deinen OpenAI-API-Schlüssel in den Einstellungen.
3. Zieh den ersten Beleg auf das Fenster und prüfe die erfasste Buchung.

Den API-Schlüssel erstellst du bei OpenAI. Dafür brauchst du ein OpenAI-Konto mit eingerichteter API-Abrechnung. Ein ChatGPT-Abo deckt diese Nutzung nicht ab.

**Wie kommen meine Zahlen zu ELSTER?**
Für die UStVA lädst du die von Pfennig erzeugte Datei in Mein ELSTER hoch, dort unter „XML-Daten hochladen“. Die EÜR-Werte überträgst du von Hand in das Formular; dafür gibt es bei ELSTER keinen Upload. Du prüfst die Angaben und sendest selbst ab.

**Welche Dateien kann ich ablegen?**
Rechnungen und Belege als PDF oder Bild, E-Rechnungen als XML, Kontoauszüge als PDF oder CSV. Auch ein Foto vom Kassenbon reicht.

**Was ist, wenn etwas falsch erkannt wird?**
Du siehst jede Buchung neben dem Original und korrigierst sie direkt. Bestätige erst, wenn die Angaben stimmen, und prüfe deine Steuerzahlen vor der Abgabe. Ungeprüfte Buchungen fließen in die Berechnung ein; Pfennig weist dich vor dem Export darauf hin.

**Kann ich Pfennig ohne OpenAI nutzen?**
Buchungen kannst du auch von Hand anlegen. Die Erkennung von Belegen und Kontoauszügen braucht den Schlüssel.

---

## 11. Schluss

## Fang mit einem Beleg an.

Lade Pfennig, richte deinen Zugang ein und schau dir an, wie aus deinem ersten Beleg eine Buchung wird.

[Kostenlos für Mac laden]

macOS 15 oder neuer · Apple Silicon · Eigener OpenAI-API-Schlüssel

---

## Weggefallen gegenüber `daft.html`

- FAQ „Was kostet die Verarbeitung?“: beantwortet Sektion 9.
- Satz zum Aktivitätslog in Sektion 7: zu technisch, und die App zeigt das Log noch nicht an.
- Zweiter Absatz in „Für wen“ (lokal, OpenAI, Schlüssel): aufgeteilt auf Sektion 7 und 9.
- Fußnote „OpenAI-Nutzung wird separat abgerechnet“ am Schluss-CTA: steht in Sektion 9.
