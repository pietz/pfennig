# AI-Native Bookkeeping for macOS
## Product & Technical Specification — Version 2

**Status:** Target implementation spec (V2, supersedes V1); see [`docs/status.md`](docs/status.md) for what is implemented now
**Target platform:** macOS 15+  
**Primary user:** German freelancer / sole proprietor using EÜR and VAT cash accounting (`Ist-Versteuerung`)  
**Development style:** local coding agent, CLI-first; XcodeGen-generated project, no hand-maintained Xcode project, Xcode GUI only for packaging/release edge cases  
**Core principle:** AI understands and proposes; deterministic Swift validates; the user can always override.

# 1. Product Vision

Build a lightweight, native macOS bookkeeping application for solo self-employed users in Germany.

The application replaces as much of the user's recurring bookkeeping workflow as practical without becoming a general ERP system or an accounting suite for larger companies.

The application is **AI-native from the core**:

- The user does not manually choose "new expense", "new income", "new payment".
- The user drops one or more documents into the application.
- The system understands what the documents represent.
- It extracts relevant information.
- It creates or updates bookkeeping records.
- It identifies missing information.
- It proposes links between invoices, receipts, payments, and credit notes.
- It asks for human confirmation only where required by the configured autonomy level.
- The user can always manually inspect and edit the underlying bookkeeping data.

The app should feel like a polished native Mac application, not like a chatbot with bookkeeping features attached.

---

# 2. Scope

## 2.1 Primary target user (V1)

- Freelancer / Freiberufler in Germany; Einzelunternehmer as close adjacent case
- One business activity
- EÜR (Einnahmenüberschussrechnung), not balance-sheet accounting
- Regularly VAT-taxed or Kleinunternehmer (§19 UStG), with `Ist-Versteuerung` (§20 UStG) where applicable
- Primarily B2B services, some B2C possible
- Typical expenses: office, software/SaaS, advertising, hardware, professional services, telecom, travel
- Domestic, EU, and third-country invoices in multiple currencies
- Several payment accounts (bank account, credit card, PayPal, cash), no bank API

## 2.2 Must not be blocked by the data model (later)

- Soll-Versteuerung
- Multiple business activities
- Zusammenfassende Meldung (ZM, §18a UStG)
- DATEV export
- iCloud sync / multi-device
- User-driven ELSTER handoff through verified local exports; no manufacturer registration, manufacturer credentials, or hosted transmission gateway
- App Sandbox (security-scoped bookmarks for the archive folder)

---

# 3. Explicit Non-Goals for V1

Do not build initially:

- Invoice creation
- CRM
- Direct bank account connection (PSD2 / FinTS)
- Payroll, inventory, full ERP
- Travel expense management, mileage logs
- Full fixed-asset / AfA (depreciation) subsystem — only the asset *flag* and warning (see 5.6)
- Anlage AVEÜR
- Deductibility rules of §4 Abs. 5 EStG (Bewirtung 70 %, Geschenke, etc.) — only the transaction's free `notes`
- OSS/IOSS, import customs, Zusammenfassende Meldung
- DATEV / SKR03 / SKR04 export (future adapter maps canonical categories to accounts; do not put account numbers into the core category system)
- Direct ELSTER submission
- Cloud accounts, multi-user, iCloud sync
- General-purpose document management
- Primary chat interface
- Function-calling agent loops against the database

---

# 4. Product Principles

## 4.1 Transaction-first, not document-first

The primary object is a **business transaction / economic event**, not a document.

A transaction can have:

- zero or more source documents
- zero or more payments (via payment allocations)
- one or more bookkeeping allocations (category + amount)
- one or more tax components (rate + base + tax)
- one tax assessment (treatment, self-assessed VAT)
- field-level provenance
- validation issues
- a credit note as a transaction of its own: negative amounts in the direction
  of the document it corrects, settled by a payment in the opposite direction
- refunds as opposite-direction payments on the transaction they refund
- review state

Worked example used throughout this spec:

```text
Adobe Systems Software Ireland Ltd · Expense · 71.39 EUR
├── Document: adobe-2026-08.pdf (invoice, sha256 6E2…)
├── Invoice 2026-08-31, invoice no. IEIN123456, net 71.39 EUR, VAT 0.00
├── Tax assessment: reverseCharge, taxable base 71.39, self-assessed VAT 13.56, deductible input VAT 13.56
├── Bookkeeping allocation: software_subscriptions 71.39 EUR
├── Payment: 2026-09-02 -71.39 EUR from account "Geschäftskonto"
└── Provenance: invoice fields = document; treatment = agent (0.93); category = rule
```

A transaction may exist before all evidence is available (payment first, invoice later; invoice first, payment later).

## 4.2 Statements

How Pfennig takes in Kontoauszüge is an open question. The deterministic CSV importer and the rule-based matcher that were built for it were removed again by product decision on 2026-09-14; the replacement will be designed AI-first. Until that design is approved there is no statement schema, no parser, no matcher and no classification model in this specification, and none should be built.

## 4.3 Deterministic core

Any rule that can be expressed as an invariant in Swift is expressed in Swift, not delegated to the model.

---

# 5. Target German Bookkeeping Rules

This section specifies the intended `Tax` and `Validation` behavior, deliberately limited to common freelancer cases. It is not a statement that tax reporting is implemented or verified. The [workflow/output research](docs/research-user-workflow.md) records current gaps; in particular, existing materialized dates and form mappings are not yet a reliable UStVA/EÜR reporting path.

## 5.1 Separate tax points

Do not collapse dates. Each transaction can carry:

| Concept | Field | Meaning |
|---|---|---|
| Invoice date | `invoice_date` | Date on the document |
| Service period | `service_period_start` / `service_period_end` | When the service was performed; a single service date is stored in both |
| Payment date(s) | `payments.payment_date` | Actual cash movement per payment |

Tax points are **not** materialized per transaction. `UStVACalculator` applies the rules below to the stored dates when it prepares a period, so a corrected invoice or payment date changes the report without a stored derivation having to be refreshed.

Rules for a profile with `vat_accounting_method = cash`:

- **EÜR date** = payment date (Zufluss/Abfluss, §11 EStG). Partially paid transactions contribute per allocation on each payment date.
- **Output VAT** (income): due in the period of payment receipt (§13 Abs. 1 Nr. 1 b UStG, Ist-Versteuerung). Per payment allocation.
- **Input VAT** (expense, normal case): deductible when the service has been performed **and** a proper invoice is on hand ([§15 Abs. 1 Nr. 1 UStG](https://www.gesetze-im-internet.de/ustg_1980/__15.html)). Invoice date alone does not establish possession; importing a historical document does not establish its receipt date. Relevant facts or an explicit reviewed tax date are needed. Payment is generally irrelevant, except for advance payments before performance, where invoice possession and payment are required.
- **§13b reverse charge (expense):** distinguish the applicable rule. Qualifying EU-established supplier services under [§13b Abs. 1 UStG](https://www.gesetze-im-internet.de/ustg_1980/__13b.html) use the end of the period of performance. Cases under Abs. 2 use invoice issuance, no later than the end of the month following performance. Advance payments need the separate Abs. 4 rule. A single invoice-date fallback for every foreign service is not sufficient. Matching input VAT follows its own eligibility requirements; Kleinunternehmer have no corresponding deduction.
- **Intra-community acquisition of goods:** has its own rule under [§13 Abs. 1 Nr. 6 UStG](https://www.gesetze-im-internet.de/ustg_1980/__13.html); do not treat it as identical to all reverse-charge services. Detailed acquisition eligibility remains review-required outside the initial automatic scope.

`tax_assessments` no longer stores a materialized date; reporting derives payment-sensitive contributions per allocation, because a single transaction date cannot represent multiple tax periods. The §13b and intra-Community rules above are still simplified to the invoice date, falling back to the start of the service period, and must be completed before the reports are called finished.

## 5.2 The "Date" column

The main table and Start show one **relevant date**, derived as: the document date (`invoice_date`), otherwise the earliest payment date, otherwise the local calendar day of the creation timestamp. Ledger and Start are therefore dated by document; tax periods stay dated by payment. This is a ledger-navigation convention, not the date to use for any EÜR or UStVA contribution.

## 5.3 10-day rule (§11 Abs. 2 S. 2 EStG)

Regularly recurring expenses/income paid within 10 days before or after the year boundary belong to the year they economically relate to. V1 does **not** re-assign automatically; it raises a **soft warning** for payments between 22 Dec and 10 Jan on transactions whose counterparty has a recurring pattern, and lets the user set `eur_year_override`.

## 5.4 Reverse charge and self-assessed VAT

For treatments `reverseCharge` and `intraCommunityAcquisition` on expenses, the recipient owes VAT and (for a fully VAT-liable business) deducts it as input VAT in the same period:

```text
taxable_base_minor      = 7139   (71.39 EUR)
self_assessed_vat_minor = 1356   (19 % of base, rounded half-up to cent)
invoice tax shown        = 0
deductible input VAT     = 1356  (derived, not stored)
```

The document's own `tax_amount` is 0; `self_assessed_vat` is computed by Swift, never by the model. Rate defaults to the German standard rate applicable at the invoice date.

For **income** with `reverseCharge` (EU B2B service to a customer with a valid VAT ID): no VAT charged, `customer_vat_id` required (soft warning if missing). ZM reporting is a future feature; V1 only tags these transactions so they can be reported later.

For a **Kleinunternehmer purchasing a typical foreign B2B service**, Pfennig computes the self-assessed VAT but sets deductible input VAT to zero. Detailed acquisition-threshold rules for EU goods remain outside the automatic rule set and require review.

## 5.4.1 Kleinunternehmer (§19 UStG)

Pfennig supports the common bookkeeping cases, not automated eligibility or regime administration:

- Domestic income is treated as `smallBusiness` rather than ordinary taxable income.
- VAT shown by a domestic supplier remains part of the document facts, but deductible input VAT is zero and the gross amount is allocated as cost.
- An explicit §19 indication on a domestic supplier invoice may produce `smallBusiness`; Pfennig never invents input VAT from its gross amount.
- Contradictory VAT on Kleinunternehmer income remains visible and produces a review warning.

Turnover thresholds, waivers, status changes, mixed activities, invoice issuance, and filing automation are deferred.

## 5.5 Kleinbetragsrechnung (§33 UStDV)

For expense documents with gross ≤ 250.00 EUR, a missing invoice number, missing customer address, and missing separate net/tax breakdown are **not** issues, provided gross amount and tax rate are present. Exceptions of §33 (e.g., intra-community supplies, §13b) still require full invoices — if treatment is not `domesticVAT`, the relaxation does not apply.

## 5.6 Assets (GWG threshold)

V1 has no depreciation. It must detect and warn:

- An expense allocation with category kind `asset_candidate` **or** any single-line expense with net > 800.00 EUR in a hardware/equipment category gets `asset_flag = true` and a **soft warning**: "Möglicherweise Anlagevermögen – nicht vollständig als Betriebsausgabe abzugsfähig."
- Allocations flagged as asset are excluded from EÜR operating-expense totals and listed separately as "Anlagegüter (manuell prüfen)". The user can clear the flag.
- Threshold (currently 800 EUR net, §6 Abs. 2 EStG) is a configuration constant in the Tax module, not hard-coded in validation.

## 5.7 Foreign currency (§16 Abs. 6 UStG)

Converted amounts may use the actual bank rate (payment amount in EUR) or the BMF monthly average rate. V1 stores both the original and the EUR amounts plus the `exchange_rate` used. Which of the two conventions a rate came from is not recorded separately: the rate and both amounts are what a report and a review need.

The user chooses the authoritative EUR amount; default is `bankActual` when a payment is linked, otherwise `documentStated`, otherwise missing.

## 5.8 Tax payments and private movements on statements

- **VAT payments to / refunds from the Finanzamt** are business transactions (Betriebsausgabe/-einnahme in the EÜR, `transaction_type = taxPayment`, category `vat_payment` / `vat_refund`).
- **Income-tax and solidarity-surcharge prepayments** are private and create no business transaction.
- **Internal transfers** between own accounts create no transaction.
- **Bank fees** are business expenses that legitimately have no invoice; category `bank_fees` sets `document_expected = false`.

## 5.9 GoBD posture

The app does not claim GoBD compliance. It supports the underlying practices: originals are immutable, every change is audited, and periods will be lockable (see 17.24). Edits inside a locked period require an explicit "Korrektur" action that records the reason.

---

# 6. Core User Experience

## 6.1 Main window

Native three-column layout:

```text
┌──────────────┬───────────────────────────────┬────────────────────┐
│ Sidebar      │ Main transaction table        │ Inspector          │
│              │                               │                    │
│ Buchungen    │ Gegenpartei | Datum | Betrag  │ Belegvorschau      │
│ Konten       │ Zahlung | Steuer | Status     │ Felder             │
│ Prüfen  (3)  │                               │ Zahlungen          │
│ Auswertung   │                               │ Steuer             │
│ Steuern      │                               │ Hinweise           │
│ Einstellungen│                               │                    │
└──────────────┴───────────────────────────────┴────────────────────┘
```

SwiftUI building blocks: `NavigationSplitView`, `Table`, native toolbar, `.inspector`, native drag-and-drop, `.searchable`, `@Observable`. Avoid custom UI unless necessary.

UI language: **German first**. Add localization infrastructure when a second locale becomes a product priority rather than carrying unused translation machinery. Code, schema, identifiers, enums: English. Numbers, currencies, dates: locale-aware via `FormatStyle`.

### Start overview (current implementation)

Start is the default entry point, with the sidebar visible. Three compact cards show recorded income, expenses, and their difference for a selectable year. These are signed booked EUR gross amounts using the ledger's relevant date (document date first, see 5.2), not an EÜR profit or cash-flow calculation. Pending import proposals are excluded. Missing amounts or unknown directions remain visible as incomplete totals.

Below the cards, Start has two columns with the same row presentation:

- **Offen** is what the user still has to decide or add: bookings whose review is open, missing expected documents, and open import proposals. Its rows lead to "Prüfen", where the decision is actually made. Empty state: "Alles erledigt".
- **Anstehend** are the outward-facing deadlines: the Umsatzsteuer-Voranmeldung periods with their due dates today, other tax tasks later. Its rows open the task itself. Empty state: a quiet "Keine Fristen".

The columns sit side by side while both fit and stack in a narrow window. Open items span all years and are not added into a combined count because categories may overlap. Document-exempt categories do not create missing-document work. Deadlines are reserved for real dates and remain hidden until supported. Keep this overview compact: no separate analysis page, recent-bookings list, or decorative chart is needed.

## 6.2 Main transaction table

Initial columns: Counterparty/Title · Relevant date · Amount (booked EUR; original shown secondary if different) · Payment status · Tax treatment · Status.

Later configurable columns: categories, invoice number, document completeness, currency, review state, account.

## 6.3 Accounts view

Deferred with the statement approach (see 4.2).

## 6.4 Inspector

For a selected transaction: document preview (PDFKit / image), transaction fields, invoice fields, bookkeeping allocations, tax components and assessment, payments and allocations, attached documents, relations, validation issues, missing information, and actions. Provenance and audit metadata remain internal rather than becoming routine interface chrome.

Actions: Confirm · Edit · Attach document · Add payment · Link payment · Unlink · Split allocation · Add relation (credit note/refund) · Re-run AI analysis · Mark asset / clear asset flag · Archive · Resolve/ignore warning.

Every material field is manually editable; manual values carry provenance `manual` and are never overwritten by the AI.

---

# 7. Import UX

## 7.1 Drag and drop

Files can be dropped nearly anywhere in the main window. Supported inputs V1: PDF, JPG/JPEG, PNG, HEIC (converted locally), XML (XRechnung/ZUGFeRD).

## 7.2 Import batch

Dropping one or more files creates an import batch. For multiple documents, never show a chain of modal dialogs; create a **review queue**:

```text
12 vorgeschlagene Änderungen
8 bereit · 3 prüfen · 1 Konflikt
```

The queue is persisted (see 17.19) and survives restarts.

**Prüfen** is the single page for everything that needs a decision, not only for imports: import proposals, failed imports, bookings whose review is open, and bookings without the document they expect, in that order and each only when it has entries. A booking row shows date, counterparty, title, amount and its short reason, and opens the booking in "Buchungen" with the inspector. Each booking section also leads into the matching ledger filter for sorting, search and bulk work. When nothing is open the page says so and names the time of the last import.

---

# 8. AI Interaction Model

## 8.1 No primary chat interface

The application communicates through filled/partially filled records, highlighted missing fields, warnings, proposals, and the review queue. A contextual free-text field may come later.

## 8.2 Missing information is a valid state

Never force the model to invent values. `null` and `unknown` are first-class.

UI distinguishes proposal state, missing information, suspicious values, invalid values, and validated records. Field-level provenance is not displayed in the ordinary workflow.

## 8.3 Field provenance

Every material field has provenance in `field_provenance`:

```text
document    — read directly from the document (extracted)
agent       — inferred by the model (not literally on the document)
calculated  — derived by Swift (tax points, self-assessed VAT, EUR conversion)
manual      — set by the user
imported    — from a structured source (XRechnung, CSV column)
rule        — applied from a user rule
```

Manual overrides are never silently replaced by a later AI run.

---

# 9. Automation Level

One user setting with three values, stored in `settings` under
`automation.level`, default **Manual**. It governs document imports; the
earlier per-capability flag presets were replaced by this single setting when the
[workflow specification](docs/specs/document-to-tax-workflow.md) was approved.

| Level | Behaviour |
|---|---|
| Manuell | Every proposal is confirmed by the user, including unambiguous ones. |
| Ausgewogen | Fully validated standard cases with an unambiguous derivation are committed without confirmation. Anything with a warning, a competing match or a missing fact stays a proposal. |
| Automatisch | No confirmation step. Warnings are recorded on the booking, which stays visible under "Prüfen"; what cannot be derived unambiguously stays an exception instead of being invented. |

A single deterministic function decides per proposal
(`ImportPipeline.AutomationPolicy.decide`). Its inputs are the level, the hard
and soft validation results, whether the derivation or match is unambiguous,
and whether a manually entered field would be overwritten. Model confidence is
not an input.

- Hard validation failures block at every level.
- Manual values are never silently overwritten; such a write becomes a review item.
- An ambiguous match is never applied automatically, at any level.
- An automatic commit runs through the same `CommitService` path as the user's
  confirmation, so provenance, duplicate handling and atomicity are identical.
- Changes within a **locked period** always require review regardless of level.

---

# 10. AI Architecture

## 10.1 Provider

V1 uses the **OpenAI Responses API** directly with strict Structured Outputs. No agent framework. A small explicit orchestration layer in Swift. Provider is behind a protocol:

```swift
protocol DocumentIntelligenceProvider: Sendable {
    func extract(document: PreparedDocument, context: ExtractionContext) async throws -> DocumentExtraction
    func disambiguate(_ request: DisambiguationRequest) async throws -> DisambiguationResult
}
```

## 10.2 Two-phase design (binding for V1)

```text
Document
  ↓ AI: extraction (one strict Structured Output call, no DB context except business profile)
  ↓ Swift: normalization (amounts, dates, counterparty, currency)
  ↓ Swift: deterministic matching against DB (see 24)
  ↓ AI only on true ambiguity: disambiguation call with ≤ 5 candidates
  ↓ Swift: proposal → validation → review policy → commit
```

- **No function calling / tool loop in V1.** The model never queries or writes the database.
- The extraction schema does **not** contain `proposedMatch`; matching is Swift's job.
- The disambiguation call receives only the minimal candidate list (id, counterparty, amount, date, invoice number, payment state) and returns a ranked choice with reasoning.

## 10.3 Statement handling

Open, see 4.2.

## 10.4 Document preparation

- PDF: sent as file input directly (page limit configurable; default ≤ 20 pages; longer PDFs are split or rejected with a message).
- HEIC: converted locally to JPEG via ImageIO before upload (OpenAI accepts JPEG/PNG/GIF/WebP).
- XRechnung / ZUGFeRD XML: parsed deterministically first (`imported` provenance); the model is only asked to classify and fill fields the structured data lacks.
- Structured data always wins over visual inference.

## 10.5 API key

User-supplied OpenAI API key stored in the **macOS Keychain** (requires a stably signed app bundle, see 35). Never in SQLite, plaintext preferences, repository files, or logs. Model selection under Advanced Settings; default model is a configuration constant with a `prompt_version` attached.

## 10.6 Structured Outputs constraints (for the coding agent)

- Use `strict: true` JSON schema.
- All properties are `required`; optional values are modelled as `anyOf: [{type}, {type: "null"}]`.
- Enums for all categorical fields. No free-form strings where an enum exists.
- Amounts are returned as **decimal strings** (`"71.39"`) plus ISO currency code; Swift converts to minor units.
- Dates as `YYYY-MM-DD` strings or null.

---

# 11. Agent Safety Model

- The model has **no write path**. All mutations are typed Swift operations inside a `ProposedOperation` enum (see 26), validated before commit.
- The model has **no read path** in V1 beyond the context Swift places in the prompt.
- If tools are ever added (post-V1): typed read tools (`searchTransactions`, `getTransaction`, `findPaymentCandidates`, `getCounterpartyHistory`, `getBusinessProfile`, `getRules`) — never arbitrary SQL; any SQL read tool would be read-only, schema-restricted, row- and time-limited.

---

# 12. Processing Pipeline

```text
Import
  ↓ Archive original (copy, never modify)
  ↓ SHA-256 + exact duplicate check
  ↓ File type / structured format detection
  ↓ [document?]  → prepare → AI extraction → normalize
  ↓ Deterministic matching (payment↔transaction, semantic duplicate)
  ↓ [ambiguous?] → AI disambiguation
  ↓ Build proposal (persisted)
  ↓ Deterministic validation
  ↓ Review policy (autonomy + locked periods)
  ↓ Commit in one SQLite transaction
```

Restartable and idempotent: `import_items` and `proposals` carry status; on restart, items in `processing` are resumed or marked `failed`, never duplicated (see 34).

---

# 13. Structured AI Output — Extraction Schema

Conceptual (production schema lives in `AI/ExtractionSchema.swift`, versioned by `prompt_version`):

```json
{
  "documentType": "invoice",
  "direction": "expense",
  "title": "Creative Cloud September",
  "counterparty": {
    "name": "Adobe",
    "countryCode": "IE",
    "vatId": "IE6364992H"
  },
  "invoice": {
    "invoiceNumber": "IEIN123456",
    "invoiceDate": "2026-08-31",
    "servicePeriodStart": "2026-08-01",
    "servicePeriodEnd": "2026-08-31",
    "currency": "EUR",
    "netAmount": "71.39",
    "taxAmount": "0.00",
    "grossAmount": "71.39"
  },
  "taxComponents": [
    { "rate": "0", "netAmount": "71.39", "taxAmount": "0.00", "kind": "reverseChargeNote" }
  ],
  "taxTreatmentHint": { "treatment": "reverseCharge" },
  "lineItems": [
    { "description": "Creative Cloud All Apps", "netAmount": "71.39", "categoryHint": "software_subscriptions" }
  ],
  "paymentInfo": { "paymentMethodHint": "creditCard", "paidIndicator": "paid", "paymentDate": null, "iban": null, "reference": null },
  "missingFields": [],
  "warnings": []
}
```

Rules: `taxTreatmentHint` is a hint; Swift decides the treatment using profile + counterparty country + VAT IDs + hint. The hint carries the treatment only: a model confidence would never be authorization, and free-text reasoning was never read. `categoryHint` values must be from the canonical category enum or null.

`counterparty.name` is the short everyday trade name (`Amazon`, not `Amazon EU S.à r.l., Niederlassung Deutschland`); the legal name stays on the archived document. `title` is the ledger line: a short German phrase of at most ~40 characters naming what was bought or billed, without serial, order or invoice numbers, dates or amounts. Normalization collapses whitespace and cuts a title longer than 60 characters at a word boundary; it never shortens a company name beyond trimming.

---

# 14. Deterministic Validation

## 14.1 Hard validations (block commit)

- Malformed currency code; amount not representable in minor units
- Impossible dates; service period end < start
- `sum(taxComponents.net) ≠ invoice.net` or `sum(taxComponents.tax) ≠ invoice.tax` beyond tolerance (default 0.02 EUR)
- `net + tax ≠ gross` beyond tolerance
- A negative amount on anything but a `creditNote`, a `creditNote` with
  positive amounts, or net, tax and gross with differing signs
  (`AMOUNT_SIGN_INVALID`)
- `sum(bookkeeping_allocations.amount) ≠ booked net amount` (or gross for non-deductible cases) beyond tolerance
- Payment allocation total exceeds payment amount
- A new payment settling more than the booked gross amount, or a refund giving
  back more than was paid (enforced at the write boundary)
- Linked IDs do not exist; unsupported state transition
- Duplicate immutable document identity (sha256)
- Mutation inside a locked period without an explicit correction action

## 14.2 Soft validations (allow save, require attention by autonomy level)

- Unusual tax rate for treatment/country
- `reverseCharge` with domestic counterparty, or `domesticVAT` with EU counterparty and VAT ID present
- Missing customer VAT ID on reverse-charge income
- Missing service date (not for Kleinbetrag)
- Missing invoice number (suppressed for Kleinbetrag, see 5.5)
- Payment amount differs from invoice (fee/FX) — propose difference as `fee` component
- Exchange rate deviates > 5 % from bank actual
- Likely semantic duplicate
- Asset candidate (see 5.6)
- 10-day-rule window (see 5.3)
- Amount > configurable threshold with `agent` provenance only

## 14.3 UI convention

Yellow = suspicious/incomplete/needs review · Red = invalid/blocked · Neutral = incomplete but acceptable · Green = validated/confirmed. Never color alone; always icon + text.

---

# 15. Money and Currency Model

## 15.1 Storage

All monetary amounts are **`Int64` minor units** with an explicit ISO-4217 currency code; the exponent comes from a currency table in `Domain` (EUR 2, USD 2, JPY 0, …). SQLite `SUM` over minor units is exact.

Exchange rates and tax rates are non-monetary decimals stored as canonical decimal **TEXT** (`"0.9214"`, `"19"`); never `REAL` for anything that feeds bookkeeping.

## 15.2 Domain type

```swift
struct Money: Codable, Hashable, Sendable {
    let minorUnits: Int64
    let currency: CurrencyCode
    var decimal: Decimal { … }          // exact, uses currency exponent
    static func fromDecimalString(_ s: String, currency: CurrencyCode) throws -> Money
}
```

Centralize parsing (German and English decimal formats), rounding (half-up to currency exponent for VAT), VAT arithmetic, and formatting. Never `Double`.

## 15.3 Original vs booked

Store separately on transactions and payments: original amount + currency, booked EUR amount, exchange rate + source (5.7), fees if identifiable. Never overwrite the original currency.

```text
Invoice: 1,000.00 USD          original
Booked:    921.40 EUR          exchange_rate 0.9214, source bmfMonthly
Paid:      928.17 EUR          bankActual
Fee:         6.77 EUR          tax component kind = fee, category bank_fees
```

---

# 16. Tax Model

## 16.1 Treatment enum (binding)

```text
domesticVAT                — German VAT charged on the document
reverseCharge              — §13b (expense) / EU B2B service without VAT (income)
intraCommunityAcquisition  — goods from EU supplier, self-assessed
intraCommunitySupply       — goods to EU business (income, later)
export                     — third-country income without VAT
importVAT                  — Einfuhrumsatzsteuer paid (expense; documented by customs/carrier invoice)
nonTaxable                 — outside VAT scope (e.g., insurance, tax payments)
exempt                     — §4 UStG exempt
smallBusiness              — §19 treatment for a Kleinunternehmer supply
unknown
```

## 16.2 Tax components vs tax assessment

- **`tax_components`**: what the document shows, per rate: rate, net, tax, kind (`standard`, `reduced`, `zero`, `reverseChargeNote`, `exempt`, `fee`, `deposit`, `other`). A Deutsche Bahn ticket has a 7 % and a 19 % component; a hotel invoice has 7 % (lodging) and 19 % (breakfast).
- **`tax_assessments`**: the single bookkeeping judgement per transaction: treatment, taxable base, VAT shown, self-assessed VAT, deductible input VAT, customer/supply type, status. No dates: the tax point is derived when a period is prepared (5.1). No supplier country either: that belongs to the counterparty.

## 16.3 Form mappings live outside the core schema

UStVA Kennzahlen and EÜR line numbers depend on the form year and applicable treatment. The target is **verified, versioned mapping tables in the Tax module**. The current files below are unverified placeholders, not completed reporting support; a year in the filename does not prove publication or verification of that year's form:

```text
Tax/FormMappings/UStVA_2026.swift   — treatment × direction × rate → Kennzahl
Tax/FormMappings/EUeR_2026.swift    — category_id → EÜR line
```

The core schema stores only stable semantics (treatment, rate, category ID, dates).

---

# 17. Data Model and SQLite Schema

SQLite is the canonical local store. Library: **GRDB.swift**. UUID strings (lowercase, RFC 4122) as primary keys. All timestamps ISO-8601 UTC (`2026-09-12T10:15:00Z`); calendar dates `YYYY-MM-DD`. All money as `INTEGER` minor units with an adjacent `*_currency` column (or a shared currency column per row). `PRAGMA foreign_keys = ON`. Soft delete via `deleted_at` where noted.

Column types below are binding for the initial migration; later changes go through numbered migrations (47).

## 17.1 `business_profiles`

```sql
CREATE TABLE business_profiles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    legal_name TEXT,
    country_code TEXT NOT NULL DEFAULT 'DE',
    tax_number TEXT,
    vat_id TEXT,
    vat_status TEXT NOT NULL,              -- taxable | smallBusiness
    vat_accounting_method TEXT NOT NULL,   -- cash | accrual
    ustva_period TEXT NOT NULL,            -- monthly | quarterly | yearly
    business_type TEXT NOT NULL,           -- freelancer | soleProprietor
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

V1 supports exactly one profile; the column exists on other tables for later multi-activity support.

## 17.3 `counterparties`

```sql
CREATE TABLE counterparties (
    id TEXT PRIMARY KEY,
    normalized_name TEXT NOT NULL,         -- lowercased, legal-form-stripped, whitespace-collapsed
    display_name TEXT NOT NULL,
    country_code TEXT,
    vat_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_counterparties_normalized ON counterparties(normalized_name);
```

## 17.4 `categories`

Canonical bookkeeping categories with stable IDs, seeded by migration. A category is retired by setting `archived_at`, never deleted. No SKR account numbers here.

```sql
CREATE TABLE categories (
    id TEXT PRIMARY KEY,                   -- stable slug, e.g. 'software_subscriptions'
    name_de TEXT NOT NULL,
    kind TEXT NOT NULL,                    -- income | expense | assetCandidate | neutral
    document_expected INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    archived_at TEXT
);
```

Initial system categories:

```text
income:   revenue_services, revenue_goods, revenue_licenses, other_income, vat_refund, interest_income
expense:  software_subscriptions, hosting_cloud, telecom, office_supplies, office_rent,
          hardware_small (≤ GWG), advertising, professional_services (Steuerberater, Anwalt),
          contractors_freelancers, travel_transport, travel_lodging, meals_entertainment (note only),
          training_books, insurance_business, bank_fees (document_expected=0), payment_provider_fees,
          memberships, postage_shipping, vat_payment, other_expense
assetCandidate: hardware_equipment, furniture, vehicles
neutral:  uncategorized
```

`kind = assetCandidate` triggers the asset warning (5.6) regardless of amount.

## 17.5 `transactions`

```sql
CREATE TABLE transactions (
    id TEXT PRIMARY KEY,
    business_profile_id TEXT NOT NULL REFERENCES business_profiles(id),
    counterparty_id TEXT REFERENCES counterparties(id),

    direction TEXT NOT NULL,               -- income | expense | unknown
    transaction_type TEXT NOT NULL,        -- invoice | receipt | creditNote | paymentOnly | taxPayment | other
                                           -- creditNote: negative amounts in the direction it corrects

    title TEXT,
    invoice_number TEXT,
    invoice_date TEXT,
    service_period_start TEXT,
    service_period_end TEXT,
    is_advance_payment INTEGER NOT NULL DEFAULT 0,

    original_currency TEXT NOT NULL DEFAULT 'EUR',
    original_net_minor INTEGER,
    original_tax_minor INTEGER,
    original_gross_minor INTEGER,

    booked_currency TEXT NOT NULL DEFAULT 'EUR',
    booked_net_minor INTEGER,
    booked_tax_minor INTEGER,
    booked_gross_minor INTEGER,
    exchange_rate TEXT,                    -- canonical decimal string

    eur_year_override INTEGER,             -- 10-day rule (5.3)

    workflow_status TEXT NOT NULL,         -- active | archived
    review_status TEXT NOT NULL,           -- unreviewed | needsReview | confirmed | conflict

    notes TEXT,
    deleted_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

No `category` column: categories live in `bookkeeping_allocations`.

## 17.6 `bookkeeping_allocations`

```sql
CREATE TABLE bookkeeping_allocations (
    id TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES transactions(id),
    category_id TEXT NOT NULL REFERENCES categories(id),
    amount_minor INTEGER NOT NULL,         -- booked currency, net for deductible-VAT cases, gross otherwise
    currency TEXT NOT NULL DEFAULT 'EUR',
    description TEXT,
    asset_flag INTEGER NOT NULL DEFAULT 0,
    private_share_percent TEXT,            -- decimal string, e.g. '30' for 30 % private use; NULL = 0
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_alloc_transaction ON bookkeeping_allocations(transaction_id);
CREATE INDEX idx_alloc_category ON bookkeeping_allocations(category_id);
```

Invariant: `SUM(amount_minor) = transactions.booked_net_minor` (or gross when input VAT is not deductible). One allocation with `uncategorized` is created automatically if the AI provides none.

## 17.7 `tax_components`

```sql
CREATE TABLE tax_components (
    id TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES transactions(id),
    kind TEXT NOT NULL,                    -- standard | reduced | zero | reverseChargeNote | exempt | fee | deposit | other
    rate TEXT,                             -- decimal string '19', '7', '0', NULL if not applicable
    net_minor INTEGER NOT NULL,
    tax_minor INTEGER NOT NULL,
    currency TEXT NOT NULL,                -- original currency
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);
CREATE INDEX idx_taxcomp_transaction ON tax_components(transaction_id);
```

## 17.8 `tax_assessments`

Exactly one assessment per transaction. Replacing it deletes the previous row; no assessment history is kept.

```sql
CREATE TABLE tax_assessments (
    id TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES transactions(id),

    treatment TEXT NOT NULL,               -- see 16.1
    customer_type TEXT NOT NULL DEFAULT 'unknown',   -- b2b | b2c | unknown
    supply_type TEXT NOT NULL DEFAULT 'unknown',     -- service | goods | unknown
    customer_vat_id TEXT,

    taxable_base_minor INTEGER,            -- booked currency
    self_assessed_vat_minor INTEGER,       -- §13b / i.g. Erwerb, computed by Swift
    currency TEXT NOT NULL DEFAULT 'EUR',

    status TEXT NOT NULL,                  -- proposed | confirmed | manualOverride
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_taxassess_transaction ON tax_assessments(transaction_id);
```

Tax points are not stored here. Income counts per payment date, input VAT at `max(Rechnungsdatum, Zahlungsdatum)` per payment, and §13b/intra-Community acquisitions at the invoice date, falling back to the start of the service period; `UStVACalculator` reads those dates directly from `transactions` and `payments`.

VAT shown, deductible input VAT and output VAT are not stored either. Every report recomputes them from `tax_components` and `payments`, and the inspector shows the freshly derived values, so a stored copy could only ever be a second, staler truth. Exactly one assessment per transaction: replacing it deletes the old row, and the unique index enforces it.

## 17.10 `documents`

```sql
CREATE TABLE documents (
    id TEXT PRIMARY KEY,
    original_filename TEXT NOT NULL,
    stored_filename TEXT NOT NULL,         -- "<sha256>.<ext>"
    relative_path TEXT NOT NULL,           -- "Documents/6E2….pdf"
    mime_type TEXT,
    sha256 TEXT NOT NULL UNIQUE,
    byte_size INTEGER NOT NULL,
    document_type TEXT,                    -- invoice | receipt | creditNote | statement | contract | other | unknown
    source TEXT NOT NULL,                  -- dragDrop | fileImport | other
    imported_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

Originals are never modified. No BLOB storage in V1.

## 17.11 `transaction_documents`

```sql
CREATE TABLE transaction_documents (
    transaction_id TEXT NOT NULL REFERENCES transactions(id),
    document_id TEXT NOT NULL REFERENCES documents(id),
    role TEXT NOT NULL,                    -- invoice | receipt | creditNote | statement | supportingEvidence | other
    created_at TEXT NOT NULL,
    PRIMARY KEY (transaction_id, document_id)
);
```

## 17.13 `payments`

```sql
CREATE TABLE payments (
    id TEXT PRIMARY KEY,
    direction TEXT NOT NULL,               -- inflow | outflow
    payment_date TEXT NOT NULL,

    original_currency TEXT NOT NULL,
    original_amount_minor INTEGER NOT NULL,       -- positive; direction says which way the money moved
    booked_currency TEXT NOT NULL DEFAULT 'EUR',
    booked_amount_minor INTEGER,
    exchange_rate TEXT,

    counterparty_name_raw TEXT,
    reference TEXT,
    payment_method TEXT,                   -- bankTransfer | card | paypal | directDebit | cash | other | unknown
    source TEXT NOT NULL,                  -- statementLine | manual
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_payments_date ON payments(payment_date);
```

## 17.14 `payment_allocations`

```sql
CREATE TABLE payment_allocations (
    id TEXT PRIMARY KEY,
    payment_id TEXT NOT NULL REFERENCES payments(id),
    transaction_id TEXT NOT NULL REFERENCES transactions(id),
    allocated_minor INTEGER NOT NULL,      -- in payment.booked_currency (EUR)
    currency TEXT NOT NULL DEFAULT 'EUR',
    match_method TEXT NOT NULL,            -- exact | reference | invoiceNumber | heuristic | manual | rule
    created_at TEXT NOT NULL
);
CREATE INDEX idx_payalloc_transaction ON payment_allocations(transaction_id);
CREATE INDEX idx_payalloc_payment ON payment_allocations(payment_id);
```

Invariant: `SUM(allocated_minor) per payment ≤ payment.booked_amount_minor`. Supports partial, combined, statement-first, and invoice-first flows.

Allocation amounts stay positive. A **refund** is a payment in the direction
opposite to the transaction's own (an inflow on an expense, an outflow on an
income); its allocation counts negatively against what the transaction has
settled. The net settled amount may never exceed the booked gross amount nor
fall below zero, so nothing can be given back that was never paid. A payment that is
larger than what the transaction can absorb - a bank fee, an exchange
difference, one transfer for several invoices - is recorded in full with only
the open remainder allocated; the surplus stays unallocated rather than being
refused.

## 17.15 `field_provenance`

Values stay typed in their domain tables; this table records origin per field.

```sql
CREATE TABLE field_provenance (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,             -- transaction | payment | taxAssessment | allocation | taxComponent | counterparty
    entity_id TEXT NOT NULL,
    field_name TEXT NOT NULL,
    provenance TEXT NOT NULL,              -- document | agent | calculated | manual | imported
    is_manual_override INTEGER NOT NULL DEFAULT 0,
    source_document_id TEXT REFERENCES documents(id),
    model_run_id TEXT REFERENCES model_runs(id),
    created_at TEXT NOT NULL,
    superseded_at TEXT
);
CREATE UNIQUE INDEX idx_prov_current ON field_provenance(entity_type, entity_id, field_name) WHERE superseded_at IS NULL;
```

Rule: an operation that would change a field whose current provenance `is_manual_override = 1` is rejected unless the actor is `user`.

The rows belong to the entity they address: deleting a replaced `tax_assessments` row deletes its provenance rows with it, since `entity_id` is not a foreign key and they would otherwise stay behind as unreachable current rows.

## 17.16 `import_batches`

```sql
CREATE TABLE import_batches (
    id TEXT PRIMARY KEY,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    status TEXT NOT NULL,                  -- running | completed | completedWithErrors | cancelled
    file_count INTEGER NOT NULL
);
```

## 17.17 `import_items`

```sql
CREATE TABLE import_items (
    id TEXT PRIMARY KEY,
    batch_id TEXT NOT NULL REFERENCES import_batches(id),
    document_id TEXT REFERENCES documents(id),
    original_filename TEXT NOT NULL,
    status TEXT NOT NULL,                  -- queued | archiving | analyzing | matching | proposed | committed | skipped | duplicate | failed
    error_code TEXT,
    error_message TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_import_items_batch ON import_items(batch_id);
```

## 17.18 `model_runs`

```sql
CREATE TABLE model_runs (
    id TEXT PRIMARY KEY,
    import_item_id TEXT REFERENCES import_items(id),
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    operation TEXT NOT NULL,               -- extraction | disambiguation
    prompt_version TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    request_metadata_json TEXT,            -- no document content, no key
    response_json TEXT,                    -- retained by default for replay tests; configurable
    input_tokens INTEGER, output_tokens INTEGER,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    status TEXT NOT NULL                   -- running | succeeded | failed | timedOut
);
```

## 17.19 `proposals`

The review queue. Persisted before it is shown.

```sql
CREATE TABLE proposals (
    id TEXT PRIMARY KEY,
    import_item_id TEXT REFERENCES import_items(id),
    idempotency_key TEXT NOT NULL UNIQUE,  -- e.g. "<import_item_id>:<prompt_version>"
    kind TEXT NOT NULL,                    -- createTransaction | updateTransaction | attachDocument | mergeDuplicate
    operations_json TEXT NOT NULL,         -- [ProposedOperation]
    summary_json TEXT NOT NULL,            -- what the review card shows
    issues_json TEXT NOT NULL,             -- validation issues at proposal time
    policy_decision TEXT NOT NULL,         -- autoCommit | needsReview | blocked
    status TEXT NOT NULL,                  -- pending | accepted | acceptedEdited | rejected | skipped | superseded | committed
    committed_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_proposals_status ON proposals(status);
```

## 17.20 `validation_issues`

```sql
CREATE TABLE validation_issues (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,             -- transaction | payment | proposal
    entity_id TEXT NOT NULL,
    severity TEXT NOT NULL,                -- info | warning | error
    code TEXT NOT NULL,                    -- stable machine code, e.g. 'TAX_RATE_UNUSUAL', 'ASSET_CANDIDATE'
    message_key TEXT NOT NULL,             -- localization key
    params_json TEXT,
    field_name TEXT,
    status TEXT NOT NULL,                  -- open | resolved | ignored
    created_at TEXT NOT NULL,
    resolved_at TEXT
);
CREATE INDEX idx_issues_entity ON validation_issues(entity_type, entity_id, status);
```

## 17.21 Learned rules

User-visible learned patterns (counterparty defaults, payment-match
patterns) with a
confirmation count and an explicit `auto_apply` flag. Tax-relevant rules
require `confirmation_count >= 3` and explicit user activation before
`auto_apply`. Their table arrives with the milestone that writes them (M8);
until then nothing learns, and the schema stays free of an unused table.

## 17.22 `audit_events`

```sql
CREATE TABLE audit_events (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,                  -- create | update | delete | link | unlink | confirm | correct | lock | unlock
    actor TEXT NOT NULL,                   -- user | agent | system | import
    proposal_id TEXT,
    before_json TEXT,
    after_json TEXT,
    reason TEXT,                           -- required for 'correct' inside locked periods
    created_at TEXT NOT NULL
);
CREATE INDEX idx_audit_entity ON audit_events(entity_type, entity_id);
```

## 17.23 `settings`

```sql
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value_json TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

Holds autonomy capability flags, default model, retention preferences. Never secrets.

## 17.24 Locked periods

A locked UStVA or EÜR period blocks changes to the tax-relevant fields inside
it (invoice date, service date, payment dates, amounts) except via the
explicit correction action, which records a reason in `audit_events`. Locking
arrives as one piece with Milestone 10 - table, enforcement and UI together.
Confirmed transactions stay directly editable until then.

## 17.25 Derived status view

`paymentStatus`, `documentStatus`, and `taxStatus` (see 19) are **not stored**. Provide a SQL view `v_transaction_status` that computes them, so table filters work without denormalization:

```sql
CREATE VIEW v_transaction_status AS
SELECT t.id,
  CASE
    WHEN t.booked_gross_minor IS NULL THEN 'unknown'
    WHEN settled.transaction_id IS NULL THEN 'unpaid'
    WHEN settled.net_allocated = 0 THEN 'refunded'
    WHEN ABS(settled.net_allocated) < ABS(t.booked_gross_minor) THEN 'partiallyPaid'
    ELSE 'paid' END AS payment_status,
  CASE
    WHEN td.doc_count IS NULL AND t.transaction_type IN ('paymentOnly') THEN 'missing'
    WHEN td.doc_count IS NULL THEN 'missing'
    ELSE 'complete' END AS document_status,
  COALESCE(ta.status, 'unknown') AS tax_status
FROM transactions t
LEFT JOIN (SELECT pa.transaction_id, SUM(signed_allocation) AS net_allocated FROM payment_allocations pa JOIN payments p ON p.id = pa.payment_id JOIN transactions tx ON tx.id = pa.transaction_id GROUP BY pa.transaction_id) settled ON settled.transaction_id = t.id
LEFT JOIN (SELECT transaction_id, COUNT(*) AS doc_count FROM transaction_documents GROUP BY transaction_id) td ON td.transaction_id = t.id
LEFT JOIN tax_assessments ta ON ta.transaction_id = t.id
WHERE t.deleted_at IS NULL;
```

`signed_allocation` stands for the allocated amount **signed by direction**:
positive when the payment moves the way the transaction expects (money out on
an expense, money in on an income), negative when it moves back. A refund is
exactly that opposite-direction payment, and a credit note - a transaction
with negative amounts - is settled by one. A transaction without any
allocation has no `settled` row and is `unpaid`; one whose payments cancel out
has a row summing to zero and is `refunded`. The expression lives in
`TransactionQueryRules` and is shared with the UStVA calculation and the write
boundary. The net amount may never leave the range between zero and the booked
gross amount; the repository enforces that when payments are written.

Categories with `document_expected = 0` map to `document_status = 'notRequired'` (handled in Swift or by extending the view in a later migration).

---

# 18. Binding Enums (consolidated)

All string enums are `enum … : String, Codable, CaseIterable, Sendable` in `Domain`, stored as their raw values. Unknown raw values from the database must fail loudly in debug and map to a `.unknown` case in release where one exists.

```text
Direction:              income | expense | unknown
TransactionType:        invoice | receipt | creditNote | paymentOnly | taxPayment | other
WorkflowStatus:         active | archived
ReviewStatus:           unreviewed | needsReview | confirmed | conflict
TaxTreatment:           see 16.1
TaxComponentKind:       standard | reduced | zero | reverseChargeNote | exempt | fee | deposit | other
TaxAssessmentStatus:    proposed | confirmed | manualOverride
CustomerType:           b2b | b2c | unknown
SupplyType:             service | goods | unknown
DocumentType:           invoice | receipt | creditNote | statement | contract | other | unknown
DocumentRole:           invoice | receipt | creditNote | statement | other
DocumentSource:         dragDrop | fileImport | other
PaymentDirection:       inflow | outflow
PaymentMethod:          bankTransfer | card | paypal | directDebit | cash | other | unknown
PaymentSource:          statementLine | manual
MatchMethod:            exact | reference | invoiceNumber | heuristic | manual
Provenance:             document | agent | calculated | manual | imported
ImportBatchStatus:      running | completed | completedWithErrors | cancelled
ImportItemStatus:       queued | archiving | analyzing | matching | proposed | committed | skipped | duplicate | failed
ModelRunOperation:      extraction | disambiguation
ModelRunStatus:         running | succeeded | failed
ProposalKind:           createTransaction | updateTransaction | attachDocument | mergeDuplicate
ProposalStatus:         pending | accepted | acceptedEdited | rejected | skipped | superseded | committed
PolicyDecision:         autoCommit | needsReview | blocked
IssueSeverity:          info | warning | error
IssueStatus:            open | resolved | ignored
AuditActor:             user | agent | system | import
AuditAction:            create | update | delete | link | unlink | confirm | correct | lock | unlock
```

---

# 19. Status Model

A transaction has no single overloaded state. Dimensions:

```text
reviewStatus   (stored):  unreviewed | needsReview | confirmed | conflict
workflowStatus (stored):  active | archived
paymentStatus  (derived): unknown | unpaid | partiallyPaid | paid | refunded
documentStatus (derived): missing | notRequired | complete
taxStatus      (derived): unknown | proposed | confirmed | manualOverride
```

The UI derives one compact display status. Filters use `v_transaction_status`.

---

# 20. Local File Layout

The app creates its archive at `~/Library/Application Support/Pfennig`. An archive created by the earlier Ziffer version is moved there once on launch; nothing is copied or deleted, and if both folders exist the Pfennig one is used. A future explicit move/export workflow may make the archive portable; onboarding does not begin with a folder picker.

```text
Pfennig/
├── bookkeeping.sqlite
├── Documents/
│   ├── 6e2….pdf
│   └── 18f….jpg
├── Exports/
├── Backups/
├── archive.json          — schema version, app version, profile id, created_at
└── README.txt            — human-readable explanation of the layout
```

Database stores relative paths only. Originals are never modified. Documents use SHA-256-based storage names. Thumbnails/previews live in `~/Library/Caches`, not in the archive.

---

# 21. Backup and Portability

Backup = zip of the archive folder with `archive.json` and `schema-version.txt`. The user can open `bookkeeping.sqlite` with standard tools, open all documents independently, export any table as CSV, create and restore a full backup. Schema is documented in `docs/schema.md` and kept in sync by a test that diffs `sqlite_master` against the doc.

---

# 22. Application Architecture

```text
App (XcodeGen target)
├── UI                — SwiftUI, no bookkeeping rules
Packages (SwiftPM):
├── Domain            — pure value types, enums, Money, LocalDate
├── Database          — GRDB, migrations, repositories, observation, v_ views
├── DocumentStore     — archive folder, hashing, copy, integrity, thumbnails
├── ImportPipeline    — coordinator, jobs, proposal builder, commit
├── AI                — Responses API client, schemas, prompts, provider protocol, retries
├── Validation        — deterministic, no network
├── Tax               — treatment decision, tax points, self-assessed VAT, thresholds, versioned form mappings
├── Analysis          — aggregation queries
└── Export            — CSV, backup, later UStVA/EÜR handoff
```

Dependencies flow downward only: UI → ImportPipeline/Analysis/Export → Database/AI/Tax/Validation → Domain. `AI` depends on `Domain` only. `Tax` and `Validation` have no network and no database dependency (they receive values).

---

# 23. Dates

Domain type `LocalDate` (year/month/day, `Comparable`, `Codable` as `YYYY-MM-DD`) for all calendar dates. `Date` only for timestamps (`created_at` etc.). Never midnight-`Date` for calendar concepts. Period helper in `Tax`: `UStVAPeriod(year, month|quarter)`. The fiscal year of a freelancer is the calendar year.

---

# 24. Payment Matching

Open, see 4.2. The scored, rule-based matcher specified here was removed on
2026-09-14 together with the CSV importer; the replacement will be designed
AI-first. Never assume one invoice = one payment: partial and combined
payments produce multiple allocations.

---

# 25. Duplicate Detection

- **Exact:** same SHA-256 → `import_item.status = duplicate`, existing document referenced, no new record.
- **Semantic:** different file, same counterparty + invoice number, or same counterparty + date + gross → proposal `mergeDuplicate` with a warning; never silently discarded.

---

# 26. Review Workflow and Proposals

```swift
struct Proposal: Codable, Sendable {
    let id: UUID
    let importItemID: UUID?
    let idempotencyKey: String
    let kind: ProposalKind
    let operations: [ProposedOperation]
    let summary: ProposalSummary
    let issues: [ValidationIssue]
    let policyDecision: PolicyDecision
}

enum ProposedOperation: Codable, Sendable {
    case createTransaction(TransactionDraft)
    case updateTransaction(id: UUID, changes: [FieldChange])
    case setAllocations(transactionID: UUID, [AllocationDraft])
    case setTaxComponents(transactionID: UUID, [TaxComponentDraft])
    case setTaxAssessment(transactionID: UUID, TaxAssessmentDraft)
    case createPayment(PaymentDraft)
    case linkPayment(paymentID: UUID, transactionID: UUID, amountMinor: Int64, method: MatchMethod)
    case unlinkPayment(allocationID: UUID)
    case attachDocument(transactionID: UUID, documentID: UUID, role: DocumentRole)
    case upsertCounterparty(CounterpartyDraft)
    case setProvenance([ProvenanceEntry])
}
```

Proposals are persisted before display. Accepting (with or without edits) commits all operations in **one** SQLite transaction via the same `CommitService` used by automated modes; only the policy differs. Every commit writes `audit_events` with `proposal_id`.

---

# 27. Review UI

```text
Adobe Systems Software Ireland Ltd
−71,39 EUR · Software-Abo

[Belegvorschau]

Rechnungsnummer     IEIN123456
Rechnungsdatum      31.08.2026
Leistungszeitraum   01.08.–31.08.2026
Zahlung             02.09.2026 · Geschäftskonto (Vorschlag, 92 %)
Steuer              Reverse Charge · selbst berechnete USt 13,56 € · Vorsteuer 13,56 €
Kategorie           Software-Abonnements (Regel)

⚠ Leistungsdatum fehlt

[Bestätigen ⏎] [Bearbeiten E] [Überspringen S] [Vorschau ␣]
```

Provenance badges per field (Beleg / KI / Berechnet / Manuell / Regel). Keyboard-first batch review. Native macOS conventions.

---

# 28. Overview

Use the compact Start overview described in section 6. Do not add a second analysis screen or decorative charts. Recorded gross overview figures remain distinct from tax-report contributions.

---

# 29. Tax Preparation

Proposed task-specific window or sheet, not another permanent dashboard. Current scope and acceptance criteria are in the [product backlog](docs/backlog.md) and [workflow research](docs/research-user-workflow.md).

- **UStVA preparation first:** choose period, resolve concrete exceptions, inspect verified year-specific Kennzahlen and their source transactions/payments, copy values and export a traceable report.
- **VAT per period:** own output VAT plus self-assessed liability minus eligible input VAT deductions. Kleinunternehmer reverse charge has no matching input VAT deduction.
- **EÜR preparation:** payment-based contributions mapped to verified year-specific positions, with private/non-deductible shares, VAT payments/refunds and asset exceptions handled explicitly.
- **Completeness:** unresolved material cases remain visible; partial preparation is an explicit draft, not a completed declaration.
- **Later:** applicable deadlines and period locking after useful reporting exists. Export must never automatically mark a period as submitted or locked.

---

# 30. Tax Submission Strategy

Correct period-specific contributions → verified form-year mappings → user-driven handoff. Provide copyable values and a traceable report first. Investigate a local UStVA XML file for manual Mein ELSTER upload early, as a bounded separate feasibility test without manufacturer registration. Public upload instructions exist, but current Pfennig-generated XML has not been validated; analogous EÜR file import is unverified. No direct ERiC transmission, hosted gateway or taxpayer-certificate handling. UStVA preparation is not the annual VAT return; EÜR is not the complete income-tax return.

---

# 31. Security and Privacy

Required: API key in Keychain; no plaintext secrets; model has no database access; originals local; user controls deletion; database and archive inspectable; document transmission to OpenAI is an explicit, documented product assumption shown at onboarding.

Later: optional database/archive encryption, log redaction, privacy mode, configurable `model_runs.response_json` retention (default: keep, for replay tests).

---

# 32. Logging

`os.Logger` with subsystems per module. Never log API keys, secrets, or full document contents. Fields: importBatchID, importItemID, documentID, transactionID, proposalID, operation, duration, model, status, errorCode.

---

# 33. Error Handling

The app is fully usable offline for existing data. If analysis fails: keep the document, mark item `failed` with code, allow retry, allow manual record creation. Network failure never corrupts local state. Rate limits use exponential backoff with jitter; max 3 attempts per item.

---

# 34. Idempotency

- Document identity: sha256.
- Proposal identity: `idempotency_key = "<import_item_id>:<prompt_version>"`; re-running analysis supersedes the old pending proposal rather than adding a second.
- Commit: inside one SQLite transaction; `proposals.status = committed` set in the same transaction.
- Restart: items in `analyzing|matching` are re-queued; any `model_runs` row with `running` is marked `timedOut`.

---

# 35. Build and Development Setup

## 35.1 Layout

```text
Repo/
├── project.yml                 ← XcodeGen source of truth for the app target
├── Package.swift               ← all non-UI modules as SwiftPM targets
├── Pfennig.xcodeproj/          ← generated, git-ignored
├── App/                        ← app target sources (SwiftUI), Info.plist, entitlements, assets
├── Sources/                    ← SwiftPM module sources (see 37)
├── Tests/                      ← Swift Testing
├── Fixtures/                   ← synthetic documents + expected extractions + recorded model responses
├── scripts/
│   ├── bootstrap.sh            ← brew install xcodegen, swiftformat; xcodegen generate
│   ├── build.sh                ← xcodebuild -project … -scheme Pfennig -configuration Debug build
│   ├── run.sh                  ← builds and opens the .app
│   ├── test.sh                 ← swift test (packages) + xcodebuild test (app target if UI tests)
│   └── lint.sh
└── docs/
    ├── schema.md
    └── privacy.md
```

## 35.2 Binding settings

- **macOS 15.0** deployment target
- **Swift 6 language mode**, strict concurrency `complete`
- **Swift Testing** for unit/integration tests; XCTest only for future UI tests
- SwiftFormat (or swift-format) with committed config
- Bundle identifier, Info.plist, entitlements (`keychain-access-groups` not needed for the default app keychain; no sandbox in V1) live in `project.yml`
- Debug builds are signed with the developer's "Apple Development" identity if available, else ad-hoc; the **bundle identifier is stable** so Keychain items survive rebuilds
- Normal workflow: `scripts/bootstrap.sh` once, then `scripts/build.sh`, `scripts/test.sh`. Xcode GUI only for signing/notarization troubleshooting.

## 35.3 Why not pure `swift build`

`swift build` produces a bare executable without an app bundle: no Info.plist, no icon, no stable code identity for the Keychain, no entitlements. Core modules still build and test with `swift build` / `swift test`; only the app shell needs `xcodebuild`.

---

# 36. Dependencies

- `GRDB.swift` (SQLite)
- Everything else: Apple frameworks (PDFKit, ImageIO, Vision not needed in V1, Swift Charts, os.Logger, Security).
- Dev tools: XcodeGen, SwiftFormat.

`Decimal` ↔ database conversion is done explicitly by `Money` and decimal-string helpers; do not rely on GRDB's default `Decimal` handling.

---

# 37. Source Layout

```text
App/
├── BookkeepingApp.swift
├── AppEnvironment.swift
├── RootView.swift
├── Sidebar/ · Transactions/ · Accounts/ · Review/ · Analysis/ · Taxes/ · Settings/ · Onboarding/
└── Resources/ (Localizable.xcstrings, Assets)

Sources/
├── Domain/          Money.swift · CurrencyCode.swift · LocalDate.swift · Enums.swift · Transaction.swift ·
│                    Payment.swift · Document.swift · TaxAssessment.swift · TaxComponent.swift ·
│                    BookkeepingAllocation.swift · Counterparty.swift · Category.swift · Proposal.swift ·
│                    ProposedOperation.swift · ValidationIssue.swift · Provenance.swift
├── Database/        AppDatabase.swift · Migrations/ (v001_initial.swift …) · Records/ · Repositories/ · Views.swift · Seed/
├── DocumentStore/   ArchiveLocator.swift · DocumentStore.swift · FileHasher.swift · ThumbnailService.swift
├── ImportPipeline/  ImportCoordinator.swift · ImportJob.swift ·
│                    ProposalBuilder.swift · ReviewPolicy.swift · CommitService.swift
├── AI/              DocumentIntelligenceProvider.swift · OpenAIResponsesClient.swift · ExtractionSchema.swift ·
│                    DisambiguationSchema.swift · Prompts/ · PromptVersion.swift ·
│                    DocumentPreparer.swift (HEIC→JPEG, PDF paging) · RecordingProvider.swift (fixtures)
├── Validation/      TransactionValidator.swift · MoneyValidator.swift · TaxValidator.swift · AllocationValidator.swift · IssueCodes.swift
├── Tax/             TaxTreatmentDecider.swift · Periods.swift · SelfAssessedVAT.swift · Thresholds.swift ·
│                    FormMappings/UStVA_2026.swift · FormMappings/EUeR_2026.swift
├── Analysis/        StartOverview.swift · UStVACalculator.swift · UStVATasks.swift · SubmittedReturns.swift
└── Export/          UStVAValueList.swift · UStVAXMLExporter.swift · UStVAPeriodText.swift
```

---

# 38. First Vertical Slice

Drop one invoice PDF into the app and end with a confirmed transaction in SQLite.

1. Launch native app (`.app` bundle from XcodeGen project)
2. Onboarding: initialize the local archive, business profile, API key into Keychain
3. Empty transaction table
4. PDF drag-and-drop → copy to `Documents/`, SHA-256
5. Extraction call (strict Structured Output), `model_runs` row
6. Normalize → tax treatment decision → tax components → allocation → tax assessment
7. Proposal persisted, validation run, shown in the review UI
8. Manual edit of one field (provenance `manual`)
9. Confirm → one SQLite transaction writes transaction, allocations, components, assessment, document link, provenance, audit
10. Transaction visible in main table; app restart shows persisted data
11. Re-run AI on the same document: no duplicate, manual field untouched

No analytics or tax exports before this works reliably.

---

# 39. Implementation Order

Historical milestone outline, not a current implementation checklist. The [status](docs/status.md) records what actually exists, and the [backlog](docs/backlog.md) supersedes this ordering and any broader deferred feature suggestions below.

**M0 — Repository foundation:** `Package.swift` with all modules, `project.yml`, scripts, Swift 6/strict concurrency, Swift Testing skeleton, `Money`/`LocalDate`, all enums, CI optional.

**M1 — Local shell:** onboarding (archive picker, profile), `NavigationSplitView`, table, inspector placeholder, settings, no AI.

**M2 — Storage:** GRDB, `v001_initial` with the schema from 17 (including proposals and provenance), views, seed categories, sample data, repositories, migration tests. Tables arrive with the milestone that writes them.

**M3 — Manual bookkeeping:** create/edit transaction, allocations, tax components, tax assessment, attach document, add/link payment manually, validation, provenance on manual edits, audit, save/reload.

**M4 — AI invoice import:** Keychain, Responses client, extraction schema, document preparer, proposal persistence, review UI, commit path, recording provider for fixtures.

**M5 — Batch import:** multiple files, background processing, review queue, error/retry states, exact + semantic duplicate detection.

**M6 — Accounts and statements:** open, see 4.2.

**M7 — Tax cases:** reverse charge with self-assessed VAT, intra-community acquisition, export, foreign currency with rate sources, mixed-rate components, Kleinbetrag rule, asset flag, 10-day rule warning, credit notes/refunds via relations.

**M8 — Autonomy:** capability flags, presets, rules with confirmation counts, auto-commit path, locked-period enforcement.

**M9 — Analysis:** monthly income/expenses on EÜR basis, VAT overview per period, incomplete transactions, unpaid revenue.

**M10 — Tax preparation:** `UStVA_2026` and `EUeR_2026` mappings, copy/export workflow, period lock UI, deadlines.

---

# 40. Testing Strategy

## 40.1 Unit tests (mandatory)

Money arithmetic and rounding; VAT and self-assessed VAT; period dating for every treatment × direction case; 10-day rule window; Kleinbetrag relaxation; asset threshold; payment allocation invariants; state transitions; duplicate detection; validation codes; the schema shape a fresh database creates (after the first public release, also the upgrade from every released schema version); provenance protection of manual fields.

## 40.2 Fixture-based AI tests

`Fixtures/documents/` holds 50–100 **synthetic** documents (generated, no real personal data) with `expected.json` per fixture and a **recorded** `response.json` from `model_runs`. A `RecordingProvider` replays recorded responses so the full pipeline (normalize → tax → match → validate → commit) runs offline in CI. A separate, opt-in live test suite re-records against the real API to detect model/prompt drift. Do not assume a newer model is better.

## 40.3 Integration tests

Invoice first, payment later · payment first, invoice later · exact duplicate PDF · semantic duplicate · partial and combined payments · USD invoice paid in EUR with fee · mixed 7/19 receipt · reverse charge expense · reverse charge income without VAT ID · manual override then AI rerun · failed model request · crash mid-import and restart · edit inside locked period.

---

# 41. Prompting Principles

Extraction system prompt emphasizes: extract only supported facts; never invent; distinguish observed from inferred; preserve original currency and exact decimal strings; determine direction relative to the supplied business profile; identify document type; give a tax-treatment **hint**, not a decision; return `missingFields` explicitly; produce only schema-valid output; use canonical category IDs from the supplied list or null.

Prompts are versioned (`prompt_version`) and stored in `AI/Prompts/` as resources; changing a prompt requires re-running the fixture suite.

---

# 42. Context Supplied to the AI

Extraction: business profile (name, VAT ID, country, VAT status, accounting method), list of canonical category IDs with one-line German/English descriptions, list of supported treatments. **No transaction data.**

Disambiguation: the payment (date, amount, reference, counterparty raw) and ≤ 5 candidates (id, counterparty, open amount, invoice date, invoice number). Nothing else.


---

# 43. Rules and Learned Patterns

Confirmed behavior becomes a visible, editable rule (e.g., counterparty Adobe → category software_subscriptions, treatment reverseCharge). Rules show their confirmation count and whether they auto-apply. Nothing hidden is learned. Tax-relevant rules have stricter activation (17.21).

---

# 44. Manual Editing Rules

A manual value replaces the active value, records provenance `manual` with `is_manual_override = 1`, writes an audit event, is protected from AI overwrite, and must still pass hard validation. Users can ignore soft warnings (issue status `ignored`, audited). Structurally impossible states cannot be committed; a labelled "Ausnahme erzwingen" path exists only for hard validations explicitly marked overridable in `IssueCodes` (none in V1 except tolerance mismatches ≤ 1 EUR).

---

# 45. Search and Filters

Search: counterparty, title, invoice number, amount (both formats), date; document full text later. No AI for search.

Filters: date range (by relevant date, invoice date, or payment date), income/expense, payment status, document status, review status, tax treatment, category, account, asset flag, missing document, missing payment.

---

# 46. Performance and Indexes

Instant local browsing; never call the model to render a screen; never require network for existing data; AI and import off the main actor; progressive import state. Indexes are listed inline in 17; add more only when query patterns are measured.

---

# 47. Data Migration Policy

Before the first public release there is exactly one schema definition, `v001_initial`, and no forward migrations, compatibility shims or dual-format readers. A schema change edits that definition and rewrites the existing development archive and fixtures once, so they carry the current shape rather than legacy leftovers. Archives and test data are still never deleted or reset; the rewrite converts them in place and keeps a backup.

After the first public schema ships, every schema change is a numbered GRDB migration (`v002_…`). Migration tests upgrade fixture databases from each released schema version. `archive.json` records the schema version; opening a newer archive with an older app is refused with a clear message.

---

# 48. Open Source Considerations

Schema docs, privacy docs (what exactly is sent to OpenAI and when), provider abstraction, standard data formats, no hosted infrastructure, synthetic fixtures only, no real invoices or keys in the repository.

---

# 49. Definition of MVP

The user can: launch without an account · use a local archive · configure the business profile and accounts · enter an OpenAI API key · drop invoices/receipts · have information extracted · review/edit/confirm proposals · see transactions in a native table · attach documents · record payments manually · handle reverse charge, foreign currency, and mixed-rate documents correctly · persist and restart without loss · inspect and edit all material values · export CSV and create/restore a full backup.

Analysis and tax preparation are the next layer.

---

# 50. Product North Star

```text
Drop documents.
Review exceptions.
Be done.
```

The AI removes clerical work. The deterministic domain layer maintains correctness. The user is the final authority.

---

# 51. Key Architecture Decisions (V2)

Do not revisit unless implementation evidence proves them wrong:

- macOS native, macOS 15+, Swift 6 strict concurrency, SwiftUI
- Local-first, no backend, no user account
- SQLite (GRDB) canonical; ordinary files for documents; no BLOBs
- Local archive in Application Support by default; open, inspectable formats and future portable move/export
- All money as Int64 minor units; non-monetary decimals as canonical strings; never floating point
- Transaction-first; documents, payments, allocations, tax components, assessments are separate entities
- Bookkeeping allocations replace a single category; canonical categories with stable IDs; no SKR numbers in core
- Separate tax points (EÜR, output VAT, input VAT); self-assessed VAT computed by Swift
- Form mappings (UStVA/EÜR) versioned in the Tax module, not in the schema
- Field provenance and proposals in the initial schema
- OpenAI Responses API with strict Structured Outputs; user-provided key in Keychain
- V1 AI = single-shot extraction + optional disambiguation; no function calling
- Manual editing always possible; manual values never overwritten by AI
- One automation level (Manuell/Ausgewogen/Automatisch) in `settings`; default Manuell; one deterministic decision function
- No primary chat UX; no direct ELSTER; no DATEV in V1
- XcodeGen project + SwiftPM modules; CLI-first; Xcode GUI only for release edge cases

---

# 52. Implementation Status

The original repository-bootstrap task is complete. The app target and scheme are named `Pfennig`; current implementation state and next priorities are maintained in [`docs/status.md`](docs/status.md) and GitHub Issues.

---

# 53. Reference Links

- OpenAI Responses API, file inputs, Structured Outputs: https://developers.openai.com/api/docs/guides/structured-outputs · https://developers.openai.com/api/docs/guides/file-inputs
- OpenAI data controls: https://developers.openai.com/api/docs/guides/your-data
- Apple SwiftUI Table: https://developer.apple.com/documentation/swiftui/table
- Apple PDFKit: https://developer.apple.com/documentation/pdfkit
- GRDB.swift: https://github.com/groue/GRDB.swift
- XcodeGen: https://github.com/yonaskolb/XcodeGen
- §11 EStG (Zufluss/Abfluss): https://www.gesetze-im-internet.de/estg/__11.html
- §6 EStG (GWG): https://www.gesetze-im-internet.de/estg/__6.html
- §13 UStG (Entstehung der Steuer): https://www.gesetze-im-internet.de/ustg_1980/__13.html
- §13b UStG (Reverse Charge): https://www.gesetze-im-internet.de/ustg_1980/__13b.html
- §15 UStG (Vorsteuerabzug): https://www.gesetze-im-internet.de/ustg_1980/__15.html
- §16 UStG (Umrechnung): https://www.gesetze-im-internet.de/ustg_1980/__16.html
- §18a UStG (ZM): https://www.gesetze-im-internet.de/ustg_1980/__18a.html
- §20 UStG (Ist-Versteuerung): https://www.gesetze-im-internet.de/ustg_1980/__20.html
- §33 UStDV (Kleinbetragsrechnung): https://www.gesetze-im-internet.de/ustdv_1980/__33.html
- ELSTER developer information: https://www.elster.de/eportal/infoseite/entwickler

---

# 54. Final Note for Implementation

Prefer the actual workflow over a new generic abstraction. Prefer a deterministic Swift invariant over another model decision. Prefer inspectable standard formats over proprietary structures. The app must remain understandable and usable without the AI layer.
