# Luna reliability investigation, 2026-10-12

The fresh baseline isolates four failing scenarios: direction in an incoming freelancer invoice, coworking category, and two joint drops that race to insert the same transaction. Keep the whole-agent benchmark and test scheduling before changing model matching instructions.

This investigation reads public fixtures, saved synthetic results, runner/scorer, agent code and relevant tests. It makes no model calls and accesses no credentials, private corpus or app archive. Its owned changes are this report, the eval runner's per-case file-concurrency option and the eval README.

## Frozen baseline

The fresh run is `evals/results/luna-reliability-baseline-20261012/report.json`: `gpt-6-luna`, `high`, 52 scenarios, two independent temporary archives per scenario. It completed **104/104** planned runs on `2026-10-12T10:38:45Z`, with **96/104 total passes, 92/100 agent-evaluable passes, 84/92 positive-task passes, and 12/12 negative-control passes**. Four invalid-input rejection runs count only toward total passes; the other eight controls are agent-evaluable. **48/52 scenarios pass both repetitions.** All eight failures occur in the same four scenarios, each failing both repeats.

- Revision before the run: `218ca5dfb6a06c563169ece743b2b1789662331a`. Concurrent authorized worktree changes mean the revision alone does not describe all execution inputs.
- Truth SHA-256: `631350547a87083546e16538cc7bac1aa30b8fcc505b6a13b5a468bfd683cef3`.
- Rendered prompt SHA-256: `4690b6ae357b3965f3ed01b992be94e44388425150fcb6ef6515bcf721eb0fa6`.
- Source manifest SHA-256: `91030dde26fe817ee9bc43a4b56b667df87ae55c694c7ef3d2589dd4b7a0f90b`. This hashes UTF-8 JSON mapping the 45 relative public source paths to their SHA-256 values, sorted by key with compact separators. Every source-hash entry in the completed baseline matches these files.

Preserve persisted whole-state pass as the primary metric. API-rejected invalid inputs demonstrate input rejection, not agent accuracy.

| Fresh failing scenario | Final-state failure | Diagnosis |
| --- | --- | --- |
| `14`, both repeats | Expense recorded as income; income category, plus wrong counterparty in repeat 1. | Real profile-perspective error; the document and truth agree. |
| `32`, both repeats | `mitgliedschaft` instead of `miete` for a fixed coworking workspace. | Category error, separate from matching. |
| `s2`, both repeats | Two hotel bookings, each with only one supporting file. | Both agents SELECT matching invoice evidence, receive `[]`, then INSERT. |
| `s3`, both repeats | Two receipt bookings, each with only one supporting file. | Same empty-read race; both correctly read the receipt number in these fresh runs. |

Fresh `s1` (scan added to seeded hotel), receipt image `41`, book category `31`, and credit note `s4` pass both repeats. No inspected fresh trace SELECTs a correct existing row and then misattaches to another row. This supports a scheduling experiment, not a lookup-instruction rewrite.

## Historical comparability and truth review

The last saved public endpoint, `exp-exp7-dates-public`, finished 104/104 with 95 total passes, 91/100 agent-evaluable passes and 83/92 positive-task passes; 45/52 scenarios passed both repeats. Its truth hash and all 128 recorded source-hash entries match current files. Its prompt differs (`fe390c704ffce64996e33786a0947df1ac91cfdca8e5034f954c449495f697f6`) and inference was September 25. This is historical evidence, not a controlled comparison against today's code or model service.

Historical traces distinguish two matching failures: `s1` repeat 1 inserts without querying the already-seeded hotel; `s2` repeat 2 and both `s3` repetitions query and receive empty rows before inserting twice. The former is an omitted lookup, the latter a race. Historical receipt-photo errors also misread `PP-040826` as `PP-0426`/`PP-04286`; direct PNG inspection confirms the former and secondary till reference `08426`. These omissions and image errors did not reproduce in the fresh baseline.

Early `exp-baseline-public` and `step2-public` reject the credit note merged into its invoice in `s4`; current truth accepts this equivalent end state. Another historical supplier mismatch (`Wortspur Jana Feld` versus the full name) needs source review before calling it a materially wrong booking. Do not carry old failure totals forward without rescoring against current reviewed truth.

The case `14` PDF's header identifies Wortspur/Jana Feld as issuer, labels Studio Linden/Mara Winter as `RECHNUNGSEMPFÄNGER`, and addresses Mara Winter while billing her for website texts. Text extraction and rendered-page inspection agree. Fresh repeat 2 correctly extracts the supplier but still chooses income; both repeats already perform a lookup. The prompt names `Mara Winter` but does not explicitly define direction from the profile holder's issuer/recipient role. That omission is a plausible experimental target, not proof of the model's internal cause. Keep the correct fixture and truth unchanged.

## Scheduling and measurement limits

`EvalMain.run` creates an isolated archive per case and repetition. `--jobs` controls independent cases. Within one joint-drop case, tasks share `FileIntake` and its repository. `SQLTool` makes each statement transactional, but SELECT and INSERT are separate calls with model inference between them. `FileIntake.InFlight` claims identical file hashes only; PDF/image hashes differ. Individual transactions cannot prevent the observed empty-read race, and `--jobs 1` would leave it intact.

The 52 cases comprise 39 positive single-file forms representing 37 transactions, six controls, and seven archive/drop/chat scenarios. Reused transactions add modalities and state transitions, not independent diversity. Two chat cases are single-turn, the profile is always a regular VAT payer, and no positive standalone document supports multiple distinct transactions. There is no declared untouched holdout.

Missing receipt associations already fail: the scorer compares exact `belege` sets and rejects missing/extra bookings. Core rejects nonexistent receipt IDs. `evalScenarioScoresTheWholeArchive` checks duplicate and missing-association outcomes.

Missing benchmark checks include review invalidation of edited seeds, preserved notes, untouched state after refusal, independent matching distractors with equal amounts/dates or reused invoice numbers across issuers, and multi-turn chat evidence retention. The scorer exempts all seeded rows from the unreviewed-state check; its corresponding test allows an edited confirmed seed to pass. Core separately checks review invalidation, so this is a measurement gap, not an established runtime defect. New expectations need document-backed values and receipt links, without private fixtures or invented facts.

## Two focused experiments

1. **Scheduling only.** Compare unchanged parallel imports with sequential imports on `s2` and `s3`, both file orders, three repetitions per order: 12 runs per configuration. Root's ignored truth clone at `evals/results/luna-scheduling-truth-20261012.json` changes only file order and scenario IDs. Freeze model, effort, prompt, source files, expected states and scorer. Check whether the second agent sees and updates the first booking. A duplicate after seeing a row is different from two empty reads. Assess a cap-only production change using the controlled result and a separate review of the actual queue loop.

2. **One profile-perspective sentence for case `14`.** Prefix the existing payment bullet with one transaction-perspective sentence: "Buche aus Sicht des Unternehmens im Profil: eigene Lieferungen und Leistungen als Einnahmen, bezogene als Ausgaben." Preserve all original payment wording. This avoids an issuer/recipient shortcut that could reverse a client-created self-billing credit. No edge-case catalogue is added. Compare two full 52-case sweeps with sequential imports, original rules versus the override, one repetition each. Existing independent outgoing invoices detect opposite-direction regressions without manufacturing a tailored mirrored fixture. Direction must follow who supplies whom, with the other party as counterparty. Do not combine direction and lookup changes or infer improvement from case `14` alone. One repetition measures the observed sweep, not a stable pass probability; focused repeats of `14` can diagnose its consistency. This repeatedly tuned corpus is development evidence, not an untouched holdout.

The category error does not justify a third experiment or a special coworking rule during this bounded effort. Any adopted change needs a final 52-case regression sweep before a reliability claim. Scheduling cannot guarantee semantic matching; a generic Swift matching engine or unique-invoice constraint would exceed the evidence and agreed design.

## Eval implementation and verification

The runner accepts `--file-jobs N` in `1...50`. After the scheduling pilot, its default changed to `1`, matching the app queue cap of one applied by root. Explicit `2` reproduces the two-file parallel control; `10` reproduces the previous app limit. File tasks use the existing add-next task-group pattern; `1` follows truth-file order and `--jobs` remains independent. The runner does not change production intake, SQL tools, model prompt or scorer.

Every new report records integer `fileJobs`; it remains optional when decoding older reports. Absent legacy values mean original unbounded per-case scheduling, never the new sequential default. Summaries/comparisons display that interpretation and rescoring preserves it. Sequential production imports reduce throughput for unrelated files while preventing the demonstrated stale empty-read race.

The runner build and no-API CLI checks pass: bounds `1`/`50`, rejection of `0`/`51`/noninteger/missing values, legacy/new summary and comparison, and rescore preserving explicit or absent provenance. Those checks initially exercised the Xcode-build executable at `.build/out/Products/Debug/PfennigEval`. A separate root launch initially selected a stale native executable and rejected `--file-jobs` before any API call or output directory. Root rebuilt with the native build system, verified `--validate-only --file-jobs 1` on that binary, and reported all 259 native tests passing. The README now pins `swift build --build-system native --product PfennigEval` before `.build/debug/PfennigEval` execution. After aligning the sequential default, this investigation rebuilt and repeated no-API checks against `/Users/pietz/Private/pfennig/.build/arm64-apple-macosx/debug/PfennigEval`; bounds `1`, `2`, `50`, default validation, invalid arguments, credential refusal, summary/comparison and legacy/serial rescore provenance all pass.

Credential input is environment-only; the `.env` fallback was removed without reading a credential file. The README describes metadata discovery and `ainv` delivery into the already-built trusted runner.

The agreed cap-only production verification plan is separate review of the actual queue-loop invariant, the 259 existing tests, Debug and unsigned Release builds, and actual whole-agent scheduling sweeps. The loop starts work only while its active count is below the cap; with a cap of one, it awaits the current full intake result, including success persistence or failure rollback/cleanup, before starting another file. Keep the existing task group and late-drop draining behavior. Direct AppModel queue unit coverage is absent; no queue service, injectable initializer or test bootstrap is added for this one-constant change. Root owns the production cap change. Final full-sweep and build verification remains pending at this report checkpoint.

## Scheduling experiment results

`evals/results/luna-scheduling-serial-20261012/report.json` completed 12/12 planned runs with `fileJobs: 1`, unchanged prompt/model/effort and truth hash `534487a8aedbae7fa4a58197f3a877ec0ff090a548a08bc70751d7a6d4d45437`. It passes **11/12** whole states: hotel original and reversed orders each 3/3, receipt reversed 3/3, receipt original 2/3. All passing runs preserve the exact expected booking, full single payment and both receipt associations.

The failed original receipt run, repeat 3, is a distinct semantic omission: the PDF agent SELECTs empty and creates booking 1; after that completes, the image agent INSERTs booking 2 directly without a SELECT. Both rows correctly identify `PP-040826`, the same supplier/date/amount, each carries one receipt and a full 2,939-cent payment. It neither misreads the document nor queries and rejects the correct existing row. Serialization prevents concurrent stale reads, but cannot guarantee that the model performs lookup.

Median case duration is 25.62 seconds; sum of case durations is 350.26 seconds. These are case durations from concurrently scheduled isolated cases, not end-user queue wall time. The parallel control and role-rule trial are awaiting mandatory human credential consent and have not made paid calls at this checkpoint. Do not claim a controlled pass-rate or speed improvement yet. Prepared configurations are reviewable independently of that consent.
