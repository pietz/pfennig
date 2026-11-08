# Reliability and annual tax readiness review

Reviewed 2026-10-12 against baseline `218ca5d`, with concurrent implementation work excluded from this initial assessment. Advisory scope: startup failure, the temporary pre-chat repair, retained-receipt retry, normal-update preservation, 2027 readiness, and a bounded drilldown design. No source edits, release, private archive access, credentials, paid calls or ELSTER session were used.

## Reliability recommendation

Keep startup failure native and terminal: report the localized opening error and archive location in an AppKit alert, then quit. A failed initializer must never continue with a fresh or in-memory repository. A retry/reset/recovery workflow is unnecessary for this step. Verify that the alert actually appears during application launch, receives focus, and exits without a crash or a blank usable bookkeeping window. A thin failed-launch branch at the app entry point is sufficient if launch timing requires it; do not spread optional repositories through the app.

Do not say that the whole archive was unchanged. `Repository.init(path:)` can finish the backed-up repair before a later SQL-tool/profile load fails. The existing repair-specific backup-failure message is narrower and accurate: its schema change has not started at that point. Opening an ordinary SQLite database can also affect journal files without changing user records.

The existing repair is appropriately bounded. It recognizes the old request columns and nonnullable receipt reference, rejects custom request indexes/triggers or conflicting table names, uses SQLite backup before mutation, checks that backup, rebuilds request/chat tables transactionally, and preserves the request autoincrement high-water mark. No general migration history is warranted. Its structural recognition is intentionally narrower than a full schema validator and should not be described as validation of every possible archive variant.

The retained-receipt fix matches the persisted model: only a successful import whose receipt is still linked to a booking suppresses another run. A detached receipt can be processed again with the same file row. The existing synthetic test verifies reattachment without another booking or another file row. A different representation of the same receipt remains an agent matching concern, outside this hash-level fix.

### Release evidence to retain

| Check | Existing evidence | Useful remaining verification |
| --- | --- | --- |
| Known pre-chat repair | Full user-table snapshots, old requests/transcript, restored backup, ID continuity, new import/chat requests, second opening | Include committed WAL data explicitly in a synthetic case if the fixture does not already establish it |
| Backup refusal | A blocked Backups location aborts before schema mutation | Keep this check and verify the native launch error for the equivalent isolated startup failure |
| Unknown old shape | Unexpected request column rejects without backup or changes | Existing coverage is proportionate; do not build a general migration matrix |
| Failure during rebuild | Transactional GRDB write is visible in source | Add one focused rollback check if it can use ordinary GRDB/SQLite failure injection without production test hooks |
| Ordinary current-schema update | Existing repair second-open check covers idempotence only | Close/reopen a synthetic on-disk archive and compare bookings, review marks, activities, files, requests, conversations, settings, export marks, IDs and original/Inbox bytes; assert no repair backup appears |
| Receipt retry after restart | Existing reattachment and failed-run retry checks | Reopen a synthetic archive with a retained detached receipt, retry using mock transport, and verify same file ID, one resulting transaction, retained original and cleaned successful Inbox copy |
| Distribution boundary | Release script produces an app-only Sparkle archive and separate manual distribution archive | Tests/build plus release-contract check establish code/package contracts, not an installed Sparkle update; an actual signed update in a disposable macOS account is separate acceptance evidence |

Compare logical database rows, not raw SQLite file hashes, because WAL/checkpoint behavior and seeded application knowledge can legitimately change the database representation. Compare original and Inbox file bytes exactly. Never use the owner's release archive as a test fixture.

`scripts/release-contract-test.sh` currently checks timestamp predicates, signing options and the appcast CLI contract. It does not establish user-data preservation. `scripts/release.sh` does not copy or reset Application Support, but source inspection alone is not evidence of a completed installed update. Build-only signing still accesses the signing setup and is not an authorization-free substitute for a release run.

Hard release blockers are a failing preservation check, an invisible/crashing startup error path, or a regression in ordinary imports/chat. Additional migration machinery, a files page and automated recovery are not prerequisites. Publication, push, notarized release execution and replacement of the installed app remain governed by the owner's explicit commands.

## 2027 verification result

**Keep the 2026-only export guard.** No 2027 UStVA form/Kennzahl contract, EÜR mapping or accepted Pfennig XML upload was verified in this review. This is an evidence limitation, not a claim that no unpublished specification exists.

| Item | Evidence as of 2026-10-12 | Consequence |
| --- | --- | --- |
| 2027 UStVA availability | ELSTER lists 01.01.2027 as its planned provision date | An owner-session 2027 form upload is a January acceptance step; the date does not certify XML compatibility |
| UStVA forms/instructions | Official search identifies BMF's 2026 publication dated 29.12.2025; ELSTER's 2026 instructions are readable | Recheck BMF for USt 1 A / USt 1 E 2027 before changing mappings or annual support |
| EÜR 2027 | No matching official 2027 form/instructions found; BMF's indexed catalogue lists EÜR 2026 | Preserve the 2026 line mapping and CSV form-year label until the 2027 form is verified |
| XML contract | ELSTER upload help still shows the v2023 example; it points to annual ERiC schemas/plausibility documentation; the ERiC link redirects to developer login | A year substitution in namespace/version is not contract evidence; no developer registration or ERiC integration is needed for the existing owner-upload route |
| Existing upload acceptance | Repository records successful Q3 2026 import on 2026-09-14, without submission | Preserve that claim; Kz 39 and 89/93/61 were added later and still need an owner-session check |

Sources: [ELSTER provision dates](https://www.elster.de/eportal/infoseite/bereitstellungstermine), [BMF UStVA 2026 publication](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/2025-12-29-vordruckmuster-USt-voranmeldung-2026.html), [ELSTER UStVA 2026 instructions](https://www.elster.de/elsterweb/helpGlobal?themaGlobal=help_ustva_2026), [BMF catalogue listing EÜR 2026](https://www.bundesfinanzministerium.de/Web/DE/Service/Publikationen/BMF_Schreiben/bmf_schreiben.html?gtp=0f883b84-81a8-47f6-89df-dbdd32dfc5b5_list%253D35%252616162_list%253D59&gts=246444_list%253Dtitle_text_sort%252Basc%25260f883b84-81a8-47f6-89df-dbdd32dfc5b5_list%253Dtitle_text_sort%252Bdesc), [ELSTER XML upload instructions](https://www.elster.de/eportal/helpGlobal?themaGlobal=ustva_upload), [ERiC documentation entry](https://www.elster.de/elsterweb/entwickler/infoseite/eric). Several direct BMF fetches returned 503, so this review does not claim a fresh complete extraction of the EÜR 2026 PDF or exhaustive proof of absence of 2027 material.

One already identifiable annual boundary deserves a recheck: current §18(2) UStG limits the special founder reporting-period treatment to 2021 through 2026. Under today's text, the regular monthly founder rule applies again afterward. Pfennig already stores the chosen monthly/quarterly rhythm, so this calls for checking the user's applicable setting when relevant, not inventing an automatic founder-status engine. Verify enacted law again at enablement. [Current §18 UStG](https://www.gesetze-im-internet.de/ustg_1980/__18.html).

The next bounded maintenance step is to compare each supported Kennzahl, amount type, timing instruction, EÜR line/title and AVEÜR column against the new official publications when available, preserve 2026 behavior with fixtures, then check representative XML in the owner's 2027 ELSTER form without sending it. Include 19/7 percent domestic bases, input VAT, both supported reverse-charge pairs, EU acquisitions 89/93/61, negative/zero amounts and Kz 39 in its applicable December case. Inspect the populated fields and Kz 83, which ELSTER imports as a manually supplied total. This is a recommendation for acceptance scope, not authorization for a login or submission.

UStVA and EÜR are separate annual contracts. If UStVA can be verified earlier, supporting that year must not silently enable unverified EÜR CSV: the current shared `ExportError.validate(year:)` would need a small explicit distinction then. Do not add that distinction before it is needed. Existing 2027 year-guard tests should stay green today. No scheduled automation was created.

## Bounded tax-total drilldown proposal

Design only. The owner being open to this feature is not an implementation mandate.

Start from an existing export line: a standard button opens a small native sheet with the contributing booking date, title, applicable contribution and a route to the existing ledger/inspector. Keep the selected tax period visible. Kz 83 can first show its existing Kennzahl components; each component can lead to the relevant bookings. EÜR income/expense/profit totals similarly use existing form lines. A category or document-date filter alone cannot explain these totals, because receipt timing, payment timing, partial payments, assets and private shares differ.

Do not derive amounts by summing `calculate([booking])`:

- UStVA derives tax from an aggregate base truncated to whole euros. Two 19.99 EUR bases yield 7.41 EUR at 19 percent after aggregate truncation; separately truncated bases yield 7.22 EUR.
- Kz 39 is a profile amount, not a booking contribution, and would repeat once per single-booking calculation.
- EÜR splits the aggregated Bewirtung line into deductible/non-deductible columns. Rounding each booking first can differ by cents from the existing result.

The clean bounded implementation, if approved, lets the existing Core calculation emit booking contributions during the same pass, and retain its existing aggregate finalization. Display the raw contributions and the actual finalization/rounding result, with a distinct profile source for Kz 39. Do not invent booking allocations for aggregate rounding. For the EÜR, deductible status belongs in the line identity because lines 63/64 have two columns. No persistence/schema, prompt or parallel accounting engine is needed.

Acceptance would require exact reconciliation to the unchanged export result for split payments, refunds, tax timing across years, assets, private share, gifts, Bewirtung, Kleinunternehmer, reverse charge, EU acquisition and December special advance. That is a small Core/UI change with accounting-sensitive tests, not merely making labels clickable; agree this boundary before implementation.

## Separate startup implementation review

Reviewed the uncommitted `App/AppModel.swift` and `App/PfennigApp.swift` change on 2026-10-12 after implementation. No correctness or complexity blocker found. The initializer now throws through to the app boundary; the existing delegate retains the error until `applicationDidFinishLaunching`, presents one application-modal alert, and terminates after dismissal. The optional model stays at the app boundary, preventing workspace/settings content and import tasks from using a failed repository. The optional release updater is initialized only after complete model initialization, and its command is omitted on failure. There is no new fallback database, recovery framework or wider optionality in the app model.

Runtime evidence was supplied by the implementing agent: a temporary application using the production bootstrap with a synthetic throwing model displayed the native alert and exited cleanly after dismissal. Debug and unsigned Release builds and 256 ordinary tests passed; live API tests were skipped. This reviewer did not rerun the GUI, access an archive or independently reproduce those runtime checks. A contentless workspace window can exist behind the modal because the scene remains declared; it cannot operate on data, and adding a separate scene/recovery system solely to remove it would add unnecessary complexity.

Optional refinement only: Finder open-file events still receive `.success` when startup has already failed, because the existing handler queues files whenever the model is absent. Returning `.failure` for a known `startupFailure` would communicate the failure more precisely to Launch Services. The modal already explains the failure and the original files are untouched, so this is not a release blocker. The ordinary successful startup/open-file path remains unchanged.
