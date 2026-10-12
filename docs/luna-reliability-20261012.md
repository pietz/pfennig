# Luna reliability investigation, 2026-10-12

Two bounded changes were adopted: one import at a time, and a generic instruction to book from the profile company's transaction perspective. The final candidate sweep passes **51/52** public scenarios; coworking category `32` still fails. Sequential imports pass **11/12** focused matching runs versus **2/12** parallel runs. An omitted lookup can still produce duplicates, so these results do not establish perfect matching or a general accuracy rate.

This investigation reads public fixtures, saved synthetic results, code and tests only. Root owns paid execution, production edits and commits. This leaf accessed no credentials, private corpus or app archive and made no model calls. Raw results are ignored local artifacts under `evals/results/`.

## Completed scorecard

All planned runs below finished. Positive-state runs mean cases whose expected final archive contains bookings, including seeded scenarios. Agent-evaluable figures exclude API-rejected invalid inputs. Controls remain separate from booking quality.

| Configuration | Completed | Whole state | Agent-evaluable | Positive state | Controls |
| --- | --- | --- | --- | --- | --- |
| Original parallel baseline, 52 scenarios twice | 104/104 | 96/104 | 92/100 | 84/92 | 12/12 |
| Focused parallel, both file orders, three repeats | 12/12 | 2/12 | 2/12 | 2/12 | 0 controls |
| Focused sequential, same cases/orders/repeats | 12/12 | 11/12 | 11/12 | 11/12 | 0 controls |
| Full sequential, original rules | 52/52 | 50/52 | 48/50 | 44/46 | 6/6 |
| Full sequential, perspective rule | 52/52 | 51/52 | 49/50 | 45/46 | 6/6 |
| Perspective rule, `14` and `01` five times each | 10/10 | 10/10 | 10/10 | 10/10 | 0 controls |

The final three configurations complete all **114** runs in the approved wrapper. Do not combine configurations into one accuracy estimate. The baseline's 12 controls include four API rejection passes and eight agent-evaluable passes; each full single sweep has two rejection passes and four agent-evaluable controls.

Reports: `luna-reliability-baseline-20261012/report.json`, `luna-scheduling-parallel-20261012/report.json`, `luna-scheduling-serial-20261012/report.json`, `luna-serial-full-20261012/report.json`, `luna-role-full-20261012/report.json`, and `luna-role-focused-20261012/report.json`, all beneath `evals/results/`.

## Frozen evidence and provenance

All configurations use `gpt-6-luna`, `high`, neutral input names, frozen corpus date/profile, isolated archives, unchanged scorer and no reasoning summaries.

| Evidence | SHA-256 |
| --- | --- |
| Public truth | `631350547a87083546e16538cc7bac1aa30b8fcc505b6a13b5a468bfd683cef3` |
| Scheduling truth clone | `534487a8aedbae7fa4a58197f3a877ec0ff090a548a08bc70751d7a6d4d45437` |
| Original rendered prompt | `4690b6ae357b3965f3ed01b992be94e44388425150fcb6ef6515bcf721eb0fa6` |
| Perspective rendered prompt | `97a100c180a65f823e33552878f9d8673229fd40072467ddda553f070d1a6adc` |
| Perspective rules | `e941ecbff3a25f18878a1a197410ba9de27eb3bc09feac145313ef0132593c80` |
| Public source manifest | `91030dde26fe817ee9bc43a4b56b667df87ae55c694c7ef3d2589dd4b7a0f90b` |

The manifest hashes compact UTF-8 JSON mapping the 45 relative public paths to source SHA-256 values, with sorted keys. All recorded hashes checked against current public sources match. The 12 scheduling pairs have byte-identical truth snapshots, prompt and source maps. The two full sweeps have identical model/effort/truth/source maps/file concurrency; rendered prompts differ only by the tested sentence. Runs occur at different times, not interleaved.

Baseline revision was `218ca5dfb6a06c563169ece743b2b1789662331a`, with concurrent authorized worktree changes; a revision alone is insufficient provenance. Root committed prepared scheduling/runner work as `3603621`. Source rules now match the measured override byte-for-byte. With the same profile/schema/date and unchanged builder, the adopted production prompt therefore equals the saved candidate prompt. This comparison uses code and artifacts, without another API call.

## Scheduling diagnosis

Baseline failures are `14`, `32`, `s2` and `s3`, each failing both repeats; 48/52 scenarios pass twice. Every fresh baseline `s2`/`s3` trace has both agents SELECT matching evidence, receive `[]`, then INSERT. Individual SQL calls are transactional, but SELECT and later INSERT remain separated by inference. Identical-byte hash claims cannot deduplicate a PDF and its image. `--jobs` controls isolated cases and cannot prevent this within-case race.

| Focused case/order | Sequential | Parallel |
| --- | --- | --- |
| Hotel PDF first | 3/3 | 0/3 |
| Hotel image first | 3/3 | 0/3 |
| Receipt PDF first | 2/3 | 1/3 |
| Receipt image first | 3/3 | 1/3 |

Nine parallel failures demonstrate two stale empty reads; the tenth (`s3` reversed, repeat 1) has both agents INSERT without lookup. Both parallel successes occur when one agent commits first and the other SELECT sees the correct row, then UPDATEs its attachments. No observed trace retrieves the correct row and then misattaches elsewhere.

The sequential failure (`s3` original, repeat 3) is a lookup omission: after the PDF creates a booking, the image agent INSERTs directly with the correct receipt number, supplier, date and amount. It never queries the existing row. Serialization prevents the demonstrated race, but cannot guarantee model compliance.

Failed hotel states double gross/payment from 33,076 to 66,152 cents; failed receipt states double 2,939 to 5,878 cents. Each duplicate carries only its own file. Passing states retain one full payment and both attachments. These are real duplicate transactions, not merely association-scoring differences.

Median focused case duration is 25.62 seconds sequential versus 21.13 parallel; summed case durations are 350.26 versus 328.73 seconds. Mean input/output tokens are 19,207/1,279 versus 17,511/1,639. These describe concurrently scheduled isolated cases, not app queue wall time or general throughput. The production cap reduces throughput for unrelated files in exchange for preventing concurrent empty reads.

## Transaction-perspective result

Case `14` is genuinely an expense: the visible PDF identifies Wortspur/Jana Feld as issuer and labels Studio Linden/Mara Winter as invoice recipient, then bills Mara Winter for website texts. Text extraction, rendered-page inspection and truth agree. Original rules book it as income in all three fresh observations: baseline twice and full sequential once. One baseline run correctly extracts the supplier while still choosing income, so this is not simply missing supplier text or matching failure.

The adopted sentence prefixes the existing payment bullet:

> Buche aus Sicht des Unternehmens im Profil: eigene Lieferungen und Leistungen als Einnahmen, bezogene als Ausgaben.

Every original payment instruction and other rule remains unchanged. Transaction role avoids reducing direction to document sender/recipient, which can misclassify client-created self-billing credits. No matching parser, special supplier rule or edge-case catalogue was added.

The candidate passes `14` in **six observed runs**: the full sweep plus five focused repeats. All eleven independent outgoing document cases remain correct in the full sweep, and outgoing `01` passes another five focused repetitions. All seven archive/drop/chat scenarios pass in both sequential full sweeps. Only `32`, coworking classified as membership instead of rent, remains wrong. No material full-state regression was observed; the adoption gate was met. No third category experiment was undertaken.

## Verification and limits

The runner defaults to `--file-jobs 1`; explicit values `1...50` control files independently of `--jobs`. New reports always record the integer; absent legacy fields mean the original all-files-at-once behavior. Summaries/comparisons display this and rescoring preserves it. Production retains its existing queue/task-group design with a cap of one.

Native runner builds and no-API checks pass for defaults, valid bounds, invalid/missing values, absent-credential refusal, legacy/new summaries/comparison, and offline rescore provenance. A stale executable initially rejected `--file-jobs` before an API call or output directory; README now pins `swift build --build-system native --product PfennigEval`. Verified native executable: `/Users/pietz/Private/pfennig/.build/arm64-apple-macosx/debug/PfennigEval`. Credential input is environment-only; the `.env` fallback was removed without reading a credential file. README documents metadata discovery and `ainv` delivery into the trusted prebuilt runner.

Final verification is complete: all 259 existing tests pass, the Debug build passes, the unsigned Release build passes, and the release contract check passes. The instruction snapshot was updated to the adopted sentence and the source rules/prompt hashes were verified against the measured override. This work does not include notarization, publication or replacing the installed release app. Queue verification includes separate source-loop review and the actual eval sweeps. At cap one, the loop awaits full intake completion, including persistence or rollback/cleanup, before launching the next file. Direct AppModel queue unit coverage is absent; no runtime abstraction or test bootstrap was added for this cap-only change.

The historical September 25 endpoint, `exp-exp7-dates-public`, has the same truth/source hashes but a different prompt and inference date: 95/104 total, 91/100 agent-evaluable, 83/92 positive states. Its seeded-hotel lookup omission and receipt-photo text errors did not recur in the fresh baseline. Earlier reports also rejected a credit merged into its invoice; current reviewed truth accepts that equivalent state. Preserve source review and offline rescoring before treating historical mismatches as model defects.

The public corpus has 39 positive single-file forms representing 37 transactions, six controls and seven scenarios. Reused layouts/modalities, single-turn chats and repeated fixtures limit independence. It always uses a regular VAT profile, has no positive standalone multi-transaction document, and has no untouched holdout. Future confidence needs independently held-out transactions, including matching distractors and no-match cases, rather than more repeats of tuned examples.

Exact attachment sets and missing/extra bookings are scored; nonexistent receipt IDs are rejected by Core. Missing benchmark checks remain edited-seed review invalidation, notes preservation and multi-turn evidence retention. Seeded rows are currently exempt from the scorer's unreviewed-state check, although Core separately tests invalidation. These are measurement gaps, not demonstrated product defects. Tax calculation agreement is not an ELSTER import certification. The measured improvement supports the two bounded changes and continued human review, not a universal reliability claim.
