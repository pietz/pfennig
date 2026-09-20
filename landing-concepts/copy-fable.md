# Landing-Page-Text für Pfennig: Vorschlag (Fable)

Stand der Fakten: `docs/specs/pfennig-neu.md`, `docs/status.md` (0.6.0 vom 2026-09-18), `README.md`. Nur Inhalt, keine Gestaltung.

---

## Teil 1: Begründung

### Zentrale Empfehlung

Positionierung: **Pfennig ist der kürzeste ehrliche Weg vom Beleg zur ELSTER-Datei, für eine Person mit EÜR, auf ihrem eigenen Mac.** Nicht „Buchhaltung einfach gemacht“, sondern der konkrete Ablauf, den die App tatsächlich hat: reinziehen, prüfen, Datei speichern, selbst hochladen. Die Seite soll klingen wie die App aussieht: eine ruhige Tabelle, kein Produkt-Launch.

Empfohlene Headline: **„Belege reinziehen. Buchung prüfen. UStVA hochladen.“**

### Warum diese Positionierung

1. **Der Ablauf ist das Alleinstellungsmerkmal, nicht die KI.** Lexoffice, sevDesk und WISO haben längst Belegerkennung. Was Pfennig anders macht: ein Fenster, eine Tabelle, keine Rechnungsstellung, kein Konto, kein Abo bei uns, eine Datei am Ende. Die Headline soll deshalb den Ablauf sagen, nicht die Technik. Die KI kommt im zweiten Satz als Mittel vor, nicht als Versprechen.

2. **Die Zielgruppe weiß, was UStVA und EÜR sind.** Wir müssen nichts erklären und dürfen die Begriffe in die Headline nehmen. Wer sie nicht kennt, ist nicht Zielgruppe. Das macht die Seite sofort spezifisch und filtert von selbst.

3. **Ehrlichkeit als Stil, nicht als Fußnote.** Die drei heiklen Wahrheiten (Dokumente gehen an OpenAI, kein direktes Absenden, EÜR-Werte werden abgetippt) stehen mitten in der Seite in normalem Ton, jeweils in einem Satz. Wer sie in Disclaimer-Sprache versteckt, wirkt unehrlich; wer sie zum Thema macht, wirkt defensiv. Beides falsch. Sie sind einfach Teil der Beschreibung, wie die App funktioniert.

4. **„Lokal“ darf nicht überverkauft werden.** Die Buchhaltung, das Archiv und die Datenbank liegen lokal. Die Belege selbst verlassen aber den Mac zur Verarbeitung. Deshalb steht nirgends „alles bleibt auf deinem Mac“ oder „Privacy first“. Stattdessen der genaue Satz: Was wo liegt und was wohin geht.

5. **Der Stand ist früh und das gehört auf die Seite.** Version 0.6, ein Nutzer, Export nur für 2026 verifiziert. Ein kurzer, sachlicher Absatz „Stand“ ist glaubwürdiger als eine Seite, die fertig tut. Er ersetzt Testimonials, die es nicht gibt.

### Was bewusst nicht auf der Seite steht

- Keine Preise, kein „kostenlos für immer“, keine Aussage über künftige Kosten. Wahr und ausreichend: Open Source unter GPLv3, Download bei GitHub, OpenAI-Nutzung zahlt der Nutzer direkt an OpenAI. Keine Beträge.
- Keine Zahlen zu Genauigkeit, Zeitersparnis oder Nutzern.
- Keine Screenshots-Beschreibung von Funktionen, die nicht gebaut sind (Storno, Wertabgaben, Kfz, Bankanbindung).
- Kein „KI-gestützt“, „intelligent“, „automatisch“ im Sinn von „du musst nichts mehr tun“. Der Nutzer prüft jede Buchung; das ist Kern der App und steht so da.
- Kein Steuerberater-Vergleich, keine Steuerberatung, keine Rechtsbelehrung. Ein Satz zur Eigenverantwortung genügt.

### Reihenfolge und Zweck der Abschnitte

1. **Hero:** Headline, drei Sätze, ein Download-Link mit Voraussetzungen. Wer nach 15 Sekunden weiß, ob die App für ihn ist, hat alles.
2. **So läuft es:** drei Schritte mit konkreten Details (Dateiformate, Prüfen im Inspector, was der Export erzeugt). Hier steht der ELSTER-Satz und der EÜR-Abtipp-Satz.
3. **Was die Tabelle kann:** wenige spezifische Punkte, die zeigen, dass es kein Spielzeug ist (Reverse Charge, Kleinunternehmer, Fremdwährung, Anlagegüter, Kontoauszüge, Aktivitätenlog, Fristen). Spezifität statt Adjektive.
4. **Wo deine Daten liegen:** ein Absatz, drei Aussagen. Lokal, OpenAI, sonst nichts.
5. **Was Pfennig nicht macht:** fünf Zeilen als Abgrenzung, nicht als Warnung. Spart beiden Seiten Zeit.
6. **Stand:** Version, wer es baut, was verifiziert ist.
7. **Schluss:** derselbe Download-Link, dazu GitHub und Änderungen.

### CTA-Ansatz

Ein einziger Handlungsaufruf: **„Laden bei GitHub“** (Link auf die Releases). Kein „Kostenlos starten“, kein „Jetzt testen“, keine E-Mail-Liste, kein Warteliste-Versprechen. Direkt neben dem Link die drei Voraussetzungen, damit niemand umsonst klickt: macOS 15 auf Apple Silicon, eigener OpenAI-API-Schlüssel, Version 0.6. Der zweite Link „Quellcode“ führt aufs Repository. Am Seitenende wiederholt sich der Download-Link ohne neue Argumente.

---

## Teil 2: Headline-Alternativen

**A (empfohlen): „Belege reinziehen. Buchung prüfen. UStVA hochladen.“**
Drei Verben, der ganze Ablauf, kein Adjektiv. Sagt implizit „du lädst selbst hoch“ und ist damit schon ehrlich. Klingt nach Werkzeug, nicht nach Dienstleistung.

**B: „Buchhaltung ohne Buchhaltungssoftware.“**
Abgrenzung von Lexoffice und Co. in vier Wörtern. Stark bei Leuten, die von großen Suiten genervt sind. Schwächer, weil sie nicht sagt, was Pfennig stattdessen ist, und weil sie leicht als Wortspiel abgetan wird. Gut als Zwischentitel über dem Abschnitt „Was Pfennig nicht macht“.

**C: „Eine Tabelle für deine EÜR. Die Belege füllt sie selbst aus.“**
Kommt der Idee „ruhige Tabelle, dahinter ein Agent“ am nächsten. Nachteil: „füllt selbst aus“ überzeichnet die Automatik, während die App ausdrücklich auf Prüfen und Bestätigen baut. Braucht sofort den Satz „du prüfst“, sonst schief.

Empfehlung: A als Headline, B als Zwischentitel, C verwerfen.

---

## Teil 3: Seitentext (Deutsch, einsatzfertig)

### Hero

**Belege reinziehen. Buchung prüfen. UStVA hochladen.**

Pfennig ist eine kleine macOS-App für Freiberufler mit EÜR und Ist-Versteuerung. Du ziehst Rechnungen, Belege und Kontoauszüge auf das Fenster. Ein KI-Modell liest jede Datei und trägt die Buchung in deine Tabelle ein, du prüfst und bestätigst. Am Ende speichert Pfennig die UStVA als XML für Mein ELSTER und die EÜR-Werte als CSV.

[Laden bei GitHub]  [Quellcode]

Version 0.6. macOS 15 auf Apple Silicon. Braucht einen eigenen OpenAI-API-Schlüssel. Open Source unter GPLv3.

### So läuft es

**1. Ablegen**
Du ziehst eine oder mehrere Dateien auf das Fenster: PDF, Bild, E-Rechnung als XML, Kontoauszug als CSV. Pfennig speichert das Original im Archiv und übergibt die Datei dem Modell. Eine Datei, die schon da war, wird erkannt und nicht erneut verarbeitet.

**2. Prüfen**
Jede neue Buchung steht sofort in der Tabelle, markiert als „Zu prüfen“. Im Inspector siehst du den Beleg neben den Feldern: Gegenpartei, Netto, Steuersatz, Kategorie, Zahlungen. Stimmt alles, bestätigst du. Stimmt etwas nicht, änderst du es. Nichts gilt als geprüft, was du nicht selbst bestätigt hast.

**3. Exportieren**
Für die UStVA speichert Pfennig eine XML-Datei, die Mein ELSTER unter „XML-Daten hochladen“ annimmt. Du lädst sie hoch, siehst das vorausgefüllte Formular und sendest selbst ab. Für die EÜR speichert Pfennig eine CSV mit Formularzeile und Betrag; die Werte überträgst du in die Anlage EÜR, einen Upload dafür gibt es bei ELSTER nicht.

### Was die Tabelle kann

- Rechnungen, Belege, Gutschriften und Kontoauszüge. Zahlungen aus dem Auszug landen an der passenden Buchung, private Bewegungen werden ausgeblendet.
- Reverse Charge, Kleinunternehmer, steuerfreie und nicht steuerbare Umsätze mit den richtigen Kennzahlen.
- Fremdwährungsbelege mit Umrechnung zum Referenzkurs des Belegtags. Alle Summen in Euro.
- Anlagegüter über 800 Euro mit linearer AfA nach der amtlichen AfA-Tabelle, samt Anlageverzeichnis im EÜR-Export.
- Privatanteil pro Buchung, Teilzahlungen, Erstattungen, Fälligkeiten mit Überfällig-Filter.
- Eine Startseite mit dem, was offen ist: zu prüfen, Beleg fehlt, überfällig, nächste Frist für UStVA und EÜR.
- Ein Aktivitätenlog, das jede Änderung zeigt, egal ob du sie gemacht hast oder das Modell.

### Wo deine Daten liegen

Datenbank, Belegarchiv und Buchhaltung liegen als Dateien in deinem Benutzerordner. Es gibt kein Konto, keinen Server von uns und keinen Sync.

Zum Lesen geht jede abgelegte Datei an OpenAI, über deinen eigenen API-Schlüssel, der im macOS-Schlüsselbund liegt. Was das kostet, rechnest du direkt mit OpenAI ab; Pfennig zeigt dir pro Datei die verbrauchten Token. Für Fremdwährungen fragt Pfennig außerdem einen öffentlichen Kursdienst, nur mit Währung und Datum, ohne Beträge.

Wenn du deine Belege nicht an OpenAI geben willst, ist Pfennig nichts für dich. Das sagen wir lieber hier als später.

### Was Pfennig nicht macht

Keine Rechnungsstellung. Keine Bankanbindung. Keine Übermittlung an ELSTER aus der App. Keine Bilanz, kein Lohn, keine Mandanten. Kein Chat mit dem Modell.

Pfennig bereitet deine Zahlen vor. Prüfen, hochladen und verantworten tust du.

### Stand

Pfennig wird von einem Freiberufler für die eigene Buchhaltung gebaut und ist noch früh: Version 0.6, ein Nutzer. UStVA und EÜR sind für das Steuerjahr 2026 gegen die amtlichen Formulare geprüft; das UStVA-XML wurde mit einem Testupload in Mein ELSTER bestätigt. Für andere Jahre exportiert die App bewusst nichts. Der Quellcode, die Spezifikation und der laufende Stand stehen offen auf GitHub.

### Schluss

**Eine Tabelle, ein Fenster, eine Datei für ELSTER.**

[Laden bei GitHub]  [Änderungen]  [Quellcode]

macOS 15 auf Apple Silicon. Eigener OpenAI-API-Schlüssel. GPLv3.

---

## Teil 4: Faktenprüfung der Aussagen

Jede Aussage im Seitentext und ihre Quelle, damit die Seite bei Änderungen der App nachgezogen werden kann.

| Aussage | Quelle |
|---|---|
| macOS 15, Apple Silicon, eigener OpenAI-Schlüssel im Schlüsselbund | README, Voraussetzungen |
| GPLv3, Download bei GitHub Releases, signiert und notarisiert | README, LICENSE, Spec 6 |
| Version 0.6, ein Nutzer | status.md (Release 0.6.0), CLAUDE.md Pre-1.0-Regel |
| PDF, PNG, JPEG, WebP, XML, CSV, TXT, JSON, HTML | Spec, Ergänzung Dateiformate |
| Dublettenerkennung über Hash | Spec 4, Ergänzung Dateien |
| Jede Agentenbuchung ungeprüft, Bestätigen im Inspector | Spec 4, „Prüfen statt Automatisierungsstufe“ |
| UStVA-XML für „XML-Daten hochladen“, Testupload 2026-09-14 | Spec 5 |
| EÜR als CSV, kein Upload bei ELSTER, abtippen | Spec 5, status.md (Formatrecherche) |
| Kontoauszüge, `nur_zahlung`, `ignoriert` ausgeblendet | Spec 2 und Ergänzung Dateien |
| Reverse Charge, Kleinunternehmer, steuerfrei, nicht steuerbar | Spec 2 `steuerbehandlung`, Spec 5 |
| Fremdwährung, Frankfurter-Referenzkurs, nur Währung und Datum übertragen | Spec, Ergänzung Fremdwährung, Spec 4 `umrechnen` |
| Anlagegüter über 800 Euro, lineare AfA, amtliche Tabelle, AVEÜR-Block | Spec, Ergänzung Anlagevermögen |
| Privatanteil, Teilzahlungen, Erstattungen, Fälligkeit, Überfällig | Spec 2 und 3 |
| Startseite mit To-Dos und Fristen | Spec 3, Startseite |
| Aktivitätenlog zeigt jede Änderung von Nutzer und Agent | Spec 2 `aktivitaeten` |
| Token pro Datei sichtbar, Kosten beim Nutzer | Spec 2 `anfragen`, Spec 4 (Modellwahl, Priority Processing) |
| Export nur Steuerjahr 2026 | status.md, Exportjahr-Schutz |
| Nicht enthalten: Rechnungsstellung, Bank, Übermittlung, Bilanz, Lohn, Mandanten, Chat | Spec 1 und 7 |

Nicht behauptet, weil nicht belegt oder nicht gebaut: Erkennungsqualität, Zeitersparnis, Nutzerzahlen, Preise, künftige Funktionen, „alle Daten bleiben lokal“.
