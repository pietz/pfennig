# AI-Native Bookkeeping for macOS
## Product & Technical Specification — Version 2

**Status:** Implementation spec (V2, supersedes V1)  
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
- It proposes links between invoices, receipts, payments, credit notes, and statements.
- It asks for human confirmation only where required by the configured autonomy level.
- The user can always manually inspect and edit the underlying bookkeeping data.

The app should feel like a polished native Mac application, not like a chatbot with bookkeeping features attached.

---

# 2. Scope

## 2.1 Primary target user (V1)

- Freelancer / Freiberufler in Germany; Einzelunternehmer as close adjacent case
- One business activity
- EÜR (Einnahmenüberschussrechnung), not balance-sheet accounting
- VAT liable, `Ist-Versteuerung` (§20 UStG)
- Primarily B2B services, some B2C possible
- Typical expenses: office, software/SaaS, advertising, hardware, professional services, telecom, travel
- Domestic, EU, and third-country invoices in multiple currencies
- Several payment accounts (bank account, credit card, PayPal, cash), imported via statement files, no bank API

## 2.2 Must not be blocked by the data model (later)

- Kleinunternehmer (§19 UStG)
- Soll-Versteuerung
- Multiple business activities
- Zusammenfassende Meldung (ZM, §18a UStG)
- DATEV export
- iCloud sync / multi-device
- Direct or semi-direct ELSTER workflows
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
- Deductibility rules of §4 Abs. 5 EStG (Bewirtung 70 %, Geschenke, etc.) — only a free `deductibility_note`
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
- one tax assessment (treatment, tax points, self-assessed VAT)
- field-level provenance
- validation issues
- relations to other transactions (credit notes, refunds, corrections)
- review state

Worked example used throughout this spec:

```text
Adobe Systems Software Ireland Ltd · Expense · 71.39 EUR
├── Document: adobe-2026-08.pdf (invoice, sha256 6E2…)
├── Invoice 2026-08-31, invoice no. IEIN123456, net 71.39 EUR, VAT 0.00
├── Tax assessment: reverseCharge, taxable base 71.39, self-assessed VAT 13.56, deductible input VAT 13.56
├── Bookkeeping allocation: software_subscriptions 71.39 EUR
├── Payment: 2026-09-02 -71.39 EUR from account "Geschäftskonto" (statement line fingerprint 8a1…)
└── Provenance: invoice fields = document; treatment = agent (0.93); category = rule
```

A transaction may exist before all evidence is available (statement first, invoice later; invoice first, payment later).

## 4.2 Statement lines are not transactions

A statement line is a fact about an account ("on 2026-09-02, -71.39 EUR left account X"). Only lines classified as **business** create a payment and, if needed, a transaction. Private transfers, internal transfers between own accounts, and income-tax prepayments stay outside the business transaction list but remain stored and visible under the account.

## 4.3 Deterministic core

Any rule that can be expressed as an invariant in Swift is expressed in Swift, not delegated to the model.

---

# 5. German Bookkeeping Rules Implemented in V1

This section is authoritative for the `Tax` and `Validation` modules. It is deliberately limited to the common freelancer cases.

## 5.1 Separate tax points

Do not collapse dates. Each transaction can carry:

| Concept | Field | Meaning |
|---|---|---|
| Invoice date | `invoice_date` | Date on the document |
| Service date | `service_date` / `service_period_start/end` | When the service was performed |
| Payment date(s) | `payments.payment_date` | Actual cash movement per payment |
| EÜR date | derived `eur_date` | Date the amount counts for income tax (§11 EStG, cash basis) |
| Output VAT point | derived `output_vat_date` | Date output VAT becomes due |
| Input VAT point | derived `input_vat_date` | Date input VAT becomes deductible |

Derivation rules for a profile with `vat_accounting_method = cash`:

- **EÜR date** = payment date (Zufluss/Abfluss, §11 EStG). Partially paid transactions contribute per allocation on each payment date.
- **Output VAT** (income): due in the period of payment receipt (§13 Abs. 1 Nr. 1 b UStG, Ist-Versteuerung). Per payment allocation.
- **Input VAT** (expense, normal case): deductible when the service has been performed **and** a proper invoice is on hand (§15 Abs. 1 Nr. 1 UStG). V1 derives `input_vat_date = max(service_date ?? invoice_date, invoice_date)`; user override allowed. Payment date is irrelevant, except:
  - **Advance payment before service/invoice:** deductible when paid and invoice on hand → `input_vat_date = max(payment_date, invoice_date)` if `is_advance_payment`.
- **§13b reverse charge (expense):** tax arises at the end of the month in which the invoice is issued, at the latest the month following service (§13b Abs. 1/2 UStG). V1 uses `invoice_date` for both the self-assessed VAT and the matching input VAT deduction. User override allowed.
- **Intra-community acquisition of goods:** same rule as reverse charge (§13 Abs. 1 Nr. 6 UStG) in V1.

Both derived dates are stored on `tax_assessments` as materialized values with provenance `calculated` so they are queryable and overridable.

## 5.2 The "Date" column

The main table shows a **relevant date** derived as: EÜR date if any payment exists, otherwise invoice date, otherwise import date. It is labelled and its origin is visible in the inspector.

## 5.3 10-day rule (§11 Abs. 2 S. 2 EStG)

Regularly recurring expenses/income paid within 10 days before or after the year boundary belong to the year they economically relate to. V1 does **not** re-assign automatically; it raises a **soft warning** for payments between 22 Dec and 10 Jan on transactions whose counterparty has a recurring pattern, and lets the user set `eur_year_override`.

## 5.4 Reverse charge and self-assessed VAT

For treatments `reverseCharge` and `intraCommunityAcquisition` on expenses, the recipient owes VAT and (for a fully VAT-liable business) deducts it as input VAT in the same period:

```text
taxable_base_minor      = 7139   (71.39 EUR)
self_assessed_vat_minor = 1356   (19 % of base, rounded half-up to cent)
deductible_input_vat_minor = 1356
invoice tax shown        = 0
```

The document's own `tax_amount` is 0; `self_assessed_vat` is computed by Swift, never by the model. Rate defaults to the German standard rate applicable at `input_vat_date`.

For **income** with `reverseCharge` (EU B2B service to a customer with a valid VAT ID): no VAT charged, `customer_vat_id` required (soft warning if missing). ZM reporting is a future feature; V1 only tags these transactions so they can be reported later.

## 5.5 Kleinbetragsrechnung (§33 UStDV)

For expense documents with gross ≤ 250.00 EUR, a missing invoice number, missing customer address, and missing separate net/tax breakdown are **not** issues, provided gross amount and tax rate are present. Exceptions of §33 (e.g., intra-community supplies, §13b) still require full invoices — if treatment is not `domesticVAT`, the relaxation does not apply.

## 5.6 Assets (GWG threshold)

V1 has no depreciation. It must detect and warn:

- An expense allocation with category kind `asset_candidate` **or** any single-line expense with net > 800.00 EUR in a hardware/equipment category gets `asset_flag = true` and a **soft warning**: "Möglicherweise Anlagevermögen – nicht vollständig als Betriebsausgabe abzugsfähig."
- Allocations flagged as asset are excluded from EÜR operating-expense totals and listed separately as "Anlagegüter (manuell prüfen)". The user can clear the flag.
- Threshold (currently 800 EUR net, §6 Abs. 2 EStG) is a configuration constant in the Tax module, not hard-coded in validation.

## 5.7 Foreign currency (§16 Abs. 6 UStG)

Converted amounts may use the actual bank rate (payment amount in EUR) or the BMF monthly average rate. V1 stores both original and EUR amounts and an `exchange_rate_source`:

```text
bankActual      — EUR amount taken from the statement line
bmfMonthly      — user-entered BMF rate
manual          — user-entered rate or amount
documentStated  — invoice itself states an EUR equivalent
unknown
```

The user chooses the authoritative EUR amount; default is `bankActual` when a payment is linked, otherwise `documentStated`, otherwise missing.

## 5.8 Tax payments and private movements on statements

- **VAT payments to / refunds from the Finanzamt** are business transactions (Betriebsausgabe/-einnahme in the EÜR, `transaction_type = taxPayment`, category `vat_payment` / `vat_refund`).
- **Income-tax and solidarity-surcharge prepayments** are private (statement line class `private`, subclass `incomeTax`).
- **Internal transfers** between own accounts are `internalTransfer` and create no transaction.
- **Bank fees** are business expenses that legitimately have no invoice; category `bank_fees` sets `document_expected = false`.

## 5.9 GoBD posture

The app does not claim GoBD compliance. It supports the underlying practices: originals are immutable, every change is audited, and periods can be locked (see 17.24). Edits inside a locked period require an explicit "Korrektur" action that records the reason.

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

UI language: **German first**, fully localizable from day one (String Catalog). Code, schema, identifiers, enums: English. Numbers, currencies, dates: locale-aware via `FormatStyle`.

## 6.2 Main transaction table

Initial columns: Counterparty/Title · Relevant date · Amount (booked EUR; original shown secondary if different) · Payment status · Tax treatment · Status.

Later configurable columns: categories, invoice number, document completeness, currency, review state, account.

## 6.3 Accounts view

Per account: statement lines with classification, balance if derivable, unmatched business lines, and import history. This is where private/internal lines live.

## 6.4 Inspector

For a selected transaction: document preview (PDFKit / image), transaction fields, invoice fields, bookkeeping allocations, tax components and assessment (with derived tax points and their origin), payments and allocations, attached documents, relations, validation issues, missing information, provenance/audit (expandable), actions.

Actions: Confirm · Edit · Attach document · Add payment · Link payment · Unlink · Split allocation · Add relation (credit note/refund) · Re-run AI analysis · Mark asset / clear asset flag · Archive · Resolve/ignore warning.

Every material field is manually editable; manual values carry provenance `manual` and are never overwritten by the AI.

---

# 7. Import UX

## 7.1 Drag and drop

Files can be dropped nearly anywhere in the main window. Supported inputs V1: PDF, JPG/JPEG, PNG, HEIC (converted locally), XML (XRechnung/ZUGFeRD), CSV (statements), plain-text statements.

## 7.2 Import batch

Dropping one or more files creates an import batch. For multiple documents, never show a chain of modal dialogs; create a **review queue**:

```text
12 vorgeschlagene Änderungen
8 bereit · 3 prüfen · 1 Konflikt
```

The queue is persisted (see 17.19) and survives restarts.

---

# 8. AI Interaction Model

## 8.1 No primary chat interface

The application communicates through filled/partially filled records, highlighted missing fields, warnings, proposals, and the review queue. A contextual free-text field may come later.

## 8.2 Missing information is a valid state

Never force the model to invent values. `null` and `unknown` are first-class.

UI distinguishes: known & validated · AI-proposed · missing · suspicious · invalid.

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

# 9. Autonomy Levels

Default is **Manual**. Levels are presets over capability flags:

```text
autoAttachDocument
autoCreateTransaction
autoLinkPayment
autoNormalizeCounterparty
autoSetCategory
autoSetTaxTreatment
autoMarkPaid
autoClassifyStatementLine
```

| Level | Behaviour |
|---|---|
| Manual | Every AI mutation is confirmed by the user. |
| Conservative | Low-risk organizational actions auto-commit (normalize names, attach identical documents, dedupe). Tax-relevant and financial changes require confirmation. |
| Balanced | Patterns confirmed ≥ 3 times (rule with `auto_apply = true`) may auto-commit: recurring vendor, known category, known payment match. Material tax changes and unusual cases require review. |
| Automated | Broader auto-commit; hard validation failures always block; destructive operations always guarded; tax treatments outside supported patterns always reviewable. |

Changes within a **locked period** always require review regardless of level.

---

# 10. AI Architecture

## 10.1 Provider

V1 uses the **OpenAI Responses API** directly with strict Structured Outputs. No agent framework. A small explicit orchestration layer in Swift. Provider is behind a protocol:

```swift
protocol DocumentIntelligenceProvider: Sendable {
    func extract(document: PreparedDocument, context: ExtractionContext) async throws -> DocumentExtraction
    func disambiguate(_ request: DisambiguationRequest) async throws -> DisambiguationResult
    func inferStatementColumnMapping(sample: StatementSample) async throws -> StatementColumnMapping
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

## 10.3 Statement CSV handling

CSV statement content is **not** sent line by line to the model. For an unknown format the AI receives header + up to 5 sample rows and returns a `StatementColumnMapping` (date column, amount column(s), sign convention, decimal separator, reference/counterparty columns, encoding hints). The mapping is stored as a rule keyed by header fingerprint; all lines are parsed deterministically. Known formats are shipped as built-in mappings (initial set: Sparkasse/Volksbank CAMT-CSV, DKB, N26, ING, comdirect, PayPal activity CSV, Stripe payouts CSV).

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
  ↓ [statement?] → parse lines → fingerprint → classify → payments
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
  "counterparty": {
    "name": "Adobe Systems Software Ireland Limited",
    "countryCode": "IE",
    "vatId": "IE6364992H",
    "street": null, "postalCode": null, "city": null
  },
  "invoice": {
    "invoiceNumber": "IEIN123456",
    "invoiceDate": "2026-08-31",
    "serviceDate": null,
    "servicePeriodStart": "2026-08-01",
    "servicePeriodEnd": "2026-08-31",
    "currency": "EUR",
    "netAmount": "71.39",
    "taxAmount": "0.00",
    "grossAmount": "71.39",
    "statedEurEquivalent": null
  },
  "taxComponents": [
    { "rate": "0", "netAmount": "71.39", "taxAmount": "0.00", "kind": "reverseChargeNote" }
  ],
  "taxTreatmentHint": { "treatment": "reverseCharge", "confidence": 0.93, "reasoning": "Irish supplier, German VAT ID on invoice, 'VAT reverse charged' note" },
  "lineItems": [
    { "description": "Creative Cloud All Apps", "netAmount": "71.39", "categoryHint": "software_subscriptions", "assetCandidate": false }
  ],
  "paymentInfo": { "paymentMethodHint": "creditCard", "paidIndicator": "paid", "paymentDate": null, "iban": null, "reference": null },
  "missingFields": ["serviceDate"],
  "warnings": []
}
```

Rules: `taxTreatmentHint` is a hint; Swift decides the treatment using profile + counterparty country + VAT IDs + hint. `categoryHint` values must be from the canonical category enum or null. Never rely on confidence alone.

---

# 14. Deterministic Validation

## 14.1 Hard validations (block commit)

- Malformed currency code; amount not representable in minor units
- Impossible dates; service period end < start
- `sum(taxComponents.net) ≠ invoice.net` or `sum(taxComponents.tax) ≠ invoice.tax` beyond tolerance (default 0.02 EUR)
- `net + tax ≠ gross` beyond tolerance
- `sum(bookkeeping_allocations.amount) ≠ booked net amount` (or gross for non-deductible cases) beyond tolerance
- Payment allocation total exceeds payment amount
- Linked IDs do not exist; unsupported state transition
- Duplicate immutable document identity (sha256)
- Duplicate statement line fingerprint on the same account
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
- Business statement line with no matching document after 60 days
- Amount > configurable threshold with `agent` provenance only

## 14.3 UI convention

Yellow = suspicious/incomplete/needs review · Red = invalid/blocked · Neutral = incomplete but acceptable · Green = validated/confirmed. Never color alone; always icon + text.

---

# 15. Money and Currency Model

## 15.1 Storage

All monetary amounts are **`Int64` minor units** with an explicit ISO-4217 currency code; the exponent comes from a currency table in `Domain` (EUR 2, USD 2, JPY 0, …). SQLite `SUM` over minor units is exact.

Exchange rates, tax rates, and confidences are non-monetary decimals stored as canonical decimal **TEXT** (`"0.9214"`, `"19"`); never `REAL` for anything that feeds bookkeeping.

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
smallBusiness              — §19 (reserved, not used in V1)
unknown
```

## 16.2 Tax components vs tax assessment

- **`tax_components`**: what the document shows, per rate: rate, net, tax, kind (`standard`, `reduced`, `zero`, `reverseChargeNote`, `exempt`, `fee`, `deposit`, `other`). A Deutsche Bahn ticket has a 7 % and a 19 % component; a hotel invoice has 7 % (lodging) and 19 % (breakfast).
- **`tax_assessments`**: the single bookkeeping judgement per transaction: treatment, taxable base, VAT shown, self-assessed VAT, deductible input VAT, tax country, customer/supply type, derived tax points, status, reasoning.

## 16.3 Form mappings live outside the core schema

UStVA Kennzahlen (e.g., 46/47/67 for §13b, 66 for input VAT, 81/86 for domestic sales) and EÜR line numbers change by form year. They are implemented as **versioned mapping tables in the Tax module**:

```text
Tax/FormMappings/UStVA_2026.swift   — treatment × direction × rate → Kennzahl
Tax/FormMappings/EUeR_2026.swift    — category_id → EÜR line
```

The core schema stores only stable semantics (treatment, rate, category ID, tax points).

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
    fiscal_year_start_month INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

V1 supports exactly one profile; the column exists on other tables for later multi-activity support.

## 17.2 `accounts`

```sql
CREATE TABLE accounts (
    id TEXT PRIMARY KEY,
    business_profile_id TEXT NOT NULL REFERENCES business_profiles(id),
    name TEXT NOT NULL,                    -- "Geschäftskonto", "PayPal", "Kreditkarte"
    kind TEXT NOT NULL,                    -- bank | creditCard | paypal | stripe | cash | other
    currency TEXT NOT NULL DEFAULT 'EUR',
    iban TEXT,
    last4 TEXT,
    is_business INTEGER NOT NULL DEFAULT 1,
    statement_mapping_rule_id TEXT REFERENCES rules(id),
    archived_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

A card that settles against the bank account is its own account; the settlement line on the bank statement is classified `internalTransfer`.

## 17.3 `counterparties`

```sql
CREATE TABLE counterparties (
    id TEXT PRIMARY KEY,
    normalized_name TEXT NOT NULL,         -- lowercased, legal-form-stripped, whitespace-collapsed
    display_name TEXT NOT NULL,
    country_code TEXT,
    vat_id TEXT,
    street TEXT, postal_code TEXT, city TEXT,
    default_category_id TEXT REFERENCES categories(id),
    default_tax_treatment TEXT,
    aliases_json TEXT,                     -- JSON array of raw names seen on statements/documents
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_counterparties_normalized ON counterparties(normalized_name);
```

## 17.4 `categories`

Canonical bookkeeping categories with stable IDs. Seeded by migration; user may add custom categories (`is_system = 0`) but cannot delete system ones. No SKR account numbers here.

```sql
CREATE TABLE categories (
    id TEXT PRIMARY KEY,                   -- stable slug, e.g. 'software_subscriptions'
    parent_id TEXT REFERENCES categories(id),
    name_de TEXT NOT NULL,
    name_en TEXT NOT NULL,
    kind TEXT NOT NULL,                    -- income | expense | assetCandidate | neutral
    document_expected INTEGER NOT NULL DEFAULT 1,
    is_system INTEGER NOT NULL DEFAULT 1,
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
    transaction_type TEXT NOT NULL,        -- invoice | receipt | creditNote | refund | paymentOnly | taxPayment | other

    title TEXT,
    invoice_number TEXT,
    invoice_date TEXT,
    service_date TEXT,
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
    exchange_rate_source TEXT,             -- bankActual | bmfMonthly | manual | documentStated | unknown

    eur_year_override INTEGER,             -- 10-day rule (5.3)
    deductibility_note TEXT,

    workflow_status TEXT NOT NULL,         -- draft | active | resolved | archived
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

Exactly one **current** assessment per transaction (`superseded_at IS NULL`); prior assessments are kept for history.

```sql
CREATE TABLE tax_assessments (
    id TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES transactions(id),

    treatment TEXT NOT NULL,               -- see 16.1
    tax_country TEXT,
    customer_type TEXT NOT NULL DEFAULT 'unknown',   -- b2b | b2c | unknown
    supply_type TEXT NOT NULL DEFAULT 'unknown',     -- service | digitalService | goods | unknown
    customer_vat_id TEXT,

    taxable_base_minor INTEGER,            -- booked currency
    vat_shown_minor INTEGER,               -- VAT on the document (booked currency)
    self_assessed_vat_minor INTEGER,       -- §13b / i.g. Erwerb, computed by Swift
    deductible_input_vat_minor INTEGER,    -- expense side
    output_vat_minor INTEGER,              -- income side
    currency TEXT NOT NULL DEFAULT 'EUR',

    input_vat_date TEXT,                   -- derived tax point (5.1), overridable
    output_vat_date TEXT,                  -- derived per payment; here: date of first/only payment, NULL if unpaid

    status TEXT NOT NULL,                  -- proposed | confirmed | manualOverride
    reasoning TEXT,
    superseded_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_taxassess_transaction ON tax_assessments(transaction_id, superseded_at);
```

Per-payment output VAT dates for partial payments are derived from `payment_allocations` at query time; `output_vat_date` is a convenience for the common single-payment case.

## 17.9 `transaction_relations`

```sql
CREATE TABLE transaction_relations (
    id TEXT PRIMARY KEY,
    from_transaction_id TEXT NOT NULL REFERENCES transactions(id),
    to_transaction_id TEXT NOT NULL REFERENCES transactions(id),
    relation_type TEXT NOT NULL,           -- creditNoteFor | refundOf | correctionOf | replaces | relatedTo
    amount_minor INTEGER,
    currency TEXT,
    note TEXT,
    created_at TEXT NOT NULL,
    UNIQUE(from_transaction_id, to_transaction_id, relation_type)
);
```

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
    page_count INTEGER,
    document_type TEXT,                    -- invoice | receipt | creditNote | statement | contract | other | unknown
    source TEXT NOT NULL,                  -- dragDrop | fileImport | shareExtension | other
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

## 17.12 `statement_lines`

```sql
CREATE TABLE statement_lines (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id),
    document_id TEXT REFERENCES documents(id),   -- the statement file
    line_fingerprint TEXT NOT NULL,        -- sha256 of normalized (account_id|booking_date|amount_minor|currency|reference|counterparty_raw)
    external_id TEXT,                      -- bank-provided transaction id if present

    booking_date TEXT NOT NULL,
    value_date TEXT,
    amount_minor INTEGER NOT NULL,         -- signed: negative = outflow
    currency TEXT NOT NULL,
    counterparty_raw TEXT,
    counterparty_iban TEXT,
    reference TEXT,
    booking_text TEXT,
    raw_json TEXT,                         -- full original row

    classification TEXT NOT NULL,          -- business | private | internalTransfer | taxPayment | unknown
    classification_subtype TEXT,           -- e.g. incomeTax | vatPayment | ownTransfer | cardSettlement
    payment_id TEXT REFERENCES payments(id),
    counter_account_id TEXT REFERENCES accounts(id),  -- for internalTransfer
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(account_id, line_fingerprint)
);
CREATE INDEX idx_stmt_account_date ON statement_lines(account_id, booking_date);
CREATE INDEX idx_stmt_classification ON statement_lines(classification);
```

Only `business` lines and `taxPayment/vatPayment` lines create a `payment`. Overlapping statement exports are safe by construction.

## 17.13 `payments`

```sql
CREATE TABLE payments (
    id TEXT PRIMARY KEY,
    account_id TEXT REFERENCES accounts(id),      -- NULL for manually entered payment with unknown account
    direction TEXT NOT NULL,               -- inflow | outflow
    payment_date TEXT NOT NULL,

    original_currency TEXT NOT NULL,
    original_amount_minor INTEGER NOT NULL,       -- positive
    booked_currency TEXT NOT NULL DEFAULT 'EUR',
    booked_amount_minor INTEGER,
    exchange_rate TEXT,
    exchange_rate_source TEXT,

    counterparty_name_raw TEXT,
    reference TEXT,
    payment_method TEXT,                   -- bankTransfer | card | paypal | directDebit | cash | other | unknown
    source TEXT NOT NULL,                  -- statementLine | manual | documentStated
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_payments_date ON payments(payment_date);
CREATE INDEX idx_payments_account ON payments(account_id);
```

## 17.14 `payment_allocations`

```sql
CREATE TABLE payment_allocations (
    id TEXT PRIMARY KEY,
    payment_id TEXT NOT NULL REFERENCES payments(id),
    transaction_id TEXT NOT NULL REFERENCES transactions(id),
    allocated_minor INTEGER NOT NULL,      -- in payment.booked_currency (EUR)
    currency TEXT NOT NULL DEFAULT 'EUR',
    match_method TEXT NOT NULL,            -- exact | reference | invoiceNumber | heuristic | aiDisambiguated | manual | rule
    confidence TEXT,                       -- decimal string 0..1
    created_at TEXT NOT NULL
);
CREATE INDEX idx_payalloc_transaction ON payment_allocations(transaction_id);
CREATE INDEX idx_payalloc_payment ON payment_allocations(payment_id);
```

Invariant: `SUM(allocated_minor) per payment ≤ payment.booked_amount_minor`. Supports partial, combined, statement-first, and invoice-first flows.

## 17.15 `field_provenance`

Values stay typed in their domain tables; this table records origin per field.

```sql
CREATE TABLE field_provenance (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,             -- transaction | payment | taxAssessment | allocation | taxComponent | counterparty | statementLine
    entity_id TEXT NOT NULL,
    field_name TEXT NOT NULL,
    provenance TEXT NOT NULL,              -- document | agent | calculated | manual | imported | rule
    is_manual_override INTEGER NOT NULL DEFAULT 0,
    source_document_id TEXT REFERENCES documents(id),
    model_run_id TEXT REFERENCES model_runs(id),
    rule_id TEXT REFERENCES rules(id),
    confidence TEXT,
    created_at TEXT NOT NULL,
    superseded_at TEXT
);
CREATE UNIQUE INDEX idx_prov_current ON field_provenance(entity_type, entity_id, field_name) WHERE superseded_at IS NULL;
```

Rule: an operation that would change a field whose current provenance `is_manual_override = 1` is rejected unless the actor is `user`.

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
    attempt_count INTEGER NOT NULL DEFAULT 0,
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
    operation TEXT NOT NULL,               -- extraction | disambiguation | statementMapping
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
    kind TEXT NOT NULL,                    -- createTransaction | updateTransaction | linkPayment | attachDocument | classifyStatementLines | mergeDuplicate
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
    entity_type TEXT NOT NULL,             -- transaction | payment | statementLine | proposal
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

## 17.21 `rules`

User-visible learned patterns and configuration rules.

```sql
CREATE TABLE rules (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,                    -- counterpartyDefaults | statementLineClassification | statementColumnMapping | paymentMatchPattern
    scope_json TEXT NOT NULL,              -- e.g. {"counterparty_id": "..."} or {"header_fingerprint": "..."}
    action_json TEXT NOT NULL,             -- e.g. {"category_id": "software_subscriptions", "tax_treatment": "reverseCharge"}
    confirmation_count INTEGER NOT NULL DEFAULT 0,
    auto_apply INTEGER NOT NULL DEFAULT 0,
    is_tax_relevant INTEGER NOT NULL DEFAULT 0,
    created_by TEXT NOT NULL,              -- user | system
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

Tax-relevant rules require `confirmation_count ≥ 3` and explicit user activation before `auto_apply`.

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

## 17.24 `locked_periods`

```sql
CREATE TABLE locked_periods (
    id TEXT PRIMARY KEY,
    business_profile_id TEXT NOT NULL REFERENCES business_profiles(id),
    scope TEXT NOT NULL,                   -- ustva | eur
    period_start TEXT NOT NULL,
    period_end TEXT NOT NULL,
    locked_at TEXT NOT NULL,
    note TEXT,
    UNIQUE(business_profile_id, scope, period_start, period_end)
);
```

A locked UStVA period blocks changes to `output_vat_date`/`input_vat_date`-relevant fields inside it except via the explicit correction action. UI for locking arrives with Milestone 10; schema and enforcement hook exist from Milestone 2.

## 17.25 Derived status view

`paymentStatus`, `documentStatus`, and `taxStatus` (see 19) are **not stored**. Provide a SQL view `v_transaction_status` that computes them, so table filters work without denormalization:

```sql
CREATE VIEW v_transaction_status AS
SELECT t.id,
  CASE
    WHEN t.booked_gross_minor IS NULL THEN 'unknown'
    WHEN COALESCE(pa.allocated, 0) = 0 THEN 'unpaid'
    WHEN pa.allocated < t.booked_gross_minor THEN 'partiallyPaid'
    ELSE 'paid' END AS payment_status,
  CASE
    WHEN td.doc_count IS NULL AND t.transaction_type IN ('paymentOnly') THEN 'missing'
    WHEN td.doc_count IS NULL THEN 'missing'
    ELSE 'complete' END AS document_status,
  COALESCE(ta.status, 'unknown') AS tax_status
FROM transactions t
LEFT JOIN (SELECT transaction_id, SUM(allocated_minor) AS allocated FROM payment_allocations GROUP BY transaction_id) pa ON pa.transaction_id = t.id
LEFT JOIN (SELECT transaction_id, COUNT(*) AS doc_count FROM transaction_documents GROUP BY transaction_id) td ON td.transaction_id = t.id
LEFT JOIN tax_assessments ta ON ta.transaction_id = t.id AND ta.superseded_at IS NULL
WHERE t.deleted_at IS NULL;
```

Categories with `document_expected = 0` map to `document_status = 'notRequired'` (handled in Swift or by extending the view in a later migration).

---

# 18. Binding Enums (consolidated)

All string enums are `enum … : String, Codable, CaseIterable, Sendable` in `Domain`, stored as their raw values. Unknown raw values from the database must fail loudly in debug and map to a `.unknown` case in release where one exists.

```text
Direction:              income | expense | unknown
TransactionType:        invoice | receipt | creditNote | refund | paymentOnly | taxPayment | other
WorkflowStatus:         draft | active | resolved | archived
ReviewStatus:           unreviewed | needsReview | confirmed | conflict
TaxTreatment:           see 16.1
TaxComponentKind:       standard | reduced | zero | reverseChargeNote | exempt | fee | deposit | other
TaxAssessmentStatus:    proposed | confirmed | manualOverride
CustomerType:           b2b | b2c | unknown
SupplyType:             service | digitalService | goods | unknown
ExchangeRateSource:     bankActual | bmfMonthly | manual | documentStated | unknown
DocumentType:           invoice | receipt | creditNote | statement | contract | other | unknown
DocumentRole:           invoice | receipt | creditNote | statement | supportingEvidence | other
DocumentSource:         dragDrop | fileImport | shareExtension | other
AccountKind:            bank | creditCard | paypal | stripe | cash | other
StatementLineClass:     business | private | internalTransfer | taxPayment | unknown
PaymentDirection:       inflow | outflow
PaymentMethod:          bankTransfer | card | paypal | directDebit | cash | other | unknown
PaymentSource:          statementLine | manual | documentStated
MatchMethod:            exact | reference | invoiceNumber | heuristic | aiDisambiguated | manual | rule
Provenance:             document | agent | calculated | manual | imported | rule
RelationType:           creditNoteFor | refundOf | correctionOf | replaces | relatedTo
ImportBatchStatus:      running | completed | completedWithErrors | cancelled
ImportItemStatus:       queued | archiving | analyzing | matching | proposed | committed | skipped | duplicate | failed
ModelRunOperation:      extraction | disambiguation | statementMapping
ModelRunStatus:         running | succeeded | failed | timedOut
ProposalKind:           createTransaction | updateTransaction | linkPayment | attachDocument | classifyStatementLines | mergeDuplicate
ProposalStatus:         pending | accepted | acceptedEdited | rejected | skipped | superseded | committed
PolicyDecision:         autoCommit | needsReview | blocked
IssueSeverity:          info | warning | error
IssueStatus:            open | resolved | ignored
RuleKind:               counterpartyDefaults | statementLineClassification | statementColumnMapping | paymentMatchPattern
AuditActor:             user | agent | system | import
AuditAction:            create | update | delete | link | unlink | confirm | correct | lock | unlock
LockScope:              ustva | eur
```

---

# 19. Status Model

A transaction has no single overloaded state. Dimensions:

```text
reviewStatus   (stored):  unreviewed | needsReview | confirmed | conflict
workflowStatus (stored):  draft | active | resolved | archived
paymentStatus  (derived): unknown | unpaid | partiallyPaid | paid
documentStatus (derived): missing | notRequired | complete
taxStatus      (derived): unknown | proposed | confirmed | manualOverride
```

The UI derives one compact display status. Filters use `v_transaction_status`.

---

# 20. Local File Layout

The user chooses or creates an **archive folder** at first launch ("Archiv erstellen / öffnen"). The chosen path is stored in app preferences (later: security-scoped bookmark for sandbox).

```text
Bookkeeping/
├── bookkeeping.sqlite
├── Documents/
│   ├── 6e2….pdf
│   └── 18f….jpg
├── Exports/
├── Backups/
├── archive.json          — schema version, app version, profile id, created_at
└── README.txt            — human-readable explanation of the layout
```

Database stores relative paths only. Originals never modified. SHA-256 filenames. Thumbnails/previews live in `~/Library/Caches`, not in the archive. Multiple archives may exist; the app opens one at a time.

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
├── StatementImport   — CSV/text parsing, column mappings, fingerprints, classification heuristics
├── ImportPipeline    — coordinator, jobs, matcher, proposal builder, commit
├── AI                — Responses API client, schemas, prompts, provider protocol, retries
├── Validation        — deterministic, no network
├── Tax               — treatment decision, tax points, self-assessed VAT, thresholds, versioned form mappings
├── Analysis          — aggregation queries
└── Export            — CSV, backup, later UStVA/EÜR handoff
```

Dependencies flow downward only: UI → ImportPipeline/Analysis/Export → Database/AI/Tax/Validation → Domain. `AI` depends on `Domain` only. `Tax` and `Validation` have no network and no database dependency (they receive values).

---

# 23. Dates

Domain type `LocalDate` (year/month/day, `Comparable`, `Codable` as `YYYY-MM-DD`) for all calendar dates. `Date` only for timestamps (`created_at` etc.). Never midnight-`Date` for calendar concepts. Period helpers in `Tax`: `UStVAPeriod(year, month|quarter)`, `FiscalYear`.

---

# 24. Payment Matching (deterministic)

Scoring in Swift, for each unallocated business payment against candidate transactions (open amount > 0, direction compatible, date within ±90 days):

```text
+50  exact amount equals open amount (booked EUR)
+35  amount within tolerance (fee/FX ≤ 3 % or ≤ 5 EUR)
+30  invoice number found in reference/booking text
+20  counterparty normalized name or alias matches counterparty_raw
+15  counterparty IBAN previously seen for this counterparty
+10  date within 14 days after invoice date
+10  rule paymentMatchPattern matches
-20  currency mismatch without known FX
```

Decision: score ≥ 70 and next candidate ≥ 25 points lower → `heuristic` match proposed; otherwise if ≥ 2 candidates ≥ 50 → AI disambiguation with those candidates; otherwise unmatched (payment-only transaction proposed if the line is business and no candidate exists). Thresholds are constants in `ImportPipeline/MatchingPolicy.swift` and covered by tests.

Never assume one invoice = one payment. Partial and combined payments produce multiple allocations.

---

# 25. Duplicate Detection

- **Exact:** same SHA-256 → `import_item.status = duplicate`, existing document referenced, no new record.
- **Statement line:** same `(account_id, line_fingerprint)` → skipped silently, counted in batch summary.
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
    case classifyStatementLine(lineID: UUID, StatementLineClass, subtype: String?)
    case upsertCounterparty(CounterpartyDraft)
    case addRelation(from: UUID, to: UUID, RelationType)
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

# 28. Analysis Screen (after MVP)

Revenue and expenses by month (EÜR basis), profit estimate, output VAT, deductible input VAT, estimated VAT payable per UStVA period, unpaid outgoing invoices, transactions missing documents, unresolved issues, flagged asset candidates. Swift Charts. No BI system.

---

# 29. Taxes Screen (after MVP)

- **Deadlines:** UStVA due dates (10th of following month/quarter, Dauerfristverlängerung flag), EÜR/ESt.
- **VAT per period:** output VAT − deductible input VAT (+ self-assessed §13b both sides) = estimated payable, each number expandable to its transactions.
- **UStVA preparation:** `UStVA_<year>` mapping renders Kennzahl, value, explanation, copy button, CSV export. Manual transfer to ELSTER.
- **EÜR preparation:** `EUeR_<year>` mapping from category IDs to lines; asset candidates listed separately.
- **Period lock** after the user marks a UStVA as submitted.

---

# 30. Tax Submission Strategy

Stage 1 correct data → Stage 2 exact form mappings (versioned) → Stage 3 export/handoff files → Stage 4 investigate ERiC/ELSTER only if justified. V1 ends at Stage 2.

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
- Statement line identity: `(account_id, line_fingerprint)`.
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
├── Bookkeeping.xcodeproj/      ← generated, git-ignored
├── App/                        ← app target sources (SwiftUI), Info.plist, entitlements, assets
├── Sources/                    ← SwiftPM module sources (see 37)
├── Tests/                      ← Swift Testing
├── Fixtures/                   ← synthetic documents + expected extractions + recorded model responses
├── scripts/
│   ├── bootstrap.sh            ← brew install xcodegen, swiftformat; xcodegen generate
│   ├── build.sh                ← xcodebuild -project … -scheme Bookkeeping -configuration Debug build
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
│                    Payment.swift · Document.swift · StatementLine.swift · TaxAssessment.swift · TaxComponent.swift ·
│                    BookkeepingAllocation.swift · Counterparty.swift · Category.swift · Proposal.swift ·
│                    ProposedOperation.swift · ValidationIssue.swift · Provenance.swift
├── Database/        AppDatabase.swift · Migrations/ (v001_initial.swift …) · Records/ · Repositories/ · Views.swift · Seed/
├── DocumentStore/   ArchiveLocator.swift · DocumentStore.swift · FileHasher.swift · ThumbnailService.swift
├── StatementImport/ StatementParser.swift · ColumnMapping.swift · BuiltInMappings/ · LineFingerprint.swift · LineClassifier.swift
├── ImportPipeline/  ImportCoordinator.swift · ImportJob.swift · Matcher.swift · MatchingPolicy.swift ·
│                    ProposalBuilder.swift · ReviewPolicy.swift · CommitService.swift
├── AI/              DocumentIntelligenceProvider.swift · OpenAIResponsesClient.swift · ExtractionSchema.swift ·
│                    DisambiguationSchema.swift · StatementMappingSchema.swift · Prompts/ · PromptVersion.swift ·
│                    DocumentPreparer.swift (HEIC→JPEG, PDF paging) · RecordingProvider.swift (fixtures)
├── Validation/      TransactionValidator.swift · MoneyValidator.swift · TaxValidator.swift · AllocationValidator.swift · IssueCodes.swift
├── Tax/             TaxTreatmentDecider.swift · TaxPoints.swift · SelfAssessedVAT.swift · Thresholds.swift ·
│                    FormMappings/UStVA_2026.swift · FormMappings/EUeR_2026.swift
├── Analysis/        Aggregations.swift
└── Export/          CSVExporter.swift · BackupExporter.swift
```

---

# 38. First Vertical Slice

Drop one invoice PDF into the app and end with a confirmed transaction in SQLite.

1. Launch native app (`.app` bundle from XcodeGen project)
2. Onboarding: create/open archive folder, business profile, API key into Keychain
3. Empty transaction table
4. PDF drag-and-drop → copy to `Documents/`, SHA-256
5. Extraction call (strict Structured Output), `model_runs` row
6. Normalize → tax treatment decision → tax components → allocation → tax assessment with derived tax points
7. Proposal persisted, validation run, shown in review UI with provenance badges
8. Manual edit of one field (provenance `manual`)
9. Confirm → one SQLite transaction writes transaction, allocations, components, assessment, document link, provenance, audit
10. Transaction visible in main table; app restart shows persisted data
11. Re-run AI on the same document: no duplicate, manual field untouched

No analytics or tax exports before this works reliably.

---

# 39. Implementation Order

**M0 — Repository foundation:** `Package.swift` with all modules, `project.yml`, scripts, Swift 6/strict concurrency, Swift Testing skeleton, `Money`/`LocalDate`, all enums, CI optional.

**M1 — Local shell:** onboarding (archive picker, profile), `NavigationSplitView`, table, inspector placeholder, settings, no AI.

**M2 — Storage:** GRDB, `v001_initial` with the complete schema from 17 (all tables including accounts, statement_lines, proposals, provenance, rules, locked_periods), views, seed categories, sample data, repositories, migration tests.

**M3 — Manual bookkeeping:** create/edit transaction, allocations, tax components, tax assessment with derived tax points, attach document, add/link payment manually, validation, provenance on manual edits, audit, save/reload.

**M4 — AI invoice import:** Keychain, Responses client, extraction schema, document preparer, proposal persistence, review UI, commit path, recording provider for fixtures.

**M5 — Batch import:** multiple files, background processing, review queue, error/retry states, exact + semantic duplicate detection.

**M6 — Accounts and statements:** accounts UI, CSV/text parsing with built-in mappings, AI column-mapping inference for unknown formats, fingerprints, line classification (business/private/internal/tax), payments from lines, deterministic matching, AI disambiguation, payment-only transactions, invoice-first and statement-first flows.

**M7 — Tax cases:** reverse charge with self-assessed VAT, intra-community acquisition, export, foreign currency with rate sources, mixed-rate components, Kleinbetrag rule, asset flag, 10-day rule warning, credit notes/refunds via relations.

**M8 — Autonomy:** capability flags, presets, rules with confirmation counts, auto-commit path, locked-period enforcement.

**M9 — Analysis:** monthly income/expenses on EÜR basis, VAT overview per period, incomplete transactions, unpaid revenue.

**M10 — Tax preparation:** `UStVA_2026` and `EUeR_2026` mappings, copy/export workflow, period lock UI, deadlines.

---

# 40. Testing Strategy

## 40.1 Unit tests (mandatory)

Money arithmetic and rounding; VAT and self-assessed VAT; tax point derivation for every treatment × direction × advance-payment case; 10-day rule window; Kleinbetrag relaxation; asset threshold; payment allocation invariants; matching scorer thresholds; statement fingerprint stability; column mapping for each built-in bank format; line classification heuristics; state transitions; duplicate detection; validation codes; migrations (upgrade from every prior fixture database); provenance protection of manual fields.

## 40.2 Fixture-based AI tests

`Fixtures/documents/` holds 50–100 **synthetic** documents (generated, no real personal data) with `expected.json` per fixture and a **recorded** `response.json` from `model_runs`. A `RecordingProvider` replays recorded responses so the full pipeline (normalize → tax → match → validate → commit) runs offline in CI. A separate, opt-in live test suite re-records against the real API to detect model/prompt drift. Do not assume a newer model is better.

## 40.3 Integration tests

Invoice first, payment later · payment first, invoice later · overlapping statement exports · PayPal line + bank settlement (internal transfer) · exact duplicate PDF · semantic duplicate · partial and combined payments · USD invoice paid in EUR with fee · mixed 7/19 receipt · reverse charge expense · reverse charge income without VAT ID · manual override then AI rerun · failed model request · crash mid-import and restart · edit inside locked period.

---

# 41. Prompting Principles

Extraction system prompt emphasizes: extract only supported facts; never invent; distinguish observed from inferred; preserve original currency and exact decimal strings; determine direction relative to the supplied business profile; identify document type; give a tax-treatment **hint** with reasoning, not a decision; return `missingFields` explicitly; produce only schema-valid output; use canonical category IDs from the supplied list or null.

Prompts are versioned (`prompt_version`) and stored in `AI/Prompts/` as resources; changing a prompt requires re-running the fixture suite.

---

# 42. Context Supplied to the AI

Extraction: business profile (name, VAT ID, country, VAT status, accounting method), list of canonical category IDs with one-line German/English descriptions, list of supported treatments. **No transaction data.**

Disambiguation: the payment (date, amount, reference, counterparty raw) and ≤ 5 candidates (id, counterparty, open amount, invoice date, invoice number). Nothing else.

Statement mapping: header row and ≤ 5 sample rows with amounts masked to structure-preserving digits where feasible.

---

# 43. Rules and Learned Patterns

Confirmed behavior becomes a visible, editable `rules` row (e.g., counterparty Adobe → category software_subscriptions, treatment reverseCharge). Rules show their confirmation count and whether they auto-apply. Nothing hidden is learned. Tax-relevant rules have stricter activation (17.21).

---

# 44. Manual Editing Rules

A manual value replaces the active value, records provenance `manual` with `is_manual_override = 1`, writes an audit event, is protected from AI overwrite, and must still pass hard validation. Users can ignore soft warnings (issue status `ignored`, audited). Structurally impossible states cannot be committed; a labelled "Ausnahme erzwingen" path exists only for hard validations explicitly marked overridable in `IssueCodes` (none in V1 except tolerance mismatches ≤ 1 EUR).

---

# 45. Search and Filters

Search: counterparty, title, invoice number, amount (both formats), date, reference text of linked statement lines; document full text later. No AI for search.

Filters: date range (by relevant date, invoice date, or payment date), income/expense, payment status, document status, review status, tax treatment, category, account, asset flag, missing document, missing payment.

---

# 46. Performance and Indexes

Instant local browsing; never call the model to render a screen; never require network for existing data; AI and import off the main actor; progressive import state. Indexes are listed inline in 17; add more only when query patterns are measured.

---

# 47. Data Migration Policy

Every schema change is a numbered GRDB migration (`v001_initial`, `v002_…`). Never ask users to delete their database once real data exists. Migration tests upgrade fixture databases from each released schema version. `archive.json` records the schema version; opening a newer archive with an older app is refused with a clear message.

---

# 48. Open Source Considerations

Schema docs, privacy docs (what exactly is sent to OpenAI and when), provider abstraction, standard data formats, no hosted infrastructure, synthetic fixtures only, no real invoices or keys in the repository.

---

# 49. Definition of MVP

The user can: launch without an account · create/open an archive folder · configure business profile and accounts · enter an OpenAI API key · drop invoices/receipts · have information extracted · review/edit/confirm proposals with visible provenance · see transactions in a native table · attach documents · record payments manually · import statement files, classify lines, and match payments · handle reverse charge, foreign currency, and mixed-rate documents correctly · persist and restart without loss · inspect and edit all material values · export CSV and create/restore a full backup.

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
- User-chosen archive folder; open, inspectable formats
- All money as Int64 minor units; non-monetary decimals as canonical strings; never floating point
- Transaction-first; documents, statement lines, payments, allocations, tax components, assessments are separate entities
- Accounts and statement lines from the start; private/internal lines are not business transactions
- Bookkeeping allocations replace a single category; canonical categories with stable IDs; no SKR numbers in core
- Separate tax points (EÜR, output VAT, input VAT); self-assessed VAT computed by Swift
- Form mappings (UStVA/EÜR) versioned in the Tax module, not in the schema
- Field provenance, proposals, relations, rules, locked periods in the initial schema
- OpenAI Responses API with strict Structured Outputs; user-provided key in Keychain
- V1 AI = single-shot extraction + optional disambiguation; no function calling; matching deterministic
- CSV statements parsed deterministically after one-time AI column mapping
- Manual editing always possible; manual values never overwritten by AI
- Autonomy capability-based; default Manual
- No primary chat UX; no direct ELSTER; no DATEV in V1
- XcodeGen project + SwiftPM modules; CLI-first; Xcode GUI only for release edge cases

---

# 52. First Task for a Coding Agent

> Create the repository described in section 35: a `Package.swift` containing the modules `Domain`, `Database`, `DocumentStore`, `StatementImport`, `ImportPipeline`, `AI`, `Validation`, `Tax`, `Analysis`, `Export` (empty where not yet needed), and an XcodeGen `project.yml` defining a macOS 15 SwiftUI app target `Bookkeeping` (Swift 6 language mode, strict concurrency, stable bundle identifier) that depends on those packages. Add `scripts/bootstrap.sh`, `build.sh`, `run.sh`, `test.sh`. Implement `Money` (Int64 minor units, currency exponent table, decimal-string parsing for German and English formats, half-up rounding), `LocalDate`, and all enums from section 18 in `Domain`. Implement `AppDatabase` with GRDB and migration `v001_initial` containing every table, index, and view from section 17, plus the seeded system categories from 17.4. Implement the onboarding flow (choose/create archive folder, business profile) and a `NavigationSplitView` with sidebar, transaction table bound to the database via GRDB observation, and an inspector placeholder. Seed three sample transactions in Debug builds. Do not integrate OpenAI yet. Write Swift Testing tests proving: database initialization and migration; Money parsing, rounding, and round-tripping; enum raw-value stability; that `v_transaction_status` derives payment status correctly for unpaid, partial, and paid fixtures; and that inserting a duplicate `(account_id, line_fingerprint)` fails.

Only after that foundation is stable should the agent implement document import (M3/M4).

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
