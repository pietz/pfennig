# Database schema

The canonical store is a single SQLite file, `bookkeeping.sqlite`, inside the
archive folder (see spec section 20). GRDB owns the connection; the schema is
created and upgraded exclusively by numbered migrations in
`Sources/Database/Migrations/`.

Conventions (spec 17):

- Primary keys are lowercase RFC 4122 UUID strings.
- Timestamps are ISO-8601 UTC strings (`2026-09-12T10:15:00Z`); calendar dates
  are `YYYY-MM-DD`.
- Money is `INTEGER` minor units with an adjacent currency column. Rates,
  percentages and confidences are canonical decimal strings, never `REAL`.
- `PRAGMA foreign_keys = ON` for every connection.
- Soft delete via `deleted_at` where noted.

`Tests/DatabaseTests/SchemaDocumentationTests.swift` keeps the documented table and view name lists in sync with `sqlite_master` from a freshly migrated database. Column and index details still require review when the schema changes.

## Migrations

| Identifier | Contents |
|---|---|
| `v001_initial` | All tables and views listed below, plus the system categories of spec 17.4. |

## Tables

<!-- sqlite_master:tables -->
```text
accounts
audit_events
bookkeeping_allocations
business_profiles
categories
counterparties
documents
field_provenance
import_batches
import_items
locked_periods
model_runs
payment_allocations
payments
proposals
rules
settings
statement_lines
tax_assessments
tax_components
transaction_documents
transaction_relations
transactions
validation_issues
```

| Table | Purpose |
|---|---|
| `business_profiles` | The business itself: VAT status, accounting method, UStVA period. Exactly one row in V1. |
| `accounts` | Payment accounts (bank, credit card, PayPal, cash). Statement lines and payments belong to an account. |
| `counterparties` | Normalized suppliers and customers with defaults for category and tax treatment. |
| `categories` | Canonical bookkeeping categories with stable slug IDs, seeded by `v001_initial`. No SKR account numbers. |
| `transactions` | The central economic event. No category column: categories live in allocations. |
| `bookkeeping_allocations` | Category splits of a transaction, including the asset flag and private share. |
| `tax_components` | What the document shows per VAT rate (7 % and 19 % on one receipt, for example). |
| `tax_assessments` | The single current bookkeeping judgement per transaction, with derived tax points. History is kept via `superseded_at`. |
| `transaction_relations` | Credit notes, refunds, corrections between transactions. |
| `documents` | Imported originals, identified by SHA-256, stored as files under `Documents/`. |
| `transaction_documents` | Which document plays which role for which transaction. |
| `statement_lines` | Raw account statement lines with classification. Unique per `(account_id, line_fingerprint)`. |
| `payments` | Actual cash movements, from statement lines or entered manually. |
| `payment_allocations` | How much of a payment belongs to which transaction: partial and combined payments. |
| `field_provenance` | Origin of every material field (document, agent, calculated, manual, imported, rule) and manual-override protection. |
| `import_batches`, `import_items` | Restartable import of dropped files. |
| `model_runs` | One row per AI call, without document content or secrets. |
| `proposals` | The persisted review queue, idempotent per import item and prompt version. |
| `validation_issues` | Deterministic validation results with stable codes. |
| `rules` | Visible, editable learned patterns with confirmation counts. |
| `audit_events` | Append-only change log for every mutation. |
| `settings` | Non-secret app settings as JSON values. Never API keys. |
| `locked_periods` | Closed UStVA/EÜR periods; changes inside require an explicit correction. |

## Views

<!-- sqlite_master:views -->
```text
v_transaction_status
```

`v_transaction_status` derives the three status dimensions that are not stored
(spec 17.25 and 19):

- `payment_status`: `unknown` when no booked gross amount is known, `unpaid`
  when nothing is allocated, `partiallyPaid` while the allocated sum is below
  the booked gross amount, otherwise `paid`.
- `document_status`: `missing` while no document is attached, else `complete`.
  Categories with `document_expected = 0` map to `notRequired` in Swift.
- `tax_status`: the status of the current tax assessment, or `unknown`.

## Indexes

`idx_counterparties_normalized` (unique), `idx_alloc_transaction`,
`idx_alloc_category`, `idx_taxcomp_transaction`, `idx_taxassess_transaction`,
`idx_stmt_account_date`, `idx_stmt_classification`, `idx_payments_date`,
`idx_payments_account`, `idx_payalloc_transaction`, `idx_payalloc_payment`,
`idx_import_items_batch`, `idx_prov_current` (unique, partial),
`idx_proposals_status`, `idx_issues_entity`, `idx_audit_entity`.

Unique constraints additionally cover `documents.sha256`,
`statement_lines(account_id, line_fingerprint)`,
`proposals.idempotency_key`,
`transaction_relations(from_transaction_id, to_transaction_id, relation_type)`
and `locked_periods(business_profile_id, scope, period_start, period_end)`.
