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

### Keychain access

The API key lives under the service `com.pietz.pfennig` with account `openai-api-key`. The old `com.pietz.ziffer` item is not migrated (pre-release rule); the key is entered once in Settings and the new item is then created by, and owned by, the current app.

Two things keep macOS from asking for Keychain access:

- Debug builds are signed with the `Apple Development` identity, whose certificate carries team `34MWWCL4H2` in its OU. That gives every build the same designated requirement, so an item one build created stays readable by the next. `scripts/common.sh` fails rather than falling back to ad-hoc signing, which would change the designated requirement on every build.
- Only `APIKeyStore.load()` reads the secret, and only when a model request is actually made. `APIKeyStore.hasKey` asks for the item's attributes instead of its data, which macOS answers without a dialog, and it is read once at launch into `AppModel.hasAPIKey`; Settings and Prüfen render from that property. Nothing in a view body touches the Keychain.

The data-protection Keychain was evaluated and rejected: it needs the `keychain-access-groups` entitlement, which is provisioning-profile backed. A locally signed build carrying it is killed by AppleMobileFileIntegrity at launch, and without it `SecItemAdd` returns `errSecMissingEntitlement` (-34018). The file Keychain with stable signing is the working arrangement.

### Deliberately kept Ziffer identifiers

These address existing local data or credentials. Renaming them would silently lose access, so they stay, each with a comment at its definition:

- The notarization Keychain profile `ziffer-notary`, still the default in `scripts/release.sh` and overridable through `NOTARY_PROFILE`.
- The `UserDefaults` key `de.ziffer.archivePath` of the unused remembered-archive path.
- `ArchiveLocator.legacyFolderName`, which must keep naming the old folder for the migration to find it.
- Historical references: `docs/legacy-github-issues.md`, the issue links to `github.com/pietz/ziffer`, and the mention of the retained `/Users/pietz/Private/ziffer` workspace.

## Current product state

The core local bookkeeping loop works:

- manual income and expense transactions remain directly editable
- original PDFs and images are archived locally
- AI extraction produces durable proposals that are reviewed before commit
- the ledger shows the short trade name and a short German title; extraction asks for both, and normalization trims, collapses and caps the title
- accepted imports commit atomically, exact document duplicates are detected, failed items can be retried, and stale proposals cannot overwrite newer work
- payments and partial payments are supported
- internal field provenance protects manual edits but is intentionally not displayed
- business-profile settings are editable prospectively; profile changes do not recalculate historical bookings
- ordinary 7%/19% VAT, mixed rates, common Kleinunternehmer cases, and typical foreign-service reverse-charge amounts have deterministic proposal derivation; this is not yet a verified tax-reporting path
- ambiguous Kleinunternehmer EU-goods cases remain unresolved for manual tax review

Confirmed transactions are editable immediately. Correction semantics are reserved for future locked periods and should not burden the ordinary workflow.

The latest verification baseline is 301 tests across 43 suites plus a successful Debug app build.

Research on 2026-09-14 confirmed material reporting gaps: tax derivation collapses payments to the first date, invoice-possession facts are absent, reverse-charge timing is oversimplified, and form-year mappings/exporters remain unverified placeholders. Start totals must not be reused as UStVA/EÜR values. See [workflow/output research](research-user-workflow.md) for the bounded report and import increments; no feature implementation or tax filing was performed in that research.

### UStVA calculation (2026-09-14)

The deterministic UStVA calculation for one Voranmeldungszeitraum exists, per the approved [UStVA specification](specs/ustva-preparation.md):

- `Tax.AllocationSplitter` splits a payment allocation proportionally across a transaction's tax components using a cumulative largest-remainder method, so the shares of all payments of a fully paid transaction reproduce its component totals to the cent.
- `Analysis.UStVACalculator.prepare(period:profile:db:)` produces a `UStVAReturn` from the stored assessments, components and payments: income by payment date, input VAT at `max(Rechnungsdatum, Zahlungsdatum)`, §13b and intra-Community acquisitions by invoice date, Kleinunternehmer without Kz 66/67 and without Kz 48 for their §19 income. Every line carries its contributions; unresolved cases become exceptions and mark the return a draft without blocking export.
- `Analysis.SubmittedReturnRepository` stores one `submitted_returns` row per period (reversible, locks nothing) with a fingerprint of the filed values, so `hasChangedSinceSubmission` can flag a period that moved after submission.

**Kennzahlen mapping status:** `Tax/FormMappings/UStVA_2026.swift` is now verified line by line against the official BMF Vordruckmuster USt 1 A 2026 (BMF letter of 29 December 2025), which corrected the earlier placeholders for Kz 66/61/67, Kz 46/47 vs. 84/85, Kz 89/93 vs. 41/44, and Kz 21 vs. 43. Note that Kz 46/47 covers only EU-established suppliers (§13b Abs. 1); third-country services belong in Kz 84/85. The **Anlage EÜR** mapping (`EUeR_2026.swift`) remains an unverified placeholder.

### Slimmer tax assessment (2026-09-14)

`tax_assessments` no longer stores per-transaction tax points or model prose. Removed: `input_vat_date` and `output_vat_date` (the UStVA calculation dates a transaction itself, from its invoice, service and payment dates), `tax_country` (it only ever held the profile's own country; the supplier country lives on the counterparty), `reasoning` (model prose that no report read; the inspector shows the freshly derived explanation instead) and `superseded_at` (unused versioning - there is one assessment per transaction, and replacing it deletes the old row).

- `Tax/TaxPoints.swift` became `Tax/Periods.swift` and keeps only `UStVAPeriod` (`FiscalYear` went with the schema cleanup below); `TaxPointDeriver` and its persistence in `BookkeepingEngine` are gone.
- `UStVACalculator` dates a §13b or intra-Community acquisition by `invoice_date`, failing that `service_date`. With neither it emits the exception "Rechnungsdatum fehlt" and leaves the transaction out of the form lines.
- The extraction schema's `taxTreatmentHint` now carries the treatment only. Its `confidence` was never read by `TaxTreatmentDecider`, and its free-text `reasoning` was never read at all. `AIConfiguration.promptVersion` moved to `2026-09-14.1`.
- `v001_initial` creates the slim table directly. The forward migration that rebuilt it for older development databases has been folded away; see the archive rewrite below.

### Pre-release schema cleanup (2026-09-14)

The schema no longer carries the scaffolding that `v001_initial` created but
no code ever wrote.

- **Tables gone:** `accounts`, `rules`, `transaction_relations`,
  `locked_periods`, with the enums `AccountKind`, `RuleKind`, `RelationType`
  and `LockScope` and the columns that only referenced them
  (`payments.account_id`, `field_provenance.rule_id`,
  `statement_lines.counter_account_id`). A statement line names its own
  account by IBAN in `account_iban`; the `statement_lines` table and the
  `StatementImport` module stay.
- **Columns gone, each verified unread:** `exchange_rate_source` on
  transactions and payments with `ExchangeRateSource`,
  `transactions.deductibility_note`, `documents.page_count`,
  `counterparties.aliases_json`, `default_category_id`,
  `default_tax_treatment`, `street`, `postal_code` and `city`,
  `categories.name_en`, `parent_id` and `is_system`,
  `payment_allocations.confidence`, `field_provenance.confidence`,
  `business_profiles.fiscal_year_start_month` and
  `import_items.attempt_count`.
- **Enum cases gone:** `DocumentRole.supportingEvidence`,
  `MatchMethod.aiDisambiguated`, `DocumentSource.shareExtension`,
  `PaymentSource.documentStated`, `ModelRunStatus.timedOut`,
  `WorkflowStatus.draft` and `.resolved`. The statement and automation cases
  stay.
- **Code gone:** the empty `CSVExporter` and `Aggregations` placeholders
  (`Analysis/Aggregations.swift` is now `StartOverview.swift`),
  `Tax.FiscalYear` (a freelancer's fiscal year is the calendar year;
  `UStVAPeriod` stays), and the locked-period validation - nothing ever
  handed the validator a locked period, so `LockedPeriodFact`,
  `TaxValidator.validateLockedPeriod` and the `LOCKED_PERIOD` issue code
  could not fire. Locking returns as one piece with its milestone.
- **Extraction:** `invoice.statedEurEquivalent`,
  `lineItems[].assetCandidate` and the counterparty's postal address are no
  longer requested; the asset flag is derived in Swift. `paymentInfo`,
  `missingFields`, `warnings`, and the counterparty's name, country and VAT
  ID stay. `AIConfiguration.promptVersion` moved to `2026-09-14.2`.
- **Schema:** `v001_initial` creates the slim shape directly and is the only
  migration. Per the pre-release rule in `AGENTS.md`, the two forward
  migrations that converged older development databases
  (`v002_slim_tax_assessments`, `v003_remove_unused_scaffolding`) were run
  once and then deleted, together with the tests that simulated the legacy
  schemas.
- **Development archive rewritten once on 2026-09-14.** The archive was
  converted in place with those migrations before they were removed: every
  row was carried over (6 transactions, 2 documents, 3 payments,
  6 tax assessments, 6 counterparties, 98 provenance rows and the rest
  unchanged), the missing `submitted_returns` table was created, and
  `grdb_migrations` records only `v001_initial` again. `PRAGMA
  integrity_check` and `PRAGMA foreign_key_check` are clean and the
  archive's `sqlite_master` now matches a freshly created database exactly,
  column order included. The pre-conversion copy is kept at
  `~/Library/Application Support/Ziffer/Backups/bookkeeping-pre-schema-cleanup-2026-09-14.sqlite`.
  No archive was reset or deleted.

New baseline: 301 tests across 43 suites plus a successful Debug app build.

### Review of the pre-release cleanups (2026-09-14)

The three cleanups above were reviewed once more end to end. What changed:

- **Replacing a tax assessment deletes its provenance rows.** The delete of
  the old `tax_assessments` row left its five `field_provenance` rows behind
  with `superseded_at` NULL, addressing an id that no longer exists; every
  re-derivation added five more. `entity_id` is deliberately not a foreign
  key, so the repository deletes them itself.
- **The import fallback of the ledger date is the local day.** `created_at` is
  a UTC timestamp; the ledger printed its local day while the SQL behind
  sorting, the year filter and the Start totals cut the UTC day, so an evening
  import sorted and counted one day - across New Year one year - before the
  date in its own row.
- **A §13b or intra-Community self-assessment falls back to the service date**
  the way `UStVACalculator` reports it, instead of to today. With one rate in
  force since 2007 this changes no amount today; it removes a divergence.
- **Removed:** the decider's unread English reasoning sentences,
  `MatchMethod.rule` and `Provenance.rule` (the rules table is gone and
  neither was ever written), and the three schema tests that only asserted the
  absence of the removed tables and columns.

Left deliberately, as decisions rather than defects:

- `tax_assessments.output_vat_minor`, `vat_shown_minor` and
  `deductible_input_vat_minor` are written and never read again - the
  calculator recomputes from components and payments, the inspector shows the
  freshly derived values. Removing them is one more schema edit plus the
  one-time archive rewrite, so it waits for an explicit go.
- Nothing enforces "exactly one assessment per transaction";
  `idx_taxassess_transaction` is not unique, and a second row would duplicate
  every transaction through `v_transaction_status`. Same cost as above.
- `statement_lines.account_iban` stays `NOT NULL`. For a statement without an
  IBAN (PDF, PayPal, Stripe) the importer should store a non-null account key
  rather than the column becoming nullable: SQLite treats NULLs as distinct,
  so `UNIQUE(account_iban, line_fingerprint)` would stop catching duplicates
  exactly where the account is unknown.
- `DuplicateValidator`, `ReferentialValidator` and `PaymentMatchValidator` have
  no production call site yet; they belong to the statement-import milestone.
- The three recorded `Fixtures/documents/*/response.json` predate the slimmed
  extraction schema. The replay passes (unknown keys are ignored), but it
  proves the parser against the older payload; re-record on the next live run.

### UStVA interface (2026-09-14)

The user interface of the [UStVA specification](specs/ustva-preparation.md) is implemented; the calculation was not changed for it.

- **Start, section "Steuern"** (`App/Tax/UStVATaskSection.swift`): the Voranmeldung that is due next with its deadline, Zahllast preview and open cases, plus every earlier period of the current and previous year that carries values or open cases and is not marked submitted, and every submitted period whose values moved since ("verändert seit Übermittlung"). An earlier period with nothing in it stays off Start; the task window reaches it through its picker. A Kleinunternehmer, and a profile set to "keine regelmäßigen Voranmeldungen", only sees a period that actually carries §13b or intra-Community amounts; for them only the current and previous period are prepared. The rows follow the ledger through a live observation.
- **Task window** (`App/Tax/UStVATaskWindow.swift`): a separate `Window` scene, so the ledger stays open beside it. Period picker with the deadline, exception list with "In Buchungen öffnen", the form values per Kennzahl with an expandable list of their single contributions, the Zahllast row, and the actions "Werte kopieren", "XML exportieren…" (still labelled *experimentell*) and "Als übermittelt markieren". Export warnings appear as a compact note under the buttons, never as a modal; an empty period shows zero values and still exports.
- **Navigation:** `AppModel.ustvaTaskPeriod` is the one period the single task window shows - Start writes it before opening the window, the window's picker writes it back; `AppModel.showTransaction(_:)` sends the user from an exception back into Buchungen with the inspector open and raises the main window.
- `Analysis.UStVATasks` is the only new calculation-adjacent code: which periods are worth showing, their deadlines (including the Dauerfristverlängerung setting, read inside the same observation so a changed setting moves the dates at once), their filing state, and the transactions behind the exceptions. `UStVACalculator` gained one safety net: a §13b or intra-Community line with a base but no tax now reports "Bemessungsgrundlage ohne Steuerbetrag" instead of dropping the Steuer line silently.
- The former UStVA rhythm "Jährlich" now reads "Keine regelmäßigen Voranmeldungen" and is confirmed once, through a small prompt in the Start section or by saving the business settings (`settings` key `ustva.periodConfirmed`).

**What remains:** the XML upload has still never been tried against Mein ELSTER. The user runs the first real test upload (filling the form, without sending) for Q3 2026 on **10 October 2026**. Only after that does the "experimentell" label come off the export; if it fails, the copyable values stay the delivery path.

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
- the ledger and Start share one date, the "Datum" column: the document date, then the earliest payment date, then the import date; tax periods stay dated by payment, and payment dates remain in the inspector
- upcoming dates stay hidden until there is a real source; no charts or separate analysis page are added
- Start drilldown filters have one shared state; returning through the Buchungen sidebar entry opens the unfiltered ledger
- leaving Buchungen through the sidebar requires confirmation when inspector edits are unsaved; the inspector cannot be hidden while edits are unsaved
- Start carries a "Steuern" section with the UStVA task; the task itself opens in a window of its own instead of a sheet, so the ledger stays reachable while exceptions are corrected
- the window may shrink to 560 pt; Start lets `ViewThatFits` stack its three metric cards, so no view measures the window itself
- showing the inspector grows the window by its width and hiding it restores the window, so the ledger keeps its width; a window that would not fit on screen keeps the standard behaviour
- editable dates are typed as `TT.MM.JJJJ` text with two-digit day and month, because the macOS date field omits leading zeros
- provenance and extraction-evidence UI are intentionally absent

Extraction evidence metadata was removed as a clean pre-1.0 schema break. Typed proposal derivation context carries treatment hints and reverse-charge notes. The development archive was rewritten onto the current schema on 2026-09-14; never reset or delete an archive merely to make its schema look fresh.

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

## Decided, not yet built

- **Refunds and credit notes.** Approved: a refund is an opposite-direction
  payment on the existing transaction, and a credit note is a transaction
  with a negative amount. Scheduled as the first part of the
  statement-import milestone, not as separate correction machinery.

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
