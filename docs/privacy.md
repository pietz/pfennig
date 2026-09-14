# Privacy and data flow

Pfennig is local-first. It has no Pfennig account, hosted backend, analytics, advertising SDK, or telemetry.

## Stored on the Mac

The selected Pfennig archive contains:

- the SQLite bookkeeping database
- imported original documents
- locally stored model responses and request metadata used for review and reproducibility
- exports and future backups

The OpenAI API key is stored in the macOS Keychain. It is not written to the archive, SQLite database, application logs, or repository files.

## Sent to OpenAI

Pfennig contacts OpenAI only when the user explicitly imports a PDF or image for AI extraction. That request contains:

- the imported document contents
- business-profile context: name, optional legal name, country, optional VAT ID, VAT status, and accounting method
- the supported bookkeeping categories and tax-treatment vocabulary

It does not include the existing transaction database, payment history, other archived documents, tax number, or unrelated files.

OpenAI processes this data under the terms and privacy choices of the API account associated with the user-provided key. Consult [OpenAI API data usage policies](https://platform.openai.com/docs/guides/your-data) before enabling document extraction.

## Network-independent behavior

Browsing, editing, and saving existing bookkeeping data does not require an internet connection. If no OpenAI API key is configured, manual bookkeeping remains available and document extraction is disabled.

## File access

Pfennig reads documents selected or dropped by the user and copies them into the local archive. The current version does not connect directly to bank accounts or synchronize the archive to a Pfennig cloud service.

## Removing data

Bookkeeping and documents remain under the user's control in the local archive folder. Removing the API key from Pfennig's settings deletes it from the macOS Keychain. Data already sent to OpenAI is governed by the API account's applicable retention controls.
