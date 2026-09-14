# Historical GitHub issues from pietz/ziffer

Snapshot taken on 2026-09-14 during the move to `pietz/pfennig`. All 7 issues and their available comments are preserved below. This is historical context, not a current implementation mandate. The old repository and its issues were not modified or transferred.

Current product decisions in [AGENTS.md](../AGENTS.md), the [workflow specification](specs/document-to-tax-workflow.md), and the [handoff](status.md) take precedence over older scope and priority statements. In particular, PDF statements are in scope, safe standard cases may be automatic, and private quality testing does not block feature planning. Issue 1 remains deliberately closed.

## Issue 1: [P0] Complete document intake and review reliability

State at snapshot: **CLOSED**. [Original issue](https://github.com/pietz/ziffer/issues/1).

#### Goal
Finish the existing document-to-booking workflow before broadening the product. A dropped batch should move predictably from durable archive registration through extraction, review, confirmation, and restart recovery without duplicates or lost work.

#### Scope
- Audit the current M4/M5 implementation against the intended state machine.
- Complete end-to-end semantic duplicate detection in addition to existing SHA deduplication.
- Verify batch-level partial failure, per-item retry, and status reporting.
- Recover or clearly resolve interrupted imports after app relaunch.
- Preserve reviewer edits when proposals refresh or related actions occur.
- Expand synthetic fixture coverage for representative German invoices and receipts.

#### Acceptance criteria
- Multiple documents can be dropped together and progress independently.
- One failed item does not block successful siblings.
- Exact and likely semantic duplicates have deterministic, tested outcomes.
- Restarting during each durable pipeline state cannot lose the archived source or create duplicate transactions.
- Confirm/reject/retry remain idempotent and manually edited values stay protected.
- Integration tests cover success, partial failure, retry, duplicate, stale proposal, and restart paths.

#### Priority
P0. Complete this before adding substantial new product surfaces.

### Comment by pietz on 2026-09-13T18:06:27Z

[Original comment](https://github.com/pietz/ziffer/issues/1#issuecomment-5655086885)

The core workflow is already implemented: multi-file intake, schema-validated extraction, durable proposals, review/edit/confirm, exact deduplication, and failed-item retry. The remaining crash-recovery and semantic-deduplication work is edge-case hardening rather than a current product priority, so we are deliberately not expanding the implementation here.

## Issue 2: [P0] Support core German EÜR tax cases, including Kleinunternehmer

State at snapshot: **OPEN**. [Original issue](https://github.com/pietz/ziffer/issues/2).

#### Goal
Support the common German EÜR bookkeeping cases with a small, deterministic rule set. Ziffer supports Ist-Versteuerung only; Soll-Versteuerung remains out of scope.

#### Supported core
- Domestic income and expenses with ordinary 7%/19% VAT.
- Mixed-rate receipts.
- German Kleinunternehmer under §19 UStG:
  - domestic income without ordinary output VAT,
  - domestic expenses booked gross with no input-VAT deduction,
  - invoices from a supplier using §19 without invented input VAT.
- Typical foreign B2B service expenses under reverse charge, including for a Kleinunternehmer: VAT liability is computed, but a Kleinunternehmer receives no matching input-VAT deduction.
- Payment dates drive EÜR and Ist-Versteuerung tax points.
- Existing manual tax choices remain protected.

#### Product principle
Prefer a few transparent rules covering common cases. If the available facts do not support a safe determination, keep the booking reviewable and visibly require manual tax review instead of adding speculative rules.

#### Explicitly deferred
- Soll-Versteuerung.
- Automated §19 eligibility, turnover thresholds, opt-out, or mid-year regime changes.
- Detailed intra-community acquisition threshold/waiver rules for Kleinunternehmer.
- Invoice generation, UStVA/ELSTER submission, and tax-adviser replacement.
- Exhaustive treatment of mixed activities and unusual exceptions.

#### Acceptance criteria
- The business profile can select regular VAT or Kleinunternehmer while remaining on Ist-Versteuerung.
- Common domestic and foreign-service fixtures produce deterministic treatment, booked expense base, VAT liability, and deductible input VAT.
- The source document's shown VAT is preserved even when it is not deductible.
- Unsupported or contradictory cases produce a stable review issue rather than a confident automatic result.
- No tax result depends on model reasoning at commit time.

## Issue 3: Parse XRechnung and ZUGFeRD e-invoices natively

State at snapshot: **OPEN**. [Original issue](https://github.com/pietz/ziffer/issues/3).

#### Goal
Ingest German structured e-invoices deterministically instead of routing standardized data through AI extraction.

#### Scope
- Accept standalone XRechnung XML and ZUGFeRD PDF/A-3 documents with embedded XML.
- Validate supported profiles/versions and preserve the original XML/PDF unchanged.
- Map EN 16931 invoice parties, identifiers, dates, currencies, totals, tax breakdowns, payment references, and line items into the existing proposal workflow.
- Fall back to the ordinary document pipeline only when no supported structured invoice is present.
- Surface malformed or inconsistent structured invoices as review issues.

#### Acceptance criteria
- Supported XRechnung and ZUGFeRD fixtures produce proposals without an AI request.
- XML totals and tax breakdowns are cross-checked deterministically.
- Duplicate handling works across the structured payload and archived source document.
- Tests cover common profiles, multiple VAT rates, reverse-charge indicators, credit notes, and malformed documents.

#### Why
German businesses must be able to receive structured e-invoices. This is also faster, cheaper, and more reliable than probabilistic extraction for standardized documents.

## Issue 4: Import and reconcile local bank statements

State at snapshot: **OPEN**. [Original issue](https://github.com/pietz/ziffer/issues/4).

#### Goal
Complete the bookkeeping loop by importing local bank statements and matching their payments to documents without requiring cloud banking access.

#### Approach
- Parse CAMT.053 XML deterministically.
- Use deterministic built-in mappings for verified bank CSV formats already researched in `docs/statement-formats.md`.
- Use AI only to propose a column mapping for an unfamiliar tabular format or to disambiguate a small set of matching candidates.
- Reuse statement fingerprints, accounts, payments, allocations, and matching structures already present in the schema.

#### Scope
- Account setup and statement import UI.
- Overlapping-file deduplication and pending-line handling.
- Classification into business, private, internal transfer, tax payment, or unknown.
- Deterministic candidate scoring by amount, currency, date window, IBAN, reference, and invoice number.
- Invoice-first, statement-first, partial, combined, fee, and foreign-currency flows.
- A focused queue for unmatched payments and missing receipts.

#### Acceptance criteria
- Large statements are handled locally without model-size limits.
- Known formats import offline and produce stable fingerprints.
- No AI call is needed for ordinary matching; ambiguous matches require review.
- Re-importing overlapping periods is idempotent.

## Issue 5: Add explicit deterministic vendor rules

State at snapshot: **OPEN**. [Original issue](https://github.com/pietz/ziffer/issues/5).

#### Goal
Let repeated confirmed bookkeeping decisions become explicit, deterministic vendor rules.

#### Scope
- Propose a rule after repeated matching decisions, never learn silently.
- Match on stable signals such as normalized counterparty, VAT ID, IBAN, description/reference pattern, or document type.
- Allow rules to suggest category, tax treatment, allocation pattern, and selected metadata.
- Show scope, precedence, confirmation count, and enabled state in a simple rule editor.
- Require stricter confirmation before tax-relevant rules can apply automatically.
- Preserve manual overrides and audit every application/change.

#### Acceptance criteria
- Rules are visible, editable, disableable, and testable against sample input.
- Conflicts resolve deterministically and never silently overwrite manual values.
- The first implementation proposes values for review; autonomous application remains separately gated.
- Tests cover precedence, false-positive boundaries, tax-sensitive activation, and counterparty changes.

## Issue 6: Add period closing and correction workflow

State at snapshot: **OPEN**. [Original issue](https://github.com/pietz/ziffer/issues/6).

#### Goal
Add an explicit period-closing and correction workflow for completed VAT/bookkeeping periods.

#### Scope
- UI to inspect and close a month/quarter using the existing `locked_periods` model.
- Block ordinary edits to tax-relevant fields in locked periods.
- Provide an explicit correction action that records the original value, correction, actor, time, and affected reporting period.
- Show lock state and correction history without making normal editing cumbersome.
- Define reopening behavior and safeguards before implementation.

#### Acceptance criteria
- Closing a period is explicit and confirmed.
- Locked transactions cannot be silently mutated through UI, import, rules, or repository calls.
- Corrections are append-only/audited and remain attributable to their original period.
- Existing unlocked transactions remain directly editable.
- Tests cover boundary dates, partial payments, imports, manual edits, and attempted automated changes.

## Issue 7: Add portable accounting exports and evaluate DATEV EXTF

State at snapshot: **OPEN**. [Original issue](https://github.com/pietz/ziffer/issues/7).

#### Goal
Provide portable, accountant-friendly exports without turning Ziffer into a cloud integration platform.

#### Phases
1. Stable general-purpose CSV export for transactions, allocations, tax components, payments, and document references.
2. Human-readable period summaries suitable for review/printing.
3. Research and implement DATEV EXTF/SKR03/SKR04 export only after the required account mapping, tax keys, document links, format specification, and validation fixtures are understood.

#### Constraints
- No live DATEV connection or developer account should be assumed for the file-export phase.
- Do not label an export DATEV-compatible until validated against the current official format and a real adviser import workflow.
- Preserve exact amounts, currencies, dates, stable identifiers, and links to original documents.

#### Acceptance criteria
- Exports are deterministic, versioned, and reproducible from a selected period.
- Round-trip/fixture tests protect delimiters, encodings, decimal formats, account mappings, and tax keys.
- Export failures cannot modify bookkeeping data.
- The UI clearly distinguishes generic exports from a validated DATEV-specific adapter.
