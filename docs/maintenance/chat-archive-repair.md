# Temporary pre-chat archive repair

Owner-approved on 2026-10-12. This fixes the known installed-archive failure `table anfragen has no column named gespraech_id`. It is a single temporary correction, to remove before 1.0, rather than a versioned migration framework.

On opening an existing archive, `ChatArchiveRepair` recognizes only the known old request columns, with nonnullable `datei_id`, no chat table and no custom request indexes/triggers. Current and new archives need no repair or backup. An unexpected old shape is rejected without changing it.

Before changing the known old schema, GRDB creates a consistent SQLite backup at `Backups/vor-chat-schema-<timestamp>-<UUID>/pfennig.sqlite` beside that archive's database and checks its integrity. SQLite's backup includes committed WAL contents. The backup directory has owner-only permissions. Failure to create or verify the backup prevents the repair.

One transaction recreates `anfragen` from the same current definition used by fresh archives, copies every historical request with its existing ID and transcript, preserves its autoincrement high-water mark, and adds the empty `gespraeche` table. It verifies row count and database integrity before commit. Bookings, receipt rows, payments, profile/settings, activities and export markers are untouched. Original receipt files and the Inbox are untouched, so the automatic repair only backs up the database. It never copies the release archive into development.

The tests use fictional archives and verify full record preservation, a restorable old-schema backup, request-ID continuity after a deleted high ID, working new import/chat requests, repeat-open behavior, backup failure, and rejection of unknown old schemas. The older [manual worksheet](0.10.0.md) remains available for the already installed release, which does not contain the automatic hook.

The related intake correction requires both a past successful import and a surviving booking that references the file before treating a hash as already processed. Removing a receipt from its booking therefore permits a later drop to reattach it, without storing the file twice. Normal booking deletion still deletes originals no remaining booking uses; failed imports still retain their originals and Inbox copies. No Dateien view was added.
