-- One-time manual correction for the owner's 0.9.0 archives, outside the app.
-- Quit Pfennig and back up the database and originals before running this file.
.bail on
BEGIN IMMEDIATE;
CREATE TEMP TABLE pfennig_010_check (ok INTEGER NOT NULL CHECK (ok = 1));
INSERT INTO pfennig_010_check
SELECT group_concat(name, ',') = 'id,datei_id,modell,gestartet_am,beendet_am,status,eingabe_tokens,ausgabe_tokens,konversation' FROM pragma_table_info('anfragen');
INSERT INTO pfennig_010_check
SELECT count(*) = 0 FROM sqlite_schema WHERE name IN ('gespraeche', 'anfragen_alt');
-- This worksheet is for the shipped schema, without custom indexes/triggers.
INSERT INTO pfennig_010_check
SELECT count(*) = 0 FROM sqlite_schema
WHERE tbl_name = 'anfragen' AND type IN ('index', 'trigger');
CREATE TEMP TABLE pfennig_010_sequence AS SELECT seq FROM sqlite_sequence WHERE name = 'anfragen';
CREATE TEMP TABLE pfennig_010_count AS SELECT count(*) AS n FROM anfragen;

ALTER TABLE anfragen RENAME TO anfragen_alt;
CREATE TABLE anfragen (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    datei_id INTEGER,                           -- Import einer Datei
    gespraech_id INTEGER,                       -- oder eine Runde eines Gesprächs
    modell TEXT NOT NULL,
    gestartet_am TEXT NOT NULL,
    beendet_am TEXT,
    status TEXT CHECK (status IN ('erfolg', 'fehler')),
    eingabe_tokens INTEGER,
    ausgabe_tokens INTEGER,
    konversation TEXT,                          -- JSON-Liste der Eingabe- und Ausgabeelemente des Laufs ohne Dateibytes
    CHECK ((datei_id IS NULL) <> (gespraech_id IS NULL))
);
-- Earlier transcripts keep their old shape; nothing reads them.
INSERT INTO anfragen (id, datei_id, modell, gestartet_am, beendet_am, status, eingabe_tokens, ausgabe_tokens, konversation)
SELECT id, datei_id, modell, gestartet_am, beendet_am, status, eingabe_tokens, ausgabe_tokens, konversation
FROM anfragen_alt;
INSERT INTO pfennig_010_check
SELECT (SELECT count(*) FROM anfragen) = (SELECT n FROM pfennig_010_count);
DROP TABLE anfragen_alt;
DELETE FROM sqlite_sequence WHERE name = 'anfragen';
INSERT INTO sqlite_sequence (name, seq) SELECT 'anfragen', seq FROM pfennig_010_sequence;

CREATE TABLE gespraeche (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titel TEXT NOT NULL,                        -- gekürzte erste Nutzernachricht
    geaendert_am TEXT NOT NULL,
    -- JSON-Liste der Responses-Elemente ohne Dateibytes; eine Datei steht als {"type": "datei", "id": 3}
    verlauf TEXT NOT NULL DEFAULT '[]'
);
INSERT INTO pfennig_010_check SELECT integrity_check = 'ok' FROM pragma_integrity_check;
COMMIT;
PRAGMA integrity_check;
