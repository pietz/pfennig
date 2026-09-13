# Project status and handoff

This file records the current implementation boundary and the next deliberate decisions. Update it when a milestone or release state changes. Product rules belong in [`concept.md`](../concept.md); durable working principles belong in [`AGENTS.md`](../AGENTS.md).

## Current product state

The core local bookkeeping loop works:

- manual income and expense transactions remain directly editable
- original PDFs and images are archived locally
- AI extraction produces durable proposals that are reviewed before commit
- accepted imports commit atomically, exact document duplicates are detected, failed items can be retried, and stale proposals cannot overwrite newer work
- payments and partial payments are supported
- internal field provenance protects manual edits but is intentionally not displayed
- business-profile settings are editable prospectively; profile changes do not recalculate historical bookings
- ordinary 7%/19% VAT, mixed rates, Ist-Versteuerung tax points, common Kleinunternehmer cases, and typical foreign-service reverse charge are covered deterministically
- ambiguous Kleinunternehmer EU-goods cases remain unresolved for manual tax review

Confirmed transactions are editable immediately. Correction semantics are reserved for future locked periods and should not burden the ordinary workflow.

The latest verification baseline is 216 tests across 37 suites plus successful Debug and Release app builds.

## Product boundary

The first audience remains German freelancers and sole proprietors using EÜR and Ist-Versteuerung, either regularly VAT-taxed or under §19 UStG.

Do not expand the initial product into Soll-Versteuerung, balance-sheet accounting, payroll, inventory, CRM, cloud banking, invoice issuance, or tax-adviser replacement. AI extracts facts and proposes; deterministic Swift owns calculations, tax treatment, validation, and persistence.

Use transparent rules for common cases. Unsupported cases should remain visibly reviewable rather than being guessed.

## Interface decisions

Ziffer is a compact native macOS utility, not a dashboard:

- the sidebar starts hidden but retains Settings
- the toolbar uses the compact direction menu and icon-only payment status
- company/product rows keep their two-line presentation
- `partiallyPaid` remains a distinct status
- the inspector uses native sections
- provenance and extraction-evidence UI are intentionally absent

Extraction evidence metadata was removed as a clean pre-1.0 schema break. Typed proposal derivation context carries treatment hints and reverse-charge notes. Existing development databases may retain an unused legacy column; never reset them merely to make their schema look fresh.

## Open-source and release state

- License: GPLv3, copyright Paul-Louis Pröve
- Repository: still private; do not change visibility or push without explicit approval
- Distribution: direct GitHub Release ZIP, not the Mac App Store
- Developer ID team: `34MWWCL4H2`
- Local signing identity and the `ziffer-notary` Keychain profile have been validated
- A local 0.1.0 test build was successfully signed, accepted by Apple notarization, stapled, and accepted by Gatekeeper
- `dist/` is ignored and contains local test artifacts only; the test ZIP is not an approved public release
- `scripts/release.sh --notarize` implements the complete local release pipeline without embedding credentials
- GitHub Actions CI is configured but cannot be observed until the workflow is pushed

Before a public release:

1. Add a proper application icon and final public-facing screenshots.
2. Prevent the unsupported GPT-6 Astra plus `reasoning.effort = none` combination in Settings or reject it locally with a clear message.
3. Enable GitHub private vulnerability reporting so [`SECURITY.md`](../SECURITY.md) has a working private channel.
4. Push while the repository is private and confirm CI succeeds.
5. Smoke-test the notarized ZIP in a clean macOS user environment without touching the working archive.
6. Review version and release notes, then rebuild from the exact clean commit to be tagged.
7. Make the repository public, tag, and publish the ZIP only with explicit approval.

See [`releasing.md`](releasing.md) for commands. Never inspect or commit `.env`, API keys, signing private keys, or notarization passwords.

## Backlog

GitHub Issues are the source of truth:

- [#2 Core German EÜR tax cases](https://github.com/pietz/ziffer/issues/2): Kleinunternehmer core is implemented; audit and finish remaining common-case acceptance criteria before closing.
- [#3 XRechnung/ZUGFeRD](https://github.com/pietz/ziffer/issues/3): recommended next product slice after release foundations.
- [#4 Local statement reconciliation](https://github.com/pietz/ziffer/issues/4)
- [#5 Deterministic vendor rules](https://github.com/pietz/ziffer/issues/5)
- [#6 Period closing and corrections](https://github.com/pietz/ziffer/issues/6)
- [#7 Portable exports and DATEV evaluation](https://github.com/pietz/ziffer/issues/7)

Issue #1 was deliberately closed because the normal import path is reliable. Do not reopen it merely to add speculative crash recovery, worker leasing, or semantic deduplication without a demonstrated user problem.

## Useful checkpoint commits

- `7e68b1e` import and inspector safety
- `c6d3b59` through `6280156` compact native workspace redesign
- `d875fb5` extraction-evidence removal
- `41d9fb8` Kleinunternehmer bookkeeping core
- `f20862c` editable business profile
- `34e55df` GPLv3 and public documentation
- `f4949fa` signed/notarized release workflow and CI
