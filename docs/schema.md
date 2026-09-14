# Database schema

The canonical store is a single SQLite file, `bookkeeping.sqlite`, inside the
archive folder (see spec section 20). GRDB owns the connection; the schema is
created by the single migration in `Sources/Database/Migrations/`.

Conventions (spec 17):

- Primary keys are lowercase RFC 4122 UUID strings.
- Timestamps are ISO-8601 UTC strings (`2026-09-12T10:15:00Z`); calendar dates
  are `YYYY-MM-DD`.
- Money is `INTEGER` minor units with an adjacent currency column. Rates and
  percentages are canonical decimal strings, never `REAL`.
- `PRAGMA foreign_keys = ON` for every connection.
- Soft delete via `deleted_at` where noted.

`Tests/DatabaseTests/SchemaDocumentationTests.swift` keeps the documented table and view name lists in sync with `sqlite_master` from a freshly migrated database. Column and index details still require review when the schema changes.

## Migrations

| Identifier | Contents |
|---|---|
| `v001_initial` | All tables and views listed below, plus the system categories of spec 17.4. |

Before the first public release this is the only migration. A schema change
edits `V001Initial.swift` in place and the development archive is rewritten
once; there are no forward migrations, compatibility shims or dual-format
readers (see `AGENTS.md`, Engineering). After a schema ships publicly, every
change becomes a numbered `v00x_...` migration and user archives are carried
forward.

## Tables

<!-- sqlite_master:tables -->
```text
audit_events
bookkeeping_allocations
business_profiles
categories
counterparties
documents
field_provenance
import_batches
import_items
model_runs
payment_allocations
payments
proposals
settings
submitted_returns
tax_assessments
tax_components
transaction_documents
transactions
validation_issues
```

| Table | Purpose |
|---|---|
| `business_profiles` | The business itself: VAT status, accounting method, UStVA period. Exactly one row in V1. |
| `counterparties` | Normalized suppliers and customers: name, country and VAT ID. No postal address. |
| `categories` | Canonical bookkeeping categories with stable slug IDs, seeded by `v001_initial`. No SKR account numbers. |
| `transactions` | The central economic event. No category column: categories live in allocations. The service period carries a single service date in both of its ends. |
| `bookkeeping_allocations` | Category splits of a transaction, including the asset flag and private share. |
| `tax_components` | What the document shows per VAT rate (7 % and 19 % on one receipt, for example). |
| `tax_assessments` | The single bookkeeping judgement per transaction: treatment, taxable base and self-assessed VAT. VAT shown, deductible input VAT and output VAT are not stored - every report and the inspector recompute them. Exactly one row per transaction, enforced by a unique index; replacing it deletes the old row. |
| `documents` | Imported originals, identified by SHA-256, stored as files under `Documents/`. |
| `transaction_documents` | Which document plays which role for which transaction. |
| `payments` | Actual cash movements, entered manually. |
| `payment_allocations` | How much of a payment belongs to which transaction: partial and combined payments. |
| `field_provenance` | Origin of every material field (document, agent, calculated, manual, imported) and manual-override protection. |
| `import_batches`, `import_items` | Restartable import of dropped files. |
| `model_runs` | One row per AI call, without document content or secrets. |
| `proposals` | The persisted review queue, idempotent per import item and prompt version. |
| `validation_issues` | Deterministic validation results with stable codes. |
| `audit_events` | Append-only change log for every mutation. |
| `settings` | Non-secret app settings as JSON values. Never API keys. |
| `submitted_returns` | UStVA periods the user marked as submitted, with the Zahllast and a fingerprint of the filed values. Locks nothing. |

## Views

<!-- sqlite_master:views -->
```text
v_transaction_status
```

`v_transaction_status` derives the three status dimensions that are not stored
(spec 17.25 and 19):

- `payment_status`: derived from the **net** allocated amount - everything
  allocated in the transaction's own direction (money out on an expense, money
  in on an income) minus everything that moved back, because a refund is an
  opposite-direction payment on the same transaction. It is `unknown` when no
  booked gross amount is known, `unpaid` when the transaction has no
  allocation at all, `refunded` when it has allocations that cancel out,
  `partiallyPaid` while the net amount is below the booked gross amount, and
  `paid` otherwise. A credit note books a negative gross amount and is settled
  by a payment in the opposite direction, so the same rule covers it.
- `document_status`: `missing` while no document is attached, else `complete`.
  Categories with `document_expected = 0` map to `notRequired` in Swift.
- `tax_status`: the status of the current tax assessment, or `unknown`.

## Indexes

`idx_counterparties_normalized` (unique), `idx_alloc_transaction`,
`idx_alloc_category`, `idx_taxcomp_transaction`,
`idx_taxassess_transaction` (unique),
`idx_payments_date`,
`idx_payalloc_transaction`, `idx_payalloc_payment`,
`idx_import_items_batch`, `idx_prov_current` (unique, partial),
`idx_proposals_status`, `idx_issues_entity`, `idx_audit_entity`.

Unique constraints additionally cover `documents.sha256`,
`proposals.idempotency_key` and
`submitted_returns(business_profile_id, year, kind, period_index)`.
