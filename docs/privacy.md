# Privacy and data flow

Pfennig is local-first. It has no Pfennig account, hosted backend, analytics, advertising SDK, or telemetry.

## Stored on the Mac

`~/Library/Application Support/Pfennig/` contains:

- the SQLite database with bookings, file metadata, the activity log, the agent run log (model, token counts, the text of the exchange without file contents) and settings
- `Archiv/` with the imported original documents, named by their SHA-256 hash
- `Inbox/` with dropped files that are still being processed or failed

The OpenAI API key is stored in the macOS Keychain. It is not written to the database, application logs, or repository files.

## Sent to OpenAI

Pfennig contacts OpenAI only when the user drops a file, when the user checks the connection in the settings, and for nothing else. A file run sends:

- the dropped document itself
- the profile: business name, tax number, VAT ID, Kleinunternehmer status, today's date
- the database schema text, the category list and the list of known counterparty names with country
- everything the agent chooses to read from the database with its `sql` tool during the run. The agent typically searches for existing bookings of the same counterparty and amount to avoid duplicates, so rows from the bookings table can be part of the request. It cannot read the settings table or the periods table, and it cannot write anything except bookings.

OpenAI processes this data under the terms and privacy choices of the API account associated with the user-provided key. Consult [OpenAI API data usage policies](https://platform.openai.com/docs/guides/your-data) before using the agent.

## Network-independent behavior

Browsing, editing, confirming and exporting existing bookings does not require an internet connection. Without an API key, manual bookkeeping and export remain available; dropped files fail with a visible error.

## File access

Pfennig reads documents dropped by the user and copies them into the local archive. It does not connect to bank accounts and does not synchronize the archive anywhere.

## Removing data

Bookkeeping and documents remain under the user's control in the local folder above. Deleting a booking also removes archived originals no other booking references. Clearing the API key in the settings deletes it from the macOS Keychain. Data already sent to OpenAI is governed by the API account's retention controls.
