# Benchmark investigation, 2026-10-12

Keep the existing whole-agent evaluation as the product benchmark. Add a small, frozen component diagnostic for extraction and a few held-out matching scenarios. The evidence supports better measurement and targeted experiments, not an agent rewrite or an Apple replacement.

This investigation inspected public fixtures, runner/scoring code, current agent code and saved synthetic results only. It made no model calls, read no credentials/private corpus/app archives, and changed no production code or scorer. Counts below were independently recomputed from saved JSON. Proposed work is explicitly separated from measured results.

## What the evidence establishes

| Evaluation | Observed result | Interpretation |
| --- | --- | --- |
| Historical Luna/high, September 25 | 95/104 total, 91/100 agent-evaluable, 83/92 positive-task runs | 52 scenarios repeated twice. Eight agent-evaluable negative-control passes contribute to 91/100; four API-rejected invalid inputs contribute only to total passes. 45/52 scenarios passed both repetitions. This is a historical endpoint measurement. |
| Apple whole-agent pilot | 1/8; 0/7 positive tasks | Only the invitation control passed. Same selected fixtures/truth as historical Luna; adapters and inference dates differ. Historical Luna repetition 1 passes 7/8. |
| Apple fixed facts configuration | 3/9 whole-facts passes; 48/63 field checks | Three cases repeated three times, representing two transactions. Hotel PDF passes; receipt and hotel scan fail all repeats. Seven checks cover facts only. |
| Historical Luna on those fact checks | 6/6 whole-facts passes; 42/42 checks | Same scorer applied to saved bookings from two repetitions. Luna performed the broader accounting task. This does not compare equal inference pipelines or latency. |
| Narrow Apple typed mutations | Selected receipt-link and private-share controls each pass 3/3 | Relevant existing rows were supplied to the model. This demonstrates constrained mutation, not autonomous archive lookup. |

Evidence: [whole-agent comparison](../results/apple-native-eight-ready-20261012/comparison.json), [fixed-facts comparison](../results/apple-consistent-facts-20261012-103238/comparison.json), [feasibility diagnostics](../results/apple-feasibility-20261012/summary.json), [historical Luna report](../../results/exp-exp7-dates-public/report.json). Raw results are ignored local artifacts; these links require the retained result folders.

The historical Luna failures are concentrated, rather than nine unrelated weaknesses: one direction error in case 14; two category errors in 31/32; two receipt-photo recognition failures in 41; four duplicate/attachment failures across s1/s2/s3. Matching and modality robustness are the best-supported next targets for the current agent.

The Apple failures can already be narrowed without another run:

- In [receipt 09](../results/apple-consistent-facts-20261012-103238/09-r1/result.json), the model copies gross line amounts into `netto`. Their sum is 29.39, while its separately extracted total net is correctly 24.70. Core calculates 5.59 tax on those mislabelled lines; the receipt explicitly states 4.69. Exact arithmetic cannot repair a wrong semantic label. The [saved OCR](../results/apple-consistent-facts-20261012-103238/09-r1/ocr.txt) contains the `ARTIKEL | BRUTTO` heading and correct totals.
- In [hotel scan 42](../results/apple-consistent-facts-20261012-103238/42-r1/result.json), date, total net and total gross are omitted despite all three being present in the [saved OCR](../results/apple-consistent-facts-20261012-103238/42-r1/ocr.txt). VAT groups are correct. More OCR preprocessing is not yet an evidence-based fix for this failure.
- These outcomes repeat identically in all three runs. The probe uses greedy sampling. Repeats establish observed repeatability on these inputs, not nine independent tests of general reliability.

## What to preserve and what is not measured

The [runner](../../runner/EvalMain.swift) already uses real intake/chat, isolated archives, frozen dates, neutral filenames, cached FX, source/truth/prompt hashes, complete saved bookings and traces, accepted correct end states, and offline rescoring. These are strong foundations. Its [scorer](../../runner/Scoring.swift) measures persisted fields, receipt associations and missing/extra bookings, not fluent claims of success. Keep that as the primary gate. A field percentage is useful diagnosis but must not compensate for a duplicate transaction or missing write.

The public corpus has **52 scenarios: 39 positive single-file forms representing 37 transactions, six controls, and seven archive/drop/chat scenarios**. There are 45 source files. The two modality variants and seeded scenario reuse are valuable paired tests, but they do not increase independent transaction diversity. Only two cases use chat, each a single turn. The profile is always a regular VAT payer. Positive single-document cases each expect one booking, so one document supporting distinct transactions is not exercised. There is no declared untouched holdout; repeated prompt experiments have used this corpus.

Specific measurement limitations:

- Seeded bookings are excluded from the scorer's unreviewed-state check even when edited. Core separately tests that agent edits reset review, and saved s7 runs correctly do so. This is a benchmark coverage gap, not evidence of a product defect. Notes preservation and multi-turn conversational state are also unscored.
- `agentEvaluated` is one Boolean for the whole case. Any recognized API/network failure excludes the case, even if earlier calls did useful work. Keep operational completion alongside conditional agent quality. Distinguish pre-inference unavailability, input rejection, transport failure, model/task failure and harness configuration error; do not count a tool-cap loop caused by forced-required tool mode as native factual accuracy. The existing blocked Apple report correctly has zero agent-evaluable cases.
- The native component and whole-agent scorers have different name normalization/accepted-value behavior. The seven-check comparison is fair for the selected cases, but its checks are correlated: net, tax, gross and VAT groups can all reflect one mistake. Never treat 63 field checks as 63 independent observations. Derived tax must remain labelled as Core-derived, not extracted tax.
- Whole-agent booking matching greedily selects the closest remaining booking. It can be order-dependent for overlapping multi-booking expectations. No current false result was established; add an adversarial scorer check before expanding such cases, rather than redesigning matching now.
- `--tax` appropriately rejects seeded scenarios, but the public modality duplicates also prevent treating a simple sum as one real quarter. Tax impact should compare expected and actual state **per scenario**, or use an explicitly deduplicated accounting corpus. The app's own calculation is useful impact diagnosis, not independent tax-law validation.

## Prioritized bounded next experiments

1. **Freeze the scorecard before the next model run.** Use existing report fields to publish total completion, agent-evaluable completion, positive-task completion, negative-control behavior and per-case repeat counts. Keep whole-state pass primary and field failures secondary. Record exact revision, prompt/truth/file hashes, adapter/OCR mode, sampling, runtime/OS and model availability. Require planned runs to finish or label the report partial. No new evaluation framework is needed.

2. **Current-agent regression slice, then breadth.** When a paid run is separately authorized, use 14,31,32,41,s1,s2,s3 plus successful controls 09,17,38,s6,s7, three fresh archives per case with one frozen configuration. This directly tests the observed weaknesses. Add a second independent receipt/hotel transaction before spending on more identical repeats. Keep a later full 52-case sweep as the regression check; do not infer whole-corpus improvement from this selected difficult slice.

3. **One Apple extraction diagnostic, fixed in advance.** Compare unchanged OCR with one generic schema alternative that asks for printed summary/VAT-group amounts rather than forcing every item into a net-line interpretation. Use 09/17/42 as development examples and include a different receipt with gross item prices and a different mixed-VAT invoice as unseen checks. Score printed values and Core-derived values separately and reject inconsistent totals. Record missing facts explicitly. This tests the evidenced semantic bottleneck without adding document-specific parsing or changing production. Broaden only if unseen examples pass; more repeats of greedy failures will add little.

4. **Six new synthetic scenarios, held out until configuration freeze.** Prioritize two ambiguous matching tasks with distractor bookings (same amount/date or reused receipt number across issuers), one no-match case, one document supporting two distinct transactions, one two-turn correction retaining a user note, and one Kleinunternehmer case in a separate truth/profile file. Give both agents the same evidence at the chosen task boundary. For autonomous matching, require retrieval from the archive and score final associations; supplied candidate rows define a different, explicitly conditional task. Hold out whole transactions and their layout/modal variants together. After inspecting failures, mark that set development data and replace the holdout for the next tuning cycle.

5. **Small scorer checks alongside the new scenarios.** Assert edited-seed review invalidation and preservation of seeded state on no-op/refusal, and verify missing/extra bookings and ambiguous matching order with hand-constructed states. Reuse existing scorer tests. Add per-case tax deltas only if they help distinguish material failures; do not replace exact state checks or build a broad metrics service.

No fresh model experiment is necessary to justify these next steps. The immediate opportunity is broader independent evidence at a clearly defined task boundary, with state-based scoring and fixed configurations.
