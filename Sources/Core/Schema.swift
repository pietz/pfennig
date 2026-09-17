import GRDB

/// The one schema definition of Pfennig. The agent reads the CREATE statements
/// back from `sqlite_master`, so the text below is documentation for a reader
/// as much as it is a definition: the enumerations sit in CHECK constraints and
/// the shape of every JSON column sits in a comment next to it.
public enum Schema {
    public static let sql = """
    CREATE TABLE buchungen (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        richtung TEXT NOT NULL CHECK (richtung IN ('einnahme', 'ausgabe')),
        art TEXT NOT NULL CHECK (art IN ('rechnung', 'beleg', 'gutschrift', 'steuerzahlung', 'nur_zahlung', 'ignoriert', 'sonstiges')),
        datum TEXT NOT NULL,                        -- Belegdatum als JJJJ-MM-TT
        belegnummer TEXT,                           -- optionale Nummer, wie auf dem Beleg angegeben
        faelligkeit TEXT CHECK (
            faelligkeit IS NULL OR (
                faelligkeit GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND date(faelligkeit, '+0 days') IS NOT NULL
                AND date(faelligkeit, '+0 days') = faelligkeit
            )
        ),                                          -- optionales Fälligkeitsdatum als JJJJ-MM-TT
        titel TEXT NOT NULL,
        kategorie TEXT,                             -- Schlüssel aus der EÜR-Kategorienliste im Code
        privatanteil_prozent INTEGER NOT NULL DEFAULT 0,
        nutzungsdauer_jahre INTEGER,                -- leer heißt gewöhnliche Ausgabe, gesetzt macht die Buchung zum Anlagegut
        notizen TEXT,
        gegenpartei_name TEXT,
        gegenpartei_land TEXT,                      -- Länderkürzel, zum Beispiel DE
        gegenpartei_ustid TEXT,
        -- JSON-Liste, mindestens ein Element, Beträge in EUR-Cent:
        -- [{"netto": 10000, "steuersatz": 19, "steuer": 1900}]
        positionen TEXT NOT NULL DEFAULT '[]',
        waehrung TEXT,                              -- nur bei Fremdwährung, leer heißt EUR
        originalbetrag TEXT,                        -- nur bei Fremdwährung, exakte Dezimalzahl in Haupteinheiten
        steuerbehandlung TEXT NOT NULL CHECK (steuerbehandlung IN ('inland', 'reverse_charge', 'kleinunternehmer', 'steuerfrei', 'nicht_steuerbar', 'unklar')),
        -- JSON-Liste, vorzeichenbehaftete Beträge in EUR-Cent (negativ = Erstattung):
        -- [{"datum": "2026-09-14", "betrag": 11900}]
        zahlungen TEXT NOT NULL DEFAULT '[]',
        -- JSON-Liste der ids aus dateien, die Belege zu dieser Buchung sind: [3]
        belege TEXT NOT NULL DEFAULT '[]',
        geprueft_am TEXT,                           -- leer heißt ungeprüft
        erstellt_am TEXT NOT NULL DEFAULT (datetime('now')),
        geaendert_am TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE dateien (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sha256 TEXT NOT NULL UNIQUE,                -- auch der Name im Archiv
        dateiname TEXT NOT NULL,
        endung TEXT NOT NULL,
        groesse INTEGER NOT NULL,                   -- in Bytes
        seiten INTEGER,                             -- nur bei PDF
        importiert_am TEXT NOT NULL
    );

    CREATE TABLE aktivitaeten (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        buchung_id INTEGER NOT NULL,
        zeitpunkt TEXT NOT NULL,
        akteur TEXT NOT NULL CHECK (akteur IN ('nutzer', 'agent')),
        vorher TEXT,                                -- JSON-Objekt der Buchungszeile vor der Änderung, leer bei Neuanlage
        nachher TEXT                                -- JSON-Objekt der Buchungszeile nach der Änderung, leer bei Löschung
    );

    CREATE TABLE anfragen (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        datei_id INTEGER NOT NULL,
        modell TEXT NOT NULL,
        gestartet_am TEXT NOT NULL,
        beendet_am TEXT,
        status TEXT CHECK (status IN ('erfolg', 'fehler')),
        eingabe_tokens INTEGER,
        ausgabe_tokens INTEGER,
        konversation TEXT                           -- JSON des Agentenlaufs ohne Dateibytes: Text, Werkzeugaufrufe, Antworten
    );

    CREATE TABLE einstellungen (
        schluessel TEXT PRIMARY KEY,
        wert TEXT NOT NULL
    );

    CREATE TABLE zeitraeume (
        jahr INTEGER NOT NULL,
        art TEXT NOT NULL CHECK (art IN ('ustva', 'euer')),
        idx INTEGER NOT NULL,                       -- 1-12 Monat, 41-44 Quartal, 0 bei der EÜR
        exportiert_am TEXT NOT NULL,
        PRIMARY KEY (jahr, art, idx)
    );

    -- Wissen der Anwendung, keine Nutzerdaten: die amtliche AfA-Tabelle für
    -- allgemein verwendbare Anlagegüter, bei jedem Start neu eingespielt.
    CREATE TABLE afa_tabelle (
        fundstelle TEXT PRIMARY KEY,
        bezeichnung TEXT NOT NULL,
        nutzungsdauer_jahre INTEGER NOT NULL,
        quelle TEXT NOT NULL
    );
    """

    /// Creates the tables the first time the database is opened. There is
    /// exactly one schema definition and no migrations before the release.
    static func create(_ db: Database) throws {
        guard try db.tableExists("buchungen") == false else { return }
        try db.execute(sql: sql)
    }
}
