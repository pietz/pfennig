# Bank / Payment Processor Statement CSV Formats

Research notes for the planned `StatementColumnMapping` parsers referenced in concept.md section 10.3 and future `statement_lines` ingestion. Fixed-format statement parsers are not implemented yet; the current `StatementImport` module contains only foundational fingerprinting logic.

Methodology: WebSearch/WebFetch against official bank help pages plus cross-checking
against open-source finance-tool parsers (hledger, beancount, Firefly III import
configs, moneymoney-style converters) that hardcode these headers against real,
byte-inspected sample exports. Confidence is stated per format. Where no authoritative
source could be found, this is stated explicitly rather than guessed. **Every format
below should still be validated against one real, current export from the target
bank before being trusted as a fixed-position parser** — several of these exports are
known to vary by account language, export template, or over time.

Each format has a synthetic fixture at `Fixtures/statements/<name>.csv` with 8-12 fully
fake rows (fake people, fake DE00-style test IBANs, no real account or personal data)
covering, where the scenario is realistic for that channel: a SaaS subscription, a
client payment referencing invoice `RE-2026-0042`, an income-tax prepayment to
"Finanzamt", an internal transfer to another own account, a bank/processor fee, and a
PayPal settlement leg.

---

## 1. Sparkasse — CSV-CAMT (V2)

**Confidence: high.** Verified against real, byte-inspected sample exports in the
open-source `RechnungsFee` repo, cross-checked against an independent Sparkasse→Homebank
converter script that hardcodes the identical column list, and against a Firefly III
import config for a specific Sparkasse (Neubrandenburg-Demmin).

Sparkasse's online banking export menu ("Umsätze exportieren") offers four options:
CSV-CAMT, CAMT (XML), CSV-MT940, MT940 (XML). "CSV-CAMT V2" is the label used on the
Excel/CSV export button; no evidence of a column-level difference between "V2" and any
other camt schema version was found — treat V2 as this CSV schema.

Fixture: `Fixtures/statements/sparkasse-camt.csv`

- **Preamble:** none. Header is line 1.
- **Encoding:** ISO-8859-15 (confirmed via an independent parser's explicit
  `encoding='iso-8859-15'`). No BOM.
- **Delimiter:** `;` (semicolon). **Quoting:** every field quoted with `"` (RFC4180-style, full quoting).
- **Header row (verbatim):**
  ```
  "Auftragskonto";"Buchungstag";"Valutadatum";"Buchungstext";"Verwendungszweck";"Glaeubiger ID";"Mandatsreferenz";"Kundenreferenz (End-to-End)";"Sammlerreferenz";"Lastschrift Ursprungsbetrag";"Auslagenersatz Ruecklastschrift";"Beguenstigter/Zahlungspflichtiger";"Kontonummer/IBAN";"BIC (SWIFT-Code)";"Betrag";"Waehrung";"Info"
  ```
- **Date format:** `DD.MM.YY` (2-digit year), both `Buchungstag` and `Valutadatum`.
- **Amount:** `Betrag`, one signed column. Comma decimal separator. No thousands
  separator observed even above 1000 (e.g. `"-1143,41"`, not `"-1.143,41"`). Leading
  `-` for debits, no sign for credits.
- **Counterparty name:** `Beguenstigter/Zahlungspflichtiger`. **Counterparty
  IBAN:** `Kontonummer/IBAN`. **Counterparty BIC:** `BIC (SWIFT-Code)`.
  **Reference/Verwendungszweck:** `Verwendungszweck` (clean, no embedded SEPA tags).
  **Booking text/type:** `Buchungstext` (e.g. `FOLGELASTSCHRIFT`, `GUTSCHRIFT`,
  `KARTENZAHLUNG`, `ENTGELTABSCHLUSS`).
- **Quirks:** `Auftragskonto` (own IBAN) repeats on every row. SEPA direct-debit
  metadata (`Glaeubiger ID`, `Mandatsreferenz`, `Kundenreferenz (End-to-End)`) are
  dedicated columns, separate from `Verwendungszweck` — unlike the MT940 variant
  below. `Info` carries statuses including `"Umsatz vorgemerkt"` for pending/not-yet
  booked lines — filter these out. All ~350 Sparkassen run the shared Finanz Informatik
  core banking platform, so this format is reported consistent bank-to-bank (not
  independently tested across more than one regional sample).
- **Sources:** Sparkasse export instructions PDF (sparkasse-gm.de); `RechnungsFee`
  sample files (github.com/nicolettas-muggelbude/RechnungsFee); Sparkasse
  CSV-CAMT→Homebank gist (gist.github.com/malefs/3cf3bc4fd1851a31bdaf42eb73767cd7);
  Firefly III import config (github.com/firefly-iii/import-configurations).

## 2. Sparkasse — CSV-MT940 (older variant)

**Confidence: high** on structure/columns (verified via byte-inspected sample);
**medium** on whether/when this is being deprecated (bank-specific announcements only).

Fixture: `Fixtures/statements/sparkasse-mt940.csv`

- **Preamble:** none. **Encoding:** ISO-8859-15 (same platform; not independently
  re-verified for this variant but very likely — medium-high confidence).
- **Delimiter:** `;`, full quoting — same conventions as CSV-CAMT.
- **Header row (verbatim, 11 columns — fewer than CAMT's 17):**
  ```
  "Auftragskonto";"Buchungstag";"Valutadatum";"Buchungstext";"Verwendungszweck";"Beguenstigter/Zahlungspflichtiger";"Kontonummer";"BLZ";"Betrag";"Waehrung";"Info"
  ```
- **Date/amount format:** identical to CSV-CAMT (`DD.MM.YY`, comma decimal, no
  thousands separator, one signed `Betrag` column).
- **Counterparty:** `Beguenstigter/Zahlungspflichtiger` (name). Uses old-style
  **`Kontonummer` + `BLZ`** (domestic account number + bank code) instead of an IBAN/BIC
  pair. **Key difference from CAMT:** no dedicated SEPA metadata columns — `Verwendungszweck`
  instead contains raw embedded SEPA tags as plain text, e.g.
  `EREF+2512400854-KD 123456 RE 001`.
- **Quirks:** this is the format most likely to disappear over time (some regional
  Sparkassen have announced discontinuing plain MT940-family export); do not assume
  it is universally still offered by every Sparkasse.
- **Sources:** same as CSV-CAMT above; DATEV community thread on Sparkasse export
  format migration (datev-community.de, thread `td-p/404909`).

## 3. Volksbank / Raiffeisenbank (VR-Banking) CSV export

**Confidence: high** for the *VR OnlineBanking web portal* export (corroborated by two
independent open-source codebases plus a byte-inspected real sample). **Low confidence**
that this generalizes to the desktop **VR-NetWorld Software** client, whose CSV export
is user-configurable (column set/order/even header presence are chosen by the user in
a saved export template) per Atruvia's own official PDF — that variant cannot be parsed
deterministically without also constraining which saved template the user exports with.
This doc and fixture cover the web-portal format only.

Fixture: `Fixtures/statements/volksbank-vr.csv`

- **Preamble:** none, header is line 1 (immediately after the BOM).
- **Encoding:** **UTF-8 with BOM** (`EF BB BF`), CRLF line endings.
- **Delimiter:** `;`. **Quoting: none** — fields are not quoted at all, even where
  `Verwendungszweck` embeds further `EREF:`/`MREF:`/`CRED:`/`IBAN:`/`BIC:` sub-tags as
  plain space-separated text.
- **Header row (verbatim):**
  ```
  Bezeichnung Auftragskonto;IBAN Auftragskonto;BIC Auftragskonto;Bankname Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;IBAN Zahlungsbeteiligter;BIC (SWIFT-Code) Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Waehrung;Saldo nach Buchung;Bemerkung;Gekennzeichneter Umsatz;Glaeubiger ID;Mandatsreferenz
  ```
- **Date format:** `DD.MM.YYYY` (4-digit year — notably different from Sparkasse's 2-digit year).
- **Amount:** `Betrag`, comma decimal, one signed column, leading `-` for debits.
- **Counterparty name:** `Name Zahlungsbeteiligter`. **Counterparty IBAN:**
  `IBAN Zahlungsbeteiligter`. **Counterparty BIC:** `BIC (SWIFT-Code) Zahlungsbeteiligter`.
  **Reference:** `Verwendungszweck`. **Booking text:** `Buchungstext` (e.g.
  `Gutschrift`, `Basislastschrift`).
- **Quirks:** includes a **running balance** column `Saldo nach Buchung` (Sparkasse
  formats have no such column). `Bezeichnung/IBAN/BIC/Bankname Auftragskonto` describe
  the *own* account verbosely (4 columns) rather than Sparkasse's single `Auftragskonto`.
  `Mandatsreferenz` is populated only for SEPA direct debits. SEPA reference tags
  appear embedded as raw text inside `Verwendungszweck`, similar to Sparkasse's MT940
  variant rather than CAMT. Since virtually all Volksbanken/Raiffeisenbanken run the
  shared Atruvia core banking platform, this format is *presumed* consistent
  bank-to-bank, but no official cross-institution spec was found to confirm it —
  validate against your specific target bank before shipping.
- **Sources:** `RechnungsFee` sample `vr-teilhaberbank.csv` (byte-inspected);
  independent corroboration in `Secret-Wolf/SimpleFinanceManager` (GitHub); Atruvia
  "VR-NetWorld Software: Umsatzexport" official PDF (desktop-client caveat).

## 4. DKB (Deutsche Kreditbank) — new portal format (2023+ relaunch)

**Confidence: high** on preamble/delimiter/encoding/quoting/date format (independently
confirmed by two unrelated open-source projects agreeing exactly). **One open item,
flagged explicitly below:** whether the `IBAN` column holds the counterparty's IBAN or
the own account's IBAN could not be conclusively resolved from the anonymized sample
used for verification.

Fixture: `Fixtures/statements/dkb.csv`

- **Preamble: 4 lines before the header**, verbatim pattern:
  ```
  "Girokonto";"<own IBAN>"
  <blank line>
  "Kontostand vom <DD.MM.YYYY>:";"<balance> €"
  ""
  ```
  (the `€` in the balance line is preceded by a non-breaking space in the real export).
- **Header row (verbatim):**
  ```
  "Buchungsdatum";"Wertstellung";"Status";"Zahlungspflichtige*r";"Zahlungsempfänger*in";"Verwendungszweck";"Umsatztyp";"IBAN";"Betrag (€)";"Gläubiger-ID";"Mandatsreferenz";"Kundenreferenz"
  ```
- **Encoding:** **UTF-8 with BOM.** **Delimiter:** `;`. **Quoting:** every field
  quoted with `"` (full quoting).
- **Date format:** `DD.MM.YY` (2-digit year).
- **Amount:** `Betrag (€)`, one signed column, comma decimal separator. **Quirk:**
  amounts are **not** zero-padded to 2 decimals (e.g. `"200"` and `"-62,3"` are both
  seen) — a parser must accept 0, 1, or 2 fractional digits. Whether a thousands
  separator (`.`) is used above 999 in this column could **not** be confirmed from the
  sample (only preamble display strings showed dot-thousands) — do not assume either
  way without testing a real >999 sample.
- **Counterparty name — quirk:** split across **two** columns, `Zahlungspflichtige*r`
  (payer) and `Zahlungsempfänger*in` (payee); both are always populated (one is "you"),
  so the parser must pick based on the sign of `Betrag (€)` or the `Umsatztyp`
  (`Eingang`/`Ausgang`) column, not assume one fixed "counterparty" column.
- **Counterparty IBAN — flagged uncertain:** single `IBAN` column, but in the
  anonymized verification sample this held what looked like the *own* account's IBAN
  on every row, which may be an anonymization artifact rather than real behavior.
  Treat this column's meaning as unconfirmed until checked against a real, non-redacted
  export; the fixture below assumes it is the counterparty's IBAN (the more useful,
  and more commonly documented, interpretation), but flag this as a re-verification
  item.
- **Reference:** `Verwendungszweck`. **Booking text/type:** no dedicated free-text
  booking-text column in this format (unlike Sparkasse/VR); use `Umsatztyp`
  (`Eingang`/`Ausgang`) plus `Status` (`Gebucht`; a pending state likely exists but was
  not observed).
- **Quirks:** SEPA metadata (`Gläubiger-ID`, `Mandatsreferenz`, `Kundenreferenz`) are
  dedicated trailing columns, empty except for direct debits — same pattern as
  Sparkasse CAMT. The pre-2023 legacy DKB format (older columns, no preamble) is
  **not** covered here (low-confidence secondary reports only) — a document with that
  older shape should not be routed to this mapping.
- **Sources:** `RechnungsFee` sample `dkb.csv` (byte-inspected);
  `GollyTicker/finance-analysis-dkb` notebook (independent parser, confirms preamble
  line count, delimiter, quoting, date format, encoding).

## 5. N26

**Confidence: high.** Verified directly against the source of `beancount-n26`
(github.com/siddhantgoel/beancount-n26), a maintained parser that hardcodes and
validates these exact header strings against real exports.

N26 exports in the account's UI language; there is **no single canonical header** —
a parser must match against known variants. This doc/fixture uses the current German
variant since the app's primary market is Germany; a real implementation should also
accept the English variants.

Fixture: `Fixtures/statements/n26.csv` (German-language export)

- **Header row variants (verbatim):**
  - English (current): `Booking Date,Value Date,Partner Name,Partner Iban,Type,Payment Reference,Category,Account Name,Amount (EUR),Original Amount,Original Currency,Exchange Rate`
  - English (older): `Date,Payee,Account number,Transaction type,Payment reference,Category,Amount (EUR),Amount (Foreign Currency),Type Foreign Currency,Exchange Rate`
  - **German (used in fixture):** `Datum,Empfänger,Kontonummer,Transaktionstyp,Verwendungszweck,Kategorie,Betrag (EUR),Betrag (Fremdwährung),Fremdwährung,Wechselkurs`
  - "Category"/"Kategorie" is optional per the source — some exports omit it.
- **Preamble:** none. **Encoding:** UTF-8, no BOM handling in the reference parser.
- **Delimiter:** `,` (comma) — used even for the German-locale export, **not**
  semicolon. **Quoting:** `QUOTE_MINIMAL` (only quoted if a field contains a comma
  or quote).
- **Date format:** ISO `YYYY-MM-DD` regardless of language variant — N26 does **not**
  use `DD.MM.YYYY` even in the German export.
- **Amount:** plain decimal **point** (not comma), no thousands separator, one signed
  column — **counter-intuitively, `Betrag (EUR)` uses `.` as decimal separator even in
  the German-language export** (confirmed: the reference parser never does a
  comma→dot substitution).
- **Counterparty name:** `Empfänger`. **Counterparty IBAN:** the German/old-layout
  export has no dedicated IBAN column (only `Kontonummer`, and even that's often
  blank for card transactions); only the newer English layout has `Partner Iban`.
  **Reference:** `Verwendungszweck`. **Booking type:** `Transaktionstyp` (constrained
  vocabulary, e.g. `Lastschrift`, `Überweisung`, `Kartenzahlung`).
- **Quirks:** no pending/status column in any variant. Foreign-currency rows populate
  `Betrag (Fremdwährung)`/`Fremdwährung`/`Wechselkurs`.
- **Sources:** `beancount-n26` source (github.com/siddhantgoel/beancount-n26);
  `bank2ynab` issue #137 "Support for N26".

## 6. ING Germany — "Umsatzanzeige" CSV export

**Confidence: high** on the current (2024-2025) format, verified against real,
dated sample export files. **Medium/flagged:** an older, structurally different
9-column quoted variant with a per-row running-balance column is documented by a
2015 source and still present in a currently-maintained `bank2ynab` config — it is
unclear whether any ING accounts still produce this; a robust parser should tolerate
both column counts.

Fixture: `Fixtures/statements/ing.csv`

- **Preamble:** 12 lines (13 with the optional balance line) before the header,
  verbatim pattern:
  ```
  Umsatzanzeige;Datei erstellt am: <DD.MM.YYYY HH:MM>

  IBAN;<own IBAN>
  Kontoname;Girokonto
  Bank;ING
  Kunde;<name>
  Zeitraum;<DD.MM.YYYY> - <DD.MM.YYYY>
  Saldo;<amount>;EUR              (only in the "mit Saldo" export option)

  Sortierung;Datum absteigend

  In der CSV-Datei finden Sie alle bereits gebuchten Umsätze. Die vorgemerkten Umsätze werden nicht aufgenommen, auch wenn sie in Ihrem Internetbanking angezeigt werden.

  ```
  Note the disclaimer text: **pending transactions are excluded from the export
  entirely** (not flagged with a status column) — there is no "vorgemerkt" status
  field in the current format.
- **Header row (verbatim, 7 columns, unquoted):**
  ```
  Buchung;Wertstellungsdatum;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Betrag;Währung
  ```
- **Encoding:** ISO-8859-1 / Windows-1252 (native export; stated by two independent
  sources). **Delimiter:** `;`, unquoted in the current format (an older 2015 sample
  shows quoted fields — tolerate both).
- **Date format:** `DD.MM.YYYY` for both `Buchung` and `Wertstellungsdatum`.
- **Amount:** German locale — comma decimal, **period thousands separator** (e.g.
  `2.647,74`, unlike the Sparkasse/DKB/VR formats which showed no thousands
  separator in samples). Leading `-` for debits. `Währung` always `EUR` in samples.
- **Counterparty:** only a single combined **name** column, `Auftraggeber/Empfänger`
  — **no IBAN/BIC column at all** in this format. **Reference:** `Verwendungszweck`
  (free text; direct debits embed order/reference numbers inline). **Booking
  type:** `Buchungstext`, constrained vocabulary (`Lastschrift`,
  `Dauerauftrag / Terminueberweisung`, `Gehalt/Rente`, `Gutschrift`, `Überweisung`, …).
- **Sources:** `RechnungsFee` sample `ing.csv`/`ing-mit-saldo.csv` (byte-inspected,
  dated Dec 2025); madflex.de "ING CSV to ledger converter"; `bank2ynab.conf`
  `[DE ING-DiBa]` section; 2015 gist (older/quoted variant, low confidence for
  current-day relevance).

## 7. comdirect

**Confidence: medium-high** on header/columns (two independent real-world sources
agree). **Low confidence on preamble length** — multiple independent reports say it
**varies** between exports (sometimes includes an "Alter Kontostand"/"Neuer Kontostand"
opening/closing balance line, sometimes not) — **a deterministic parser must locate
the header row by content-matching the known header string, not by a fixed skip-count.**

Fixture: `Fixtures/statements/comdirect.csv` (built with a 3-line preamble as one
common real-world example; the parser this feeds must still detect the header by
content, not position)

- **Header row (verbatim):**
  ```
  Buchungstag;Wertstellung (Valuta);Vorgang;Buchungstext;Umsatz in EUR
  ```
  A separate Visa/credit-card export variant exists with header
  `"Buchungstag";"Umsatztag";"Vorgang";"Referenz";"Buchungstext";"Umsatz in EUR"`
  (quoted) — not covered by this fixture.
- **Encoding:** ISO-8859-15 (confirmed in a real user's hledger rules file against a
  real 2025 export). **Delimiter:** `;` (one automated fetch claimed comma; the raw
  source directly contradicts that — discard it).
- **Date format:** `DD.MM.YYYY`.
- **Amount:** `Umsatz in EUR`, one signed column, comma decimal, leading `-` for debits.
- **Counterparty / reference — major quirk:** comdirect provides **no separate
  columns** for counterparty name, IBAN/BIC, or purpose text. Everything is crammed
  into the single `Buchungstext` field as **space-separated labeled sub-strings with
  no delimiter between them**, e.g. `Auftraggeber: <name> Buchungstext: <description>`
  (incoming) or `Empfänger: <name> Buchungstext: <description>` (outgoing), or
  `Buchungstext: <description> Karte Nr. …` (card transactions). **A parser must
  regex-split on the literal labels `Auftraggeber:`, `Empfänger:`, `Buchungstext:`
  inside that one field** — there is no structured IBAN/BIC field for the
  counterparty at all. `Vorgang` (separate column) holds the transaction-type label
  (`Kartenzahlung`, `Lastschrift`, `Überweisung`, …).
- **Sources:** `johannesgerer/buchhaltung` Haskell importer source
  (`Importers.hs`); `simonmichael/hledger` GitHub issue #2465 (real rules file + real
  parse failure against a real Sept-2025 export); comdirect community forum threads
  confirming both the label-embedding behavior and the variable preamble.

## 8. PayPal — German-locale "Alle Transaktionen" activity CSV

**Confidence: medium-high** on the current 41-column header (verified verbatim via raw
HTML of a dated PayPal help-article page describing a Dec 2024 format change) and on
formatting conventions (verified via a real 2015 sample row, still consistent with
PayPal's documented behavior). **Not independently re-confirmed against a live 2026
export** — PayPal has changed this schema multiple times historically (at least 3
header variants found), so a parser should validate the header rather than assume it
is permanently fixed.

How to obtain: Activity page → download icon → "Benutzerdefiniert" → transaction type
"Alle Transaktionen" → format "CSV".

Fixture: `Fixtures/statements/paypal.csv` (current 41-column format)

- **Header row (verbatim, 41 columns):**
  ```
  "Datum","Uhrzeit","Zeitzone","Name","Typ","Status","Währung","Brutto","Gebühr","Netto","Absender E-Mail-Adresse","Empfänger E-Mail-Adresse","Transaktionscode","Lieferadresse","Adress-Status","Artikelbezeichnung","Artikelnummer","Versand- und Bearbeitungsgebühr","Versicherungsbetrag","Umsatzsteuer","Option 1 Name","Option 1 Wert","Option 2 Name","Option 2 Wert","Zugehöriger Transaktionscode","Rechnungsnummer","Zollnummer","Anzahl","Empfangsnummer","Guthaben","Adresszeile 1","Adresszusatz","Ort","Bundesland","PLZ","Land","Telefon","Betreff","Hinweis","Ländervorwahl","Auswirkung auf Guthaben"
  ```
- **Preamble:** none. **Encoding:** not independently confirmed for the German
  locale specifically; the one real-world parser found (`elcojacobs/paypal-exact-parser`)
  opens PayPal CSVs as **UTF-8 with BOM** (`utf-8-sig`) and falls back to
  cp1252/latin-1 per-field on decode errors — treat as the safest default but build
  the parser to auto-detect BOM and fall back gracefully rather than hard-failing.
- **Delimiter:** comma. **Quoting — quirk:** in a real verified sample, the `Datum`
  field is **unquoted** while every other field is double-quoted (not uniform
  "all fields quoted").
- **Date format:** `DD.MM.YYYY`, unquoted. Separate `"Uhrzeit"` column as a quoted
  `HH:MM:SS` string, plus a separate `"Zeitzone"` column using German abbreviations
  (`MESZ`/`MEZ`) rather than IANA timezone names.
- **Amount:** German locale — thousands separator `.`, decimal separator `,` (e.g.
  `"1.594,36"`). **Three-column gross/fee/net model:** `Brutto` (gross) − `Gebühr`
  (fee, shown with a leading `-` even though it's a cost) = `Netto` (net); currency in
  `Währung`.
- **Counterparty:** `Name` (display name); `Absender E-Mail-Adresse` /
  `Empfänger E-Mail-Adresse` for sender/recipient email (no IBAN/BIC — PayPal
  transactions are identified by email/account, not bank details). **Reference:**
  `Rechnungsnummer` (merchant-supplied invoice number). `Transaktionscode` is PayPal's
  own transaction ID; `Zugehöriger Transaktionscode` links to a related transaction
  (e.g. the bank-debit leg that funded a PayPal payment). **Type/status:** `Typ`
  (e.g. "Web Accept-Zahlung"), `Status` (e.g. "Abgeschlossen"). `Auswirkung auf
  Guthaben` (balance impact) is present only in this current format, not in older
  variants.
- **Sources:** paypal.com/de/cshelp/article/help145 (official export instructions);
  tomitzek.net PayPal CSV v1/v2 format-change article (raw HTML verified); a real
  2015 sample export quoted on homebanking-hilfe.de (raw HTML verified);
  `elcojacobs/paypal-exact-parser` (GitHub, encoding behavior);
  `andreoliwa/bank-csv-rs` (documents English-locale header variants used for
  auto-detection).

## 9. Stripe — payouts / balance transactions CSV

**Confidence: high** on the current schema, sourced directly from Stripe's own
report-type reference (docs.stripe.com/reports/report-types/balance). **Correction
to a common assumption:** Stripe's current CSV schema uses **snake_case** column
names (`balance_transaction_id`, `created`, `gross`, `fee`, `net`, …), not
Title-Case-with-spaces — any Title-Case variant seen elsewhere is a legacy/superseded
format. **Medium confidence** on the exact date/time string format (not explicitly
documented; ISO 8601 is Stripe's convention elsewhere but not confirmed for this
specific report).

Stripe versions its report schemas (e.g. `balance_change_from_activity.itemized.1`
through `.7`); the fixture uses the latest documented default column set.

Fixture: `Fixtures/statements/stripe-balance-transactions.csv` (itemized balance
change from activity, `balance_change_from_activity.itemized.7`, default columns)

- **Header row (verbatim, default columns):**
  ```
  balance_transaction_id,created,available_on,currency,gross,fee,net,reporting_category,description
  ```
  (Stripe also offers 100+ optional columns — `customer_id`, `customer_name`,
  `customer_email`, `invoice_id`, `invoice_number`, `payment_intent_id`,
  `statement_descriptor`, etc. — and a related but distinct **itemized payouts**
  report, `payouts.itemized.5`, with header
  `balance_transaction_id,currency,description,effective_at,fee,gross,net,payout_expected_arrival_date,payout_id,payout_status,reporting_category`.
  A **payouts summary** report (`payouts.summary.2`) and **balance summary** report
  (`balance.summary.1`) also exist, both far shorter — not fixture-ed separately here.)
- **Delimiter:** comma, standard CSV quoting (not explicitly stated by Stripe's docs;
  assumed standard RFC4180 — low-risk assumption for a Stripe-generated file).
- **Amount — important, verified:** `gross`/`fee`/`net` are **decimal major units**
  (e.g. euros, not cents) in these CSV reports — explicitly documented by Stripe.
  This differs from the Stripe REST API, which uses integer minor units; **do not
  treat these CSV amounts as cents.**
- **Dates:** `created`/`available_on` come as a local-timezone value and (optionally)
  a `_utc`-suffixed twin always in UTC.
- **Counterparty / reference:** no single "counterparty" field — `description`
  (Stripe's free-text transaction description), plus optional `customer_name`,
  `customer_email`, `invoice_number` when those optional columns are enabled.
  `reporting_category` classifies the row (`charge`, `refund`, `payout`, `fee`,
  `transfer`, etc.).
- **Sources:** docs.stripe.com/reports/balance; docs.stripe.com/reports/report-types/balance
  (authoritative machine-readable schema table with per-version default columns).

## 10. American Express Germany — account/transaction CSV export

**Confidence: low.** Public documentation of the exact CSV layout is thin; this
section and fixture should be treated as best-effort and re-verified against a real
export before being trusted as a fixed-position parser.

Fixture: `Fixtures/statements/amex-de.csv`

- **What is verified (medium confidence, from a real screenshot in an official
  Lexware FinanzManager 2025 support PDF of an actual downloaded Amex DE file):** the
  base export (Amex online account → "Kontobewegungen und Abrechnungen" →
  "Transaktionen herunterladen" → CSV) has at minimum these columns, default filename
  `activity.csv`:
  ```
  Datum,Beschreibung,Karteninhaber,Konto #,Betrag
  ```
- **Date format:** `DD/MM/YYYY` (from real sample rows, e.g. `29/04/2022`) — note
  this is **not** the `DD.MM.YYYY` convention used by German bank exports.
- **Amount:** comma decimal separator, no thousands separator observed in samples.
  **Sign convention — quirk, per the same source:** import guidance for this export
  explicitly instructs users to invert the sign when importing into bookkeeping
  software, implying Amex's own export shows purchases as **positive** amounts (the
  opposite of the debit-negative convention used by the German bank formats above).
  The fixture follows this documented convention.
- **Delimiter:** comma (explicitly selected as "Trennzeichen: Komma" in the import
  guide, matching the source file). **Note (not independently verified, but logically
  necessary):** a comma delimiter combined with a comma decimal separator is only
  unambiguous if the amount field is quoted (or a different quote/escape convention
  is used) — the source screenshot did not show a raw byte sample to confirm this.
  The fixture quotes the `Betrag` field (e.g. `"23,79"`) to keep it parseable; treat
  the real export's exact quoting behavior here as unconfirmed.
- **Not verified / explicitly unknown — do not guess at runtime:**
  - Whether the "alle weiteren Transaktionsdetails einschließen" (include extended
    details) checkbox adds specific named extra columns (e.g. merchant address,
    category, reference) — no German column names found for this extended view.
  - File encoding (UTF-8 vs. Windows-1252/ISO-8859-1) — not documented anywhere found;
    a real risk area given umlauts in German merchant names. The fixture is written as
    UTF-8 as a reasonable modern default, but this is **not verified**.
  - Quoting style/character — an import wizard screenshot showed a "Texterkennungszeichen"
    (text-qualifier) selector but its default value could not be confirmed.
  - Whether a value-date, status, or reference/invoice-number column exists at all.
  - Whether `Karteninhaber` appears on single-cardholder consumer accounts or only
    multi-cardholder business accounts.
- **Recommendation:** given the weak evidentiary base, the Amex DE parser should
  sniff the header row against a small set of known candidate layouts at import time
  rather than being hard-coded to one exact schema — of all ten formats in this
  document, this is the one where "no guessing at runtime" is hardest to guarantee.
- **Sources:** Lexware FinanzManager 2025 official support PDF (real screenshot with
  header and sample rows); handbuch.fibuscan.de (confirms download flow only, no
  column names); kontocsv.de / smartkontoauszug.de (confirm "unusual, non-DATEV
  format" but do not quote native headers).

---

## Summary

| Format | Confidence | Encoding | Delimiter | Preamble | Date format | Decimal sep. |
|---|---|---|---|---|---|---|
| Sparkasse CSV-CAMT | High | ISO-8859-15 | `;` | none | DD.MM.YY | `,` |
| Sparkasse CSV-MT940 | High (structure) | ISO-8859-15 | `;` | none | DD.MM.YY | `,` |
| Volksbank/VR (web portal) | High | UTF-8+BOM | `;` | none | DD.MM.YYYY | `,` |
| DKB (2023+) | High (medium on IBAN column meaning) | UTF-8+BOM | `;` | 4 lines | DD.MM.YY | `,` |
| N26 | High | UTF-8 | `,` | none | YYYY-MM-DD | `.` |
| ING Germany | High | ISO-8859-1/CP1252 | `;` | 12-13 lines | DD.MM.YYYY | `,` |
| comdirect | Medium-high | ISO-8859-15 | `;` | variable, detect by header | DD.MM.YYYY | `,` |
| PayPal (DE) | Medium-high | UTF-8+BOM (inferred) | `,` | none | DD.MM.YYYY | `,` |
| Stripe | High | UTF-8 (assumed) | `,` | none | ISO-ish (unconfirmed exact) | `.` |
| American Express DE | Low | Unverified | `,` | none (unconfirmed) | DD/MM/YYYY | `,` |
