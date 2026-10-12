# Apple AI feasibility experiments, 2026-10-12

Historical measurements from the archived `experiment/apple-intelligence` checkout, retained on 2026-10-12. The normal app has no Apple provider. See the [isolated eval README](../README.md) for current standalone commands; full-agent commands below require the archived integration revision.

**A convenient, stable replacement for the full OpenAI agent is not established.** Smaller native components do work: two fact-extraction configurations and two typed mutations pass controlled repeats. They do not establish reliable general import, tax classification, autonomous matching or full chat parity. The original whole-agent pilot remains [1/8 versus historical Luna's 7/8](apple-intelligence-evaluation-20261012.md).

All experiments use public fictional fixtures and isolated temporary repositories. Production `Sources`/`App`, settings, real archives and credentials were untouched. No paid API call or release occurred. The [summary and all raw results](../results/apple-feasibility-20261012/summary.json) preserve successes, failures, tool statements, actual saved rows, inputs and reported usage.

## What changed the outcome

| Route | Observed result |
| --- | --- |
| Direct native images + guided decimal-string facts, cases 09/17/42 | No complete exact fact result. Receipt amounts partly correct; issuer invented/date format wrong. Hotel values invented. Scan refused as potentially unsafe. |
| Generic Vision text OCR + the same facts | Dates/vendors improved, but amounts were swapped or assigned to the wrong table fields. Readable OCR alone was insufficient. |
| Row-preserving generic OCR + regex guides | Compiled, but all four diagnostic requests rejected the schema with `UnsupportedGuide`. These are runtime configuration/capability errors, not factual failures. |
| German fields, date components, integer EUR cents | Receipt 09 fully correct; hotel/scan often supplied euro magnitudes as cents and duplicated a total as a line. |
| Whole euros + cent components, with model-generated aggregate tax | Better hotel positions, but aggregate tax still wrong. Receipt amounts could be 100 times too large. |
| Whole euros + cents, existing Core tax calculation | Hotel 17 fully correct. The same route mistakes receipt gross amounts for net; an earlier scan run selects the stay-start date. No universal winning extraction schema. |
| Native `RecognizeDocumentsRequest` layout, case 17 | Correct table totals and money after Core calculation, but the one fact extraction leaves invoice date null. Vision merges some net/rate cells and omits item descriptions from table cells; it is not perfect table reconstruction. |
| OCR + raw SQL, shorter/shared prompts and supplied rows | Wrong SQL repeatedly uses nonexistent columns, with no successful writes. Forcing calls does not fix statement generation. |
| Narrow typed private-share/receipt-link tools + supplied rows | Correct database effects and completed responses with `.allowed`, confirmed below. No generated SQL: the wrapper composes a fixed primitive and passes it through SQLTool. |

The generic row-preserving OCR sorts recognized boxes into reading lines by their vertical position, then columns by horizontal position. It has no document-specific accounting rules. The separate Native Documents route uses Apple's actual document/table API; the final runner can invoke it directly. Its tested prepared case-17 text is retained in that result's `ocr.txt`.

## Controlled successes

All final guide examples are unrelated to fixture amounts: `12.34`, `12,34`, `1234`, `123`, `123,00`. Early failed diagnostics are retained rather than overwritten. The final hotel controls restore the generic invoice-date guide and use the same configuration for repetitions 2, 3 and 4.

| Control | Result | Mean model-response time | Reported input/output tokens per run |
| --- | --- | ---: | --- |
| Row OCR + integer-cent receipt facts, case 09, `facts-clean` r1–r3 | 3/3 exact date, vendor, receipt number, net/tax/gross and VAT groups | 2.49 s | 977 / 117 |
| Row OCR + euro/cent facts + Core tax, hotel 17, r2–r4 | 3/3 exact same checks, including 7%/19% groups | 4.68 s | 1,272 / 211 |
| Typed private-share mutation, s7, `.allowed` r1–r3 | 3/3 sets 50%, one booking, unreviewed | 2.32 s | 2,855–2,859 / 48 |
| Typed receipt-link mutation, s1, `.allowed` r1–r3 | 3/3 retains original receipt and adds the scan to the same booking, unreviewed | 7.92 s | 3,786–3,788 / 74–452 |

The successes are deliberately narrow. Candidate booking rows are supplied upfront, so they do **not** prove autonomous database lookup or matching among a large archive. Assistant wording can still be misleading: a successful link response says a new booking was added although the tool only updated an existing booking. The disposable runner does not reproduce the production request/inbox/chat-history lifecycle.

The euro/cent schema supports only positive EUR amounts and integer VAT rates. It does not demonstrate credits, FX/original-currency precision, fractional VAT rates, tax-treatment decisions or payment inference. Some group/tax values are computed with existing `Position.steuer` and `Cent`, not literally extracted by the model. That calculation correctly rejects neither a wrong gross-as-net interpretation nor a wrong date by itself; generated facts still need reconciliation/validation. No receipt-specific parser or alternative bookkeeping engine was added.

The initial `.required` runs performed correct typed effects but then failed the disposable 12-SQL-call cap. Apple documents that required mode needs an explicit exit condition, such as switching to `.allowed` in a dynamic profile. Those cap failures are API configuration failures, not evidence that the model cannot finish a correctly configured tool task. Raw SQL's nonexistent-column errors remain independently wrong. No failed required-mode run is counted as an overall success.

`seconds` measures the model/session response after rendering/OCR. Later controls also record `preparationSeconds` and `totalProbeSeconds`; these fields are absent in early diagnostics. Typical row-OCR preparation here is about 0.15–0.22 s. The researcher measured Native Documents recognition at 25.57 s cold; its prepared-text model response took 6.42 s. These are component observations, not measured whole-app throughput or an end-to-end Luna speed comparison.

## Follow-up: one fixed extraction pipeline

At the owner's request for comparable numbers, the unchanged final `ocr-lines-core-units` configuration was run three times on **each** of cases 09, 17 and 42. No document-dependent schema choice or further tuning occurred. Seven common factual checks cover date, issuer, receipt number, net, tax, gross and VAT groups. The same checks were independently applied to Luna's stored booking outputs for those cases, after verifying matching ground-truth and fixture hashes.

| Document case | Adapted Apple, three new repeats | Historical Luna/high, two repeats |
| --- | ---: | ---: |
| 09, ordinary receipt | 0/3 | 2/2 |
| 17, mixed-VAT hotel PDF | 3/3 | 2/2 |
| 42, scan of the same hotel invoice | 0/3 | 2/2 |
| All seven factual checks correct | **3/9 (33.3%)** | **6/6 (100%)** |
| Individual checks correct | **48/63 (76.2%)** | **42/42 (100%)** |

Receipt 09 treats gross item prices as net, deriving EUR 5.59 tax instead of EUR 4.69. Scan 42 leaves date, aggregate net and gross missing in all three repeats. The hotel PDF passes every check in every repeat. Apple averages 4.35 seconds for model response and 4.57 seconds for the entire disposable probe; these are not comparable to Luna's historical whole-booking latency.

This is a small test of three document forms and two underlying transactions. Apple has three fresh repeats per form; Luna has two saved repeats from 2026-09-25. Luna completed a broader booking task, while Apple only emitted facts and used Core to calculate tax. The field comparison does not measure category, tax treatment, payments, matching, SQL or lifecycle. It confirms that the earlier per-document successes do not establish one reliable generic extraction route.

Evidence and scoring script: [comparison.json](../results/apple-consistent-facts-20261012-103238/comparison.json) and [compare-facts.py](../results/apple-consistent-facts-20261012-103238/compare-facts.py). Every run retains its raw result, supplied OCR and instructions in that directory. Reproduce with the existing runner's `extract ocr-lines-core-units` mode for each case, using a fresh output directory for each repetition. No app code, real archive or credentials changed.

## Cloud and next decision

The separately authorized synthetic PCC probe reports available/32K context, but actual trivial inference immediately fails with error 1046. No receipt cloud inference followed. Access, production managed-entitlement/App Store eligibility and bookkeeping quality remain unproven; available status alone is insufficient. PCC is cloud processing, distinct from the local routes. See [the capability investigation](apple-intelligence-capabilities-20261012.md).

The evidence supports native task-scoped helpers, not promoting Apple to the default. A later staged prototype would need one consistent generic extraction contract, reconciliation of declared and calculated amounts, reliable categories/tax/payments, and the existing lifecycle safeguards. The current evidence does not justify another full-corpus benchmark or accepting readable text as accounting accuracy.

## Reproduce

Final review independently checked the twelve successful control artifacts against their claimed facts or saved booking state. `scripts/test.sh --build-system native` passes all 262 tests, `scripts/build.sh` succeeds, formatting is clean and the standalone probe compiles. These checks do not turn the component experiments into full app parity.

Run from this checkout's repository root; fixtures default to its public `evals/2026-q3`. `build.sh` builds and links the native SwiftPM Core/Agent/GRDB objects. The runner has a 12-SQL-call disposable cap and no OpenAI credential path.

```sh
evals/apple-ai/build.sh
/tmp/pfennig-apple-ai-probe extract ocr-lines-facts-clean 09 /tmp/apple-receipt-check
/tmp/pfennig-apple-ai-probe extract ocr-lines-core-units 17 /tmp/apple-hotel-check
/tmp/pfennig-apple-ai-probe workflow guided-allowed s7-chat-private-share /tmp/apple-share-check
/tmp/pfennig-apple-ai-probe workflow guided-allowed s1-scan-for-booked-hotel /tmp/apple-link-check
/tmp/pfennig-apple-ai-probe extract document-core-units 17 /tmp/apple-document-layout-check
```

Each directory holds `result.json`, `ocr.txt` and `instructions.txt`; use a fresh directory for a new run. The optional fifth runner argument supplies previously prepared OCR text, which was used for the single Native Documents diagnostic. The runner preserves the final controlled configurations; initial decimal-string diagnostics used an earlier guide configuration, so their saved artifacts document those historical observations rather than an identical rerun with this source. Superseded source copies and the separate document-layout helper were removed. The runner compiles with Xcode 27/Swift 6.4. No production implementation change is included.
