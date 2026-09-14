# Produkt-Backlog: vom Beleg zur Steuerabgabe

**Aktualisierung beim Umzug zu Pfennig:** Die anschließend getroffenen Nutzerentscheidungen in der [Workflow-Spezifikation](specs/document-to-tax-workflow.md) ergänzen und korrigieren diese Rechercheplanung: sichere Standardfälle automatisch übernehmen, Steueraufgaben auf Start verlinken. Die Spezifikation wartet noch auf Freigabe; diese Entscheidungen selbst sind bereits getroffen. Alte GitHub-Issues sind [lokal gesichert](legacy-github-issues.md). Übergabestand: [status.md](status.md).

Stand 14.09.2026, Recherche nach `e84acc2`. Prioritäten sind Empfehlungen, keine Zusage für den nächsten Release. GitHub Issues bleiben die technischen Arbeitspakete; diese Übersicht ordnet den Nutzerablauf. Produktscope: deutsche Selbstständige, EÜR, Ist-Versteuerung, Regelbesteuerung und Kleinunternehmer. Begründung, Code-Lücken und Abnahmekriterien stehen in [Recherche zum Nutzerworkflow](research-user-workflow.md).

> Belege ablegen → prüfen und zuordnen → Zahlen nachvollziehen → Steuerdaten vorbereiten → selbst abgeben.

## A. Was bereits funktioniert

| Abschnitt | Vorhanden | Grenze |
|---|---|---|
| Ablage | Lokales SQLite-Archiv und unveränderte Originalbelege; Dateien wieder öffnen | Noch kein geführter Sicherungs-/Wiederherstellungsworkflow |
| Eingang | PDF-/Bildimport, strukturierte KI-Extraktion, mehrere Dateien, Wiederholung fehlgeschlagener Importe | Qualität an vielfältigen echten Belegen noch nicht ausreichend belegt |
| Prüfung | Vorschläge prüfen, bearbeiten, bestätigen oder ablehnen; direkte manuelle Buchungen | Nicht jede steuerliche Ausnahme wird automatisch gelöst |
| Nachvollziehbarkeit | Interne Änderungs-/Herkunftshistorie und Schutz manueller Änderungen; exakte Dateiduplikate erkennen | Keine allgemeine semantische Dublettenerkennung |
| Beleg ergänzen | Fehlenden Beleg an bestehende Buchung hängen | Automatische Zuordnung zu einer Kontobewegung fehlt |
| Zahlungen | Manuelle Zahlungen und Teilzahlungen | Kontoauszüge: Ansatz offen, KI-first |
| Fachliche Basis | Häufige 7%/19%-Fälle, Mischbelege, §19 und typische Reverse-Charge-Dienstleistungen | Keine fertige UStVA-/EÜR-Auswertung, kein vollständiges AfA-System |
| Start | Echte Jahressummen, offene Prüfungen, fehlende Belege, Filter-Verlinkungen | Bruttoübersicht, keine steuerliche Gewinnermittlung; noch keine echten Termine |
| Offline | Bestehende Daten ohne KI/Netz nutzbar, Belege im Finder zugänglich | Kein benutzerfreundlicher Buchungs-/Steuerexport |

## B. Fehlende Bausteine nach Priorität

### Separater Sicherheits-/Qualitätsstrang: bisheriges P0

Der Nutzer übernimmt die privaten Belegqualitätstests separat. Dieser Strang blockiert nicht die Planung oder den nächsten Ausbau von Steuerausgabe und Importen. Die Aufgaben bleiben vor einer Empfehlung für ernsthafte Nutzung relevant; eine ausdrücklich experimentelle Quellcode-Preview ist davon zu unterscheiden.

| Aufgabe | Kleiner, überprüfbarer Abschluss |
|---|---|
| **Echte Belege testen** | Kuratierten privaten Testbestand durch den vollständigen Import-/Prüfablauf laufen lassen; materielle Fehler dokumentieren und beheben |
| **Daten herausbekommen** | CSV-Nachweis mit Beleg- und Zahlungsreferenzen im Berichtsausbau mitliefern; kein vorgelagerter eigener Featureblock |
| **Sichern und wiederherstellen** | Konsistente lokale Archivkopie und verifizierter Wiederherstellungsweg, zunächst ohne Cloud-/Backup-Automatik |
| **Erstinstallation und Updates absichern** | Frisches macOS-Benutzerkonto testen, unterstützte KI-Einstellungen prüfen, klare Grenzen dokumentieren; veröffentlichte Archive bei Updates erhalten |

### P1: Den vollständigen Buchhaltungsablauf schließen

| Funktion | Erster sinnvoller Umfang |
|---|---|
| **UStVA-Vorbereitung zuerst** | Zeitraum → konkrete Ausnahmen → geprüfte Formularwerte mit Einzelbelegen → kopierbare Übertragungshilfe; Teilzahlungen, Vorsteuerzeitpunkt und typische Reverse-Charge-Fälle fachlich schließen |
| **UStVA-XML früh prüfen** | Begrenzter Machbarkeitstest für lokalen Export und manuelles Hochladen; öffentliche Uploadanleitung ist belegt, aktueller vollständiger Formatvertrag und ein erfolgreicher Import noch nicht; keine Herstellerregistrierung |
| **Kontoauszüge** | Ansatz offen, KI-first |
| **Beleg zuerst oder Zahlung zuerst** | Gegenstück am selben Vorgang ergänzen statt doppelt buchen; Teilzahlungen sowie lösbare Zuordnungen; fehlende Belege aus geschäftlichen Kontobewegungen entdecken |
| **EÜR-Vorbereitung anschließend** | Zahlungsgerechte Jahresauswertung nach geprüften Formularpositionen; Umsatzsteuerzahlungen, Privatanteile und Jahreswechsel berücksichtigen; Anlagen und nicht unterstützte Korrekturen separat ausweisen |
| **E-Rechnungen als Importinkrement** | XRechnung UBL/CII, danach eingebettetes ZUGFeRD-XML; strukturierte Fakten lokal lesen und vorhandenen Prüfpfad verwenden; kein eigener Buchhaltungsworkflow |

UStVA und EÜR brauchen eigene fachliche Berechnungen, nicht einfach die Start-Summen oder das erste Zahlungsdatum. Manuell erfasste Zahlungen erlauben einen ersten Report. Die vorhandenen Formular-Mappings sind ausdrücklich ungeprüft und keine freigegebene Abgabegrundlage. Ein aufgabenbezogenes Fenster/Sheet reicht; Start und Buchungen bleiben ruhig. Export ist keine Abgabe, ungelöste relevante Fälle bleiben als Entwurf erkennbar.

### P2: Bedienaufwand reduzieren

| Funktion | Anlass / Grenze |
|---|---|
| Wiederkehrende Anbieterregeln | Wiederholt bestätigte Kategorien/Zuordnungen vorschlagen; kein freies Regelwerk vorsorglich bauen |
| Anstehende Termine auf Start | Nur bekannte Verpflichtungen und zutreffende Termine, keine leeren Kalenderfunktionen |
| Perioden prüfen/festhalten/sperren | Auf nutzbaren Auswertungen aufbauen; Freigabe, Abgabe und Sperre nicht vermischen |

### P3: Bewusst zurückgestellt

- Iteratives Tool Calling für schwierige Zuordnungen: erst wenn ein konkreter Fall den Mehrwert zeigt; keine neue Harness-Abhängigkeit nötig.
- DATEV-Adapter und weitere Übergabeformate: nach einem brauchbaren einfachen Export.
- Vollständige Anlagen-/AfA-Verwaltung: vorerst Anlagekandidaten sichtbar manuell prüfen.
- Direkte ELSTER-Übermittlung: derzeit nicht geplant, da Herstellerregistrierung ausdrücklich nicht gewünscht ist.
- Keine Erweiterung zu Rechnungsstellung, CRM, Bilanzbuchhaltung oder Einkommensteuerberatung.

## C. Output ohne eigenen ELSTER-Übermittlungsdienst

| Weg | Einschätzung |
|---|---|
| Formularnahe UStVA-/EÜR-Übertragungshilfe | **Empfohlener Einstieg.** Pfennig berechnet und erklärt; Nutzer prüft und überträgt in Mein ELSTER |
| Kopierbare Werte, druckbarer Bericht/PDF, CSV | Sinnvoll für Übertragung, eigene Unterlagen oder Steuerberatung; nicht automatisch ein akzeptiertes ELSTER-Importformat |
| UStVA-XML zum manuellen Hochladen | **Früher, begrenzter Machbarkeitstest.** Öffentliche Anleitung enthält Nutzdatenstruktur, Beispiel und Zeichensatz; vollständige Jahresschemata werden in die ERiC-Dokumentation verwiesen. Kein aktueller Pfennig-Import validiert; ohne Registrierung prüfen, sonst Übertragungshilfe beibehalten |
| EÜR-Dateiimport | Auf der geprüften Formularseite kein entsprechender externer Import dokumentiert; nicht versprechen |
| Direkte Übermittlung mit ERiC | Lokale C-Bibliothek möglich, aber Entwicklerregistrierung/Hersteller-ID erforderlich; das ist unabhängig vom persönlichen ELSTER-Zugang |

Ein ausgefülltes PDF ersetzt nicht die reguläre elektronische Abgabe. Eine einfache öffentliche UStVA-/EÜR-REST-API ohne diesen Integrationsaufwand ist hier nicht belegt. Auch eine Drittanbieter-API würde zusätzliche externe Verarbeitung und einen Anbieter statt einer rein lokalen Lösung bedeuten.

Offizielle Quellen:
- [UStVA-Formular mit Hinweis auf externen XML-Upload](https://www.elster.de/eportal/formulare-leistungen/alleformulare/ustvaeru)
- [UStVA: öffentliche XML-Uploadanleitung](https://www.elster.de/eportal/helpGlobal?themaGlobal=ustva_upload)
- [Anlage EÜR: authentifizierte elektronische Übermittlung](https://www.elster.de/eportal/formulare-leistungen/alleformulare/euer)
- [Mein ELSTER: unterstützte CSV-Importformulare](https://www.elster.de/eportal/helpGlobal?themaGlobal=anleitung_zur_importfunktion_eop)
- [Entwicklerregistrierung und ERiC](https://www.elster.de/elsterweb/infoseite/entwickler)

## D. Vorschlag für die nächsten Schritte

1. **Erstes Steuerergebnis:** Einen UStVA-Zeitraum fachlich korrekt und nachvollziehbar bis zur Übertragungshilfe schließen. Einfachen CSV-Nachweis mitliefern. XML-Machbarkeit früh separat prüfen, aber nicht zum Blocker machen.
2. **Weniger Handarbeit:** Beidseitigen Beleg-/Zahlungsabgleich schließen, einschließlich vorhandener manueller Zahlungen und Teilzahlungen. Kontoauszüge: Ansatz offen, KI-first.
3. **Jahresabschluss vorbereiten:** EÜR-Ausgabe auf der gemeinsamen Berichtsbasis ergänzen. Nicht unterstützte Jahresabschlussarbeiten sichtbar halten, keine scheinbar vollständige Erklärung erzeugen.
4. **Strukturierten Eingang ergänzen:** E-Rechnungen als begrenztes Importinkrement, bei passender Arbeitsteilung parallel zu den anderen Schritten.
5. **Danach Komfort:** Regeln, echte Termine und Periodenfreigabe erst auf einem nutzbaren Eingangs-/Ausgangsworkflow aufbauen.

Private Belegqualitätstests laufen beim Nutzer separat. Sicherung/Wiederherstellung und Release-Prüfungen bleiben wichtige eigene Aufgaben, nicht die Antwort auf die aktuelle Frage nach den nächsten Kernfunktionen.

Private Testbelege bleiben außerhalb des Repositories. Eine Übertragung an OpenAI erfolgt nur nach ausdrücklicher Freigabe; auch Antworten und Logs können private Daten enthalten. Öffentliches Regressionstestmaterial muss freigegeben oder sinnvoll anonymisiert sein.

## E. Datenmodell und erste Veröffentlichung

Die Trennung von Geschäftsvorgang, Beleg, Zahlung und Zuordnung passt zu beiden Eingangswegen; es gibt derzeit keinen konkreten Grund für einen Schema-Neuentwurf. Die Breite des vorbereiteten Modells ist aber kein Beleg, dass alle Workflows bereits funktionieren. Stabilität wird mit realen Fällen, Abgleich und wiederherstellbaren Archiven nachgewiesen, nicht mit weiteren Tabellen.

**Open-Source-Preview: ja**, mit ehrlicher Beschreibung als lokale Belegerfassung/Buchhaltung im frühen Stadium. **Vollständiger Accountable-Ersatz: noch nicht**, besonders wegen Abgleich und Steuerausgabe. Auch nach UStVA/EÜR-Vorbereitung bleiben jährliche Umsatzsteuererklärung, vollständige Einkommensteuererklärung und gegebenenfalls ZM eigenständige Aufgaben. Release-Technik und Freigaben bleiben separat in [status.md](status.md) und [releasing.md](releasing.md) geführt; diese Planung autorisiert keine Veröffentlichung, Übermittlung oder privaten Belegtests.
