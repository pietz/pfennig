# Native extraction: four of five permitted configurations, 2026-10-12

**The original development failures improved, but reserved expense cases regressed. Do not adopt this as a general importer.** The selected configuration improves development from **3/9 to 9/9**, while the four reserved expense transactions fall from **6/12 to 3/12**. The experiment therefore demonstrates a useful decomposition on familiar examples, not reliable generalization. OpenAI remains the production agent.

Four configurations were declared before their inference, including the unchanged baseline. Configuration 4 was frozen before validation; the fifth was deliberately unused. All **60 planned probe runs completed**, comprising 71 native responses because eleven runs used a second extraction call. There were no availability, process, timeout or model-execution errors. No cloud/PCC/OpenAI calls, credentials, private records or real app archives were used.

## Frozen task and evaluation boundary

The task extracts seven document facts: date, issuer, receipt number, net, tax, gross and VAT groups. Primary success requires all checks plus no execution error. Field counts are diagnostic and correlated. No booking classification, payments, lookup, persistence or complete agent lifecycle is measured.

Development used 09/17/42, three forms of two transactions. Reserved validation was declared as 10/18/31/44/05 before inference. These are other public synthetic transactions not used in this native tuning sequence, not an independently collected or permanently untouched holdout. Every final case ran three times with greedy sampling. Repeated facts were identical within every case/configuration; the repetitions establish repeatability, not independent generalization evidence.

A label defect became apparent during baseline validation: **05 is an outgoing credit**, whose expected bookkeeping counterparty is its customer, whereas the extraction prompt asks for the issuer. Saved Luna bookings cannot establish document issuer here. Before final inference, we explicitly separated 05 into a **six-check signed-credit diagnostic**, with issuer unscored. No model/prompt/schema tuning or replacement case followed that correction. The seven expense forms remain the seven-check headline. Both the reusable comparator and standalone probe now mark this boundary instead of silently treating a correct issuer as a failure. Archived raw 05 `mismatches` retain the old issuer-label failure; the derived comparisons correct it transparently.

## Every attempted configuration

All use the same generic row OCR and greedy decoding, with tools disabled. Configurations 2–4 development runs reuse configuration 1's saved OCR. Schema source and instructions are retained beside each run.

| # | Mode and declared change | Development selection result | Evidence |
| --- | --- | --- | --- |
| 1 | `ocr-lines-core-units`: unchanged euro/cent net-line baseline; Core derives tax from generated net/rate | 1/3 complete; 16/21 checks | [Manifest](../results/five-20261012-c1-dev/manifest.json), [scores](../results/five-20261012-c1-dev/comparison.json) |
| 2 | `ocr-lines-summary`: summary-first instruction with existing decimal-string Facts schema; model emits printed/summed tax | 0/3; 12/21 | [Manifest](../results/five-20261012-c2-dev/manifest.json), [scores](../results/five-20261012-c2-dev/comparison.json) |
| 3 | `ocr-lines-printed`: typed required summary; signed euro/cent amounts, date components, percentage rates, printed VAT tax groups. Core sums printed group taxes only | 0/3; 18/21 | [Manifest](../results/five-20261012-c3-dev/manifest.json), [scores](../results/five-20261012-c3-dev/comparison.json) |
| 4 | `ocr-lines-staged`: same summary call. One rate uses total net; multiple rates trigger a separate focused extraction of actual net lines and same-row rates, summed by Core | 3/3; 21/21 | [Manifest](../results/five-20261012-c4-dev/manifest.json), [scores](../results/five-20261012-c4-dev/comparison.json) |

Configuration 2 fixes dates but emits decimal commas, fraction rates and tax amounts as group net. Configuration 3 fixes the other six checks but still assigns incorrect group nets. Configuration 4 fixes that development bottleneck. Its first call has a 1,000-token response cap; the conditional second call has 800. Baseline has 800 and configuration 2 has 600. There are no retries or document-specific routes. Model extraction supplies semantics; Core only performs exact conversion/aggregation in configuration 4.

## Paired final results

Both configurations ran the same eight forms, three times each, under macOS 27.0.1 on Apple Silicon. All 24 final configuration-4 OCR inputs byte-match the paired baseline's first OCR for that case. Both final runs used the same source snapshot hash `706a54f9edfa736b8f08a4ba49bd0538909a225027cd1f3ed6b76e74d2b9e1c8`; the manifests also retain binary, truth and fixture hashes. Later source changes only improve failure-usage logging and the outgoing scorer label, with offline verification and no additional inference.

| Expense subset | Baseline complete facts | Final complete facts | Baseline fields | Final fields |
| --- | ---: | ---: | ---: | ---: |
| Development 09/17/42 | 3/9 | 9/9 | 48/63 | 63/63 |
| Reserved 10/18/31/44 | 6/12 | 3/12 | 78/84 | 72/84 |
| Pooled, secondary only | 9/21 | 12/21 | 126/147 | 135/147 |

Historical Luna/high has **14/14 complete expense-fact results, 98/98 checks**, using its two saved repetitions per form from September 25. This is an honest historical factual reference, not a fresh endpoint benchmark or equal-work latency comparison. The historical whole-agent Apple 1/8 versus Luna 7/8 remains a different measurement and is unchanged.

| Case | Baseline → final, passes/3 | Final observed limitation |
| --- | --- | --- |
| 09, receipt | 0 → 3 | Previously used gross item prices as net; corrected on this transaction |
| 17, hotel PDF | 3 → 3 | Remains correct |
| 42, same hotel scan | 0 → 3 | Previously omitted printed date and totals; corrected |
| 10, printing invoice | 3 → 3 | Reserved success |
| 18, restaurant | 0 → 0 | Net components total 68.00, with no printed overall net; gross is 74.44. Required-summary output invents 68.44 and 82.44 |
| 31, book | 0 → 0 | Both read printed gross 29.96 as 29.06 |
| 44, gift | 3 → 0 | Regression: final reads printed gross 49.98 as 49.08 |

The separate outgoing-credit diagnostic improves **0/3 to 3/3**, or **0/18 to 18/18 six-field checks**; historical Luna is 2/2, 12/12. Native issuer is correctly Studio Linden and is not compared with the customer stored in the booking. This validates one signed, single-rate example only. The mixed-rate allocation schema still uses positive-only net amounts; mixed-rate credits are not established.

Generic arithmetic reconciliation detects all nine failed final expense runs here: total net plus tax versus gross, and group net/tax sums versus totals. It records errors without changing facts. This is useful rejection evidence, not a repair or proof that all factual errors will violate arithmetic. Case18 exposes a schema mismatch: the required printed total-net field is absent, although component nets are present and sum correctly. Required-summary schemas do not establish abstention when facts are absent. Foreign currencies, noninteger VAT rates, missing information and broader layouts remain outside the validated domain.

Across all 24 paired runs, mean model/session duration increases from 3.74 to 5.34 seconds. The final route sometimes uses two calls. Total preprocessing timings are not comparable because it reuses OCR. These are diagnostic measurements, not an app speed claim.

Final evidence: [baseline manifest](../results/five-20261012-c1-final/manifest.json), [baseline scores](../results/five-20261012-c1-final/comparison.json), [final manifest](../results/five-20261012-c4-final/manifest.json), [final scores](../results/five-20261012-c4-final/comparison.json). Each folder retains all results, raw generated structures, OCR, instructions, source snapshot and logs. Generated artifacts remain locally ignored by Git.

## Reusable changes and verification

[run-experiment.py](../run-experiment.py) declares the case/repeat plan before inference, refuses existing output folders, captures provenance, records failures/timeouts and supports exact OCR replay. [compare-facts.py](../compare-facts.py) keeps missing runs in the planned denominator, rejects mixed/unplanned results, reports execution failure even with correct facts, separates outgoing six-check diagnostics and records reconciliation without repair. No new framework or production provider was introduced.

Verification passed: eight offline Python scorer tests; standalone Swift signed-money, allocation and outgoing-scoring self-checks; all twelve existing eval tests via `scripts/test.sh --filter eval`; standalone compilation and SwiftFormat. The original saved nine-run pilot still rescored to exactly 3/9, 48/63, with historical Luna 6/6, 42/42. Report links and paired OCR equality were checked. No commit or push was made.

The final root review independently verified every manifest and all 60 probes/71 responses, the paired source/binary hashes and OCR equality, the split development/validation metrics and the nine observed reconciliation failures. All 256 project tests and the normal app build also passed. Only eval files and status documentation changed; the work was committed locally after review, with no push or release.

The bounded conclusion is to retain these probes and measurement improvements, while keeping native extraction experimental. More tuning on the same receipt/hotel would not resolve the negative reserved-case evidence.
