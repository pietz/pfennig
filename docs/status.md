# Project status and handoff

This file records the current implementation boundary and the next deliberate decisions. Update it when a milestone or release state changes. Product rules belong in [`concept.md`](../concept.md); durable working principles belong in [`AGENTS.md`](../AGENTS.md).

## Pfennig handoff (2026-09-14)

- The user bought `pfennig.app` and chose **Pfennig** as the new product name. The active working directory is `/Users/pietz/Private/pfennig`; the new private remote is [pietz/pfennig](https://github.com/pietz/pfennig).
- This is an independent local Git clone with the full history through `6518b9a`, not a fresh implementation. The old `/Users/pietz/Private/ziffer` directory and `pietz/ziffer` repository remain unchanged. Continue only in the new working directory.
- The coordinated rename from Ziffer to Pfennig was **completed on 2026-09-14** and is described in the section below. No website or DNS setup was requested.
- Do not run private-document tests or relocate/reset data without authorization.
- Ignored build directories, generated project files and release artifacts were not copied. Regenerate/rebuild using the existing scripts. Credentials remain in the existing local Keychain, not in either repository.
- The [document-to-tax specification](specs/document-to-tax-workflow.md) is **Draft — awaiting approval**, not approved for implementation. The user already selected automatic processing of safe cases, CSV **and PDF** statements, and copyable form values as an acceptable first delivery with XML pursued early. Do not repeat those questions or treat the spec as already approved.
- The latest user direction is automation-first: one document entrance, receipt-first or payment-first enrichment, durable actionable exceptions, a clean interface without chat, and tax tasks linked from Start. This supersedes older manual-first and CSV-only suggestions in research/backlog documents. Actual implementation still requires review of every import proposal.
- All seven original GitHub issues and their available comment are captured in [the local issue archive](legacy-github-issues.md), including the deliberate closure of issue 1. The new GitHub repository has no copied issues yet. Do not transfer, recreate or reopen old tickets automatically; review them against the latest decisions first.

**Resume here:** read this handoff and the workflow specification. Obtain explicit approval of that draft before implementation. The rename did not authorize new features, private archive access, a release, a push, or making the repository public.

## Rename to Pfennig (2026-09-14)

The product is Pfennig everywhere a user or maintainer sees a name: app display name and bundle, window and settings text, onboarding, README, CONTRIBUTING, SECURITY, `concept.md`, `AGENTS.md`, the release and CI pipelines, `project.yml`, `Package.swift`, the `PfennigApp` entry point, the `PfennigRecord` protocol, and the scratch names used by tests.

- The bundle identifier changed from `com.pietz.ziffer` to `com.pietz.pfennig`, keeping the existing `com.pietz` prefix structure. The Developer ID team `34MWWCL4H2` and the signing identity are unchanged.
- The Xcode project, scheme, app bundle and release ZIPs are now `Pfennig`. Regenerate with `scripts/bootstrap.sh` after the rename; the old `Ziffer.xcodeproj` was never committed.

### Archive location and migration

The default archive is `~/Library/Application Support/Pfennig`. `ArchiveLocator.migrateLegacyArchiveIfNeeded()` runs on every launch and, when only the old `Ziffer` folder exists, renames it to the new location. Both folders live on the same volume, so this is a move, not a copy.

- If both folders exist, the Pfennig archive is used, a warning is logged, and the old folder is left untouched.
- If the move fails, the app keeps using the old folder in place, so existing bookkeeping stays reachable.
- Nothing is ever deleted or overwritten. `Tests/DocumentStoreTests/ArchiveTests.swift` covers all four cases in temporary directories; the real archive was not opened during the rename.

### Deliberately kept Ziffer identifiers

These address existing local data or credentials. Renaming them would silently lose access, so they stay, each with a comment at its definition:

- Keychain service `com.pietz.ziffer` with account `openai-api-key` in `Sources/AI/APIKeyStore.swift`. The bundle identifier did change, so macOS may show its usual Keychain access dialog the first time the renamed app reads the item. If access is denied, `load()` returns `nil` and the app asks for the key again; nothing else breaks.
- The notarization Keychain profile `ziffer-notary`, still the default in `scripts/release.sh` and overridable through `NOTARY_PROFILE`.
- The `UserDefaults` key `de.ziffer.archivePath` of the unused remembered-archive path.
- `ArchiveLocator.legacyFolderName`, which must keep naming the old folder for the migration to find it.
- Historical references: `docs/legacy-github-issues.md`, the issue links to `github.com/pietz/ziffer`, and the mention of the retained `/Users/pietz/Private/ziffer` workspace.

## Current product state

The core local bookkeeping loop works:

- manual income and expense transactions remain directly editable
- original PDFs and images are archived locally
- AI extraction produces durable proposals that are reviewed before commit
- accepted imports commit atomically, exact document duplicates are detected, failed items can be retried, and stale proposals cannot overwrite newer work
- payments and partial payments are supported
- internal field provenance protects manual edits but is intentionally not displayed
- business-profile settings are editable prospectively; profile changes do not recalculate historical bookings
- ordinary 7%/19% VAT, mixed rates, common Kleinunternehmer cases, and typical foreign-service reverse-charge amounts have deterministic proposal derivation; this is not yet a verified tax-reporting path
- ambiguous Kleinunternehmer EU-goods cases remain unresolved for manual tax review

Confirmed transactions are editable immediately. Correction semantics are reserved for future locked periods and should not burden the ordinary workflow.

The latest verification baseline is 226 tests across 38 suites plus a successful Debug app build.

Research on 2026-09-14 confirmed material reporting gaps: tax derivation collapses payments to the first date, invoice-possession facts are absent, reverse-charge timing is oversimplified, and form-year mappings/exporters remain unverified placeholders. Start totals must not be reused as UStVA/EÜR values. See [workflow/output research](research-user-workflow.md) for the bounded report and import increments; no feature implementation or tax filing was performed in that research.

## Product boundary

The first audience remains German freelancers and sole proprietors using EÜR and Ist-Versteuerung, either regularly VAT-taxed or under §19 UStG.

Do not expand the initial product into Soll-Versteuerung, balance-sheet accounting, payroll, inventory, CRM, cloud banking, invoice issuance, or tax-adviser replacement. AI extracts facts and proposes; deterministic Swift owns calculations, tax treatment, validation, and persistence.

Use transparent rules for common cases. Unsupported cases should remain visibly reviewable rather than being guessed.

## Interface decisions

Pfennig is a compact native macOS utility with a restrained Start overview:

- the sidebar starts visible on Start and retains Buchungen, Prüfen, and Settings
- the toolbar uses the compact direction menu and icon-only payment status
- company/product rows keep their two-line presentation
- `partiallyPaid` remains a distinct status
- the inspector uses native sections
- the start page reads persisted transactions and pending proposals through live local observations; its year totals and open-item rows link into the existing filtered views
- Start totals use recorded EUR gross amounts and the ledger's relevant date, not tax-profit or cash-flow calculations; open items span all years
- upcoming dates stay hidden until there is a real source; no charts or separate analysis page are added
- Start drilldown filters have one shared state; returning through the Buchungen sidebar entry opens the unfiltered ledger
- leaving Buchungen through the sidebar requires confirmation when inspector edits are unsaved; the inspector cannot be hidden while edits are unsaved
- provenance and extraction-evidence UI are intentionally absent

Extraction evidence metadata was removed as a clean pre-1.0 schema break. Typed proposal derivation context carries treatment hints and reverse-charge notes. Existing development databases may retain an unused legacy column; never reset them merely to make their schema look fresh.

## Open-source and release state

- License: GPLv3, copyright Paul-Louis Pröve
- Repository: still private; do not change visibility or push without explicit approval
- Distribution: direct GitHub Release ZIP, not the Mac App Store
- Developer ID team: `34MWWCL4H2`
- Local signing identity and the `ziffer-notary` Keychain profile have been validated; that profile name deliberately survives the rename
- A local 0.1.0 test build was successfully signed, accepted by Apple notarization, stapled, and accepted by Gatekeeper
- The old workspace's ignored `dist/` contains local test artifacts only; they were not copied to the new workspace and are not an approved public release
- `scripts/release.sh --notarize` implements the complete local release pipeline without embedding credentials
- GitHub Actions [passed in the new private repository](https://github.com/pietz/pfennig/actions/runs/34830245796) for `6518b9a` (Swift tests and unsigned macOS build); recheck CI for the eventual release commit

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

[Product backlog](backlog.md) groups implemented features and proposed priorities across the full input-to-tax-output workflow. Current recommendation: UStVA preparation first with an early, bounded XML feasibility check, then statement reconciliation and EÜR; e-invoices are a separate import increment. Private-document quality testing is parked with the user, not a blocker to this planning. No manufacturer registration or direct ELSTER transmission is planned. Public UStVA XML upload is documented, but no current Pfennig-generated file has been validated; an analogous EÜR upload remains unverified.

Historical GitHub issues remain in the old `pietz/ziffer` repository, with their full contents preserved [locally](legacy-github-issues.md). Their scope and priorities must be reconciled with the newer workflow decisions, not implemented blindly:

- [#2 Core German EÜR tax cases](https://github.com/pietz/ziffer/issues/2): Kleinunternehmer core is implemented; audit and finish remaining common-case acceptance criteria before closing.
- [#3 XRechnung/ZUGFeRD](https://github.com/pietz/ziffer/issues/3): structured input support as a bounded increment alongside the report/reconciliation work, not a separate accounting workflow.
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
