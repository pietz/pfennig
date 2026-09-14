# Pfennig Product and Engineering Principles

## Repository handoff

The project is now **Pfennig** (`pfennig.app`), with its active workspace at `/Users/pietz/Private/pfennig` and private repository `pietz/pfennig`. The old `ziffer` directory and repository are retained unchanged. Application targets, archive location, signing setup, and much existing documentation still use Ziffer; this is not a second product. Do not blindly rename technical identifiers or move user data as part of branding.

Read `docs/status.md` for the handoff, then `docs/specs/document-to-tax-workflow.md` for the latest workflow decisions. That specification is still **Draft — awaiting approval**. Its explicitly recorded user decisions are settled; older manual-first/CSV-only plans do not reopen them. Historical GitHub issues are preserved in `docs/legacy-github-issues.md`.

## Product

Ziffer is a native, local-first macOS bookkeeping application for Germany. It helps users turn documents and payments into reviewed bookkeeping records without requiring an account, hosted backend, or opaque automation.

The product north star is:

> Belege ablegen. Ausnahmen prüfen. Fertig.

`concept.md` is the detailed product specification. Keep it and this file aligned when product decisions change.

### Settled workflow and decision lens

The product exists to remove as much routine bookkeeping work as possible for the initial audience, not merely to digitize manual entry. Aim to cover the great majority of their everyday workflows; “90%” expresses this product ambition, not a measured accuracy or coverage guarantee.

- One drag-and-drop entrance accepts the ordinary bookkeeping documents the user has, including receipts, invoice PDFs/images, CSV and PDF statements, and structured e-invoices. Do not make users select a workflow before importing or artificially restrict statement support to CSV.
- A business transaction can start with either its document or its payment. Ziffer identifies, organizes, and joins the corresponding evidence, enriching the same transaction rather than creating duplicate income or expense.
- Automatically apply unambiguous links and fully validated, supported standard cases. Do not require routine confirmation of every imported transaction. Missing facts, conflicting evidence, ambiguous matches, and material tax uncertainty become durable, actionable exceptions; model confidence alone is not sufficient authorization.
- Use capable multimodal models for understanding PDFs/images and unstructured documents. Use local parsers for structured facts where appropriate; both paths feed the same validated workflow. Choose preprocessing and bounded tools to remove user work, not to create separate product modes. Neither an agent framework nor a chat interface is required.
- Complete the outgoing workflow too: derive the applicable tax tasks and deadlines, surface them on Start, and prepare UStVA/EÜR values and practical handoff with minimal manual work. Users should not have to select all relevant bookings again for each report.
- Keep the workspace clean. Show what needs a decision rather than exposing the machinery of extraction, matching, or agent execution. Chat is outside the current scope.

These principles and the receipt-first/payment-first workflow are settled. Infer ordinary implementation choices from them instead of repeatedly reopening foundational product questions. Ask only about genuinely unresolved consequential behavior.

## Initial Audience

Build first for:

- German freelancers and sole proprietors
- Einnahmenüberschussrechnung (EÜR)
- Ist-Versteuerung
- both regularly VAT-taxed businesses and Kleinunternehmer under §19 UStG

Do not broaden the initial product to Soll-Versteuerung, GmbH/UG accounting, double-entry balance sheets, payroll, inventory, CRM, projects, time tracking, tax-adviser replacement, or non-German tax systems.

## 80/20 Product Rule

Prefer a small number of clear rules that correctly cover the common workflows.

- Optimize for frequent, material cases rather than exhaustive legal edge cases.
- Add complexity only for a concrete user need or demonstrated failure.
- Do not turn hypothetical crash scenarios, rare tax exceptions, or speculative future integrations into immediate architecture projects.
- When available facts do not support a safe automatic decision, keep the item reviewable and say that tax review is required.
- A visible, honest limitation is better than a large rule system that appears more certain than it is.

Common cases worth supporting include domestic 7%/19% VAT, mixed-rate receipts, Kleinunternehmer income and expenses, typical foreign SaaS reverse charge, payments, and straightforward credit notes or refunds.

## AI and Deterministic Logic

AI extracts document facts and creates proposals. Deterministic application rules validate and authorize supported automatic actions; AI does not independently authorize bookkeeping or tax decisions. The user remains the final authority, without having to approve every safe standard case.

- Use strict structured extraction and validate the response schema.
- Keep German tax calculations, treatment rules, totals, dates, and persistence deterministic in Swift.
- Successful extraction should flow directly into normalization, deterministic derivation, and a reviewable proposal.
- Do not add AI where a small local parser or deterministic rule is sufficient.
- The user is the final authority and can edit material values directly.
- Keep internal provenance and manual-override protection, but do not clutter the interface with provenance labels.

## Tax Scope

Support Ist-Versteuerung only for now.

For Kleinunternehmer, cover the common bookkeeping behavior:

- domestic income uses §19 treatment rather than ordinary output VAT
- supplier VAT on expenses remains recorded but is not deductible
- expenses are allocated using the gross cost when input VAT is not deductible
- typical foreign B2B service expenses can create reverse-charge VAT liability without a matching input-VAT deduction

Defer automated eligibility thresholds, regime changes, mixed-activity exceptions, detailed EU goods-acquisition thresholds, invoice issuance, and filing automation until they become an explicit product priority.

Use current official primary sources for consequential tax rules. Describe Ziffer as supporting bookkeeping and GoBD practices, not as providing tax advice or blanket compliance certification.

Tax preparation and user-driven handoff are in scope; direct filing is not. Do not introduce ELSTER manufacturer registration, manufacturer credentials, or a hosted transmission gateway. Treat manual XML upload as a separate capability that must be verified per form and year; an export is not a submission. Copyable form values are an accepted first delivery, not the long-term endpoint: pursue a verified UStVA XML handoff early, without making the first useful report depend on it.

## Experience

Ziffer should feel like a compact, restrained macOS utility.

- Prefer standard SwiftUI and AppKit behavior over custom interface inventions.
- Keep the main workspace calm and information-dense.
- Show actions and warnings when they help the user decide something.
- Use Start for a compact financial overview and actionable open items; do not add a separate analysis page for the same information.
- Show upcoming items only when real dates are available. Avoid decorative charts, badges, and explanatory chrome that do not improve the workflow.
- Preserve direct editing for ordinary, unlocked transactions.

## GitHub Workflow

- Use GitHub Issues as the central inbox for ideas, bugs, and improvements; avoid a duplicate local backlog. An open issue is not a delivery promise.
- Keep product principles, larger-change specifications, and implementation status in the repository. Small, clear changes need no separate spec.
- Work directly on `main` by default. Use branches and pull requests for longer experiments, independent parallel work, and external contributions.
- Reference relevant issues in commits and close them when completed. Keep labels simple: Idee, Fehler, Verbesserung.
- Never post private receipts or statements in public issues; report security problems privately. Push only when the user asks.

## Engineering

- Read `docs/status.md` at the start of a work session and keep it current when implementation or release state changes.
- Make the simplest coherent change that serves the current product.
- Reuse the existing domain model and native components before adding abstractions.
- Test common accounting paths and material boundaries first.
- Preserve user-owned local databases and test data. Never solve a migration problem by asking users to delete an archive.
- Before the first public release, update the initial schema directly rather than adding compatibility shims; after a schema ships publicly, use forward migrations.
- Keep ordinary confirmed transactions directly editable. Require correction semantics only when a future locked period makes them necessary.
- Never access or act on `.env` files, API keys, signing private keys, or notarization passwords.
- Keep changes consistent with the local-first architecture: existing data must remain browsable without network or model access.
