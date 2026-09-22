-- One-time manual correction for the owner's 0.8.0 archives, outside the app.
-- Quit Pfennig and back up the database and originals before running this file.
.bail on
BEGIN IMMEDIATE;
CREATE TEMP TABLE pfennig_09_check (ok INTEGER NOT NULL CHECK (ok = 1));
INSERT INTO pfennig_09_check
SELECT group_concat(name, ',') = 'id,richtung,art,datum,belegnummer,faelligkeit,titel,kategorie,privatanteil_prozent,nutzungsdauer_jahre,notizen,gegenpartei_name,gegenpartei_land,gegenpartei_ustid,positionen,waehrung,originalbetrag,steuerbehandlung,zahlungen,belege,geprueft_am,erstellt_am,geaendert_am' FROM pragma_table_info('buchungen');
INSERT INTO pfennig_09_check
SELECT instr(sql, 'steuerbehandlung TEXT NOT NULL CHECK') > 0
    AND instr(sql, '''unklar''') > 0
FROM sqlite_schema WHERE type = 'table' AND name = 'buchungen';
-- This worksheet is for the shipped schema, without custom indexes/triggers.
INSERT INTO pfennig_09_check
SELECT count(*) = 0 FROM sqlite_schema
WHERE tbl_name = 'buchungen' AND type IN ('index', 'trigger');
CREATE TEMP TABLE pfennig_09_sequence AS SELECT seq FROM sqlite_sequence WHERE name = 'buchungen';

CREATE TABLE buchungen_09 (
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
    -- bei reverse_charge und innergemeinschaftlicher_erwerb: geschuldeter Satz (19 oder 7) in steuersatz, steuer 0
    positionen TEXT NOT NULL DEFAULT '[]',
    waehrung TEXT,                              -- nur bei Fremdwährung, leer heißt EUR
    originalbetrag TEXT,                        -- nur bei Fremdwährung, exakte Dezimalzahl in Haupteinheiten
    -- reverse_charge: grenzüberschreitende Dienstleistungen; innergemeinschaftlicher_erwerb: in Deutschland steuerpflichtiger Warenbezug aus einem anderen EU-Staat
    steuerbehandlung TEXT CHECK (steuerbehandlung IN ('inland', 'reverse_charge', 'innergemeinschaftlicher_erwerb', 'kleinunternehmer', 'steuerfrei', 'nicht_steuerbar')),
    -- JSON-Liste, vorzeichenbehaftete Beträge in EUR-Cent (negativ = Erstattung):
    -- [{"datum": "2026-09-14", "betrag": 11900}]
    zahlungen TEXT NOT NULL DEFAULT '[]',
    -- JSON-Liste der ids aus dateien, die Belege zu dieser Buchung sind: [3]
    belege TEXT NOT NULL DEFAULT '[]',
    geprueft_am TEXT,                           -- leer heißt ungeprüft
    erstellt_am TEXT NOT NULL DEFAULT (datetime('now')),
    geaendert_am TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT INTO buchungen_09 (id, richtung, art, datum, belegnummer, faelligkeit, titel, kategorie, privatanteil_prozent, nutzungsdauer_jahre, notizen, gegenpartei_name, gegenpartei_land, gegenpartei_ustid, positionen, waehrung, originalbetrag, steuerbehandlung, zahlungen, belege, geprueft_am, erstellt_am, geaendert_am)
SELECT id, richtung, art, datum, belegnummer, faelligkeit, titel, kategorie, privatanteil_prozent, nutzungsdauer_jahre, notizen, gegenpartei_name, gegenpartei_land, gegenpartei_ustid, positionen, waehrung, originalbetrag, NULLIF(steuerbehandlung, 'unklar'), zahlungen, belege, geprueft_am, erstellt_am, geaendert_am
FROM buchungen;
INSERT INTO pfennig_09_check
SELECT (SELECT count(*) FROM buchungen) = (SELECT count(*) FROM buchungen_09);
DROP TABLE buchungen;
ALTER TABLE buchungen_09 RENAME TO buchungen;
UPDATE sqlite_sequence SET seq = max(seq, coalesce((SELECT seq FROM pfennig_09_sequence), 0))
WHERE name = 'buchungen';

-- Normalize only the enum field in saved snapshots; retain notes, timestamps,
-- IDs, amounts and the original agent-request transcripts unchanged.
UPDATE aktivitaeten SET vorher = json_set(vorher, '$.steuerbehandlung', NULL)
WHERE json_extract(vorher, '$.steuerbehandlung') = 'unklar';
UPDATE aktivitaeten SET nachher = json_set(nachher, '$.steuerbehandlung', NULL)
WHERE json_extract(nachher, '$.steuerbehandlung') = 'unklar';
INSERT INTO pfennig_09_check SELECT integrity_check = 'ok' FROM pragma_integrity_check;
COMMIT;
PRAGMA integrity_check;
