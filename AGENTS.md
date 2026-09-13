# Ziffer Product and Engineering Principles

## Product

Ziffer is a native, local-first macOS bookkeeping application for Germany. It helps users turn documents and payments into reviewed bookkeeping records without requiring an account, hosted backend, or opaque automation.

The product north star is:

> Belege ablegen. Ausnahmen prüfen. Fertig.

`concept.md` is the detailed product specification. Keep it and this file aligned when product decisions change.

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

AI extracts document facts and creates proposals. It does not make the final bookkeeping or tax decision.

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

## Experience

Ziffer should feel like a compact, restrained macOS utility.

- Prefer standard SwiftUI and AppKit behavior over custom interface inventions.
- Keep the main workspace calm and information-dense.
- Show actions and warnings when they help the user decide something.
- Avoid dashboards, badges, explanatory chrome, and status surfaces that do not improve the core workflow.
- Preserve direct editing for ordinary, unlocked transactions.

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
