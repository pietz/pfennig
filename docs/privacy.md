# Privacy and data flow

Pfennig is local-first. It has no Pfennig account, hosted backend, analytics, advertising SDK, or telemetry.

## Stored on the Mac

`~/Library/Application Support/Pfennig/` contains:

- the SQLite database with bookings, file metadata, the activity log, the agent run log (model, token counts, the exchange without file contents), the chat conversations (the exchange without file contents, files referenced by their archive entry) and settings
- `Archiv/` with the imported and attached original documents, named by their SHA-256 hash
- `Inbox/` with dropped files that are still being processed or failed

Each provider’s API key is stored separately in the macOS Keychain. It is not written to the database, application logs, or repository files.

## Sent to the selected AI provider

Pfennig contacts the selected provider (OpenAI or OpenRouter) only when the user drops a file, when the user sends a chat message, when the user checks the connection in the settings, and for nothing else. Requests use the stateless Responses API and ask not to store responses (`store: false`); the conversation is kept on the Mac and sent again in full with every request. A file run sends:

- the dropped document itself
- the profile: business name, tax number, VAT ID, Kleinunternehmer status, today's date
- the database schema text, the category list and the list of known counterparty names with country
- everything the agent chooses to read from the database with its `sql` tool during the run. The agent typically searches for existing bookings of the same counterparty and amount to avoid duplicates, so rows from the bookings table can be part of the request. It cannot read the settings table or the periods table, and it cannot write anything except bookings.

A chat message sends the same profile, schema and tool results, the message with any attached files, and the earlier messages, tool calls, answers and attached files of that conversation, read again from the archive.

New imports and conversations use the provider selected in settings. Each conversation retains its provider and model, including after settings change. Existing conversations without provider metadata continue through OpenAI. Keys are sent only to their corresponding fixed service endpoint.

OpenAI processes this data under the terms and privacy choices of the API account associated with the user-provided key. Consult [OpenAI API data usage policies](https://platform.openai.com/docs/guides/your-data) before using the agent.

OpenRouter forwards requests to upstream model providers. Pfennig requests providers that do not collect data (`data_collection: deny`) and requires support for supplied parameters. PDF handling is explicitly native, avoiding an automatic external OCR parser. These settings do not establish a universal retention or regional-processing guarantee. The user’s OpenRouter account policies and the actual upstream provider terms still apply. See [OpenRouter routing](https://openrouter.ai/docs/guides/routing/provider-selection) and [PDF handling](https://openrouter.ai/docs/guides/overview/multimodal/pdfs).

## Network-independent behavior

Browsing, editing, confirming and exporting existing bookings does not require an internet connection. Without an API key, manual bookkeeping and export remain available; dropped files fail with a visible error.

## File access

Pfennig reads documents dropped by the user and copies them into the local archive. It does not connect to bank accounts and does not synchronize the archive anywhere.

## Removing data

Bookkeeping and documents remain under the user's control in the local folder above. Deleting a booking also removes archived originals no other booking references. Deleting a chat conversation removes its stored exchange; files attached in it stay in the archive. Clearing a key in settings deletes only the selected provider’s Keychain entry. Data already sent to a provider is governed by that service’s account policies and retention controls.
